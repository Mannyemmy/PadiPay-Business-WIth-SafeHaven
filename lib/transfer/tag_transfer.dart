import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padi_pay_business/payment_successful_page.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';

class TagTransferPage extends StatefulWidget {
  const TagTransferPage({super.key});

  @override
  State<TagTransferPage> createState() => _TagTransferPageState();
}

class _TagTransferPageState extends State<TagTransferPage> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController remarkController = TextEditingController();
  bool sendAnonymously = false;
  bool isLoading = false;
  bool isCheckingUsername = false;
  bool isUsernameValid = false;
  String feeText = "Free transfers";
  Map<String, dynamic>? recipientData;
  String? receiverUid;
  Timer? _usernameDebounce;
  String? counterpartyId;
  List<Map<String, dynamic>> _recentTagTransfers = [];
  bool _loadingRecents = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    amountController.addListener(_updateFee);
    usernameController.addListener(_debounceCheckUsername);
    _loadRecentTagTransfers();
  }

  Future<void> _loadRecentTagTransfers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loadingRecents = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'transfer')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();
      final seen = <String>{};
      final entries = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final receiverId = data['receiverId']?.toString() ?? '';
        if (receiverId.isEmpty || receiverId == 'unknown') continue;
        if (seen.contains(receiverId)) continue;
        seen.add(receiverId);
        entries.add(data);
        if (entries.length >= 10) break;
      }
      final enriched = <Map<String, dynamic>>[];
      for (final txn in entries) {
        final receiverId = txn['receiverId']?.toString() ?? '';
        final storedUsername = txn['username']?.toString() ?? '';
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(receiverId)
              .get();
          final userData = userDoc.data() ?? {};
          enriched.add({
            'uid': receiverId,
            'username': storedUsername.isNotEmpty ? storedUsername : userData['username']?.toString() ?? '',
            'name': txn['recipientName']?.toString() ?? '',
            'profileImage': userData['profileImage']?.toString() ?? '',
          });
        } catch (_) {
          enriched.add({
            'uid': receiverId,
            'username': storedUsername,
            'name': txn['recipientName']?.toString() ?? '',
            'profileImage': '',
          });
        }
      }
      if (mounted) setState(() => _recentTagTransfers = enriched);
    } catch (e) {
      debugPrint('loadRecentTagTransfers error: $e');
    }
    if (mounted) setState(() => _loadingRecents = false);
  }

  void _updateFee() {
    setState(() {
      feeText = "Free transfers";
    });
  }

  void _debounceCheckUsername() {
    _usernameDebounce?.cancel();
    _usernameDebounce = Timer(const Duration(milliseconds: 500), _checkUsername);
  }

  Future<void> _checkUsername() async {
    final username = usernameController.text.trim().toLowerCase();
    if (username.isEmpty) {
      setState(() {
        isUsernameValid = false;
        recipientData = null;
        receiverUid = null;
        isCheckingUsername = false;
      });
      return;
    }

    setState(() => isCheckingUsername = true);

    try {
      // First read from usernames collection to get the uid
      final usernameDoc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username)
          .get();

      final uid = (usernameDoc.data() ?? {})['uid'] as String?;
      
      if (uid != null) {
        // Then fetch the user details
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();

        if (userDoc.exists) {
          setState(() {
            isUsernameValid = true;
            recipientData = userDoc.data();
            receiverUid = uid;
            isCheckingUsername = false;
          });
          return;
        }
      }

      setState(() {
        isUsernameValid = false;
        recipientData = null;
        receiverUid = null;
        isCheckingUsername = false;
      });
    } catch (e) {
      debugPrint('Error checking username: $e');
      showSimpleDialog('Error checking username', Colors.red);
      setState(() {
        isUsernameValid = false;
        recipientData = null;
        receiverUid = null;
        isCheckingUsername = false;
      });
    }
  }

  Future<Map<String, dynamic>?> getCompanyVirtualAccount() async {
    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('company')
          .doc('account_details')
          .get();
      if (!docSnap.exists) return null;
      final data = docSnap.data()!;
      return {
        'uid': data['uid']?.toString() ?? '',
        'id': data['accountId']?.toString() ?? '',
        'type': data['accountType']?.toString() ?? '',
        'bankId': data['bankId']?.toString() ?? '',
        'bankName': data['bankName']?.toString() ?? '',
        'accountNumber': data['accountNumber']?.toString() ?? '',
        'accountName': data['accountName']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('getCompanyVirtualAccount error: $e');
      return null;
    }
  }

  Future<void> _createCounterparty() async {
    if (recipientData == null || !isUsernameValid) {
      showSimpleDialog('Please verify recipient tag', Colors.red);
      return;
    }

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];
      final String? accountType = details['accountType'];
      String? bankId = details['bankId'];

      if ((bankId == null || bankId.isEmpty) && details['bankName'] != null && details['bankName'].toString().isNotEmpty) {
        final resolved = await resolveBankIdByName(details['bankName']);
        if (resolved != null) {
          bankId = resolved;
          debugPrint('Resolved user bankId by name: $bankId');
        }
      }

      if (accountId == null || accountId.isEmpty) {
        showSimpleDialog('Account ID not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }
      if (bankId == null || bankId.isEmpty) {
        showSimpleDialog('Bank ID not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }
      if (accountType == null) {
        showSimpleDialog('Account Type not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final recipientAccountNumber =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['accountNumber'];
      String? recipientBankId =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['bank']?['id'];
      final recipientBankName =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['bank']?['name'];
      final recipientAccountName =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['accountName'];

      // Try to resolve bank id from name if missing
      if ((recipientBankId == null || recipientBankId.isEmpty) && recipientBankName != null && recipientBankName.isNotEmpty) {
        final resolved = await resolveBankIdByName(recipientBankName);
        if (resolved != null) {
          recipientBankId = resolved;
          debugPrint('Resolved recipient bankId by name: $recipientBankId');
        }
      }

      if (recipientAccountNumber == null || recipientBankId == null) {
        showSimpleDialog(
          'Recipient doesn\'t have bank account details yet',
          Colors.red,
        );
        setState(() => isLoading = false);
        return;
      }

      // Check if counterparty already exists
      final query = await FirebaseFirestore.instance.collection('counterparties')
          .where('userId', isEqualTo: user.uid)
          .where('recipientAccountNumber', isEqualTo: recipientAccountNumber)
          .where('recipientBankCode', isEqualTo: recipientBankId)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        setState(() {
          counterpartyId = query.docs.first.id;
        });
        setState(() => isLoading = false);
        return;
      }

      final result = await callCloudFunctionLogged('sudoCreateCounterparty', source: 'business_app', payload: {
        'accountId': accountId,
        'bankId': recipientBankId,
        'accountType': accountType,
        'accountName': recipientAccountName,
        'bankName': recipientBankName,
        'accountNumber': recipientAccountNumber,
        'bankCode': recipientBankId,
      });
      final counterpartyIdd = result.data['data']['id'];
      await FirebaseFirestore.instance
          .collection('counterparties')
          .doc(counterpartyIdd)
          .set({
        ...result.data,
        'userId': user.uid,
        'recipientAccountNumber': recipientAccountNumber,
        'recipientBankCode': recipientBankId,
        'ownerAccountId': accountId,
      });

      setState(() {
        counterpartyId = counterpartyIdd;
      });
    } catch (e) {
      debugPrint('createCounterparty error: $e');
      showSimpleDialog('Error creating counterparty', Colors.red);
    }
    setState(() => isLoading = false);
  }

  Future<void> _sudoTransferNip() async {
    if (recipientData == null || amountController.text.isEmpty) {
      return;
    }

    // Verify PIN before proceeding
    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];

      if (accountId == null || accountId.isEmpty) {
        showSimpleDialog('Account details not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      // Recipient's Sudo account ID (internal book transfer)
      final toAccountId = recipientData!['sudoData']?['virtualAccount']?['data']?['id']?.toString();
      if (toAccountId == null || toAccountId.isEmpty) {
        showSimpleDialog('Recipient account not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final result = await callCloudFunctionLogged('sudoTransferIntra', source: 'business_app', payload: {
        'fromAccountId': accountId,
        'toAccountId': toAccountId,
        'amount': double.parse(amountController.text) * 100,
        'currency': 'NGN',
        'narration': remarkController.text,
        'idempotencyKey': const Uuid().v4(),
      });

      final status = result.data['data']['attributes']['status'];
      final failureReason = result.data['data']['attributes']['failureReason'];
      if (status == "FAILED") {
        showSimpleDialog('Transfer failed: $failureReason', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final recipientAccountNumber =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['accountNumber'];
      final recipientBankName =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['bank']?['name'];
      final recipientBankId =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['bank']?['id'];
      final recipientAccountName =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['accountName'];

      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'receiverId': receiverUid ?? 'unknown',
        'type': 'transfer',
        'bank_code': recipientBankId,
        'account_number': recipientAccountNumber,
        'amount': double.parse(amountController.text),
        'reason': remarkController.text,
        'currency': 'NGN',
        'api_response': result.data,
        'reference': result.data['data']['id'] + "",
        'recipientName': recipientAccountName,
        'bankName': recipientBankName,
        'username': usernameController.text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      showModalBottomSheet(
        context: context,
        builder: (context) => PaymentSuccessfulPage(
          amount: amountController.text,
          actionText: "Done",
          title: "Payment Successful",
          description: "Your transfer has been processed successfully.",
          recipientName: recipientAccountName,
          bankName: recipientBankName ?? 'Unknown Bank',
          bankCode: recipientBankId ?? '',
          accountNumber: recipientAccountNumber,
          reference: result.data['data']['id'] ?? "",
        ),
        isScrollControlled: true,
      );
    } catch (e) {
      debugPrint('sudoTransferNip error: $e');
      if(e.toString().contains("There was an error processing the request")){
        showSimpleDialog("Network Downtime", Colors.red);
        return;
      }
      showSimpleDialog('Error processing transfer', Colors.red);
    }
    setState(() => isLoading = false);
  }

  Future<void> _ghostTransfer() async {
    if (recipientData == null || amountController.text.isEmpty) {
      showSimpleDialog('Please complete all fields', Colors.red);
      return;
    }

    // Verify PIN before proceeding
    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final details = await getCurrentAccountIdAndType();
      final String? userAccountId = details['accountId'];
      final String? userAccountType = details['accountType'];
      final String? userBankId = details['bankId'];

      if (userAccountId == null || userAccountId.isEmpty ||
          userAccountType == null || userAccountType.isEmpty ||
          userBankId == null || userBankId.isEmpty) {
        showSimpleDialog('User account details not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final companyVa = await getCompanyVirtualAccount();
      if (companyVa == null ||
          companyVa['id'].isEmpty ||
          companyVa['type'].isEmpty ||
          companyVa['bankId'].isEmpty ||
          companyVa['accountNumber'].isEmpty) {
        showSimpleDialog('Company account not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final recipientAccountNumber =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['accountNumber'];
      final recipientBankId =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['bank']?['id'];
      final recipientBankName =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['bank']?['name'];
      final recipientAccountName =
          recipientData!['sudoData']?['virtualAccount']?['data']?['attributes']?['accountName'];

      if (recipientAccountNumber == null || recipientBankId == null) {
        showSimpleDialog(
          'Recipient doesn\'t have bank account details yet',
          Colors.red,
        );
        setState(() => isLoading = false);
        return;
      }

      // First transfer: user to company (book transfer — both on Sudo)
      final amountNaira = double.parse(amountController.text);
      final fee = 0;
      final amountToCompanyKobo = (amountNaira + fee) * 100;
      final narration1 =
          'Ghost Mode to Company: ${remarkController.text.isNotEmpty ? remarkController.text : 'Transfer'}';
      final firstResult = await callCloudFunctionLogged('sudoTransferIntra', source: 'business_app', payload: {
        'fromAccountId': userAccountId,
        'toAccountId': companyVa['id'],
        'amount': amountToCompanyKobo,
        'currency': 'NGN',
        'narration': narration1,
        'idempotencyKey': const Uuid().v4(),
      });
      final firstStatus = firstResult.data['data']['attributes']['status'];
      final firstFailureReason =
          firstResult.data['data']['attributes']['failureReason'];
      if (firstStatus == "FAILED") {
        showSimpleDialog(
          'Transfer to company failed: $firstFailureReason',
          Colors.red,
        );
        setState(() => isLoading = false);
        return;
      }

      // Check/create counterparty for recipient (from company)
      final queryRecipientCp = await FirebaseFirestore.instance.collection('counterparties')
          .where('ownerAccountId', isEqualTo: companyVa['id'])
          .where('recipientAccountNumber', isEqualTo: recipientAccountNumber)
          .where('recipientBankCode', isEqualTo: recipientBankId)
          .limit(1)
          .get();

      String recipientCounterpartyId;
      if (queryRecipientCp.docs.isNotEmpty) {
        recipientCounterpartyId = queryRecipientCp.docs.first.id;
      } else {
        final createRecipientCpResult = await callCloudFunctionLogged('sudoCreateCounterparty', source: 'business_app', payload: {
          'accountId': companyVa['id'],
          'bankId': recipientBankId, // recipient's bank id
          'accountType': companyVa['type'],
          'accountName': recipientAccountName,
          'bankName': recipientBankName,
          'accountNumber': recipientAccountNumber,
          'bankCode': recipientBankId,
        });
        recipientCounterpartyId = createRecipientCpResult.data['data']['id'];
        await FirebaseFirestore.instance
            .collection('counterparties')
            .doc(recipientCounterpartyId)
            .set({
          ...createRecipientCpResult.data,
          'userId': companyVa['uid'],
          'recipientAccountNumber': recipientAccountNumber,
          'recipientBankCode': recipientBankId,
          'ownerAccountId': companyVa['id'],
        });
      }

      // Second transfer: company to recipient
      final amountToRecipientKobo = amountNaira * 100;
      final narration2 = remarkController.text.isNotEmpty
          ? remarkController.text
          : 'Ghost Mode Transfer';
      final secondResult = await callCloudFunctionLogged('sudoTransferNip', source: 'business_app', payload: {
        'accountType': companyVa['type'],
        'accountId': companyVa['id'],
        'counterpartyId': recipientCounterpartyId,
        'amount': amountToRecipientKobo,
        'currency': 'NGN',
        'narration': narration2,
        'idempotencyKey': const Uuid().v4(),
      });
      final secondStatus = secondResult.data['data']['attributes']['status'];
      final secondFailureReason =
          secondResult.data['data']['attributes']['failureReason'];
      if (secondStatus == "FAILED") {
        showSimpleDialog(
          'Transfer to recipient failed: $secondFailureReason',
          Colors.red,
        );
        setState(() => isLoading = false);
        return;
      }

      // Log transaction
      await FirebaseFirestore.instance.collection('transactions').add({
        'actualSender': user.uid,
        'userId': companyVa['uid'],
        'receiverId': receiverUid ?? 'unknown',
        'type': 'ghost_transfer',
        'bank_code': recipientBankId,
        'account_number': recipientAccountNumber,
        'amount': amountNaira,
        'reason': remarkController.text,
        'currency': 'NGN',
        'api_response': secondResult.data,
        'reference': secondResult.data['data']['id'],
        'recipientName': recipientAccountName,
        'bankName': recipientBankName,
        'username': usernameController.text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      showModalBottomSheet(
        context: context,
        builder: (context) => PaymentSuccessfulPage(
          amount: amountController.text,
          actionText: "Done",
          title: "Payment Successful",
          description: "Your transfer has been processed successfully.",
          recipientName: recipientAccountName,
          bankName: recipientBankName ?? 'Unknown Bank',
          bankCode: recipientBankId ?? '',
          accountNumber: recipientAccountNumber,
          reference: secondResult.data['data']['id'] ?? "",
        ),
        isScrollControlled: true,
      );
    } catch (e) {
      debugPrint('ghostTransfer error: $e');
      showSimpleDialog('Error processing ghost transfer', Colors.red);
    }
    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    amountController.removeListener(_updateFee);
    usernameController.removeListener(_debounceCheckUsername);
    _usernameDebounce?.cancel();
    amountController.dispose();
    usernameController.dispose();
    remarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 20),
                    Row(
                      children: [
                        InkWell(
                          onTap: () {
                            if (_currentPage == 0) {
                              Navigator.of(context).pop();
                            } else {
                              setState(() => _currentPage = 0);
                            }
                          },
                          child: Icon(
                            Icons.arrow_back_ios,
                            color: Colors.black87,
                            size: 20,
                          ),
                        ),
                        Spacer(),
                        Text(
                          "Send Money via Tag",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Spacer(),
                      ],
                    ),
                    SizedBox(height: 30),
                    // PAGE 0: Username selection
                    if (_currentPage == 0) ...[
                      const Text('Recipient Tag'),
                      const SizedBox(height: 8),
                      TextField(
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.none,
                        style: TextStyle(fontSize: 14),
                        controller: usernameController,
                        keyboardType: TextInputType.name,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          hintText: "username",
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          prefixIcon: Icon(
                            Icons.alternate_email,
                            color: Colors.grey.shade600,
                          ),
                          suffixIcon: usernameController.text.isEmpty
                              ? null
                              : Padding(
                                  padding: const EdgeInsets.all(14.0),
                                  child: isCheckingUsername
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  primaryColor,
                                                ),
                                          ),
                                        )
                                      : Icon(
                                          Icons.check_circle,
                                          color: isUsernameValid
                                              ? Colors.green
                                              : Colors.red,
                                          size: 20,
                                        ),
                                ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (usernameController.text.isNotEmpty && !isCheckingUsername)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(
                              isUsernameValid ? Icons.check_circle : Icons.error,
                              size: 16,
                              color: isUsernameValid ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isUsernameValid ? 'Username found' : 'Username not found',
                              style: TextStyle(
                                color: isUsernameValid ? Colors.green : Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isCheckingUsername || !isUsernameValid
                            ? null
                            : () => setState(() => _currentPage = 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Next',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ]
                    // PAGE 1: Amount & Remark
                    else if (_currentPage == 1) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: primaryColor.withValues(alpha: 0.12),
                              child: Text(
                                usernameController.text.isNotEmpty
                                    ? usernameController.text[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    usernameController.text,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '@${usernameController.text}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text('Amount to Send'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Text(
                                '₦',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                keyboardType: TextInputType.number,
                                controller: amountController,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade600,
                                  ),
                                  hintText: '0.00',
                                ),
                              ),
                            ),
                            Text(
                              feeText,
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Amount presets
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.8,
                        children: [500, 1000, 2000, 5000, 9999, 10000].map((amt) {
                          final fmtAmt = amt.toString().replaceAllMapped(
                            RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                            (m) => '${m[1]},',
                          );
                          return GestureDetector(
                            onTap: () => setState(() =>
                                amountController.text = amt.toString()),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '₦$fmtAmt',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text('Remark'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: remarkController,
                        decoration: InputDecoration(
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: 'What is this transfer for? (optional)',
                        ),
                      ),
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Ghost Mode",
                                style: GoogleFonts.inter(
                                  color: Colors.black26,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                "Send money anonymously",
                                style: GoogleFonts.inter(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          FlutterSwitch(
                            width: 50,
                            height: 25,
                            toggleSize: 20,
                            borderRadius: 20,
                            padding: 3,
                            value: sendAnonymously,
                            activeColor: primaryColor,
                            inactiveColor: Colors.grey.shade300,
                            onToggle: (val) async {
                              setState(() => sendAnonymously = val);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isLoading || (double.tryParse(amountController.text) ?? 0.0) <= 0
                            ? null
                            : () async {
                                final currentUser = FirebaseAuth.instance.currentUser;
                                if (currentUser != null && receiverUid != null && receiverUid == currentUser.uid) {
                                  showSimpleDialog('You cannot send money to your own tag', Colors.red);
                                  return;
                                }
                                if (!sendAnonymously) {
                                  await _createCounterparty();
                                  await _sudoTransferNip();
                                } else {
                                  await _ghostTransfer();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: isLoading
                            ? CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'Confirm',
                                style: TextStyle(color: Colors.white),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
              // Recents section - only on page 0
              if (_currentPage == 0) ...[
                if (_loadingRecents)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_recentTagTransfers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                            child: Text(
                              'Recents',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _recentTagTransfers.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: Colors.grey.shade100,
                            ),
                            itemBuilder: (context, index) {
                              final r = _recentTagTransfers[index];
                              final name = r['name']?.toString() ?? 'Unknown';
                              final username = r['username']?.toString() ?? '';
                              final profileImage = r['profileImage']?.toString() ?? '';
                              final initials = name
                                  .split(' ')
                                  .where((s) => s.isNotEmpty)
                                  .take(2)
                                  .map((s) => s[0].toUpperCase())
                                  .join();
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor: primaryColor.withValues(alpha: 0.12),
                                  backgroundImage: profileImage.isNotEmpty
                                      ? NetworkImage(profileImage)
                                      : null,
                                  child: profileImage.isEmpty
                                      ? Text(
                                          initials,
                                          style: TextStyle(
                                            color: primaryColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  '@$username',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: name.isNotEmpty
                                    ? Text(
                                        name,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      )
                                    : null,
                                onTap: () {
                                  setState(() {
                                    usernameController.text = username;
                                    receiverUid = r['uid']?.toString();
                                    isUsernameValid = username.isNotEmpty;
                                  });
                                  if (isUsernameValid) {
                                    setState(() => _currentPage = 1);
                                  }
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}