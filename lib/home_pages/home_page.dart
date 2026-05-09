import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/airtimes/buy_airtime.dart';
import 'package:padi_pay_business/bills/pay_bills.dart';
import 'package:padi_pay_business/home_pages/cashback_history_page.dart';
import 'package:padi_pay_business/home_pages/transaction_item.dart';
import 'package:padi_pay_business/home_pages/utils.dart';
import 'package:padi_pay_business/kyc/user_upgrade_manager.dart';
import 'package:padi_pay_business/my_business/my_business.dart';
import 'package:padi_pay_business/nfc_prompt_bottom_sheet.dart';
import 'package:padi_pay_business/kyb/business_upgrade_manager.dart';
import 'package:padi_pay_business/profile/profile_page.dart';
import 'package:padi_pay_business/storefront/storefront_management_page.dart';
import 'package:padi_pay_business/super_agent/super_agent_hub.dart';
import 'package:padi_pay_business/padi_book/padi_book_page.dart';
import 'package:padi_pay_business/transactions_history.dart'
    hide TransactionItem;
import 'package:padi_pay_business/transfer/transfer_funds_page.dart';
import 'package:padi_pay_business/transfer_details.dart';
import 'package:padi_pay_business/ui/bottom_nav_bar.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:padi_pay_business/payment_screen.dart';
import 'package:padi_pay_business/wifi_payment.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:in_app_update/in_app_update.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _balanceVisible = true;
  int _currentBusinessIndex = 0;
  String userName = "";
  bool isBusinessAccount = true;
  bool _balanceLoaded = false;
  String? userTag = "";
  final bool _isLoadingBalance = false;
  bool showAwaitingDocsBanner = false;
  bool showCreateBusinessBankAccountBanner = false;
  bool showStorefrontActivationBanner = false;
  bool businessProfileExists = false;
  bool kybVerificationSubmitted = false;
  bool isLoadingCreateAccount = false;
  bool storefrontEnabled = false;
  bool isActivatingStorefront = false;
  String? activeStandId;
  bool isStandMode = false;
  bool isLoggedInStandUser = false;
  bool isSuperAgentUser = false;
  bool _isLoadingTransactions = true;
  bool _headerLoaded = false;

  // Recent transactions
  List<DocumentSnapshot> _recentTxSentDocs = [];
  List<DocumentSnapshot> _recentTxReceivedDocs = [];
  List<DocumentSnapshot> _recentCardTxDocs = [];
  int superAgentStars = 0;
  double superAgentCommissionCurrentMonth = 0;
  double superAgentCommissionAvailable = 0;
  String parentBusinessName = '';
  List<Map<String, dynamic>> businesses = [
    {
      'name': 'Business Name LTD',
      'phone': '',
      'balance': 0.00,
      'type': 'main',
      'standId': null,
      'accountData': null,
      'contacts': [
        'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=50&h=50&fit=crop&crop=face',
        'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=50&h=50&fit=crop&crop=face',
        'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=50&h=50&fit=crop&crop=face',
        'https://images.unsplash.com/photo-1552053831-71594a27632d?w=50&h=50&fit=crop&crop=face',
        'https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?w=50&h=50&fit=crop&crop=face',
      ],
    },
  ];
  late List<String> quickSendImages;
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  StreamSubscription<QuerySnapshot>? _sentSub;
  StreamSubscription<QuerySnapshot>? _cardTxSub;
  StreamSubscription<QuerySnapshot>? _receivedSub;
  StreamSubscription<QuerySnapshot>? _cpSub;
  StreamSubscription<QuerySnapshot>? _receivedCpSub;
  List<QueryDocumentSnapshot> sentDocs = [];
  List<QueryDocumentSnapshot> receivedDocs = [];
  List<QueryDocumentSnapshot> receivedCpDocs = [];
  List<String> cpIds = [];

  void _logStorefrontBannerState(
    String stage, {
    bool? busDocExists,
    bool? hasStorefrontTagValue,
    bool? storefrontEnabledValue,
    bool? businessAccountValue,
    bool? standUserValue,
    bool? awaitingDocsValue,
    bool? createAccountBannerValue,
    bool? bannerValue,
    String? tagValue,
  }) {
    debugPrint(
      '[StorefrontBanner][$stage] '
      'businessDocExists=${busDocExists ?? businessProfileExists} '
      'hasStorefrontTag=${hasStorefrontTagValue ?? ((userTag ?? '').trim().isNotEmpty)} '
      'storefrontEnabled=${storefrontEnabledValue ?? storefrontEnabled} '
      'isBusinessAccount=${businessAccountValue ?? isBusinessAccount} '
      'isLoggedInStandUser=${standUserValue ?? isLoggedInStandUser} '
      'showAwaitingDocsBanner=${awaitingDocsValue ?? showAwaitingDocsBanner} '
      'showCreateBusinessBankAccountBanner=${createAccountBannerValue ?? showCreateBusinessBankAccountBanner} '
      'showStorefrontActivationBanner=${bannerValue ?? showStorefrontActivationBanner} '
      'userTag=${tagValue ?? userTag}',
    );
  }

  Future<void> saveToken() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    await saveUserDeviceToken(userId);
  }

  Future<void> fetchBusinessCustomer() async {
    await fetchAndPrintCustomer();
  }

  Future<void> _fastLoadHeader() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('businesses').doc(uid).get(),
        FirebaseFirestore.instance.collection('users').doc(uid).get(),
        FirebaseFirestore.instance.collection('standUsers').doc(uid).get(),
      ]);

      final busSnap = results[0];
      final userSnap = results[1];
      final standSnap = results[2];

      String name = '';
      String phone = '';
      String tag = '';
      String? accountId;

      // Determine primary account and its balance
      if (busSnap.exists) {
        final d = busSnap.data() as Map<String, dynamic>;
        final bd = d['business_data'] as Map<String, dynamic>?;
        name = bd?['name'] ?? d['businessName'] ?? '';
        final va =
            d['safehavenData']?['virtualAccount']?['data']
                as Map<String, dynamic>?;
        phone = va?['attributes']?['accountNumber']?.toString() ?? '';
        accountId = va?['id']?.toString();
        tag = name.replaceAll(' ', '_');
      } else if (userSnap.exists) {
        final d = userSnap.data() as Map<String, dynamic>;
        final first = d['firstName'] ?? '';
        final last = d['lastName'] ?? '';
        name = '$first $last'.trim();
        tag = d['userName'] ?? '';
        final va = getVirtualAccountData(d);
        phone = va?['attributes']?['accountNumber']?.toString() ?? '';
        accountId = va?['id']?.toString();
      } else if (standSnap.exists) {
        final d = standSnap.data() as Map<String, dynamic>;
        tag = d['userName'] ?? '';
        // For stand users we might not have a direct accountId here, will be fetched later.
      }

      // Fetch balance if we have an accountId
      double balance = 0.0;
      if (accountId != null) {
        try {
          balance = await sudoFetchAccountBalance(accountId);
        } catch (e) {
          debugPrint('[FastLoad] Balance fetch failed: $e');
        }
      }

      if (!mounted) return;
