import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padi_pay_business/payment_successful_page.dart';
import 'package:padi_pay_business/transfer/padi_aliases_page.dart';
import 'package:padi_pay_business/ui/account_image_scanner.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:uuid/uuid.dart';

class BankTransferPage extends StatefulWidget {
  final bool initialGhostMode;
  const BankTransferPage({super.key, this.initialGhostMode = false});

  @override
  State<BankTransferPage> createState() => _BankTransferPageState();
}

class _BankTransferPageState extends State<BankTransferPage> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController accountNumberController = TextEditingController();
  final TextEditingController remarkController = TextEditingController();
  final TextEditingController accountNameController = TextEditingController();

  String? selectedBank;
  List<PadiAlias> _aliases = [];

  String? selectedBankName;
  List<Map<String, dynamic>> banks = [];
  bool sendAnonymously = false;
  bool isLoading = false;
  bool isFetchingAccountName = false;
  bool isFetchingBanks = false;
  String? counterpartyId;
  String feeText = "";
  List<Map<String, dynamic>> _recentTransfers = [];
  bool _loadingRecents = false;
  int _currentPage = 0; // 0: account details, 1: amount & remark

  // ── Cached user data (preloaded once) ──────────────────────────────
  Map<String, dynamic>? _cachedUserDoc;
  double? _cachedBalance;
  bool _isFetchingBalance = false;
  String? _ownAccountNumber;
  Map<String, dynamic>? _cachedCompanyVa;

  @override
  void initState() {
    super.initState();
    sendAnonymously = widget.initialGhostMode;
    amountController.addListener(_updateFee);
    _initAllParallel();
  }

  /// Preloads everything in parallel – no UI blocking.
  Future<void> _initAllParallel() async {
    await Future.wait([
      _prefetchUserDoc(),
      _fetchBanks(),
      _loadAliases(),
      _loadRecentTransfers(),
    ]);
  }

  Future<void> _loadAliases() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('padi_aliases')
          .orderBy('alias')
          .get();
      if (mounted) {
        setState(() {
          _aliases = snapshot.docs.map(PadiAlias.fromDoc).toList();
        });
      }
    } catch (e) {
      debugPrint('loadAliases error: $e');
    }
  }

  // ── User data (cached) ────────────────────────────────────────────
  Future<void> _prefetchUserDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      _cachedUserDoc = doc.data();
      _ownAccountNumber = _cachedUserDoc?['safehavenData']
          ?['virtualAccount']?['data']?['attributes']?['accountNumber']
          ?.toString();
      _fetchAndCacheBalance();
      _cachedCompanyVa = await getCompanyVirtualAccount();
    } catch (e) {
      debugPrint('_prefetchUserDoc error: $e');
    }
  }

  Future<void> _fetchAndCacheBalance() async {
    if (_isFetchingBalance) return;
    _isFetchingBalance = true;
    try {
      final accountId = _cachedUserDoc?['safehavenData']
          ?['virtualAccount']?['data']?['id']?.toString();
      if (accountId == null || accountId.isEmpty) return;

      final callable = FirebaseFunctions.instance.httpsCallable(
        'safehavenFetchAccountBalance',
      );
      final result = await callable.call({'accountId': accountId});
      final balanceKobo =
          (result.data['data']['availableBalance'] as num?)?.toDouble() ?? 0.0;
      _cachedBalance = balanceKobo / 100;
      debugPrint('✅ Balance pre-fetched: ₦$_cachedBalance');
    } catch (e) {
      debugPrint('_fetchAndCacheBalance error: $e');
    } finally {
      _isFetchingBalance = false;
    }
  }

  Future<double> _getBalance() async {
    if (_cachedBalance != null) return _cachedBalance!;
    await _fetchAndCacheBalance();
    return _cachedBalance ?? 0.0;
  }

  Future<bool> _checkBalance(double amountNaira) async {
    const fee = 50.0;
    final totalRequired = amountNaira + fee;
    final balance = await _getBalance();
    if (balance < totalRequired) {
      showSimpleDialog(
        'Insufficient balance. Balance: ₦${balance.toStringAsFixed(2)}. '
        'Required: ₦${totalRequired.toStringAsFixed(2)} (includes ₦50 fee)',
        Colors.red,
      );
      return false;
    }
    return true;
  }

  // ── Bank list ─────────────────────────────────────────────────────
  Future<void> _fetchBanks() async {
    setState(() => isFetchingBanks = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('banks')
          .get();
      if (snapshot.docs.isNotEmpty) {
        setState(() {
          banks = snapshot.docs.map((doc) => {
            'id': doc.id,
            'attributes': {'name': doc.data()['name']},
          }).toList();
          isFetchingBanks = false;
        });
        return;
      }

      // Fallback to cloud function
      final result = await callCloudFunctionLogged(
        'safehavenBankList',
        source: 'bank_transfer_page.dart',
      );
      final apiBankList = (result.data as Map)['data'] as List<dynamic>;
      final batch = FirebaseFirestore.instance.batch();
      for (var item in apiBankList) {
        final map = item as Map;
        final docRef = FirebaseFirestore.instance
            .collection('banks')
            .doc(map['id'].toString());
        batch.set(docRef, {'name': (map['attributes'] as Map)['name']?.toString()});
        banks.add({
          'id': map['id'].toString(),
          'attributes': {'name': (map['attributes'] as Map)['name']?.toString()},
        });
      }
      await batch.commit();
      setState(() => isFetchingBanks = false);
    } catch (e) {
      debugPrint('safehavenBankList error: $e');
      setState(() => isFetchingBanks = false);
    }
  }

  // ── Account name enquiry with cache ───────────────────────────────
  Future<void> _safehavenNameEnquiry() async {
    if (accountNumberController.text.length != 10 || selectedBank == null) {
      showSimpleDialog(
        'Please enter valid account number and select a bank',
        Colors.red,
      );
      return;
    }

    final docId = '${selectedBank}_${accountNumberController.text}';
    final cached = await FirebaseFirestore.instance
        .collection('verified_accounts')
        .doc(docId)
        .get();
    if (cached.exists) {
      setState(() => accountNameController.text = cached.data()!['accountName']);
      return;
    }

    setState(() => isFetchingAccountName = true);
    try {
      final result = await callCloudFunctionLogged(
        'safehavenNameEnquiry',
        source: 'bank_transfer_page.dart',
        payload: {
          'accountNumber': accountNumberController.text,
          'bankIdOrBankCode': selectedBank,
        },
      );
      final accountName = result.data['data']['attributes']['accountName'];
      setState(() => accountNameController.text = accountName);
      await FirebaseFirestore.instance
          .collection('verified_accounts')
          .doc(docId)
          .set({
            'accountName': accountName,
            'verifiedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('safehavenNameEnquiry error: $e');
      showSimpleDialog('Error verifying account', Colors.red);
    }
    setState(() => isFetchingAccountName = false);
  }

  // ── Auto‑lookup from existing counterparties (cached) ─────────────
  Future<void> _autoLookupCounterparty(String accountNumber) async {
    if (accountNumber.length != 10) return;
    setState(() => isFetchingAccountName = true);
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('counterparties')
          .where('recipientAccountNumber', isEqualTo: accountNumber)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        String? bankId = data['recipientBankCode'] as String?;
        final accountName = data['data']?['attributes']?['accountName'] as String? ??
            data['attributes']?['accountName'] as String? ??
            data['accountName'] as String?;
        final bankName = data['bankName'] as String? ??
            data['data']?['attributes']?['bank']?['name'] as String?;

        if (bankId == null && bankName != null) {
          bankId = await _resolveBankIdByName(bankName);
        }

        if (bankId != null && accountName != null) {
          setState(() {
            selectedBank = bankId;
            selectedBankName = bankName;
            accountNameController.text = accountName;
          });
          setState(() => isFetchingAccountName = false);
          return;
        }
      }
    } catch (e) {
      debugPrint('_autoLookupCounterparty error: $e');
    }
    setState(() => isFetchingAccountName = false);
  }

  Future<String?> _resolveBankIdByName(String bankName) async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('banks')
          .where('name', isEqualTo: bankName)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.id;

      // Fallback: search loaded banks list
      for (final b in banks) {
        final bname = (b['attributes']['name'] as String? ?? '').toLowerCase();
        if (bname == bankName.toLowerCase()) return b['id'] as String;
      }
    } catch (e) {
      debugPrint('_resolveBankIdByName error: $e');
    }
    return null;
  }

  // ── Company VA (cached) ──────────────────────────────────────────
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
        'id': data['safehavenAccountId']?.toString() ?? data['accountId']?.toString() ?? '',
        'type': data['safehavenAccountType']?.toString() ?? data['accountType']?.toString() ?? '',
        'bankId': data['safehavenBankCode']?.toString() ?? data['bankId']?.toString() ?? '',
        'bankName': data['safehavenBankName']?.toString() ?? data['bankName']?.toString() ?? '',
        'accountNumber': data['safehavenAccountNumber']?.toString() ?? data['accountNumber']?.toString() ?? '',
        'accountName': data['safehavenAccountName']?.toString() ?? data['accountName']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('getCompanyVirtualAccount error: $e');
      return null;
    }
  }

  // ── Create counterparty (reuse) ──────────────────────────────────
  Future<void> _createCounterparty() async {
    if (accountNameController.text.isEmpty || selectedBank == null) {
      showToast('Please verify account details', Colors.red);
      return;
    }

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];
      final String? accountType = details['accountType'];

      String? resolvedBankId = selectedBank;
      if (resolvedBankId == null && selectedBankName != null) {
        resolvedBankId = await _resolveBankIdByName(selectedBankName!);
      }
      if (resolvedBankId == null) throw Exception('Bank ID not found');

      final existing = await FirebaseFirestore.instance
          .collection('counterparties')
          .where('userId', isEqualTo: user.uid)
          .where('recipientAccountNumber', isEqualTo: accountNumberController.text)
          .where('recipientBankCode', isEqualTo: resolvedBankId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        setState(() => counterpartyId = existing.docs.first.id);
        setState(() => isLoading = false);
        return;
      }

      final bank = banks.firstWhere((b) => b['id'] == resolvedBankId);
      final result = await callCloudFunctionLogged(
        'safehavenCreateCounterparty',
        source: 'bank_transfer_page.dart',
        payload: {
          'accountId': accountId,
          'bankId': resolvedBankId,
          'accountType': accountType,
          'accountName': accountNameController.text,
          'bankName': bank['attributes']['name'],
          'accountNumber': accountNumberController.text,
          'bankCode': resolvedBankId,
        },
      );
      final cpId = result.data['data']['id'];
      await FirebaseFirestore.instance.collection('counterparties').doc(cpId).set({
        ...result.data,
        'userId': user.uid,
        'recipientAccountNumber': accountNumberController.text,
        'recipientBankCode': resolvedBankId,
        'ownerAccountId': accountId,
      });
      setState(() => counterpartyId = cpId);
    } catch (e) {
      debugPrint('createCounterparty error: $e');
      showSimpleDialog('Error creating counterparty', Colors.red);
    }
    setState(() => isLoading = false);
  }

  // ── NIP Transfer (external) ──────────────────────────────────────
  Future<void> _safehavenTransferNip() async {
    if (counterpartyId == null || amountController.text.isEmpty) {
      showSimpleDialog('Please complete all fields', Colors.red);
      return;
    }
    final amountNaira = double.parse(amountController.text);
    if (!await _checkBalance(amountNaira)) return;

    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];
      final String? accountType = details['accountType'];

      final result = await callCloudFunctionLogged(
        'safehavenTransferNip',
        source: 'bank_transfer_page.dart',
        payload: {
          'accountType': accountType,
          'accountId': accountId,
          'counterpartyId': counterpartyId,
          'amount': amountNaira * 100,
          'currency': 'NGN',
          'narration': remarkController.text,
          'idempotencyKey': const Uuid().v4(),
        },
      );
      final status = result.data['data']['attributes']['status'];
      final failureReason = result.data['data']['attributes']['failureReason'];
      if (status == "FAILED") {
        showSimpleDialog('Transfer failed: $failureReason', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final bank = banks.cast<Map<String, dynamic>?>().firstWhere(
        (b) => b?['id'] == selectedBank,
        orElse: () => null,
      )!;
      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'type': 'transfer',
        'bank_code': selectedBank,
        'account_number': accountNumberController.text,
        'amount': amountNaira,
        'reason': remarkController.text,
        'currency': 'NGN',
        'api_response': result.data,
        'reference': result.data['data']['id'],
        'recipientName': accountNameController.text,
        'bankName': bank['attributes']['name'],
        'timestamp': FieldValue.serverTimestamp(),
      });

      showModalBottomSheet(
        context: context,
        builder: (context) => PaymentSuccessfulPage(
          amount: amountController.text,
          actionText: "Done",
          title: "Payment Successful",
          description: "Your transfer has been processed successfully.",
          recipientName: accountNameController.text,
          bankName: bank['attributes']['name'] ?? 'Unknown Bank',
          bankCode: selectedBank ?? '',
          accountNumber: accountNumberController.text,
          reference: result.data['data']['id'] ?? "",
        ),
        isScrollControlled: true,
      );
    } catch (e) {
      debugPrint('safehavenTransferNip error: $e');
      showSimpleDialog('Error processing transfer', Colors.red);
    }
    setState(() => isLoading = false);
  }

  // ── Ghost Transfer (anonymous) ───────────────────────────────────
  Future<void> _ghostTransfer() async {
    if (amountController.text.isEmpty ||
        accountNameController.text.isEmpty ||
        selectedBank == null) {
      showSimpleDialog(
        'Please complete all fields and verify account',
        Colors.red,
      );
      return;
    }
    final amountNaira = double.parse(amountController.text);
    if (!await _checkBalance(amountNaira)) return;

    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final details = await getCurrentAccountIdAndType();
      final String? userAccountId = details['accountId'];
      final String? userAccountType = details['accountType'];

      final companyVa = _cachedCompanyVa ?? await getCompanyVirtualAccount();
      if (companyVa == null || companyVa['id'].isEmpty) {
        throw Exception('Company account not found');
      }

      // 1️⃣ User → Company (INTRA transfer)
      final intraResult = await callCloudFunctionLogged(
        'safehavenTransferIntra',
        source: 'bank_transfer_page.dart',
        payload: {
          'fromAccountId': userAccountId,
          'toAccountId': companyVa['id'],
          'amount': (amountNaira + 50.0) * 100,
          'narration': 'Ghost Mode: ${remarkController.text.isNotEmpty ? remarkController.text : 'Transfer'}',
          'idempotencyKey': const Uuid().v4(),
        },
      );
      if (intraResult.data['data']['attributes']['status'] == 'FAILED') {
        showSimpleDialog(
          'Transfer to company failed: ${intraResult.data['data']['attributes']['failureReason']}',
          Colors.red,
        );
        setState(() => isLoading = false);
        return;
      }

      final recipientAccountNumber = accountNumberController.text;
      final recipientBankId = selectedBank;
      final recipientBank = banks.cast<Map<String, dynamic>?>().firstWhere(
        (b) => b?['id'] == selectedBank,
        orElse: () => null,
      )!;
      final recipientBankName = recipientBank['attributes']['name'] as String? ?? 'Unknown Bank';
      final recipientAccountName = accountNameController.text;

      String recipientCounterpartyId;
      final existingCp = await FirebaseFirestore.instance
          .collection('counterparties')
          .where('ownerAccountId', isEqualTo: companyVa['id'])
          .where('recipientAccountNumber', isEqualTo: recipientAccountNumber)
          .where('recipientBankCode', isEqualTo: recipientBankId)
          .limit(1)
          .get();
      if (existingCp.docs.isNotEmpty) {
        recipientCounterpartyId = existingCp.docs.first.id;
      } else {
        final cpResult = await callCloudFunctionLogged(
          'safehavenCreateCounterparty',
          source: 'bank_transfer_page.dart',
          payload: {
            'accountId': companyVa['id'],
            'bankId': recipientBankId,
            'accountType': companyVa['type'],
            'accountName': recipientAccountName,
            'bankName': recipientBankName,
            'accountNumber': recipientAccountNumber,
            'bankCode': recipientBankId,
          },
        );
        recipientCounterpartyId = cpResult.data['data']['id'];
        await FirebaseFirestore.instance
            .collection('counterparties')
            .doc(recipientCounterpartyId)
            .set({
              ...cpResult.data,
              'userId': companyVa['uid'],
              'recipientAccountNumber': recipientAccountNumber,
              'recipientBankCode': recipientBankId,
              'ownerAccountId': companyVa['id'],
            });
      }

      // 3️⃣ Company → Recipient (NIP transfer)
      final nipResult = await callCloudFunctionLogged(
        'safehavenTransferNip',
        source: 'bank_transfer_page.dart',
        payload: {
          'accountType': companyVa['type'],
          'accountId': companyVa['id'],
          'counterpartyId': recipientCounterpartyId,
          'amount': amountNaira * 100,
          'currency': 'NGN',
          'narration': remarkController.text.isNotEmpty ? remarkController.text : 'Ghost Mode Transfer',
          'idempotencyKey': const Uuid().v4(),
        },
      );
      if (nipResult.data['data']['attributes']['status'] == 'FAILED') {
        showSimpleDialog(
          'Transfer to recipient failed: ${nipResult.data['data']['attributes']['failureReason']}',
          Colors.red,
        );
        setState(() => isLoading = false);
        return;
      }

      await FirebaseFirestore.instance.collection('transactions').add({
        'actualSender': user.uid,
        'userId': user.uid,
        'type': 'ghost_transfer',
        'bank_code': recipientBankId,
        'account_number': recipientAccountNumber,
        'amount': amountNaira,
        'reason': remarkController.text,
        'currency': 'NGN',
        'api_response': nipResult.data,
        'reference': nipResult.data['data']['id'],
        'recipientName': recipientAccountName,
        'bankName': recipientBankName,
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
          bankName: recipientBankName,
          bankCode: recipientBankId ?? '',
          accountNumber: recipientAccountNumber,
          reference: nipResult.data['data']['id'] ?? "",
        ),
        isScrollControlled: true,
      );
    } catch (e) {
      debugPrint('ghostTransfer error: $e');
      showSimpleDialog('Error processing ghost transfer', Colors.red);
    }
    setState(() => isLoading = false);
  }

  // ── Recent transfers ─────────────────────────────────────────────
  Future<void> _loadRecentTransfers() async {
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
      final recents = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final acct = data['account_number']?.toString() ?? '';
        final bank = data['bank_code']?.toString() ?? '';
        if (acct.isEmpty) continue;
        final key = '${acct}_$bank';
        if (!seen.contains(key)) {
          seen.add(key);
          recents.add(data);
          if (recents.length >= 10) break;
        }
      }
      if (mounted) setState(() => _recentTransfers = recents);
    } catch (e) {
      debugPrint('loadRecentTransfers error: $e');
    }
    if (mounted) setState(() => _loadingRecents = false);
  }

  // ── Scan from image ──────────────────────────────────────────────
  Future<void> _onScanAccountImage() async {
    final result = await scanAccountFromImage(context);
    if (result == null) return;
    if (result.accountNumber != null && result.accountNumber!.isNotEmpty) {
      setState(() => accountNumberController.text = result.accountNumber!);
    }
    if (result.bankName != null &&
        result.bankName!.isNotEmpty &&
        banks.isNotEmpty) {
      final bankNameLower = result.bankName!.toLowerCase();
      final matched = banks.cast<Map<String, dynamic>?>().firstWhere(
        (b) => (b!['attributes']['name'] as String).toLowerCase().contains(bankNameLower) ||
            bankNameLower.contains((b['attributes']['name'] as String).toLowerCase()),
        orElse: () => null,
      );
      if (matched != null) {
        setState(() {
          selectedBank = matched['id'] as String;
          selectedBankName = matched['attributes']['name'] as String;
        });
      }
    }
    if (accountNumberController.text.length == 10) {
      _autoLookupCounterparty(accountNumberController.text);
      if (selectedBank != null) _safehavenNameEnquiry();
    }
  }

  void _updateFee() {
    final amount = double.tryParse(amountController.text) ?? 0.0;
    setState(() {
      feeText = amount > 0 ? "Fee: ₦50.00" : "";
    });
  }

  // ── Lifecycle ────────────────────────────────────────────────────
  @override
  void dispose() {
    amountController.removeListener(_updateFee);
    amountController.dispose();
    accountNumberController.dispose();
    remarkController.dispose();
    accountNameController.dispose();
    super.dispose();
  }

  // ── UI ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
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
                          child: const Icon(Icons.arrow_back_ios, color: Colors.black87, size: 20),
                        ),
                        const Spacer(),
                        const Text(
                          "Bank Transfer",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 30),
                    if (_currentPage == 0) ...[
                      const Text('Beneficiary Account Number'),
                      const SizedBox(height: 8),
                      TextField(
                        maxLength: 10,
                        controller: accountNumberController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [LengthLimitingTextInputFormatter(10)],
                        decoration: InputDecoration(
                          counterText: "",
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          hintText: 'Account number',
                          suffixIcon: IconButton(
                            tooltip: 'Scan account details from photo',
                            icon: const Icon(Icons.camera_alt_outlined),
                            onPressed: _onScanAccountImage,
                          ),
                        ),
                        onChanged: (value) {
                          if (value.length == 10) {
                            _autoLookupCounterparty(value);
                            if (selectedBank != null) _safehavenNameEnquiry();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Beneficiary Bank'),
                      const SizedBox(height: 8),
                      isFetchingBanks
                          ? Center(child: CircularProgressIndicator(color: primaryColor))
                          : DropdownSearch<String>(
                              popupProps: PopupProps.menu(
                                menuProps: const MenuProps(backgroundColor: Colors.white),
                                searchFieldProps: TextFieldProps(
                                  decoration: InputDecoration(
                                    hintText: "Search bank...",
                                    hintStyle: const TextStyle(fontSize: 14),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                                showSearchBox: true,
                                fit: FlexFit.loose,
                                constraints: BoxConstraints(
                                  maxHeight: 300,
                                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                                ),
                                itemBuilder: (context, item, isDisabled, isSelected) =>
                                    ListTile(title: Text(item, overflow: TextOverflow.ellipsis, maxLines: 1)),
                              ),
                              items: (filter, _) async => banks
                                  .where((b) => (b['attributes']['name'] as String)
                                      .toLowerCase()
                                      .contains(filter.toLowerCase()))
                                  .map((b) => b['attributes']['name'] as String)
                                  .toList(),
                              decoratorProps: DropDownDecoratorProps(
                                decoration: InputDecoration(
                                  hintText: "Select Bank",
                                  hintStyle: TextStyle(color: Colors.grey.shade600),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  selectedBank = banks.firstWhere((b) => b['attributes']['name'] == value)['id'];
                                  selectedBankName = value;
                                  if (accountNumberController.text.length == 10) _safehavenNameEnquiry();
                                });
                              },
                              selectedItem: selectedBank != null
                                  ? banks
                                      .cast<Map<String, dynamic>?>()
                                      .firstWhere((b) => b?['id'] == selectedBank, orElse: () => null)
                                      ?['attributes']?['name'] as String?
                                  : null,
                            ),
                      const SizedBox(height: 16),
                      if (isFetchingAccountName || accountNameController.text.isNotEmpty) ...[
                        const Text('Account Name'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: accountNameController,
                          enabled: false,
                          decoration: InputDecoration(
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            hintText: 'Account name',
                            suffixIcon: isFetchingAccountName
                                ? Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: accountNumberController.text.length == 10 &&
                                selectedBank != null &&
                                accountNameController.text.isNotEmpty
                            ? () => setState(() => _currentPage = 1)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Next', style: TextStyle(color: Colors.white)),
                      ),
                    ] else if (_currentPage == 1) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: primaryColor.withValues(alpha: 0.12),
                              child: Text(
                                accountNameController.text
                                    .split(' ')
                                    .where((s) => s.isNotEmpty)
                                    .take(2)
                                    .map((s) => s[0].toUpperCase())
                                    .join(),
                                style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(accountNameController.text,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  Text(
                                    '${accountNumberController.text} · ${_getBankName()}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Row(
                          children: [
                            const Text('₦', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: amountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
  isDense: true,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  contentPadding: EdgeInsets.zero,
  hintText: '0.00',
),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ),
                            Text(feeText, style: GoogleFonts.inter(color: primaryColor, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
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
                            onTap: () => setState(() => amountController.text = amt.toString()),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              alignment: Alignment.center,
                              child: Text('₦$fmtAmt', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          hintText: 'Enter Remark',
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Ghost Mode", style: GoogleFonts.inter(color: Colors.black26)),
                              const SizedBox(height: 5),
                              Text("Send money anonymously",
                                  style: GoogleFonts.inter(color: Colors.black54, fontWeight: FontWeight.w600)),
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
                            onToggle: (val) => setState(() => sendAnonymously = val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isLoading || (double.tryParse(amountController.text) ?? 0.0) <= 0
                            ? null
                            : () async {
                                if (sendAnonymously) {
                                  await _ghostTransfer();
                                } else {
                                  await _createCounterparty();
                                  await _safehavenTransferNip();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Confirm', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              ),
              if (_currentPage == 0 && _recentTransfers.isNotEmpty)
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
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: Text('Recents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _recentTransfers.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: Colors.grey.shade100,
                          ),
                          itemBuilder: (context, index) {
                            final r = _recentTransfers[index];
                            final name = r['recipientName']?.toString() ?? 'Unknown';
                            final acct = r['account_number']?.toString() ?? '';
                            final bank = r['bankName']?.toString() ?? '';
                            final alias = _aliases
                                .where((a) => a.type == 'account' && a.accountNumber == acct)
                                .firstOrNull;
                            final initials = name
                                .split(' ')
                                .where((s) => s.isNotEmpty)
                                .take(2)
                                .map((s) => s[0].toUpperCase())
                                .join();
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: CircleAvatar(
                                backgroundColor: primaryColor.withValues(alpha: 0.12),
                                child: Text(
                                  initials,
                                  style: GoogleFonts.inter(
                                    color: primaryColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (alias != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '~${alias.alias}',
                                        style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                '$acct · $bank',
                                style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 12),
                              ),
                              onTap: () {
                                final bankCode = r['bank_code']?.toString();
                                final bankNameFromRecent = r['bankName']?.toString();

                                setState(() {
                                  accountNumberController.text = acct;
                                  accountNameController.text = name;

                                  if (bankCode != null && bankCode.isNotEmpty) {
                                    final matchedBank = banks
                                        .cast<Map<String, dynamic>?>()
                                        .firstWhere((b) => b?['id'] == bankCode, orElse: () => null);
                                    if (matchedBank != null && matchedBank['id'] != null) {
                                      selectedBank = bankCode;
                                    } else if (bankNameFromRecent != null && bankNameFromRecent.isNotEmpty) {
                                      final nameMatched = banks
                                          .cast<Map<String, dynamic>?>()
                                          .firstWhere(
                                            (b) => (b?['attributes']?['name'] as String? ?? '')
                                                    .toLowerCase() ==
                                                bankNameFromRecent.toLowerCase(),
                                            orElse: () => null,
                                          );
                                      if (nameMatched != null) {
                                        selectedBank = nameMatched['id'] as String?;
                                      }
                                    }
                                  }

                                  _currentPage = 1;
                                });

                                Future.delayed(const Duration(milliseconds: 100), () {
                                  if (acct.length == 10 && selectedBank != null && mounted) {
                                    _safehavenNameEnquiry();
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getBankName() {
    if (selectedBank == null || banks.isEmpty) return 'Unknown Bank';
    final bank = banks.cast<Map<String, dynamic>?>()
        .firstWhere((b) => b?['id'] == selectedBank, orElse: () => null);
    if (bank == null) return 'Unknown Bank';
    final name = (bank['attributes']?['name'] as String?)?.trim();
    return (name?.isNotEmpty == true) ? name! : 'Unknown Bank';
  }
}