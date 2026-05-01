import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/payment_successful_page.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:uuid/uuid.dart';
class WithdrawForCustomerPage extends StatefulWidget {
  const WithdrawForCustomerPage({super.key});
  @override
  State<WithdrawForCustomerPage> createState() =>
      _WithdrawForCustomerPageState();
}
class _WithdrawForCustomerPageState extends State<WithdrawForCustomerPage> {
  bool isTagMode = true;
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController accountNumberController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController remarkController = TextEditingController();
  List<Map<String, dynamic>> banks = [];
  String? selectedBank;
  String? selectedBankName;
  bool isLoading = false;
  bool isResolving = false;
  bool isValid = false;
  bool isFetchingBanks = false;
  Map<String, dynamic>? recipientInfo;
  String resolvedAccountName = '';
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _fetchBanks();
    usernameController.addListener(_debounceResolve);
    accountNumberController.addListener(_onAccountNumberChanged);
    amountController.addListener(() {
      setState(() {});
    });
  }
  void _debounceResolve() {
    _debounce?.cancel();
    if (isTagMode) {
      _debounce = Timer(const Duration(milliseconds: 1000), _resolveByTag);
    }
  }
  void _onAccountNumberChanged() {
    final value = accountNumberController.text;
    if (!isTagMode) {
      if (value.length == 10 && selectedBank != null) {
        _resolveByAccount();
      } else if (value.length != 10) {
        setState(() {
          recipientInfo = null;
          isValid = false;
          resolvedAccountName = '';
        });
      }
    }
  }
  Future<void> _fetchBanks() async {
    setState(() => isFetchingBanks = true);
    try {
      var snapshot = await FirebaseFirestore.instance.collection('banks').get();
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
          final docRef = FirebaseFirestore.instance
              .collection('banks')
              .doc(map['id'].toString());
          batch.set(docRef, {
            'name': (map['attributes'] as Map)['name']?.toString(),
          });
        }
        await batch.commit();
        snapshot = await FirebaseFirestore.instance.collection('banks').get();
        for (var doc in snapshot.docs) {
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
      setState(() => isFetchingBanks = false);
    }
  }
  void _showBankBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String searchText = '';
        return StatefulBuilder(
          builder: (context, setState) {
            final filteredBanks = banks.where((bank) {
              return (bank['attributes']['name'] as String)
                  .toLowerCase()
                  .contains(searchText.toLowerCase());
            }).toList();
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        onChanged: (value) {
                          setState(() => searchText = value);
                        },
                        decoration: InputDecoration(
                          hintText: "Search bank...",
                          hintStyle: const TextStyle(fontSize: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          suffixIcon: const Icon(Icons.search),
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredBanks.length,
                        itemBuilder: (context, index) {
                          final bank = filteredBanks[index];
                          return ListTile(
                            title: Text(
                              bank['attributes']['name'] as String,
                              style: const TextStyle(fontSize: 14),
                            ),
                            onTap: () {
                              setState(() {
                                selectedBank = bank['id'] as String;
                                selectedBankName =
                                    bank['attributes']['name'] as String;
                                if (accountNumberController.text.length == 10) {
                                  _resolveByAccount();
                                }
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  String _normalizeTag(String tag) {
    return tag.toLowerCase().replaceAll(' ', '_');
  }
  Future<void> _resolveByTag() async {
    String inputTag = usernameController.text.trim();
    String normalizedInput = _normalizeTag(inputTag);
    debugPrint(
      'Entry for resolution: "$inputTag" (normalized: "$normalizedInput")',
    );
    if (inputTag.isEmpty) {
      setState(() {
        recipientInfo = null;
        isValid = false;
        resolvedAccountName = '';
        isResolving = false;
      });
      return;
    }
    setState(() => isResolving = true);
    try {
      Map<String, dynamic>? info;
      String? errorMessage;
      // Query users first via usernames public index
      final usernameDoc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(normalizedInput)
          .get();
      debugPrint(
        'Username lookup for "$normalizedInput" exists: ${usernameDoc.exists}',
      );
      if (usernameDoc.exists) {
        final uid = (usernameDoc.data() ?? {})['uid'] as String?;
        if (uid != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          if (userDoc.exists) {
            final data = userDoc.data();
            debugPrint('Found user $uid, userName: ${data?['userName']}');
            final vaData = data?['sudoData']?['virtualAccount']?['data'];
            if (vaData != null) {
              info = {'uid': uid, 'data': data, 'collection': 'users'};
            } else {
              errorMessage = 'Recipient does not have virtual account setup';
            }
          }
        }
      }
      if (info == null && errorMessage == null) {
        // Query businesses by fetching all and filtering client-side
        debugPrint('No user match, checking businesses...');
        final busSnapshot = await FirebaseFirestore.instance
            .collection('businesses')
            .get();
        debugPrint('Businesses collection has ${busSnapshot.docs.length} docs');
        for (var doc in busSnapshot.docs) {
          final data = doc.data();
          final businessName = data['business_data']?['name'] ?? '';
          final normalizedBusinessName = _normalizeTag(businessName);
          debugPrint(
            'Business ${doc.id}: original "$businessName" (normalized: "$normalizedBusinessName")',
          );
          if (normalizedBusinessName == normalizedInput) {
            final vaData = data['sudoData']?['virtualAccount']?['data'];
            if (vaData != null) {
              info = {'uid': doc.id, 'data': data, 'collection': 'businesses'};
              debugPrint('Matched business ${doc.id}');
              break;
            } else {
              errorMessage = 'Recipient does not have virtual account setup';
              break;
            }
          }
        }
        if (info == null && errorMessage == null) {
          errorMessage = 'Username not found';
          // Log all for debugging if no match
          debugPrint('No business match found, logging all business names:');
          for (var doc in busSnapshot.docs) {
            final data = doc.data();
            final bname = data['business_data']?['name'] ?? 'null';
            final normBname = _normalizeTag(bname);
            debugPrint('Business ${doc.id}: "$bname" (norm: "$normBname")');
          }
        }
      }
      if (info != null) {
        final data = info['data'];
        final vaData = data['sudoData']?['virtualAccount']?['data'];
        final attributes = vaData?['attributes'] as Map<String, dynamic>? ?? {};
        String displayName;
        if (info['collection'] == 'users') {
          displayName =
              attributes['accountName'] as String? ??
              data['displayName'] ??
              inputTag;
        } else {
          displayName =
              attributes['accountName'] as String? ??
              data['business_data']?['name'] ??
              inputTag;
        }
        setState(() {
          recipientInfo = info;
          isValid = true;
          resolvedAccountName = displayName;
        });
      } else {
        setState(() {
          recipientInfo = null;
          isValid = false;
          resolvedAccountName = '';
        });
        if (errorMessage != null) {
          showToast(errorMessage, Colors.red);
        }
      }
    } catch (e) {
      debugPrint('Error resolving tag: $e');
      showToast('Error checking tag', Colors.red);
      setState(() {
        recipientInfo = null;
        isValid = false;
        resolvedAccountName = '';
      });
    }
    setState(() => isResolving = false);
  }
  Future<Map<String, dynamic>?> _getRecipientInfoByAccount(
    String accNum,
    String bankId,
  ) async {
    // Query users
    final userQuery = await FirebaseFirestore.instance
        .collection('users')
        .where(
          'sudoData.virtualAccount.data.attributes.accountNumber',
          isEqualTo: accNum,
        )
        .where(
          'sudoData.virtualAccount.data.attributes.bank.id',
          isEqualTo: bankId,
        )
        .limit(1)
        .get();
    if (userQuery.docs.isNotEmpty) {
      final doc = userQuery.docs.first;
      final data = doc.data();
      final vaData = data['sudoData']?['virtualAccount']?['data'];
      if (vaData != null) {
        return {'uid': doc.id, 'data': data, 'collection': 'users'};
      }
    }
    // Query businesses
    final busQuery = await FirebaseFirestore.instance
        .collection('businesses')
        .where(
          'sudoData.virtualAccount.data.attributes.accountNumber',
          isEqualTo: accNum,
        )
        .where(
          'sudoData.virtualAccount.data.attributes.bank.id',
          isEqualTo: bankId,
        )
        .limit(1)
        .get();
    if (busQuery.docs.isNotEmpty) {
      final doc = busQuery.docs.first;
      final data = doc.data();
      if (data['kycStatus'] == 'APPROVED') {
        return {'uid': doc.id, 'data': data, 'collection': 'businesses'};
      }
    }
    return null;
  }
  Future<void> _resolveByAccount() async {
    final accNum = accountNumberController.text;
    final bankId = selectedBank;
    if (accNum.length != 10 || bankId == null) return;
    setState(() => isResolving = true);
    try {
      final info = await _getRecipientInfoByAccount(accNum, bankId);
      setState(() {
        recipientInfo = info;
        isValid = info != null;
        if (info != null) {
          final data = info['data'];
          final vaData = data['sudoData']?['virtualAccount']?['data'];
          final attributes =
              vaData?['attributes'] as Map<String, dynamic>? ?? {};
          resolvedAccountName =
              attributes['accountName'] as String? ??
              data['displayName'] ??
              accNum;
        } else {
          resolvedAccountName = '';
        }
        isResolving = false;
      });
      if (info == null) {
        showToast(
          'Account not found or not KYC approved in our system',
          Colors.red,
        );
      }
    } catch (e) {
      debugPrint('Error resolving account: $e');
      showToast('Error resolving account', Colors.red);
      setState(() {
        recipientInfo = null;
        isValid = false;
        resolvedAccountName = '';
        isResolving = false;
      });
    }
  }
  Future<Map<String, dynamic>> getCurrentAccountDetails() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return {};
    }
    // Check business first
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
          final attributes =
              virtualAccData['attributes'] as Map<String, dynamic>? ?? {};
          final bankMap = attributes['bank'] as Map<String, dynamic>? ?? {};
          String? bankId = bankMap['id'] as String?;
          final String? bankName = bankMap['name'] as String?;
          if ((bankId == null || bankId.isEmpty) && bankName != null && bankName.isNotEmpty) {
            final resolved = await resolveBankIdByName(bankName);
            if (resolved != null) {
              bankId = resolved;
              debugPrint('Resolved initiator bankId by name: $bankId');
            }
          }
          return {
            'accountId': virtualAccData['id'] as String,
            'accountType': virtualAccData['type'] as String?,
            'bankId': bankId,
            'accountNumber': attributes['accountNumber'] as String?,
            'accountName': attributes['accountName'] as String?,
            'bankName': bankName,
          };
        }
      }
    }
    // Fallback to personal
    final DocumentSnapshot<Map<String, dynamic>> userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (userSnap.exists && userSnap.data() != null) {
      final data = userSnap.data()!;
      final Map<String, dynamic>? virtualAccData =
          data['sudoData']?['virtualAccount']?['data']
              as Map<String, dynamic>?;
      if (virtualAccData != null && virtualAccData['id'] != null) {
        final attributes =
            virtualAccData['attributes'] as Map<String, dynamic>? ?? {};
        final bankMap = attributes['bank'] as Map<String, dynamic>? ?? {};
        return {
          'accountId': virtualAccData['id'] as String,
          'accountType': virtualAccData['type'] as String?,
          'bankId': bankMap['id'] as String?,
          'accountNumber': attributes['accountNumber'] as String?,
          'accountName': attributes['accountName'] as String?,
          'bankName': bankMap['name'] as String?,
        };
      }
    }
    return {};
  }
  Future<double> fetchCurrentBalance() async {
    // Use centralized utils helper which resolves the current account (including
    // stand accounts) and fetches the balance.
    final balance = await fetchCurrentAccountBalance();
    return balance;
  }
  Future<String> _getInitiatorName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Unknown';
    // Assume business app, check businesses first
    final busSnap = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(user.uid)
        .get();
    if (busSnap.exists && busSnap.data() != null) {
      return busSnap.data()!['business_data']?['name'] ?? 'Unknown';
    }
    // Fallback to users
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (userSnap.exists && userSnap.data() != null) {
      return userSnap.data()!['displayName'] ?? 'Unknown';
    }
    return 'Unknown';
  }
  Future<void> _initiateWithdrawal() async {
    setState(() {
      isLoading = true;
    });
    final amountText = amountController.text;
    if (amountText.isEmpty) {
      showToast('Please enter amount', Colors.red);
      setState(() {
        isLoading = false;
      });
      return;
    }
    final amountNaira = double.tryParse(amountText);
    if (amountNaira == null || amountNaira <= 0 || amountNaira > 500000) {
      showToast('Amount must be between ₦1 and ₦500,000', Colors.red);
      setState(() {
        isLoading = false;
      });
      return;
    }
    if (recipientInfo == null || !isValid) {
      showToast('Please select a valid user', Colors.red);
      setState(() {
        isLoading = false;
      });
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showToast('No authenticated user found', Colors.red);
      setState(() {
        isLoading = false;
      });
      return;
    }
    try {
      final balance = await fetchCurrentBalance();
      print(balance);
      if (balance < amountNaira) {
        showToast('Insufficient balance in customer account.', Colors.red);
         setState(() {
      isLoading=false;
    });
        return;
      }
    } catch (e) {
      print(e);
   // showToast('Error checking balance: $e', Colors.red);
       setState(() {
      isLoading=false;
    });
      return;
    }
    // Pre-fetch initiator details and compute recipient name
    final initiatorDetails = await getCurrentAccountDetails();
    if (initiatorDetails['accountId'] == null) {
      showToast('Your account details not found', Colors.red);
      return;
    }
    final recipientData = recipientInfo!['data'];
    final recipientVaData =
        recipientData['sudoData']?['virtualAccount']?['data'];
    final recipientAttributes =
        recipientVaData?['attributes'] as Map<String, dynamic>? ?? {};
    final recipientAccountName =
        recipientAttributes['accountName'] as String? ?? '';
    final recipientBank = recipientAttributes['bank'] as Map<String, dynamic>? ?? {};
    final recipientBankName = recipientBank['name'] as String? ?? '';
    final recipientBankCode = recipientBank['id'] as String? ?? '';
    final recipientAccountNumber = recipientAttributes['accountNumber'] as String? ?? '';
    final initiatorName = await _getInitiatorName();
    setState(() => isLoading = true);
    String? requestId;
    try {
      requestId = const Uuid().v4();
      final pin = (1000 + Random().nextInt(9000)).toString().padLeft(4, '0');
      final now = DateTime.now();
      await FirebaseFirestore.instance
          .collection('pending_withdrawals')
          .doc(requestId)
          .set({
            'requestId': requestId,
            'initiatorUid': user.uid,
            'initiatorDetails': initiatorDetails,
            'initiatorName': initiatorName,
            'recipientUid': recipientInfo!['uid'],
            'recipientCollection': recipientInfo!['collection'],
            'amount': amountNaira,
            'remark': remarkController.text.isEmpty
                ? 'Withdrawal Request'
                : remarkController.text,
            'pin': pin,
            'status': 'pending',
            'recipientAccountName': recipientAccountName,
            'recipientBankName': recipientBankName,
            'recipientBankCode': recipientBankCode,
            'recipientAccountNumber': recipientAccountNumber,
            'transactionAdded': false,
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(
              now.add(const Duration(minutes: 10)),
            ),
          });
      await FirebaseFunctions.instance.httpsCallable('sendWithdrawalPin').call({
        'requestId': requestId,
      });
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                WithdrawalStatusPage(requestId: requestId ?? ""),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error initiating withdrawal: $e');
     // showToast(e.toString(), Colors.red);
      if (requestId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('pending_withdrawals')
              .doc(requestId)
              .delete();
        } catch (delE) {
          debugPrint('Failed to delete pending doc: $delE');
        }
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }
  @override
  void dispose() {
    _debounce?.cancel();
    usernameController.removeListener(_debounceResolve);
    accountNumberController.removeListener(_onAccountNumberChanged);
    amountController.removeListener(() {});
    usernameController.dispose();
    accountNumberController.dispose();
    amountController.dispose();
    remarkController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.black87,
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      "Customer Withdrawal",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            isTagMode = true;
                            accountNumberController.clear();
                            selectedBank = null;
                            selectedBankName = null;
                            recipientInfo = null;
                            isValid = false;
                            resolvedAccountName = '';
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isTagMode ? primaryColor : null,
                          foregroundColor: isTagMode
                              ? Colors.white
                              : primaryColor,
                          side: BorderSide(
                            color: isTagMode
                                ? Colors.transparent
                                : primaryColor,
                          ),
                        ),
                        child: const Text('Tag'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            isTagMode = false;
                            usernameController.clear();
                            recipientInfo = null;
                            isValid = false;
                            resolvedAccountName = '';
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: !isTagMode ? primaryColor : null,
                          foregroundColor: !isTagMode
                              ? Colors.white
                              : primaryColor,
                          side: BorderSide(
                            color: !isTagMode
                                ? Colors.transparent
                                : primaryColor,
                          ),
                        ),
                        child: const Text('Bank Account'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (isTagMode) ...[
                  const Text('Recipient Tag'),
                  const SizedBox(height: 8),
                  TextField(
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.none,
                    style: const TextStyle(fontSize: 14),
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
                              child: isResolving
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
                                      color: isValid
                                          ? Colors.green
                                          : Colors.red,
                                      size: 20,
                                    ),
                            ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_ ]')),
                    ],
                  ),
                ] else ...[
                  const Text('Beneficiary Bank'),
                  const SizedBox(height: 8),
                  isFetchingBanks
                      ? const Center(
                          child: CircularProgressIndicator(color: primaryColor),
                        )
                      : GestureDetector(
                          onTap: _showBankBottomSheet,
                          child: AbsorbPointer(
                            child: TextField(
                              controller: TextEditingController(
                                text: selectedBankName,
                              ),
                              readOnly: true,
                              decoration: InputDecoration(
                                hintText: "Select Bank",
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade600,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                suffixIcon: const Icon(Icons.arrow_drop_down),
                              ),
                            ),
                          ),
                        ),
                  const SizedBox(height: 16),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      hintText: 'Account number',
                    ),
                  ),
                ],
                if (recipientInfo != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'User: $resolvedAccountName',
                            style: TextStyle(color: Colors.green),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Amount to Withdraw'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey, width: 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '₦',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: '0.00',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                          ),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Remark (Optional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: remarkController,
                  decoration: InputDecoration(
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: 'Enter Remark',
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed:
                      isLoading ||
                          isResolving ||
                          !isValid ||
                          amountController.text.isEmpty
                      ? null
                      : _initiateWithdrawal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Initiate Withdrawal',
                          style: TextStyle(color: Colors.white,fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class WithdrawalStatusPage extends StatefulWidget {
  final String requestId;
  const WithdrawalStatusPage({super.key, required this.requestId});
  @override
  State<WithdrawalStatusPage> createState() => _WithdrawalStatusPageState();
}
class _WithdrawalStatusPageState extends State<WithdrawalStatusPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Withdrawal Status'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('pending_withdrawals')
              .doc(widget.requestId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: primaryColor),
              );
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(child: Text('Request not found'));
            }
            final data = snapshot.data!.data()!;
            String status = data['status'] as String;
            final amount = data['amount'] as double;
            final expiresAt = (data['expiresAt'] as Timestamp).toDate();
            final recipientName = data['recipientAccountName'] as String? ?? '';
            final recipientBankName = data['recipientBankName'] as String? ?? '';
            final recipientBankCode = data['recipientBankCode'] as String? ?? '';
            final recipientAccountNumber = data['recipientAccountNumber'] as String? ?? '';
            var timeLeft = expiresAt.difference(DateTime.now()).inSeconds;
            String currentStatus = status;
            if (status == 'pending' && timeLeft <= 0) {
              currentStatus = 'expired';
              // Update once on expiry (no periodic timer)
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  FirebaseFunctions.instance
                      .httpsCallable('cancelWithdrawalRequest')
                      .call({
                        'requestId': widget.requestId,
                        'reason': 'expired',
                      });
                }
              });
            }
            Widget body;
            if (currentStatus == 'pending') {
              // Calculate time left
              final _ = timeLeft ~/ 60;
              body = Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hourglass_empty, size: 64, color: Colors.orange),
                  const SizedBox(height: 20),
                  const Text(
                    'Waiting for Confirmation',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  // Isolated timer widget to avoid full rebuild
                  TimerDisplay(
                    duration: Duration(
                      seconds: timeLeft.clamp(0, 600),
                    ), // Max 10 min
                  ),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Customer enters PIN sent to their phone to confirm the withdrawal.',textAlign: TextAlign.center,),
                  ),
                  const SizedBox(height: 50),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await FirebaseFunctions.instance
                            .httpsCallable('cancelWithdrawalRequest')
                            .call({
                              'requestId': widget.requestId,
                              'reason': 'cancelled',
                            });
                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                        showToast('Cancel failed', Colors.red);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text(
                      'Cancel Request',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => WithdrawalApprovalPage(requestId: widget.requestId),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                    ),
                    child: const Text(
                      'Enter PIN',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            } 
            
           else if (currentStatus == 'approved') {
              final transferRef = data['transferRef'] ?? 'N/A';
              body = Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20), // Placeholder while modal shows
                  const Text('Processing...'),
                ],
              );
              // Show modal
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (context) => PaymentSuccessfulPage(
                      bankName: recipientBankName,
                      actionText: 'Done',
                      title: 'Withdrawal Successful',
                      description: 'Your withdrawal has been processed successfully.',
                      amount: amount.toString(),
                      recipientName: recipientName,
                      bankCode: recipientBankCode,
                      accountNumber: recipientAccountNumber,
                      reference: transferRef,
                    ),
                  ).then((_) {
                    if (mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (context) => const HomePage()),
                      );
                    }
                  });
                }
              });
            } else if (currentStatus == 'declined' ||
                currentStatus == 'cancelled') {
              body = Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel, size: 64, color: Colors.red),
                  const SizedBox(height: 20),
                  Text(
                    currentStatus == 'declined'
                        ? 'Request Declined'
                        : 'Request Cancelled',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back'),
                  ),
                ],
              );
            } else if (currentStatus == 'expired') {
              body = Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.access_time, size: 64, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text(
                    'Request Expired',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.popUntil(context, (route) => route.isFirst),
                    child: const Text('New Request'),
                  ),
                ],
              );
            } else {
              body = Text('Unknown status: $currentStatus');
            }
            return body;
          },
        ),
      ),
    );
  }
}
// Add this custom widget for isolated timer updates
class TimerDisplay extends StatefulWidget {
  final Duration duration;
  const TimerDisplay({super.key, required this.duration});
  @override
  State<TimerDisplay> createState() => _TimerDisplayState();
}
class _TimerDisplayState extends State<TimerDisplay> {
  late Timer _timer;
  late Duration _remaining;
  @override
  void initState() {
    super.initState();
    _remaining = widget.duration;
    if (_remaining.inSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _remaining.inSeconds > 0) {
          setState(() => _remaining -= const Duration(seconds: 1));
        } else {
          _timer.cancel();
        }
      });
    }
  }
  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final mins = _remaining.inSeconds ~/ 60;
    final secs = _remaining.inSeconds % 60;
    return Text(
      'Time remaining: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
      style: const TextStyle(fontSize: 16),
    );
  }
}
class WithdrawalApprovalPage extends StatefulWidget {
  final String requestId;
  const WithdrawalApprovalPage({super.key, required this.requestId});
  @override
  State<WithdrawalApprovalPage> createState() => _WithdrawalApprovalPageState();
}
class _WithdrawalApprovalPageState extends State<WithdrawalApprovalPage> {
  bool isLoading = false;
  String? storedPin;
  double? amount;
  String? initiatorName;
  String? recipientAccountName;
  String? recipientBankName;
  String? recipientBankCode;
  String? recipientAccountNumber;
  String? recipientUid;
  String? recipientCollection;
  Map<String, dynamic>? initiatorDetails;
  DateTime? createdAt;
  String pinInput = '';
  String? counterpartyId;
  @override
  void initState() {
    super.initState();
    _loadRequestDetails();
  }
  Future<void> _loadRequestDetails() async {
    final doc = await FirebaseFirestore.instance
        .collection('pending_withdrawals')
        .doc(widget.requestId)
        .get();
    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        storedPin = data['pin'] as String?;
        amount = data['amount'] as double?;
        initiatorName = data['initiatorName'] as String? ?? 'Unknown';
        initiatorDetails = data['initiatorDetails'] as Map<String, dynamic>?;
        recipientAccountName = data['recipientAccountName'] as String?;
        recipientBankName = data['recipientBankName'] as String?;
        recipientBankCode = data['recipientBankCode'] as String?;
        recipientAccountNumber = data['recipientAccountNumber'] as String?;
        recipientUid = data['recipientUid'] as String?;
        recipientCollection = data['recipientCollection'] as String?;
        createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      });
      if (data['status'] != 'pending' || storedPin == null) {
        showToast('Request no longer valid', Colors.red);
        Navigator.pop(context);
      }
    }
  }
  Future<Map<String, String?>> getCurrentAccountIdAndType() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'accountId': null, 'accountType': null, 'bankId': null};

    // 1. Check business first
    final DocumentSnapshot<Map<String, dynamic>> busSnap = await FirebaseFirestore.instance.collection('businesses').doc(uid).get();

    if (busSnap.exists && busSnap.data() != null) {
      final data = busSnap.data()!;
      final String kycStatus = data['kycStatus'] ?? '';

      if (kycStatus == 'APPROVED') {
        final Map<String, dynamic>? virtualAccData = data['sudoData']?['virtualAccount']?['data'] as Map<String, dynamic>?;

        if (virtualAccData != null && virtualAccData['id'] != null) {
          final bankMap = virtualAccData['attributes']?['bank'] as Map<String, dynamic>?;
          final String? bankId = bankMap?['id']?.toString();

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
          data['sudoData']?['virtualAccount']?['data'] as Map<String, dynamic>?;

      if (virtualAccData != null && virtualAccData['id'] != null) {
        final bankMap = virtualAccData['attributes']?['bank'] as Map<String, dynamic>?;
        final String? bankId = bankMap?['id']?.toString();

        return {
          'accountId': virtualAccData['id'] as String,
          'accountType': virtualAccData['type'] as String?,
          'bankId': bankId,
        };
      }
    }

    return {'accountId': null, 'accountType': null, 'bankId': null};
  }
  Future<void> _createCounterparty() async {
    if (recipientAccountName == null || recipientBankCode == null || recipientAccountNumber == null) {
      showToast('Recipient details incomplete', Colors.red);
      return;
    }

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showToast('No authenticated user found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];
      final String? accountType = details['accountType'];
      final String? bankId = details['bankId'];

      if (accountId == null || accountId.isEmpty) {
        showToast('Account ID not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }
      if (bankId == null || bankId.isEmpty) {
        showToast('Bank ID not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }
      if (accountType == null) {
        showToast('Account Type not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      // Check if counterparty already exists
      final query = await FirebaseFirestore.instance.collection('counterparties')
          .where('userId', isEqualTo: user.uid)
          .where('recipientAccountNumber', isEqualTo: recipientAccountNumber)
          .where('recipientBankCode', isEqualTo: recipientBankCode)
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
        'bankId': recipientBankCode,
        'accountType': accountType,
        'accountName': recipientAccountName,
        'bankName': recipientBankName,
        'accountNumber': recipientAccountNumber,
        'bankCode': recipientBankCode,
      });
      final counterpartyIdd = result.data['data']['id'];
      await FirebaseFirestore.instance
          .collection('counterparties')
          .doc(counterpartyIdd)
          .set({
        ...result.data,
        'userId': user.uid,
        'recipientAccountNumber': recipientAccountNumber,
        'recipientBankCode': recipientBankCode,
        'ownerAccountId': accountId,
      });

      setState(() {
        counterpartyId = counterpartyIdd;
      });
    } catch (e) {
      debugPrint('createCounterparty error: $e');
      showToast('Error creating counterparty', Colors.red);
    }
    setState(() => isLoading = false);
  }
  Future<void> _sudoTransferNip() async {
    if (counterpartyId == null || amount == null) {
      showToast('Counterparty or amount missing', Colors.red);
      return;
    }

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showToast('No authenticated user found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];
      final String? accountType = details['accountType'];

      if (accountId == null || accountId.isEmpty || accountType == null) {
        showToast('Account details not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final result = await callCloudFunctionLogged('sudoTransferNip', source: 'business_app', payload: {
        'accountType': accountType,
        'accountId': accountId,
        'counterpartyId': counterpartyId,
        'amount': amount! * 100,
        'currency': 'NGN',
        'narration': 'Withdrawal to ${recipientAccountName ?? 'Customer'}',
        'idempotencyKey': const Uuid().v4(),
      });

      final status = result.data['data']['attributes']['status'];
      final failureReason = result.data['data']['attributes']['failureReason'];
      if (status == "FAILED") {
        showToast('Transfer failed: $failureReason', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final transferRef = result.data['data']['id'];

      // Update pending withdrawal
      await FirebaseFirestore.instance
          .collection('pending_withdrawals')
          .doc(widget.requestId)
          .update({
        'status': 'approved',
        'pin': null,
        'transferRef': transferRef,
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // Save transaction
      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'receiverId': recipientUid ?? 'unknown',
        'type': 'withdrawal',
        'bank_code': recipientBankCode,
        'account_number': recipientAccountNumber,
        'amount': amount!,
        'reason': 'Customer Withdrawal',
        'currency': 'NGN',
        'api_response': result.data,
        'reference': transferRef,
        'recipientName': recipientAccountName,
        'bankName': recipientBankName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => PaymentSuccessfulPage(
            bankName: recipientBankName ?? 'Unknown Bank',
            actionText: 'Continue to Home',
            title: 'Withdrawal Successful',
            description: 'Funds have been transferred successfully to the recipient\'s bank account.',
            amount: amount.toString(),
            recipientName: recipientAccountName ?? 'Unknown',
            bankCode: recipientBankCode ?? '',
            accountNumber: recipientAccountNumber ?? '',
            reference: transferRef,
          ),
        ).then((_) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const HomePage()),
            );
          }
        });
      }
    } catch (e) {
      debugPrint('sudoTransferNip error: $e');
      showToast('Error processing transfer', Colors.red);
    }
    setState(() => isLoading = false);
  }
  Future<void> _approveWithdrawal() async {
    if (pinInput != storedPin) {
      setState(() {
        pinInput = '';
      });
      showToast('Invalid PIN', Colors.red);
      return;
    }
    setState(() => isLoading = true);
    try {
      await _createCounterparty();
      if (counterpartyId == null) {
        setState(() => isLoading = false);
        return;
      }
      await _sudoTransferNip();
    } catch (e) {
      showToast('Approval failed', Colors.red);
    } finally {
      setState(() => isLoading = false);
    }
  }
  Future<void> _declineWithdrawal() async {
    try {
      await FirebaseFirestore.instance
          .collection('pending_withdrawals')
          .doc(widget.requestId)
          .update({
            'status': 'declined',
            'pin': null, // Invalidate PIN
          });
      showToast('Request declined', Colors.orange);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } catch (e) {
      showToast('Decline failed', Colors.red);
    }
  }
  void _onNumberTap(int number) {
    if (pinInput.length < 4) {
      setState(() {
        pinInput += number.toString();
      });
    }
  }
  void _onBackspaceTap() {
    if (pinInput.isNotEmpty) {
      setState(() {
        pinInput = pinInput.substring(0, pinInput.length - 1);
      });
    }
  }
  void _onEnterTap() {
    _approveWithdrawal();
  }
  List<Widget> _buildKeypadRow(List<dynamic> items, bool isBottomRow) {
    return items.map<Widget>((item) {
      if (item is int) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: ElevatedButton(
              onPressed: () => _onNumberTap(item),
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(20),
              ),
              child: Text(
                item.toString(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );
      } else if (item == 'backspace') {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: ElevatedButton(
              onPressed: _onBackspaceTap,
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(20),
              ),
              child: const Icon(Icons.backspace, size: 24),
            ),
          ),
        );
      } else if (item == 'enter') {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: ElevatedButton(
              onPressed: pinInput.length == 4 ? _onEnterTap : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: pinInput.length == 4 ? Colors.green : Colors.grey,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 20),
              ),
              child: const Text(
                'Enter',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }).toList();
  }
  @override
  Widget build(BuildContext context) {
    if (storedPin == null || amount == null || initiatorName == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final List<int> numbers = List.generate(10, (index) => index)..shuffle();
    final List<List<dynamic>> keypadLayout = [
      [numbers[0], numbers[1], numbers[2]],
      [numbers[3], numbers[4], numbers[5]],
      [numbers[6], numbers[7], numbers[8]],
      [numbers[9], 'backspace', 'enter'],
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Confirm Withdrawal to ${recipientAccountName ?? 'Customer'}'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Amount: ₦${amount!.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Initiated: ${createdAt!.day}/${createdAt!.month}/${createdAt!.year} at ${createdAt!.hour.toString().padLeft(2, '0')}:${createdAt!.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 40),
            const Text(
              'Enter PIN to Confirm',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (index) => Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey),
                  color: pinInput.length > index ? Colors.blue : Colors.transparent,
                ),
                child: const Icon(Icons.circle, color: Colors.white, size: 20),
              )),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: keypadLayout.map((row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(children: _buildKeypadRow(row, row.contains('enter'))),
                )).toList(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _declineWithdrawal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text(
                      'Decline',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