setState(() {
  if (name.isNotEmpty) userName = name;
  if (tag.isNotEmpty) userTag = tag;
  if (phone.isNotEmpty && businesses.isNotEmpty) {
    businesses[0]['phone'] = phone;
  }
  businesses[0]['balance'] = balance;
  _headerLoaded = true;
  _balanceLoaded = true;   // ✅ balance is now known
  _balanceVisible = true;
});
    } catch (e) {
      debugPrint('[FastLoad] Error: $e');
      if (mounted)
        setState(
          () => _headerLoaded = true,
        ); // still mark loaded to avoid eternal spinner
    }
  }

  Future<double> _fetchCurrentMonthCommissionsTotal(String businessId) async {
    final now = DateTime.now();

    final byBusinessId = await FirebaseFirestore.instance
        .collection('superAgentCommissions')
        .where('superAgentBusinessId', isEqualTo: businessId)
        .get();

    final byLegacyId = await FirebaseFirestore.instance
        .collection('superAgentCommissions')
        .where('superAgentId', isEqualTo: businessId)
        .get();

    final merged = <String, Map<String, dynamic>>{};
    for (final doc in byBusinessId.docs) {
      merged[doc.id] = doc.data();
    }
    for (final doc in byLegacyId.docs) {
      merged[doc.id] = doc.data();
    }

    double total = 0;
    for (final item in merged.values) {
      final status = (item['status'] ?? 'credited').toString().toLowerCase();
      if (status != 'credited') continue;

      final createdAtRaw = item['createdAt'];
      DateTime createdAt;
      if (createdAtRaw is Timestamp) {
        createdAt = createdAtRaw.toDate();
      } else if (createdAtRaw is DateTime) {
        createdAt = createdAtRaw;
      } else if (createdAtRaw is String) {
        createdAt =
            DateTime.tryParse(createdAtRaw) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        createdAt = DateTime.fromMillisecondsSinceEpoch(0);
      }

      if (createdAt.year == now.year && createdAt.month == now.month) {
        total += (item['amount'] as num?)?.toDouble() ?? 0;
      }
    }

    return total;
  }

  @override
  void initState() {
    super.initState();
    fetchBusinessCustomer();
    saveToken();
    _loadActiveStandId();
    quickSendImages = List<String>.from(
      businesses[_currentBusinessIndex]['contacts'],
    );

    // Phase 1: load header data (name, account number, tag, balance)
    _fastLoadHeader().then((_) {
      // Phase 2: load everything else in the background
      _fetchBusinessData();
      _initTransactionStreams(); // we'll create this method
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        createStroWalletUser();
        await _reconcilePendingAtmTransactions();
        await _backfillAtmTransactionsFromStatement();
        await _checkForUpdate();
      });
    });
  }

  void _initTransactionStreams() {
    _sentSub = FirebaseFirestore.instance
        .collection('transactions')
        .where(
          Filter.or(
            Filter('userId', isEqualTo: uid),
            Filter('actualSender', isEqualTo: uid),
          ),
        )
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots()
        .listen((snap) {
          if (mounted) setState(() => _recentTxSentDocs = snap.docs);
        }, onError: (e) => debugPrint('Sent tx stream error: $e'));

    _receivedSub = FirebaseFirestore.instance
        .collection('transactions')
        .where('receiverId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots()
        .listen((snap) {
          if (mounted) setState(() => _recentTxReceivedDocs = snap.docs);
        });

    _cpSub = FirebaseFirestore.instance
        .collection('counterparties')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
          if (mounted) {
            setState(() => cpIds = snap.docs.map((doc) => doc.id).toList());
            _updateCpStream();
          }
        });

    _cardTxSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
          if (mounted) setState(() => _recentCardTxDocs = snap.docs);
        });
  }

  Future<void> createStroWalletUser() async {
    createStroWalletUserIfNeeded(context);
  }

  /// Queries Firestore for all pending ATM transactions belonging to this user
  /// and calls the Safe Haven Kimono reconciliation function for each one.
  /// Runs silently in the background — no UI blocking.
  Future<void> _reconcilePendingAtmTransactions() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: uid)
          .where('type', isEqualTo: 'atm_payment')
          .where('status', isEqualTo: 'pending')
          .get();

      if (snap.docs.isEmpty) {
        debugPrint('[Reconcile] No pending ATM transactions found.');
        return;
      }

      debugPrint(
        '[Reconcile] Found ${snap.docs.length} pending ATM transaction(s). Reconciling...',
      );

      for (final doc in snap.docs) {
        final data = doc.data();
        // Prefer Safe Haven's retrievalReferenceNumber (saved as safeHavenRrn)
        // over the app-generated rrn — Kimono only matches on retrievalReferenceNumber
        final rrn = (data['safeHavenRrn'] as String?)?.isNotEmpty == true
            ? data['safeHavenRrn'] as String
            : data['rrn'] as String?;
        if (rrn == null || rrn.isEmpty) {
          debugPrint('[Reconcile] Doc ${doc.id} has no RRN — skipping');
          continue;
        }

        try {
          debugPrint(
            '[Reconcile] Reconciling doc=${doc.id} rrn=$rrn (safeHavenRrn=${data['safeHavenRrn']})',
          );
          final result = await FirebaseFunctions.instance
              .httpsCallable('reconcileAtmTransaction')
              .call({'rrn': rrn, 'transactionDocId': doc.id});

          debugPrint('[Reconcile] Raw response for rrn=$rrn: ${result.data}');
          final resultMap = result.data as Map? ?? {};
          final status = resultMap['status'] as String? ?? 'pending';
          final responseCode = resultMap['responseCode'];
          final safeHavenStatus = resultMap['safeHavenStatus'];
          debugPrint(
            '[Reconcile] doc=${doc.id} rrn=$rrn → status=$status | responseCode=$responseCode | safeHavenStatus=$safeHavenStatus',
          );
        } catch (e) {
          debugPrint('[Reconcile] Failed for doc=${doc.id} rrn=$rrn: $e');
        }
      }
    } catch (e) {
      debugPrint('[Reconcile] _reconcilePendingAtmTransactions error: $e');
    }
  }

  /// Calls backend backfill that uses Safe Haven account statements to:
  /// 1) resolve pending ATM transactions that missed RRN save, and
  /// 2) import statement transactions missing in Firestore.
  Future<void> _backfillAtmTransactionsFromStatement() async {
    try {
      debugPrint('[Backfill] Triggering statement-based ATM backfill...');
      final result = await FirebaseFunctions.instance
          .httpsCallable('backfillAtmTransactionsFromStatement')
          .call({'daysBack': 7});

      final data = result.data as Map? ?? {};
      final accountId = data['accountId'];
      final rows = data['statementRows'];
      final reconciled = data['reconciledCount'];
      final imported = data['importedCount'];

      debugPrint(
        '[Backfill] accountId=$accountId | statementRows=$rows | reconciled=$reconciled | imported=$imported',
      );
    } catch (e) {
      debugPrint('[Backfill] Failed to run statement backfill: $e');
    }
  }

  Future<void> _loadActiveStandId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      activeStandId = prefs.getString('activeStandId');
      if (activeStandId != null) {
        setState(() {
          isStandMode = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading active stand ID: $e');
    }
  }
  // Balance fetching is now centralized in `utils.sudoFetchAccountBalance`.

  Future<void> _checkForUpdate() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (!mounted) return;
        final doUpdate = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Update available'),
            content: const Text(
              'A newer version is available on Google Play. Update now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Later'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Update'),
              ),
            ],
          ),
        );

        if (doUpdate == true) {
          try {
            await InAppUpdate.performImmediateUpdate();
          } catch (e) {
            debugPrint('Immediate update failed: $e');
            try {
              await InAppUpdate.startFlexibleUpdate();
              await InAppUpdate.completeFlexibleUpdate();
            } catch (e2) {
              debugPrint('Flexible update failed: $e2');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('In-app update check failed: $e');
    }
  }

  int tier = 0;
  String kycStatus = "";
  String customerId = "";

  Future<void> _fetchBusinessData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final currentEmail = (currentUser?.email ?? '').trim().toLowerCase();
      final useSuperAgentMock = currentEmail == 'justefe99@gmail.com';

      DocumentSnapshot busSnap = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(uid)
          .get();

      businessProfileExists = busSnap.exists;

      String kybStatus = '';
      bool isKybApproved = false;
      String? businessAccountId;

      String first = '';
      String last = '';
      String busName = '';
      String busPhone = '';
      double bal = 0.0;
      bool isSuperAgent = false;
      int stars = 0;
      double monthlyCommission = 0;
      double availableCommission = 0;
      bool storefrontEnabledLocal = false;
      // Stand user helpers
      String? parentBusinessId;
      String? standId;
      Map<String, dynamic>? myStand;

      showCreateBusinessBankAccountBanner = false;
      showAwaitingDocsBanner = false;
      showStorefrontActivationBanner = false;
      storefrontEnabled = false;
      _logStorefrontBannerState(
        'reset',
        busDocExists: busSnap.exists,
        storefrontEnabledValue: storefrontEnabledLocal,
        businessAccountValue: isBusinessAccount,
        standUserValue: isLoggedInStandUser,
        awaitingDocsValue: showAwaitingDocsBanner,
        createAccountBannerValue: showCreateBusinessBankAccountBanner,
        bannerValue: showStorefrontActivationBanner,
      );
      parentBusinessName = '';
      isLoggedInStandUser = false;

      // Early detection for stand user
      bool earlyStandUser = false;
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('standUsers')
            .doc(uid)
            .get();
        if (userDoc.exists) {
          Map<String, dynamic> udata = userDoc.data() as Map<String, dynamic>;
          if (udata['parentBusinessId'] != null && udata['standId'] != null) {
            parentBusinessId = udata['parentBusinessId'];
            standId = udata['standId'];
            earlyStandUser = true;
            isLoggedInStandUser = true;
            isBusinessAccount = true;
            showAwaitingDocsBanner = false;
            showCreateBusinessBankAccountBanner = false;

            if (parentBusinessId != null) {
              DocumentSnapshot parentBusSnap = await FirebaseFirestore.instance
                  .collection('businesses')
                  .doc(parentBusinessId)
                  .get();
              if (parentBusSnap.exists) {
                Map<String, dynamic> parentData =
                    parentBusSnap.data() as Map<String, dynamic>;
                Map<String, dynamic>? businessDataMap =
                    parentData['business_data'] as Map<String, dynamic>?;
                busName =
                    businessDataMap?['name'] ??
                    parentData['businessName'] ??
                    busName;
                List<dynamic> posStands = parentData['posStands'] ?? [];
                for (var s in posStands) {
                  if (s is Map<String, dynamic> && s['standId'] == standId) {
                    myStand = s;
                    break;
                  }
                }
                if (myStand != null) {
                  final standAccountData = myStand['accountData'];
                  Map<String, dynamic>? standDataMap;
                  if (standAccountData is Map<String, dynamic> &&
                      standAccountData.containsKey('data')) {
                    standDataMap =
                        standAccountData['data'] as Map<String, dynamic>?;
                  }
                  final standAttributes =
                      (standDataMap != null &&
                          standDataMap.containsKey('attributes'))
                      ? (standDataMap['attributes'] as Map<String, dynamic>?) ??
                            {}
                      : {};
                  busPhone = standAttributes['accountNumber'] ?? busPhone;
                  final standAccountId = standDataMap?['id'];
                  if (standAccountId != null) {
                    try {
                      bal = await sudoFetchAccountBalance(standAccountId);
                    } catch (e) {
                      debugPrint('Error fetching stand balance (early): $e');
                      bal = 0.0;
                    }
                  }
                }
                activeStandId = standId;
                parentBusinessName = busName;
                setState(() {
                  userTag = busName.replaceAll(' ', '_');
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error detecting early stand user: $e');
      }

      if (earlyStandUser) {
        // Stand user already handled – skip remaining business logic.
      } else {
        // ----- FETCH TIER FROM USERS DOC (source of truth for KYB) -----
        int userTier = 0;
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            final safehavenTier =
                (userData['safehavenData']?['tier'] as num?)?.toInt() ?? 0;
            final sudoTier =
                (userData['sudoData']?['tier'] as num?)?.toInt() ?? 0;
            userTier = safehavenTier > 0 ? safehavenTier : sudoTier;
          }
        } catch (e) {
          debugPrint('Error fetching user tier: $e');
        }

        if (busSnap.exists) {
          Map<String, dynamic> data = busSnap.data() as Map<String, dynamic>;

          kybVerificationSubmitted = data['kybVerification'] != null;

          isSuperAgent = data['isSuperAgent'] == true;
          storefrontEnabledLocal = data['storefront']?['enabled'] == true;
          stars = (data['superAgentStars'] ?? 0) is int
              ? (data['superAgentStars'] ?? 0) as int
              : int.tryParse((data['superAgentStars'] ?? '0').toString()) ?? 0;
          availableCommission =
              (data['superAgentAvailableEarnings'] as num?)?.toDouble() ?? 0.0;
          if (isSuperAgent) {
            monthlyCommission = await _fetchCurrentMonthCommissionsTotal(uid);
          }

          kybStatus = data['kycStatus'] ?? '';

          // ---------- NEW RULE: Only tier 3 is fully KYB approved ----------
          isKybApproved = (userTier == 3);

          // Determine if business has a virtual account (safehavenData.virtualAccount)
          final bizSafehaven = data['safehavenData'] as Map<String, dynamic>?;
          final bizVa =
              bizSafehaven?['virtualAccount'] as Map<String, dynamic>?;
          final bizVaData = bizVa?['data'] as Map<String, dynamic>?;
          final hasBizVirtualAccount = bizVaData?['id'] != null;

          // ----- Banner logic based on tier and virtual account existence -----
          if (isKybApproved && !hasBizVirtualAccount) {
            // Tier 3 but no virtual account → show "Create Bank Account" banner
            showCreateBusinessBankAccountBanner = true;
            showAwaitingDocsBanner = false;
          } else {
            showCreateBusinessBankAccountBanner = false;
            // For tiers 1,2 or tier 3 with account already, check for required documents
            if (kybStatus == "AWAITING_DOCUMENT" &&
                (data['requiredDocuments'] is List) &&
                (data['requiredDocuments'] as List).isNotEmpty) {
              showAwaitingDocsBanner = true;
            } else {
              showAwaitingDocsBanner = false;
            }
          }

          // Resolve account ID and balance (if possible)
          if (hasBizVirtualAccount) {
            businessAccountId = bizVaData!['id'].toString();
          } else {
            final vaData = await resolveVirtualAccount(uid);
            businessAccountId = vaData?['id']?.toString();
          }

          if (businessAccountId != null) {
            try {
              bal = await sudoFetchAccountBalance(businessAccountId!);
            } catch (e) {
              debugPrint('Error fetching business balance: $e');
            }
          }
        }

        // Decide which account to use (business or personal)
        if (busSnap.exists && isKybApproved && businessAccountId != null) {
          Map<String, dynamic> data = busSnap.data() as Map<String, dynamic>;
          final businessDataMap =
              data['business_data'] as Map<String, dynamic>?;
          busName = businessDataMap?['name'] ?? data['businessName'] ?? busName;

          final safehavenData = data['safehavenData'] as Map<String, dynamic>?;
          final va = safehavenData?['virtualAccount'] as Map<String, dynamic>?;
          final vaData = va?['data'] as Map<String, dynamic>?;
          final attrs = vaData?['attributes'] as Map<String, dynamic>?;
          busPhone = attrs?['accountNumber']?.toString() ?? busPhone;

          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
            if (userDoc.exists) {
              final ud = userDoc.data()!;
              first = ud['firstName']?.toString() ?? first;
              last = ud['lastName']?.toString() ?? last;
            }
          } catch (e) {
            debugPrint('Error fetching user names: $e');
          }

          bal = await sudoFetchAccountBalance(businessAccountId!);
          isBusinessAccount = true;
          setState(() => userTag = busName.replaceAll(' ', '_'));
        } else if (!earlyStandUser) {
          // Check if auth user exists in regular `users` collection, otherwise
          // fall back to `standUsers` (some accounts may live there).
          DocumentSnapshot userSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          if (!userSnap.exists) {
            userSnap = await FirebaseFirestore.instance
                .collection('standUsers')
                .doc(uid)
                .get();
          }
          if (userSnap.exists) {
            Map<String, dynamic> data = userSnap.data() as Map<String, dynamic>;
            parentBusinessId = data['parentBusinessId'];
            standId = data['standId'];
            first = data['firstName'] ?? first;
            last = data['lastName'] ?? last;
            userTag = data['userName'] ?? '';
          }
          if (parentBusinessId != null && standId != null) {
            // Stand user (non‑early branch)
            isLoggedInStandUser = true;
            isBusinessAccount = true;
            showAwaitingDocsBanner = false;
            showCreateBusinessBankAccountBanner = false;
            DocumentSnapshot parentBusSnap = await FirebaseFirestore.instance
                .collection('businesses')
                .doc(parentBusinessId)
                .get();
            if (parentBusSnap.exists) {
              Map<String, dynamic> parentData =
                  parentBusSnap.data() as Map<String, dynamic>;
              Map<String, dynamic>? businessDataMap =
                  parentData['business_data'] as Map<String, dynamic>?;
              busName =
                  businessDataMap?['name'] ??
                  parentData['businessName'] ??
                  busName;
              List<dynamic> posStands = parentData['posStands'] ?? [];
              for (var stand in posStands) {
                if (stand is Map<String, dynamic> &&
                    stand['standId'] == standId) {
                  myStand = stand;
                  break;
                }
              }
              if (myStand != null) {
                final standAccountData = myStand['accountData'];
                Map<String, dynamic>? standDataMap;
                if (standAccountData is Map<String, dynamic> &&
                    standAccountData.containsKey('data')) {
                  standDataMap =
                      standAccountData['data'] as Map<String, dynamic>?;
                }
                final standAttributes =
                    (standDataMap != null &&
                        standDataMap.containsKey('attributes'))
                    ? (standDataMap['attributes'] as Map<String, dynamic>?) ??
                          {}
                    : {};
                busPhone = standAttributes['accountNumber'] ?? 'N/A';
                parentBusinessName = busName;
                final standAccountId = standDataMap?['id'];
                if (standAccountId != null) {
                  bal = await sudoFetchAccountBalance(standAccountId);
                } else {
                  bal = 0.0;
                }
              }
              activeStandId = standId;
              setState(() {
                userTag = busName.replaceAll(' ', '_');
              });
            } else {
              busName = 'Business';
              busPhone = 'N/A';
              bal = 0.0;
              activeStandId = standId;
              setState(() {
                userTag = busName.replaceAll(' ', '_');
              });
            }
          } else {
            // Regular user (personal account)
            isBusinessAccount = false;
            if (userSnap.exists) {
              Map<String, dynamic> data =
                  userSnap.data() as Map<String, dynamic>;
              final personalVirtualAcc = getVirtualAccountData(data);
              if (personalVirtualAcc != null) {
                String? accNum =
                    personalVirtualAcc['attributes']?['accountNumber']
                        ?.toString();
                final personalAccountId = personalVirtualAcc['id']?.toString();
                if ((accNum == null || accNum.toString().isEmpty) &&
                    personalAccountId != null) {
                  await _fetchAndUpdateVirtualAccount(
                    personalAccountId,
                    FirebaseFirestore.instance.collection('users').doc(uid),
                  );
                  final refreshed = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .get();
                  accNum = getVirtualAccountData(
                    refreshed.data(),
                  )?['attributes']?['accountNumber']?.toString();
                }
                busPhone = accNum ?? 'N/A';
                tier = int.tryParse(getWalletTier(data) ?? '0') ?? 0;
                String? personalAccountId2 = personalVirtualAcc['id']
                    ?.toString();
                if (personalAccountId2 != null) {
                  bal = await sudoFetchAccountBalance(personalAccountId2);
                }
              } else {
                busPhone = 'N/A';
                bal = 0.0;
              }
            }
          }
        }
      }

      // Build full name and businesses list
      String fullName = "$first $last".trim();
      List<Map<String, dynamic>> allBusinesses = [];

      if (parentBusinessId != null && standId != null) {
        if (myStand != null) {
          final standAccountData = myStand['accountData'];
          Map<String, dynamic>? standDataMap;
          if (standAccountData is Map<String, dynamic> &&
              standAccountData.containsKey('data')) {
            standDataMap = standAccountData['data'] as Map<String, dynamic>?;
          }
          final standAttributes =
              (standDataMap != null && standDataMap.containsKey('attributes'))
              ? (standDataMap['attributes'] as Map<String, dynamic>?) ?? {}
              : {};
          final standAccountNumber = standAttributes['accountNumber'] ?? 'N/A';
          double standBalance = bal;
          allBusinesses.add({
            'name': myStand['name'] ?? 'POS Stand',
            'phone': standAccountNumber,
            'balance': standBalance,
            'type': 'stand',
            'standId': myStand['standId'],
            'accountData': standAccountData,
            'location': myStand['location'] ?? '',
            'contacts': [
              'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=50&h=50&fit=crop&crop=face',
              'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=50&h=50&fit=crop&crop=face',
              'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=50&h=50&fit=crop&crop=face',
            ],
          });
        } else {
          allBusinesses.add({
            'name': 'My POS Stand',
            'phone': busPhone,
            'balance': bal,
            'type': 'stand',
            'standId': standId,
            'accountData': null,
            'location': '',
            'contacts': [
              'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=50&h=50&fit=crop&crop=face',
              'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=50&h=50&fit=crop&crop=face',
              'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=50&h=50&fit=crop&crop=face',
            ],
          });
        }
      } else if (busSnap.exists) {
        // Add main business
        allBusinesses.add({
          'name': busName,
          'phone': busPhone,
          'balance': bal,
          'type': 'main',
          'standId': null,
          'accountData': null,
          'contacts': [
            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=50&h=50&fit=crop&crop=face',
            'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=50&h=50&fit=crop&crop=face',
            'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=50&h=50&fit=crop&crop=face',
            'https://images.unsplash.com/photo-1552053831-71594a27632d?w=50&h=50&fit=crop&crop=face',
            'https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?w=50&h=50&fit=crop&crop=face',
          ],
        });

        // Load stands
        Map<String, dynamic> busData = busSnap.data() as Map<String, dynamic>;
        List<dynamic> posStands = busData['posStands'] ?? [];
        for (var stand in posStands) {
          if (stand is Map<String, dynamic>) {
            final standAccountData = stand['accountData'];
            Map<String, dynamic>? standDataMap;
            if (standAccountData is Map<String, dynamic> &&
                standAccountData.containsKey('data')) {
              standDataMap = standAccountData['data'] as Map<String, dynamic>?;
            }
            final standAttributes =
                (standDataMap != null && standDataMap.containsKey('attributes'))
                ? (standDataMap['attributes'] as Map<String, dynamic>?) ?? {}
                : {};
            final standAccountNumber =
                standAttributes['accountNumber'] ?? 'N/A';
            final standAccountId = standDataMap?['id'];
            double standBalance = 0.0;
            if (standAccountId != null) {
              try {
                standBalance = await sudoFetchAccountBalance(standAccountId);
              } catch (e) {
                debugPrint('Error fetching stand balance: $e');
              }
            }
            allBusinesses.add({
              'name': stand['name'] ?? 'POS Stand',
              'phone': standAccountNumber,
              'balance': standBalance,
              'type': 'stand',
              'standId': stand['standId'],
              'accountData': standAccountData,
              'location': stand['location'] ?? '',
              'contacts': [
                'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=50&h=50&fit=crop&crop=face',
                'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=50&h=50&fit=crop&crop=face',
                'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=50&h=50&fit=crop&crop=face',
              ],
            });
          }
        }
      } else {
        // Regular user
        allBusinesses.add({
          'name': fullName.isNotEmpty ? fullName : '',
          'phone': busPhone,
          'balance': bal,
          'type': 'main',
          'standId': null,
          'accountData': null,
          'contacts': [
            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=50&h=50&fit=crop&crop=face',
            'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=50&h=50&fit=crop&crop=face',
            'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=50&h=50&fit=crop&crop=face',
            'https://images.unsplash.com/photo-1552053831-71594a27632d?w=50&h=50&fit=crop&crop=face',
            'https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?w=50&h=50&fit=crop&crop=crop&face',
          ],
        });
      }

      // Find index to select based on activeStandId
      int selectedIndex = 0;
      if (activeStandId != null) {
        for (int i = 0; i < allBusinesses.length; i++) {
          if (allBusinesses[i]['standId'] == activeStandId) {
            selectedIndex = i;
            break;
          }
        }
      }

      final hasStorefrontTag = (userTag ?? '').trim().isNotEmpty;

      setState(() {
        String displayTopName = (parentBusinessId != null && standId != null)
            ? (myStand != null ? (myStand['name'] ?? busName) : busName)
            : (isBusinessAccount
                  ? busName
                  : (fullName.isNotEmpty ? fullName : ''));
        userName = displayTopName;
        businesses = allBusinesses;
        _currentBusinessIndex = selectedIndex;
        isSuperAgentUser = useSuperAgentMock ? true : isSuperAgent;
        superAgentStars = useSuperAgentMock ? 4 : stars;
        superAgentCommissionCurrentMonth = useSuperAgentMock
            ? 32500
            : monthlyCommission;
        superAgentCommissionAvailable = useSuperAgentMock
            ? 86500
            : availableCommission;
        storefrontEnabled = storefrontEnabledLocal;
        showStorefrontActivationBanner =
            hasStorefrontTag &&
            !isLoggedInStandUser &&
            !showAwaitingDocsBanner &&
            !showCreateBusinessBankAccountBanner &&
            !storefrontEnabledLocal;
        quickSendImages = List<String>.from(
          businesses[_currentBusinessIndex]['contacts'],
        );
      });

      _logStorefrontBannerState(
        'after-setstate',
        busDocExists: businessProfileExists,
        hasStorefrontTagValue: hasStorefrontTag,
        storefrontEnabledValue: storefrontEnabled,
        businessAccountValue: isBusinessAccount,
        standUserValue: isLoggedInStandUser,
        awaitingDocsValue: showAwaitingDocsBanner,
        createAccountBannerValue: showCreateBusinessBankAccountBanner,
        bannerValue: showStorefrontActivationBanner,
        tagValue: userTag,
      );
    } catch (e) {
      print(e);
    }
  }

  void _updateCpStream() {
    _receivedCpSub?.cancel();
    if (cpIds.isEmpty) {
      receivedCpDocs = [];
      return;
    }
    _receivedCpSub = FirebaseFirestore.instance
        .collection('transactions')
        .where(
          'api_response.data.relationships.counterParty.data.id',
          whereIn: cpIds,
        )
        .snapshots()
        .listen((snap) {
          setState(() {
            receivedCpDocs = snap.docs;
          });
        });
  }

  // Fetch authoritative bank and accountNumber for a given virtual accountId,
  // then update Firestore wallet attributes for both safehavenData and sudoData.
  Future<void> _fetchAndUpdateVirtualAccount(
    String accountId,
    DocumentReference userDocRef,
  ) async {
    try {
      print('Calling sudoFetchAccountNumber for accountId: $accountId');
      final callable = FirebaseFunctions.instance.httpsCallable(
        'sudoFetchAccountNumber',
      );
      final result = await callable.call({'accountId': accountId});
      print('sudoFetchAccountNumber response: ${result.data}');

      dynamic resp = result.data;
      String? accountNumber;
      String? bankName;

      if (resp is Map) {
        // Common shapes handled
        accountNumber =
            resp['accountNumber']?.toString() ??
            resp['data']?['attributes']?['accountNumber']?.toString();
        if (resp['bank'] != null) {
          if (resp['bank'] is Map) {
            bankName = resp['bank']['name']?.toString();
          } else {
            bankName = resp['bank']?.toString();
          }
        }
        bankName ??= resp['data']?['attributes']?['bank']?['name']?.toString();
      }

      if (accountNumber == null && bankName == null) {
        print(
          'sudoFetchAccountNumber: no accountNumber or bank found in response',
        );
        return;
      }

      final updates = <String, dynamic>{};
      if (accountNumber != null) {
        updates['sudoData.virtualAccount.data.attributes.accountNumber'] =
            accountNumber;
        updates['safehavenData.virtualAccount.data.attributes.accountNumber'] =
            accountNumber;
      }
      if (bankName != null) {
        updates['sudoData.virtualAccount.data.attributes.bank'] = {
          'name': bankName,
        };
        updates['safehavenData.virtualAccount.data.attributes.bank'] = {
          'name': bankName,
        };
      }

      if (updates.isNotEmpty) {
        await userDocRef.update(updates);
        print('Updated Firestore virtualAccount attributes: $updates');
        setState(() {
          if (accountNumber != null) {
            // Update local businesses list if applicable (main account)
            for (int i = 0; i < businesses.length; i++) {
              if (businesses[i]['type'] == 'main') {
                businesses[i]['phone'] = accountNumber;
                // If current selected business is this main entry, ensure displayed balance/phone updates
                if (_currentBusinessIndex == i) {
                  // Trigger rebuild by setting same value (already modified)
                }
                break;
              }
            }
          }
        });
      }
    } catch (e) {
      print('Error in _fetchAndUpdateVirtualAccount: $e');
    }
  }

  @override
  void dispose() {
    _sentSub?.cancel();
    _receivedSub?.cancel();
    _cpSub?.cancel();
    _receivedCpSub?.cancel();
    _cardTxSub?.cancel(); // ✅ add this

    super.dispose();
  }

  void _toggleBalanceVisibility() {
    setState(() {
      _balanceVisible = !_balanceVisible;
    });
  }

  void _copyPhoneNumber() {
    final phone = businesses[_currentBusinessIndex]['phone'] ?? '';
    Clipboard.setData(ClipboardData(text: phone.toString()));
    // Clear clipboard after 15 seconds to reduce data exposure
    Future.delayed(const Duration(seconds: 15), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  void _copyTag() {
    if (userTag == null || userTag!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: userTag!));
    showToast("Tag copied", Colors.green);
    Future.delayed(const Duration(seconds: 15), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  String get _storefrontUrl {
    final cleanTag = (userTag ?? '').trim().toLowerCase();
    return cleanTag.isEmpty ? '' : 'https://$cleanTag.padipay.co';
  }

  Future<void> _openStorefrontManagement() async {
    final cleanTag = (userTag ?? '').trim().toLowerCase();
    _logStorefrontBannerState('open-management-tapped', tagValue: cleanTag);
    if (cleanTag.isEmpty) {
      showToast('Tag unavailable', Colors.red);
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StorefrontManagementPage(
          username: cleanTag,
          initialEnabled: storefrontEnabled,
        ),
      ),
    );

    await _fetchBusinessData();
  }

  Future<void> _activateStorefront() async {
    _logStorefrontBannerState('activate-tapped');
    if ((userTag ?? '').trim().isEmpty) {
      showToast('Set up your tag before activating storefront', Colors.red);
      return;
    }

    setState(() => isActivatingStorefront = true);
    try {
      await FirebaseFirestore.instance.collection('businesses').doc(uid).set({
        'storefront': {
          'enabled': true,
          'url': _storefrontUrl,
          'activatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        storefrontEnabled = true;
        showStorefrontActivationBanner = false;
      });
      _logStorefrontBannerState('activate-success');
      showToast('Storefront activated', Colors.green);
      await _openStorefrontManagement();
    } catch (e) {
      debugPrint('[StorefrontBanner][activate-error] $e');
      showToast('Failed to activate storefront', Colors.red);
    } finally {
      if (mounted) {
        setState(() => isActivatingStorefront = false);
      }
    }
  }

  String _superAgentTierName(int stars) {
    if (stars >= 5) return 'My Padi';
    if (stars == 4) return 'Who Goes';
    if (stars == 3) return 'Clear Road';
    if (stars == 2) return 'Boss Man';
    if (stars == 1) return 'Sharp Guy';
    return 'Unranked';
  }

  Future<void> _switchBusiness(int index) async {
    final selectedBusiness = businesses[index];

    // Update selected index and quick send images immediately
    setState(() {
      _currentBusinessIndex = index;
      quickSendImages = List<String>.from(businesses[index]['contacts']);
    });

    final prefs = await SharedPreferences.getInstance();

    // If selecting a stand, persist active stand, set stand mode,
    // set the top header to the stand name and parentBusinessName to
    // the main business name. Also fetch the stand account balance
    // (if we have accountData.id) to keep the UI up-to-date.
    if (selectedBusiness['type'] == 'stand' &&
        selectedBusiness['standId'] != null) {
      await prefs.setString('activeStandId', selectedBusiness['standId']);

      // Determine parent business name (main business entry if present)
      String parentName = '';
      try {
        final mainBusiness = businesses.firstWhere(
          (b) => b['type'] == 'main',
          orElse: () => businesses[0],
        );
        parentName = mainBusiness['name'] ?? '';
      } catch (e) {
        parentName = '';
      }

      // Extract accountId from nested accountData if present
      String? accountId;
      final accountData = selectedBusiness['accountData'];
      if (accountData is Map<String, dynamic> &&
          accountData.containsKey('data')) {
        final dataMap = accountData['data'] as Map<String, dynamic>?;
        accountId = dataMap?['id']?.toString();
      }

      // Fetch and update balance if we have an account id
      if (accountId != null) {
        try {
          final newBal = await sudoFetchAccountBalance(accountId);
          setState(() {
            businesses[index]['balance'] = newBal;
            userName = selectedBusiness['name'] ?? parentName;
            parentBusinessName = parentName;
            activeStandId = selectedBusiness['standId'];
            isStandMode = true;
          });
        } catch (e) {
          // On error still update display state
          setState(() {
            userName = selectedBusiness['name'] ?? parentName;
            parentBusinessName = parentName;
            activeStandId = selectedBusiness['standId'];
            isStandMode = true;
          });
        }
      } else {
        // No account id, just update display state
        setState(() {
          userName = selectedBusiness['name'] ?? parentName;
          parentBusinessName = parentName;
          activeStandId = selectedBusiness['standId'];
          isStandMode = true;
        });
      }
    } else {
      // Selecting a main business or personal account: clear active stand
      await prefs.remove('activeStandId');
      setState(() {
        activeStandId = null;
        isStandMode = false;
        parentBusinessName = selectedBusiness['name'] ?? '';
        userName = selectedBusiness['name'] ?? '';
      });
    }
  }

  void _showBusinessSwitchSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          bottom: true,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Switch Business",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 16),
                          SizedBox(width: 5),
                          Text("New", style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...businesses.asMap().entries.map((entry) {
                  final index = entry.key;
                  final business = entry.value;
                  return ListTile(
                    leading: Container(
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      padding: EdgeInsets.all(15),
                      child: Text(
                        getInitials(business['name']),
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    title: Text(business['name']),
                    subtitle: Text(business['phone']),
                    trailing: index == _currentBusinessIndex
                        ? const Icon(Icons.check_circle, color: primaryColor)
                        : null,
                    onTap: () {
                      _switchBusiness(index);
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> refresh() async {
    navigateTo(context, HomePage(), type: NavigationType.clearStack);
  }

  @override
  Widget build(BuildContext context) {
    final currentBusiness = businesses[_currentBusinessIndex];
    final balance = currentBusiness['balance'];
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          color: primaryColor,
          backgroundColor: Colors.white,
          onRefresh: refresh,
          child: SizedBox.expand(
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          SvgPicture.asset(
                            'assets/Frame 1707480412.svg',
                            width: MediaQuery.of(context).size.width,
                          ),
                          Container(
                            width: MediaQuery.of(context).size.width,
                            color: Colors.white.withValues(
                              alpha: 0.1,
                            ), // 10% white overlay
                          ),
                          Column(
                            children: [
                              SizedBox(height: 30),
                              Container(
                                margin: EdgeInsets.symmetric(horizontal: 25),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(width: 10),
                                    CircleAvatar(
                                      backgroundColor: Colors.white30,
                                      radius: 20,
                                      child: Icon(
                                        Icons.person,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      userName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Spacer(),
                                    GestureDetector(
                                      onTap: () {
                                        navigateTo(
                                          context,
                                          DevicesListScreen(
                                            deviceType: DeviceType.advertiser,
                                          ),
                                        );
                                      },
                                      child: Icon(
                                        Icons.wifi_tethering,
                                        size: 25,
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 20),
                                    Icon(
                                      Icons.notifications_outlined,
                                      size: 25,
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                    SizedBox(width: 15),
                                  ],
                                ),
                              ),
                              Container(
                                margin: EdgeInsets.only(
                                  top: 20,
                                  left: 15,
                                  right: 15,
                                ),
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: Alignment.center,
                                    radius: 1.0,
                                    colors: [
                                      Color(0xFFEAECF0).withValues(alpha: 0.3),
                                      Color(0xFFEAECF0).withValues(alpha: 0.3),
                                      Color(0xFFEAECF0).withValues(alpha: 0.5),
                                      Color(0xFFEAECF0).withValues(alpha: 0.8),
                                      Color(0xFFEAECF0),
                                      Color(0xFFEAECF0),
                                    ],
                                    stops: [0, 0.2, 0.4, 0.6, 0.8, 1],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    width: 0.5,
                                    color: Color(0xFFEAECF0),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        showModalBottomSheet(
                                          context: context,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.vertical(
                                              top: Radius.circular(20),
                                            ),
                                          ),
                                          builder: (context) {
                                            return SafeArea(
                                              bottom: true,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 24,
                                                    ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Receive Payment',
                                                      style: TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    SizedBox(height: 8),
                                                    Text(
                                                      'Choose how you want to receive',
                                                      style: TextStyle(
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    SizedBox(height: 24),
                                                    _ReceiveOptionTile(
                                                      disabled: false,
                                                      icon: Icons.credit_card,
                                                      title: 'ATM Card',
                                                      subtitle:
                                                          'Receive via debit or credit card',
                                                      onTap: () {
                                                        Navigator.pop(context);
                                                        navigateTo(
                                                          context,
                                                          PaymentScreen(),
                                                        );
                                                      },
                                                    ),
                                                    SizedBox(height: 12),
                                                    _ReceiveOptionTile(
                                                      disabled: false,
                                                      icon: Icons.nfc,
                                                      title: 'PadiPay User',
                                                      subtitle:
                                                          'Tap to receive from a PadiPay user',
                                                      onTap: () {
                                                        Navigator.pop(context);
                                                        showModalBottomSheet(
                                                          context: context,
                                                          builder: (context) {
                                                            return NFCPromptBottomSheet(
                                                              isReader: false,
                                                            );
                                                          },
                                                        );
                                                      },
                                                    ),
                                                    SizedBox(height: 16),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 15,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primaryColor,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                Icons.touch_app_outlined,
                                                color: primaryColor,
                                              ),
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              "Tap to Receive Payment",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Spacer(),
                                            Icon(
                                              Icons.arrow_outward,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 25),
                                    Row(
                                      children: [
                                        GestureDetector(
                                          onTap: isBusinessAccount
                                              ? _showBusinessSwitchSheet
                                              : null,
                                          child: Container(
                                            padding: EdgeInsets.only(
                                              left: 0,
                                              right: 10,
                                              top: 2,
                                              bottom: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.5,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  margin: EdgeInsets.all(5),
                                                  padding: EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    FontAwesomeIcons.user,
                                                    color: Colors.grey,
                                                    size: 16,
                                                  ),
                                                ),
                                                Text(
                                                  isBusinessAccount
                                                      ? "${(currentBusiness['type'] == 'stand' && parentBusinessName.isNotEmpty) ? parentBusinessName : currentBusiness['name']} | ${currentBusiness['phone']}"
                                                      : "$userName | ${currentBusiness['phone']}",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                if (isBusinessAccount) ...[
                                                  SizedBox(width: 2),
                                                  Icon(
                                                    Icons.keyboard_arrow_down,
                                                    color: Colors.white,
                                                  ),
                                                ],
                                                SizedBox(width: 5),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Spacer(),
                                        GestureDetector(
                                          onTap: _copyPhoneNumber,
                                          child: Icon(
                                            FontAwesomeIcons.copy,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.only(
                                            left: 0,
                                            right: 10,
                                            top: 2,
                                            bottom: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                margin: EdgeInsets.all(5),
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  FontAwesomeIcons.user,
                                                  color: Colors.grey,
                                                  size: 16,
                                                ),
                                              ),
                                              Text(
                                                "Padi-Tag | @$userTag",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              SizedBox(width: 5),
                                            ],
                                          ),
                                        ),
                                        Spacer(),
                                        GestureDetector(
                                          onTap: _copyTag,
                                          child: Icon(
                                            FontAwesomeIcons.copy,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),

                                    SizedBox(height: 15),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              "Account Balance",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 5),
                               Row(
  children: [
    if (!_balanceLoaded)
      const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      )
    else
      Text(
        _balanceVisible ? "₦${formatNumber(balance)}" : "••••••••",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 25,
          fontWeight: FontWeight.bold,
        ),
      ),
    const SizedBox(width: 10),
    GestureDetector(
      onTap: _toggleBalanceVisibility,
      child: Icon(
        _balanceVisible
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        color: Colors.white,
      ),
    ),
  ],
),
                                    if (isSuperAgentUser) ...[
                                      SizedBox(height: 30),
                                      InkWell(
                                        onTap: () {
                                          navigateTo(
                                            context,
                                            const SuperAgentHubPage(),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Ink(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 16,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Color(0xFF1A4CCF),
                                                Color(0xFF4C2FB8),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.12,
                                                ),
                                                blurRadius: 12,
                                                offset: Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons
                                                    .workspace_premium_outlined,
                                                color: Colors.amber.shade200,
                                                size: 18,
                                              ),
                                              SizedBox(width: 6),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: List.generate(
                                                      5,
                                                      (index) => Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              right: 2,
                                                            ),
                                                        child: Icon(
                                                          index <
                                                                  superAgentStars
                                                              ? Icons.star
                                                              : Icons
                                                                    .star_outline,
                                                          color: Colors
                                                              .amber
                                                              .shade200,
                                                          size: 14,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(height: 2),
                                                  Text(
                                                    _superAgentTierName(
                                                      superAgentStars,
                                                    ),
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Spacer(),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    'This Month: ₦${formatNumber(superAgentCommissionCurrentMonth)}',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Available: ₦${formatNumber(superAgentCommissionAvailable)}',
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              SizedBox(width: 8),
                                              Icon(
                                                Icons.chevron_right,
                                                color: Colors.white70,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        InkWell(
                                          onTap: () {
                                            navigateTo(
                                              context,
                                              ChooseTransferFundsType(),
                                            );
                                          },
                                          child: Container(
                                            alignment: Alignment.center,
                                            width:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.4,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 30,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(40),
                                            ),
                                            child: Text(
                                              "Transfer",
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () {
                                            navigateTo(
                                              context,
                                              AddViaBankTransfer(),
                                            );
                                          },
                                          child: Container(
                                            alignment: Alignment.center,
                                            width:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.4,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 30,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: primaryColor,
                                              borderRadius:
                                                  BorderRadius.circular(40),
                                            ),
                                            child: Text(
                                              "Deposit",
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      _buildBody(),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 25,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: BottomNavBar(
                      currentIndex: _selectedIndex,
                      onTap: (index) {
                        if (index == 0) {
                          setState(() => _selectedIndex = index);
                          return;
                        }
                        if (index == 2) {
                          navigateTo(
                            context,
                            MyBusiness(),
                            type: NavigationType.push,
                          );
                        }
                        if (index == 4) {
                          navigateTo(
                            context,
                            ProfilePage(),
                            type: NavigationType.push,
                          );
                        }
                        if (index == 5) {
                          navigateTo(
                            context,
                            const PadiBookPage(),
                            type: NavigationType.push,
                          );
                        }
                        if (index == 3) {
                          navigateTo(
                            context,
                            TransactionsHistory(),
                            type: NavigationType.push,
                          );
                        } else {
                          setState(() => _selectedIndex = index);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 15),
        Column(
          children: [
            if (!isBusinessAccount) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: 10.0,
                  left: 16.0,
                  right: 16.0,
                ),
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(width: 1, color: Colors.grey.shade200),
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: primaryColor.withValues(alpha: 0.1),
                        ),
                        child: Icon(
                          showCreateBusinessBankAccountBanner
                              ? Icons.account_balance
                              : showAwaitingDocsBanner
                              ? Icons.document_scanner
                              : kybVerificationSubmitted
                              ? Icons.hourglass_bottom
                              : Icons.verified_user,
                          color: primaryColor,
                          size: 20,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              showCreateBusinessBankAccountBanner
                                  ? "Business Verified – Create Bank Account"
                                  : showAwaitingDocsBanner
                                  ? "Business Documents Required"
                                  : kybVerificationSubmitted
                                  ? "Business Verification Pending"
                                  : "Business Verification Required",
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 5),
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.6,
                              child: Text(
                                showCreateBusinessBankAccountBanner
                                    ? "Your business verification is complete. Tap to create your dedicated business bank account."
                                    : showAwaitingDocsBanner
                                    ? "Provide your business documents to complete verification."
                                    : kybVerificationSubmitted
                                    ? "Your business verification is under review. "
                                    : "Provide your business details to comply with financial regulations.",
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            SizedBox(height: 15),
                            InkWell(
                              onTap: showCreateBusinessBankAccountBanner
                                  ? () async {
                                      setState(() {
                                        isLoadingCreateAccount = true;
                                      });

                                      try {
                                        final functions =
                                            FirebaseFunctions.instance;

                                        // Check if stroWalletUser already exists
                                        final userDocSnap =
                                            await FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(uid)
                                                .get();
                                        if (!userDocSnap.exists) {
                                          throw Exception(
                                            'User document not found',
                                          );
                                        }
                                        final userData = userDocSnap.data()!;

                                        // Only create StroWallet user if it doesn't exist
                                        if (!userData.containsKey(
                                          'stroWalletUser',
                                        )) {
                                          try {
                                            final firstname =
                                                userData['firstName'] ?? '';
                                            final lastname =
                                                userData['lastName'] ?? '';
                                            final email =
                                                userData['email'] ?? '';
                                            final phone =
                                                userData['phone'] ?? '';
                                            final nin = userData['nin'] ?? '';
                                            final dob = userData['dob'] ?? '';
                                            final name =
                                                userData['userName'] ??
                                                '$firstname $lastname';
                                            final line1 =
                                                userData['address']?['street'] ??
                                                '';
                                            final city =
                                                userData['address']?['city'] ??
                                                '';
                                            final state =
                                                userData['address']?['state'] ??
                                                '';

                                            final cardFunc = functions
                                                .httpsCallable(
                                                  'createStrowalletNairaCardUser',
                                                );
                                            final cardPayload = {
                                              'firstname': firstname,
                                              'lastname': lastname,
                                              'email': email,
                                              'phone': phone,
                                              'nin': nin,
                                              'dob': dob,
                                              'name': name,
                                              'line1': line1,
                                              'city': city,
                                              'state': state,
                                            };
                                            print(
                                              'Sending createStrowalletNairaCardUser payload: $cardPayload',
                                            );
                                            final cardResult = await cardFunc
                                                .call(cardPayload);
                                            print(
                                              'Create Strowallet Naira Card User Response: ${cardResult.data}',
                                            );

                                            // Update user doc with stroWalletUser
                                            final userDocRef = FirebaseFirestore
                                                .instance
                                                .collection('users')
                                                .doc(uid);
                                            await userDocRef.update({
                                              'stroWalletUser': cardResult.data,
                                            });
                                            print(
                                              'StroWallet user created successfully',
                                            );
                                          } catch (stroError) {
                                            print(
                                              'Error creating StroWallet user: $stroError',
                                            );
                                            // Continue with bank account creation even if StroWallet fails
                                          }
                                        } else {
                                          print(
                                            'StroWallet user already exists, skipping creation',
                                          );
                                        }

                                        // Create business bank account
                                        DocumentReference docRef =
                                            FirebaseFirestore.instance
                                                .collection('businesses')
                                                .doc(uid);
                                        final createAccountFunc = functions
                                            .httpsCallable(
                                              'safehavenCreateSubAccount',
                                            );
                                        final idempotencyKey = Uuid().v4();
                                        final accountPayload = {
                                          'customerId': customerId,
                                          'currency': 'NGN',
                                          'type': "BusinessCustomer",
                                          'idempotencyKey': idempotencyKey,
                                        };
                                        print(
                                          'Sending sudoCreateSubAccount payload: $accountPayload',
                                        );
                                        final createAccountResult =
                                            await createAccountFunc.call(
                                              accountPayload,
                                            );
                                        print(
                                          'Create Electronic Account Response: ${createAccountResult.data}',
                                        );
                                        await docRef.update({
                                          'sudoData.virtualAccount':
                                              createAccountResult.data,
                                        });
                                        showToast(
                                          "Business bank account created successfully",
                                          Colors.green,
                                        );
                                        setState(() {
                                          isLoadingCreateAccount = false;
                                        });

                                        navigateTo(context, HomePage());
                                      } catch (e) {
                                        setState(() {
                                          isLoadingCreateAccount = false;
                                        });
                                        print(e);
                                        showToast(
                                          "Failed to create business account",
                                          Colors.red,
                                        );
                                      }
                                    }
                                  : (showAwaitingDocsBanner ||
                                        businessProfileExists ||
                                        !businessProfileExists)
                                  ? () => navigateTo(
                                      context,
                                      BusinessUpgradeManager(),
                                    )
                                  : () => navigateTo(
                                      context,
                                      UserUpgradeManager(tier: tier.toString()),
                                    ),
                              child: isLoadingCreateAccount
                                  ? Center(
                                      child: SizedBox(
                                        height: 25,
                                        width: 25,
                                        child: CircularProgressIndicator(
                                          color: primaryColor,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      alignment: Alignment.center,
                                      width:
                                          MediaQuery.of(context).size.width *
                                          0.6,
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryColor,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        showCreateBusinessBankAccountBanner
                                            ? "Create Bank Account"
                                            : showAwaitingDocsBanner
                                            ? "Submit Documents"
                                            : kybVerificationSubmitted
                                            ? "View Progress"
                                            : "Verify Business",
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (showStorefrontActivationBanner && businessProfileExists) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: 10.0,
                  left: 16.0,
                  right: 16.0,
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(width: 1, color: Colors.grey.shade200),
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: primaryColor.withValues(alpha: 0.12),
                        ),
                        child: Icon(
                          Icons.storefront,
                          color: primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Launch Your Storefront',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Get your own public web link, sell data directly to customers, and keep all sales in your transaction history.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Perks: shareable site, direct payments, in-app tracking.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(height: 15),
                            InkWell(
                              onTap: isActivatingStorefront
                                  ? null
                                  : _activateStorefront,
                              child: isActivatingStorefront
                                  ? Center(
                                      child: SizedBox(
                                        height: 25,
                                        width: 25,
                                        child: CircularProgressIndicator(
                                          color: primaryColor,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      alignment: Alignment.center,
                                      width:
                                          MediaQuery.of(context).size.width *
                                          0.6,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryColor,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Activate Storefront',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            SizedBox(height: 15),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(width: 16),
                  Stack(
                    children: [
                      Container(
                        constraints: BoxConstraints(
                          minWidth: 300,
                          maxWidth: MediaQuery.of(context).size.width * 0.85,
                        ),
                        padding: EdgeInsets.only(top: 16, left: 16, right: 10),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "CAC Registration",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    "Let's help you register your\nbusiness with the Corporate Affairs Commission and get your\nCAC certificate.",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                  SizedBox(height: 15),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "Get Started",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 10,
                                          color: Colors.white.withOpacity(0.9),
                                        ),
                                      ),
                                      SizedBox(width: 5),
                                      Icon(
                                        Icons.arrow_forward,
                                        size: 15,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ],
                                  ),

                                  // Row(
                                  //   mainAxisAlignment:
                                  //       MainAxisAlignment.spaceBetween,
                                  //   children: [
                                  //     Spacer(),
                                  //     Row(
                                  //       mainAxisAlignment:
                                  //           MainAxisAlignment.center,
                                  //       children: [
                                  //         Container(
                                  //           width: 10,
                                  //           height: 10,
                                  //           decoration: BoxDecoration(
                                  //             color: Colors.white,
                                  //             shape: BoxShape.circle,
                                  //           ),
                                  //         ),
                                  //         SizedBox(width: 5),
                                  //         Container(
                                  //           width: 10,
                                  //           height: 10,
                                  //           decoration: BoxDecoration(
                                  //             color: Colors.white.withOpacity(
                                  //               0.5,
                                  //             ),
                                  //             shape: BoxShape.circle,
                                  //           ),
                                  //         ),
                                  //       ],
                                  //     ),
                                  //     Spacer(),
                                  //   ],
                                  // ),
                                  SizedBox(height: 15),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: -30,
                        right: 0,
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: Image.asset(
                            "assets/Group 481516.png",
                            width: 130,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: 8),

                  // Stack(
                  //   children: [
                  //     Container(
                  //       constraints: BoxConstraints(
                  //         minWidth: 300,
                  //         maxWidth: MediaQuery.of(context).size.width * 0.85,
                  //       ),
                  //       padding: EdgeInsets.only(top: 16, left: 16, right: 16),
                  //       decoration: BoxDecoration(
                  //         color: Color(0xFF9000FF),
                  //         borderRadius: BorderRadius.circular(10),
                  //       ),
                  //       child: Row(
                  //         children: [
                  //           Expanded(
                  //             child: Column(
                  //               crossAxisAlignment: CrossAxisAlignment.start,
                  //               mainAxisSize: MainAxisSize.min,
                  //               children: [
                  //                 Text(
                  //                   "Smart Cards",
                  //                   style: TextStyle(
                  //                     fontSize: 14,
                  //                     fontWeight: FontWeight.bold,
                  //                     color: Colors.white,
                  //                   ),
                  //                 ),
                  //                 SizedBox(height: 10),
                  //                 Text(
                  //                   "Create physical, virtual or anonymous\ncards, all managed in one app\n",
                  //                   style: TextStyle(
                  //                     fontWeight: FontWeight.w600,
                  //                     fontSize: 12,
                  //                     color: Colors.white.withOpacity(0.8),
                  //                   ),
                  //                 ),
                  //                 SizedBox(height: 15),
                  //                 Row(
                  //                   mainAxisSize: MainAxisSize.min,
                  //                   children: [
                  //                     Text(
                  //                       "Get Started",
                  //                       style: TextStyle(
                  //                         fontWeight: FontWeight.w600,
                  //                         fontSize: 10,
                  //                         color: Colors.white.withOpacity(0.9),
                  //                       ),
                  //                     ),
                  //                     SizedBox(width: 5),
                  //                     Icon(
                  //                       Icons.arrow_forward,
                  //                       size: 15,
                  //                       color: Colors.white.withOpacity(0.9),
                  //                     ),
                  //                   ],
                  //                 ),
                  //                 Row(
                  //                   mainAxisAlignment:
                  //                       MainAxisAlignment.spaceBetween,
                  //                   children: [
                  //                     Spacer(),
                  //                     Row(
                  //                       mainAxisAlignment:
                  //                           MainAxisAlignment.center,
                  //                       children: [
                  //                         Container(
                  //                           width: 10,
                  //                           height: 10,
                  //                           decoration: BoxDecoration(
                  //                             color: Colors.white,
                  //                             shape: BoxShape.circle,
                  //                           ),
                  //                         ),
                  //                         SizedBox(width: 5),
                  //                         Container(
                  //                           width: 10,
                  //                           height: 10,
                  //                           decoration: BoxDecoration(
                  //                             color: Colors.white.withOpacity(
                  //                               0.5,
                  //                             ),
                  //                             shape: BoxShape.circle,
                  //                           ),
                  //                         ),
                  //                       ],
                  //                     ),
                  //                     Spacer(),
                  //                   ],
                  //                 ),
                  //                 SizedBox(height: 15),
                  //               ],
                  //             ),
                  //           ),
                  //         ],
                  //       ),
                  //     ),
                  //     Positioned(
                  //       bottom: 0,
                  //       right: 0,
                  //       child: Align(
                  //         alignment: Alignment.bottomRight,
                  //         child: Image.asset("assets/drfjihlk.png", width: 130),
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  SizedBox(width: 16),
                ],
              ),
            ),
            SizedBox(height: 35),
            Row(
              children: [
                SizedBox(width: 16),
                Text(
                  "Pay Bills",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            SizedBox(height: 15),
            Row(
              children: [
                Spacer(),
                InkWell(
                  onTap: () {
                    navigateTo(context, BuyAirtimePage());
                  },
                  child: Column(
                    children: [
                      Image.asset("assets/airtime.png", width: 50),
                      SizedBox(height: 10),
                      Text(
                        "Airtime",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Spacer(),
                Column(
                  children: [
                    Image.asset("assets/qr_pay.png", width: 50),
                    SizedBox(height: 10),
                    Text(
                      "QR Pay",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Spacer(),
                InkWell(
                  onTap: () {
                    //  navigateTo(context, page)
                  },
                  child: Column(
                    children: [
                      Image.asset("assets/betting.png", width: 50),
                      SizedBox(height: 10),
                      Text(
                        "Betting",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Spacer(),
              ],
            ),
            SizedBox(height: 40),
            Row(
              children: [
                Spacer(),
                InkWell(
                  onTap: () {
                    navigateTo(context, PayBillsPage(bill: 2));
                  },
                  child: Column(
                    children: [
                      Image.asset("assets/cable_tv.png", width: 50),
                      SizedBox(height: 10),
                      Text(
                        "Cable TV",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Spacer(),
                InkWell(
                  onTap: () {
                    navigateTo(context, PayBillsPage(bill: 1));
                  },
                  child: Column(
                    children: [
                      Image.asset("assets/data.png", width: 50),
                      SizedBox(height: 10),
                      Text(
                        "Data",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Spacer(),
                InkWell(
                  onTap: () {
                    navigateTo(context, PayBillsPage(bill: 0));
                  },
                  child: Column(
                    children: [
                      Image.asset("assets/electricity.png", width: 50),
                      SizedBox(height: 10),
                      Text(
                        "Electricity",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Spacer(),
              ],
            ),
            SizedBox(height: 40),
            Row(
              children: [
                Spacer(),
                InkWell(
                  onTap: () {
                    navigateTo(context, CashbackHistoryPage());
                  },
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(13),

                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.withValues(alpha: 0.1),
                        ),
                        child: Icon(
                          Icons.savings,
                          color: Colors.green,
                          size: 30,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        "Cashback",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Spacer(),
                InkWell(
                  onTap: () {
                    _openStorefrontManagement();
                  },
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(13),

                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blueGrey.withValues(alpha: 0.1),
                        ),
                        child: Icon(
                          Icons.business,
                          color: Colors.blueGrey,
                          size: 30,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        "Storefront",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Spacer(),
                Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainState: true,
                  maintainAnimation: true,
                  child: InkWell(
                    onTap: () async {
                      await _openStorefrontManagement();
                    },
                    child: Column(
                      children: [
                        Image.asset("assets/electricity.png", width: 50),
                        SizedBox(height: 10),
                        Text(
                          "Electricity",
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Spacer(),
              ],
            ),
            SizedBox(height: 40),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildRecentTransactionsSection(),
            ),
          ],
        ),
        SizedBox(height: 150),
      ],
    );
  }

  Widget _buildRecentTransactionsSection() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final recentDocs = _getMergedRecentTransactions(limit: 5);

    // Build 5 most recent unique recipients for the "Recents" row
    final List<Map<String, dynamic>> recentRecipients = [];
    final Set<String> seenRecipientKeys = {};
    for (final doc in _getMergedRecentTransactions(limit: 50)) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type']?.toString().toLowerCase() ?? '';
      if (type != 'transfer' && type != 'ghost_transfer') continue;
      final isOutgoing = data['userId'] == uid || data['actualSender'] == uid;
      if (!isOutgoing) continue;
      final recipientName =
          data['recipientName']?.toString() ??
          data['account_number']?.toString() ??
          'Unknown';
      final key =
          data['account_number']?.toString() ??
          data['receiverId']?.toString() ??
          recipientName;
      if (seenRecipientKeys.contains(key)) continue;
      seenRecipientKeys.add(key);
      recentRecipients.add(data);
      if (recentRecipients.length >= 5) break;
    }

    final bool hasData = recentDocs.isNotEmpty || recentRecipients.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Transaction History',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            GestureDetector(
              onTap: () => navigateTo(
                context,
                TransactionsHistory(),
                type: NavigationType.push,
              ),
              child: Text(
                'See All',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ),
          ],
        ),

        // Recents row (horizontal avatars of recent transfer recipients)
        if (recentRecipients.isNotEmpty) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: recentRecipients.length,
              itemBuilder: (context, index) {
                final r = recentRecipients[index];
                final name = r['recipientName']?.toString() ?? 'Unknown';
                final initials = name.trim().isEmpty
                    ? '?'
                    : name
                          .trim()
                          .split(' ')
                          .where((s) => s.isNotEmpty)
                          .take(2)
                          .map((s) => s[0].toUpperCase())
                          .join();
                return GestureDetector(
                  onTap: () => navigateTo(
                    context,
                    TransactionsHistory(),
                    type: NavigationType.push,
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: primaryColor.withValues(alpha: 0.15),
                          child: Text(
                            initials,
                            style: GoogleFonts.inter(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 52,
                          child: Text(
                            name.split(' ').first,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Last 5 transactions list
        if (_isLoadingTransactions)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: CircularProgressIndicator(
              color: primaryColor,
              strokeWidth: 2,
            ),
          )
        else if (recentDocs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text(
                  'No transactions yet',
                  style: GoogleFonts.inter(
                    color: Colors.grey.shade500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentDocs.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey.shade100),
            itemBuilder: (context, index) {
              final doc = recentDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final type = data['type']?.toString().toLowerCase() ?? '';
              final bool isOutgoing =
                  type != 'transfer' && type != 'ghost_transfer'
                  ? true
                  : (data['userId'] == uid || data['actualSender'] == uid);
              final otherId = isOutgoing
                  ? (data['receiverId'] ?? '')
                  : (data['userId'] ?? '');

              Color bgColor = const Color(0xFFE3F2FD);
              Color iconColor = const Color(0xFF1565C0);
              Offset offset = Offset.zero;
              if (type == 'transfer') {
                bgColor = isOutgoing
                    ? const Color(0xFFF3E5F5)
                    : const Color(0xFFE8F5E9);
                iconColor = isOutgoing
                    ? const Color(0xFF7B1FA2)
                    : const Color(0xFF2E7D32);
                if (isOutgoing) offset = const Offset(-2, 2);
              } else if (type.contains('ghost')) {
                bgColor = const Color(0xFFECEFF1);
                iconColor = const Color(0xFF37474F);
              } else if (type.contains('giveaway')) {
                bgColor = const Color(0xFFFFF8E1);
                iconColor = const Color(0xFFFF6F00);
              } else if (type == 'deposit' ||
                  type == 'fund' ||
                  type == 'add_money') {
                bgColor = const Color(0xFFE8F5E9);
                iconColor = const Color(0xFF2E7D32);
              } else if (type == 'card_debit') {
                bgColor = const Color(0xFFFFF3E0);
                iconColor = const Color(0xFFE65100);
              } else if (type == 'card_declined') {
                bgColor = const Color(0xFFFFEBEE);
                iconColor = const Color(0xFFC62828);
              } else if (type == 'card_refund') {
                bgColor = const Color(0xFFE8F5E9);
                iconColor = const Color(0xFF2E7D32);
              }

              final isCardTx =
                  type == 'card_debit' ||
                  type == 'card_declined' ||
                  type == 'card_refund';
              final amountSign = type == 'card_refund'
                  ? '+'
                  : type == 'card_declined'
                  ? '' // declined = no debit occurred
                  : (!isOutgoing ||
                        type == 'deposit' ||
                        type == 'giveaway_claim' ||
                        type == 'add_money' ||
                        type == 'fund')
                  ? '+'
                  : '-';
              final amountValue =
                  ((data['amount'] as num?) ??
                  (data['debitAmount'] as num?) ??
                  0);
              final formattedAmount = NumberFormat(
                '#,##0.00',
              ).format(amountValue);

              final date = _txDocDate(data);
              final formattedTime = DateFormat('HH:mm').format(date);
              final formattedDate = DateFormat('MMM d, yyyy').format(date);

              final name = isCardTx
                  ? (data['merchant'] ?? 'Card Transaction')
                  : data['senderName'] ??
                        data['debitAccountName'] ??
                        data['originatorAccountName'] ??
                        data['counterParty']?['accountName'] ??
                        data['recipientName'] ??
                        data['phoneNumber'] ??
                        data['meterNumber'] ??
                        data['smartcard_number'] ??
                        data['account_number'] ??
                        'Unknown';

              final reference =
                  data['reference']?.toString() ??
                  (data['api_response']?['data']?['attributes']?['reference']
                      as String?) ??
                  (data['transactionId'] as String?) ??
                  '';

              final status = _getStatus(data);
              final Color statusColor;
              if (type == 'card_debit' || type == 'card_refund') {
                statusColor = Colors.green;
              } else if (type == 'card_declined') {
                statusColor = Colors.red;
              } else {
                statusColor = _getStatusColor(status);
              }
              final Color amountColor = isCardTx
                  ? (type == 'card_refund'
                        ? Colors.green
                        : type == 'card_declined'
                        ? Colors.grey.shade600
                        : Colors.red)
                  : statusColor;
              final statusDisplay = isCardTx
                  ? (type == 'card_debit'
                        ? 'Successful'
                        : type == 'card_declined'
                        ? 'Declined'
                        : 'Refunded')
                  : status.replaceAll('_', ' ').isNotEmpty
                  ? status.replaceAll('_', ' ')[0].toUpperCase() +
                        status.replaceAll('_', ' ').substring(1)
                  : status;

              return Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: TransactionItem(
                  docId: doc.id,
                  icon: _txIcon(type, isOutgoing),
                  otherId: otherId.toString(),
                  amount: '$amountSign₦$formattedAmount',
                  amountColor: amountColor,
                  formattedTime: formattedTime,
                  formattedDate: formattedDate,
                  status: statusDisplay,
                  statusColor: statusColor,
                  isOutgoing: isOutgoing,
                  otherName: name.toString(),
                  type: type,
                  reference: reference,
                  bgColor: bgColor,
                  iconColor: iconColor,
                  offset: offset,
                  cardData: isCardTx ? data : null,
                ),
              );
            },
          ),
      ],
    );
  }

  List<DocumentSnapshot> _getMergedRecentTransactions({int limit = 5}) {
    final Map<String, DocumentSnapshot> seen = {};
    for (final doc in [
      ..._recentTxSentDocs,
      ..._recentTxReceivedDocs,
      ..._recentCardTxDocs,
    ]) {
      seen[doc.id] = doc;
    }
    const excludedTypes = {'card_created', 'card_failed'};
    final sorted =
        seen.values.where((doc) {
          final type =
              (doc.data() as Map<String, dynamic>)['type']?.toString() ?? '';
          return !excludedTypes.contains(type);
        }).toList()..sort((a, b) {
          final aDate = _txDocDate(a.data() as Map<String, dynamic>);
          final bDate = _txDocDate(b.data() as Map<String, dynamic>);
          return bDate.compareTo(aDate);
        });
    return sorted.take(limit).toList();
  }

  DateTime _txDocDate(Map<String, dynamic> data) {
    final dynamic ts =
        data['timestamp'] ??
        data['createdAtFirestore'] ??
        data['createdAt'] ??
        data['createdAtUtc'];
    if (ts == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is String) {
      try {
        return DateTime.parse(ts);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  IconData _txIcon(String type, bool isOutgoing) {
    switch (type.toLowerCase()) {
      case 'transfer':
        return isOutgoing ? FontAwesomeIcons.paperPlane : Icons.arrow_downward;
      case 'airtime':
        return FontAwesomeIcons.phone;
      case 'data':
      case 'mobile_data':
        return FontAwesomeIcons.wifi;
      case 'electricity':
        return FontAwesomeIcons.bolt;
      case 'cable':
        return Icons.tv;
      case 'add_money':
      case 'fund':
      case 'deposit':
        return Icons.arrow_downward;
      case 'giveaway_claim':
      case 'giveaway_create':
        return FontAwesomeIcons.gift;
      case 'ghost_transfer':
        return FontAwesomeIcons.ghost;
      case 'card_debit':
        return Icons.credit_card;
      case 'card_declined':
        return Icons.credit_card;
      case 'card_refund':
        return Icons.undo;
      default:
        return FontAwesomeIcons.exchangeAlt;
    }
  }

  String _getStatus(Map<String, dynamic> data) {
    if (data['status'] != null) {
      return data['status'].toString().toLowerCase();
    }
    if (data['api_response']?['data']?['attributes']?['status'] != null) {
      return data['api_response']['data']['attributes']['status']
          .toString()
          .toLowerCase();
    }
    if (data['fullData']?['attributes']?['status'] != null) {
      return data['fullData']['attributes']['status'].toString().toLowerCase();
    }
    return 'unknown';
  }

  Color _getStatusColor(String status) {
    if (['success', 'completed', 'successful', 'approved'].contains(status)) {
      return Colors.green;
    } else if (['pending', 'to be paid'].contains(status)) {
      return Colors.orange;
    } else if (['failed', 'unsuccessful', 'declined'].contains(status)) {
      return Colors.red;
    } else if (status == 'reversed') {
      return Colors.grey;
    }
    return Colors.grey;
  }
}

class _ReceiveOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool disabled;

  const _ReceiveOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.45 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: primaryColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              disabled
                  ? Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: Colors.grey.shade400,
                    )
                  : Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
