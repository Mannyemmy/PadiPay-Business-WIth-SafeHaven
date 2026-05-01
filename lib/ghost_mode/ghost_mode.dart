import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:padi_pay_business/success_page.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:uuid/uuid.dart';

class GhostModeTransfer extends StatefulWidget {
  const GhostModeTransfer({super.key});

  @override
  State<GhostModeTransfer> createState() => _GhostModeTransferState();
}

class _GhostModeTransferState extends State<GhostModeTransfer> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController accountNumberController = TextEditingController();
  final TextEditingController remarkController = TextEditingController();
  final TextEditingController accountNameController = TextEditingController();
  String? selectedBank;
  List<Map<String, dynamic>> banks = [];
  bool isLoading = false;
  bool isFetchingBanks = false;
  String feeText = "Fee: ₦50.00";

  Future<Map<String, String?>> getCurrentAccountIdAndType() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return {'accountId': null, 'accountType': null, 'bankId': null};
    }

    // 1. Check business first
    final DocumentSnapshot<Map<String, dynamic>> busSnap =
        await FirebaseFirestore.instance
            .collection('businesses')
            .doc(uid)
            .get();

    if (busSnap.exists && busSnap.data() != null) {
      final data = busSnap.data()!;
      final String kycStatus = data['kycStatus'] ?? '';

      if (kycStatus == 'APPROVED') {
        final Map<String, dynamic>? virtualAccData =
            data['sudoData']?['virtualAccount']?['data']
                as Map<String, dynamic>?;

        if (virtualAccData != null && virtualAccData['id'] != null) {
          final bankMap =
              virtualAccData['attributes']?['bank'] as Map<String, dynamic>?;
          final String? bankId = bankMap?['id'] as String?;

          return {
            'accountId': virtualAccData['id'] as String,
            'accountType': virtualAccData['type'] as String?,
            'bankId': bankId,
          };
        }
      }
    }

    // 2. Fallback to personal account
    final DocumentSnapshot<Map<String, dynamic>> userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (userSnap.exists && userSnap.data() != null) {
      final data = userSnap.data()!;
      final Map<String, dynamic>? virtualAccData =
          data['sudoData']?['virtualAccount']?['data']
              as Map<String, dynamic>?;

      if (virtualAccData != null && virtualAccData['id'] != null) {
        final bankMap =
            virtualAccData['attributes']?['bank'] as Map<String, dynamic>?;
        final String? bankId = bankMap?['id'] as String?;

        return {
          'accountId': virtualAccData['id'] as String,
          'accountType': virtualAccData['type'] as String?,
          'bankId': bankId,
        };
      }
    }

    return {'accountId': null, 'accountType': null, 'bankId': null};
  }

  @override
  void initState() {
    super.initState();
    _fetchBanks();
    amountController.addListener(_updateFee);
  }

  void _updateFee() {
    final amount = double.tryParse(amountController.text) ?? 0.0;
    final fee = amount > 0 ? 50.0 : 0.0;
    setState(() {
      feeText = "Fee: ₦${fee.toStringAsFixed(2)}";
    });
  }

  Future<void> _fetchBanks() async {
    setState(() => isFetchingBanks = true);
    try {
      final snapshot = await FirebaseFirestore.instance.collection('banks').get();
      List<Map<String, dynamic>> bankList = [];
      for (var doc in snapshot.docs) {
        bankList.add({
          'id': doc.id,
          'attributes': {'name': doc.data()['name']},
        });
      }
      if (bankList.isEmpty) {
        final result = await callCloudFunctionLogged('sudoBankList', source: 'business_app');
        final data = result.data as Map<String, dynamic>;
        final apiBankList = data['data'] as List<dynamic>;
        final batch = FirebaseFirestore.instance.batch();
        for (var item in apiBankList) {
          final map = item as Map;
          final docRef = FirebaseFirestore.instance.collection('banks').doc(map['id'].toString());
          batch.set(docRef, {
            'name': (map['attributes'] as Map)['name']?.toString(),
          });
        }
        await batch.commit();
        // Reload from Firestore after saving
        final newSnapshot = await FirebaseFirestore.instance.collection('banks').get();
        for (var doc in newSnapshot.docs) {
          bankList.add({
            'id': doc.id,
            'attributes': {'name': doc.data()['name']},
          });
        }
      }
      setState(() {
        banks = bankList;
        isFetchingBanks = false;
      });
    } catch (e) {
      debugPrint('sudoBankList error: $e');
      showToast('Error fetching banks', Colors.red);
      setState(() => isFetchingBanks = false);
    }
  }

  Future<void> _sudoNameEnquiry() async {
    if (accountNumberController.text.length != 10 || selectedBank == null) {
      showToast(
        'Please enter valid account number and select a bank',
        Colors.red,
      );
      return;
    }

    final docId = '${selectedBank}_${accountNumberController.text}';
    final doc = await FirebaseFirestore.instance.collection('verified_accounts').doc(docId).get();

    if (doc.exists) {
      setState(() {
        accountNameController.text = doc.data()!['accountName'];
      });
      return;
    }

    setState(() => isLoading = true);
    try {
      final result = await callCloudFunctionLogged('sudoNameEnquiry', source: 'business_app', payload: {
            'accountNumber': accountNumberController.text,
            'bankIdOrBankCode': selectedBank,
          });
      final accountName = result.data['data']['attributes']['accountName'];
      setState(() {
        accountNameController.text = accountName;
      });
      await FirebaseFirestore.instance.collection('verified_accounts').doc(docId).set({
        'accountName': accountName,
        'verifiedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('sudoNameEnquiry error: $e');
      showToast('Error verifying account', Colors.red);
    }
    setState(() => isLoading = false);
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

  Future<void> _sudoTransferNip() async {
    final accountName = accountNameController.text;
    final selectedBankValue = selectedBank;
    final amountText = amountController.text;
    if (accountName.isEmpty ||
        selectedBankValue == null ||
        amountText.isEmpty) {
      showToast('Please complete and verify all fields', Colors.red);
      return;
    }
    final amountNaira = double.tryParse(amountText);
    if (amountNaira == null || amountNaira <= 0) {
      showToast('Please enter a valid amount', Colors.red);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showToast('No authenticated user found', Colors.red);
      return;
    }

    setState(() => isLoading = true);
    try {
      final details = await getCurrentAccountIdAndType();
      final String userAccountId = details['accountId'] ?? '';
      final String userAccountType = details['accountType'] ?? '';
      final String userBankId = details['bankId'] ?? '';

      if (userAccountId.isEmpty ||
          userAccountType.isEmpty ||
          userBankId.isEmpty) {
        showToast('User account details not found', Colors.red);
        return;
      }

      final companyVa = await getCompanyVirtualAccount();
      if (companyVa == null ||
          companyVa['id'].isEmpty ||
          companyVa['type'].isEmpty ||
          companyVa['bankId'].isEmpty ||
          companyVa['accountNumber'].isEmpty) {
        showToast('Company account not found', Colors.red);
        setState(() {
          isLoading = false;
        });
        return;
      }

      final recipientAccountNumber = accountNumberController.text;
      final recipientBankId = selectedBank;
      final recipientBank = banks.firstWhere(
        (b) => b['id'] == selectedBank,
      );
      final recipientBankName = recipientBank['attributes']['name'];

      // First transfer: user to company (book transfer — both on Sudo)
      final fee = 50.0;
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
        showToast(
          'Transfer to company failed: $firstFailureReason',
          Colors.red,
        );
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
              'accountName': accountName,
              'bankName': recipientBankName,
              'accountNumber': accountNumberController.text,
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
        showToast(
          'Transfer to recipient failed: $secondFailureReason',
          Colors.red,
        );
        return;
      }

      // Log transaction (for the final transfer)
      await FirebaseFirestore.instance.collection('transactions').add({
        'actualSender': user.uid,
        'userId': companyVa['uid'],
        'type': 'ghost_transfer',
        'bank_code': selectedBank,
        'account_number': accountNumberController.text,
        'amount': amountNaira,
        'reason': remarkController.text,
        'currency': 'NGN',
        'api_response': secondResult.data,
        'reference': secondResult.data['data']['id'],
        'recipientName': accountName,
        'bankName': recipientBankName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      showModalBottomSheet(
        context: context,
        builder: (context) => const SuccessBottomSheet(
          actionText: "Done",
          title: "Transfer Successful",
          description: "Your transfer has been processed successfully.",
        ),
        isScrollControlled: true,
      );
    } catch (e) {
      print('sudoTransferNip error: $e');
      showToast('Error processing transfer', Colors.red);
    }
    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    amountController.removeListener(_updateFee);
    amountController.dispose();
    accountNumberController.dispose();
    remarkController.dispose();
    accountNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(
        255,
        67,
        66,
        66,
      ).withValues(alpha: 0.2),
      body: SafeArea(bottom: true,
        child: Stack(
          children: [
            SizedBox.expand(child: Image.asset("assets/mdi_anonymous.png")),
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop();
                          },
                          child: const Icon(
                            Icons.arrow_back_ios,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          "Ghost Mode",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w300,
                            ),
                            "Your account details will be kept confidential and not shared with the recipient.",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      'Beneficiary Account Number',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      maxLength: 10,
                      controller: accountNumberController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [LengthLimitingTextInputFormatter(10)],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w100,
                      ),
                      decoration: InputDecoration(
                        counterText: "",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: 'Account number',
                        hintStyle: const TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w100,
                        ),
                      ),
                      onChanged: (value) {
                        if (value.length == 10 && selectedBank != null) {
                          _sudoNameEnquiry();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Account Name',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: accountNameController,
                      enabled: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w100,
                      ),
                      decoration: InputDecoration(
                        hintStyle: const TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w100,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: 'Account name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Beneficiary Bank',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
                    const SizedBox(height: 8),
                    isFetchingBanks
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          )
                        : DropdownSearch<String>(
                            popupProps: PopupProps.menu(
                              menuProps: const MenuProps(
                                backgroundColor: Color.fromARGB(
                                  255,
                                  67,
                                  66,
                                  66,
                                ),
                              ),
                              searchFieldProps: TextFieldProps(
                                decoration: InputDecoration(
                                  hintText: "Search bank...",
                                  hintStyle: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white54,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(8),
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                style: TextStyle(color: Colors.white),
                              ),
                              showSearchBox: true,
                              fit: FlexFit.loose,
                              constraints: BoxConstraints(maxHeight: 300),
                              itemBuilder:
                                  (context, item, isDisabled, isSelected) {
                                    return ListTile(
                                      title: Text(
                                        item,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    );
                                  },
                            ),
                            items: (filter, _) async {
                              return banks
                                  .where(
                                    (bank) =>
                                        ((bank['attributes'] as Map?)?['name']
                                                    as String? ??
                                                '')
                                            .toLowerCase()
                                            .contains(filter.toLowerCase()),
                                  )
                                  .map(
                                    (bank) =>
                                        (bank['attributes'] as Map?)?['name']
                                            as String? ??
                                        '',
                                  )
                                  .toList();
                            },
                            decoratorProps: DropDownDecoratorProps(
                              decoration: InputDecoration(
                                // hintText: "Select Bank",
                                hintStyle: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w100,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                suffixIcon: Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            dropdownBuilder: (context, selectedItem) {
                              return Text(
                                selectedItem ?? "Select Bank",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              );
                            },
                            onChanged: (value) {
                              setState(() {
                                selectedBank =
                                    banks.firstWhere(
                                          (b) =>
                                              ((b['attributes']
                                                      as Map?)?['name']
                                                  as String?) ==
                                              value,
                                        )['id']
                                        as String?;
                                if (accountNumberController.text.length == 10) {
                                  _sudoNameEnquiry();
                                }
                              });
                            },
                            selectedItem: selectedBank != null
                                ? ((banks.firstWhere(
                                            (b) => b['id'] == selectedBank,
                                            orElse: () => <String, dynamic>{
                                              'attributes': <String, dynamic>{
                                                'name': '',
                                              },
                                            },
                                          )['attributes']
                                          as Map?)?['name']
                                      as String?)
                                : null,
                          ),
                    const SizedBox(height: 16),
                    const Text(
                      'Amount to Send',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
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
                          Expanded(
                            child: TextField(
                              controller: amountController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w100,
                              ),
                              decoration: InputDecoration(
                                hintStyle: const TextStyle(
                                  color: Colors.white54,
                                  fontWeight: FontWeight.w100,
                                ),
                                border: InputBorder.none,
                                hintText: '₦0.00',
                              ),
                            ),
                          ),
                          Text(
                            feeText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Remark',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: remarkController,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w100,
                      ),
                      decoration: InputDecoration(
                        hintStyle: const TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w100,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: 'Enter Remark',
                      ),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              await _sudoTransferNip();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Send',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}