import 'package:padi_pay_business/atm_transaction_service.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:padi_pay_business/atm_payment/atm_payment_successful_page.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tappa/flutter_tappa.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:flutter/foundation.dart';

// -- Terminal credentials -----------------------------------------------------
const _kTerminalId = '2ISWH246';
const _kUniqueId = 'P260300000569';
const _kClientId = '69aaa68647cc7a0024a332c8';

// -- Enums --------------------------------------------------------------------
enum _InitStatus { loading, ready, error }

enum _TxStatus { idle, processing, failed, uncertain }

/// Thrown when the user explicitly cancels the NFC tap dialog.
class _CancelledException implements Exception {
  const _CancelledException();
}

/// Thrown when a network drop mid-transaction leaves the outcome unknown.
class _UncertainException implements Exception {
  const _UncertainException();
}

// Add at the top of the file, outside the class:
Completer<String>? _globalTxCompleter;
String _globalTxRrn = '';
double _globalRawAmount = 0;
String _globalSafeHavenRrn = '';
String _globalChargedAmount = '';
String _globalTxTag = '';
Future<void> _saveTappaLog({
  required String eventType,
  required String status,
  String? amount,
  String? rrn,
  String? errorCode,
  String? errorMessage,
  String? cardData,
  Map<String, dynamic>? additionalData,
}) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    final logData = {
      'userId': user?.uid,
      'eventType': eventType,
      'status': status,
      'timestamp': FieldValue.serverTimestamp(),
      'terminalId': _kTerminalId,
      'uniqueId': _kUniqueId,
      'clientId': _kClientId,
      if (amount != null) 'amount': amount,
      if (rrn != null) 'rrn': rrn,
      if (errorCode != null) 'errorCode': errorCode,
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (cardData != null) 'cardData': cardData,
      if (additionalData != null) 'additionalData': additionalData,
    };

    await FirebaseFirestore.instance.collection('tappaLogs').add(logData);
    debugPrint('[TappaLog] Saved to Firestore: $eventType - $status');
  } catch (e) {
    debugPrint('[TappaLog] Failed to save: $e');
  }
}

// -- Failure model ------------------------------------------------------------

class _TxFailure {
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  const _TxFailure({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
  });
}

class _PaymentException implements Exception {
  final _TxFailure failure;
  const _PaymentException(this.failure);
  @override
  String toString() => '${failure.title}: ${failure.detail}';
}

_TxFailure _iso8583Failure(String code) {
  switch (code) {
    case '01':
      return const _TxFailure(
        title: 'Contact Your Bank',
        detail: 'Ask the customer to call their bank before trying again.',
        icon: Icons.phone_outlined,
        color: Color(0xFFE67E22),
      );
    case '05':
      return const _TxFailure(
        title: 'Payment Declined',
        detail:
            'The customer\'s bank declined this transaction. Try a different card.',
        icon: Icons.block_rounded,
        color: Color(0xFFE74C3C),
      );
    case '12':
      return const _TxFailure(
        title: 'Invalid Transaction',
        detail: 'This transaction type is not supported for this card.',
        icon: Icons.error_outline_rounded,
        color: Color(0xFFE74C3C),
      );
    case '13':
      return const _TxFailure(
        title: 'Invalid Amount',
        detail: 'The amount entered is not valid for this card.',
        icon: Icons.money_off_rounded,
        color: Color(0xFFE74C3C),
      );
    case '14':
      return const _TxFailure(
        title: 'Invalid Card',
        detail: 'The card details could not be verified. Try tapping again.',
        icon: Icons.credit_card_off_rounded,
        color: Color(0xFFE74C3C),
      );
    case '41':
    case '43':
      return const _TxFailure(
        title: 'Card Restricted',
        detail:
            'This card has been reported. Ask the customer to contact their bank.',
        icon: Icons.block_rounded,
        color: Color(0xFFE74C3C),
      );
    case '51':
      return const _TxFailure(
        title: 'Insufficient Funds',
        detail: 'The customer doesn\'t have enough balance for this amount.',
        icon: Icons.account_balance_wallet_outlined,
        color: Color(0xFFE67E22),
      );
    case '54':
      return const _TxFailure(
        title: 'Card Expired',
        detail:
            'This card has expired. Ask the customer to use a different card.',
        icon: Icons.credit_card_off_rounded,
        color: Color(0xFFE74C3C),
      );
    case '55':
      return const _TxFailure(
        title: 'Incorrect PIN',
        detail: 'The PIN entered was wrong. Ask the customer to try again.',
        icon: Icons.lock_outline_rounded,
        color: Color(0xFFE67E22),
      );
    case '56':
      return const _TxFailure(
        title: 'Card Not Found',
        detail: 'This card could not be found. Try a different card.',
        icon: Icons.credit_card_off_rounded,
        color: Color(0xFFE74C3C),
      );
    case '57':
    case '58':
    case '59':
      return const _TxFailure(
        title: 'Transaction Not Allowed',
        detail:
            'The customer\'s bank has not permitted this type of transaction.',
        icon: Icons.do_not_disturb_alt_rounded,
        color: Color(0xFFE74C3C),
      );
    case '61':
      return const _TxFailure(
        title: 'Limit Exceeded',
        detail: 'This amount exceeds the customer\'s daily withdrawal limit.',
        icon: Icons.remove_circle_outline_rounded,
        color: Color(0xFFE67E22),
      );
    case '63':
      return const _TxFailure(
        title: 'Security Check Failed',
        detail:
            'A security check failed. Ask the customer to contact their bank.',
        icon: Icons.security_rounded,
        color: Color(0xFFE74C3C),
      );
    case '65':
      return const _TxFailure(
        title: 'Too Many Transactions',
        detail:
            'The customer has exceeded their daily transaction limit. Try later.',
        icon: Icons.repeat_rounded,
        color: Color(0xFFE67E22),
      );
    case '91':
      return const _TxFailure(
        title: 'Bank Unavailable',
        detail:
            'The customer\'s bank is temporarily unavailable. Try again shortly.',
        icon: Icons.cloud_off_rounded,
        color: Color(0xFFE67E22),
      );
    case '96':
      return const _TxFailure(
        title: 'System Error',
        detail: 'A system error occurred at the bank. Please try again.',
        icon: Icons.error_outline_rounded,
        color: Color(0xFFE67E22),
      );
    default:
      return const _TxFailure(
        title: 'Payment Declined',
        detail: 'The transaction was declined by the bank.',
        icon: Icons.block_rounded,
        color: Color(0xFFE74C3C),
      );
  }
}

_TxFailure _tappaFailure(int code, String? raw) {
  switch (code) {
    case -21:
      return const _TxFailure(
        title: 'Card Not Detected',
        detail: 'Hold the card steady on the back of the device and try again.',
        icon: Icons.nfc_rounded,
        color: Color(0xFFE67E22),
      );
    case 32:
      return const _TxFailure(
        title: 'Network Error',
        detail:
            'A network error occurred during PIN verification. Check your connection and try again.',
        icon: Icons.wifi_off_rounded,
        color: Color(0xFFE67E22),
      );
    case 50:
      return const _TxFailure(
        title: 'Card Read Failed',
        detail:
            'The card could not be read. Try tapping again or use a different card.',
        icon: Icons.nfc_rounded,
        color: Color(0xFFE67E22),
      );
    case 30:
    case 31:
    case 33:
    case 34:
    case 35:
    case 36:
    case 37:
    case 38:
    case 39:
      return const _TxFailure(
        title: 'PIN Entry Failed',
        detail: 'The PIN could not be verified. Ask the customer to try again.',
        icon: Icons.lock_outline_rounded,
        color: Color(0xFFE67E22),
      );
    case 100:
    case 101:
    case 102:
    case 103:
    case 104:
      return const _TxFailure(
        title: 'Card Error',
        detail: 'An error occurred reading the card. Try tapping again.',
        icon: Icons.credit_card_off_rounded,
        color: Color(0xFFE74C3C),
      );
    default:
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final data = decoded['data'] as Map<String, dynamic>?;
          final field39 = data?['field39'] as String?;
          if (field39 != null) return _iso8583Failure(field39);
          final msg = decoded['message'] as String?;
          if (msg != null && msg.isNotEmpty) {
            return _TxFailure(
              title: 'Payment Failed',
              detail: msg,
              icon: Icons.error_outline_rounded,
              color: const Color(0xFFE74C3C),
            );
          }
        } catch (_) {}
      }
      return const _TxFailure(
        title: 'Payment Failed',
        detail: 'The transaction could not be completed. Please try again.',
        icon: Icons.error_outline_rounded,
        color: Color(0xFFE74C3C),
      );
  }
}

/// Formats an amount string (e.g. "1000.00") with thousand separators.
String _formatAmountDisplay(String amountStr) {
  final parts = amountStr.split('.');
  final intPart = parts[0];
  final decPart = parts.length > 1 ? parts[1] : '';

  final buffer = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(intPart[i]);
  }

  return decPart.isNotEmpty
      ? '${buffer.toString()}.$decPart'
      : buffer.toString();
}

// -- VA data helpers ----------------------------------------------------------
Map<String, dynamic> _normalizeVaData(dynamic raw, String uid) {
  final va = raw as Map<String, dynamic>;
  debugPrint('[Settlement] _normalizeVaData input keys: ${va.keys.toList()}');

  final attrs = va['attributes'] as Map<String, dynamic>?;
  debugPrint('[Settlement] attributes block present: ${attrs != null}');
  if (attrs != null) {
    debugPrint('[Settlement] attributes keys: ${attrs.keys.toList()}');
    debugPrint('[Settlement] attributes.bank: ${attrs['bank']}');
  }

  final bankObj = attrs?['bank'] as Map<String, dynamic>?;
  final bankId = bankObj?['id']?.toString() ?? '';
  final bankName = bankObj?['name']?.toString() ?? '';

  final fallbackBankId = va['bankId']?.toString() ?? '';
  final fallbackBankName = va['bankName']?.toString() ?? '';

  return {
    'uid': uid,
    'id': va['id']?.toString() ?? '',
    'type': va['type']?.toString() ?? '',
    'bankId': bankId.isNotEmpty ? bankId : fallbackBankId,
    'bankName': bankName.isNotEmpty ? bankName : fallbackBankName,
    'accountNumber':
        attrs?['accountNumber']?.toString() ??
        va['accountNumber']?.toString() ??
        '',
    'accountName':
        attrs?['accountName']?.toString() ??
        va['accountName']?.toString() ??
        '',
  };
}

Future<Map<String, dynamic>?> _fetchCompanyVirtualAccount() async {
  debugPrint('[Settlement] ── _fetchCompanyVirtualAccount() ─────────────────');
  try {
    final doc = await FirebaseFirestore.instance
        .collection('company')
        .doc('account_details')
        .get();

    if (!doc.exists) {
      debugPrint('[Settlement] company/account_details doc does NOT exist');
      return null;
    }

    final data = doc.data() ?? <String, dynamic>{};
    debugPrint(
      '[Settlement] company/account_details raw keys: ${data.keys.toList()}',
    );

    final result = {
      'uid': 'company',
      'id': data['accountId']?.toString() ?? '',
      'type': data['accountType']?.toString() ?? '',
      'bankId': data['bankId']?.toString() ?? '',
      'bankName': data['bankName']?.toString() ?? '',
      'accountNumber': data['accountNumber']?.toString() ?? '',
      'accountName': data['accountName']?.toString() ?? '',
    };

    debugPrint(
      '[Settlement] Company VA → id=${result['id']} | type=${result['type']} | '
      'bank=${result['bankName']} (${result['bankId']}) | '
      'account=${result['accountNumber']} | name=${result['accountName']}',
    );
    return result;
  } catch (e, st) {
    debugPrint('[Settlement] _fetchCompanyVirtualAccount ERROR: $e\n$st');
    return null;
  }
}

Future<Map<String, dynamic>?> _fetchMerchantVirtualAccount() async {
  debugPrint('[Settlement] ── _fetchMerchantVirtualAccount() ────────────────');
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    debugPrint('[Settlement] No authenticated user — aborting');
    return null;
  }
  debugPrint('[Settlement] Fetching VA for uid=${user.uid}');

  try {
    Map<String, dynamic>? normalizedVa;
    bool needsBankIdUpdate = false;
    String existingBankName = '';

    debugPrint('[Settlement] Trying businesses/${user.uid}...');
    final businessDoc = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(user.uid)
        .get();

    if (businessDoc.exists) {
      final data = businessDoc.data();
      debugPrint(
        '[Settlement] businesses doc exists. Keys: ${data?.keys.toList()}',
      );

      if (data != null) {
        final safehavenData = data['safehavenData'] as Map<String, dynamic>?;
        dynamic vaRaw = safehavenData?['virtualAccount']?['data'];

        vaRaw ??= data['virtualAccount'];

        if (vaRaw != null) {
          debugPrint('[Settlement] Raw VA from businesses: $vaRaw');
          normalizedVa = _normalizeVaData(vaRaw, user.uid);

          final bankId = normalizedVa['bankId'] as String? ?? '';
          existingBankName = normalizedVa['bankName'] as String? ?? '';

          if (bankId.isEmpty) {
            debugPrint(
              '[Settlement] ⚠️ BankId is missing for merchant VA in businesses!',
            );
            needsBankIdUpdate = true;
          } else {
            debugPrint(
              '[Settlement] Normalized (businesses) → '
              'id=${normalizedVa['id']} | bank=${normalizedVa['bankName']} (${normalizedVa['bankId']}) | '
              'account=${normalizedVa['accountNumber']} | name=${normalizedVa['accountName']}',
            );
            return normalizedVa;
          }
        }
      }
    } else {
      debugPrint('[Settlement] businesses/${user.uid} doc does NOT exist');
    }

    if (normalizedVa == null || needsBankIdUpdate) {
      debugPrint('[Settlement] Falling back to users/${user.uid}...');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data();
        debugPrint('[Settlement] users doc keys: ${data?.keys.toList()}');

        final vaRaw = data?['safehavenData']?['virtualAccount']?['data'];
        debugPrint(
          '[Settlement] users safehavenData.virtualAccount.data present: ${vaRaw != null}',
        );

        if (vaRaw != null) {
          debugPrint('[Settlement] Raw VA from users: $vaRaw');
          normalizedVa = _normalizeVaData(vaRaw, user.uid);

          final bankId = normalizedVa['bankId'] as String? ?? '';
          existingBankName = normalizedVa['bankName'] as String? ?? '';

          if (bankId.isEmpty) {
            debugPrint(
              '[Settlement] ⚠️ BankId is missing for merchant VA in users!',
            );
            needsBankIdUpdate = true;
          } else {
            debugPrint(
              '[Settlement] Normalized (users) → '
              'id=${normalizedVa['id']} | bank=${normalizedVa['bankName']} (${normalizedVa['bankId']}) | '
              'account=${normalizedVa['accountNumber']} | name=${normalizedVa['accountName']}',
            );
            needsBankIdUpdate = false;
            return normalizedVa;
          }
        }
      } else {
        debugPrint('[Settlement] users/${user.uid} doc does NOT exist');
      }
    }

    if (normalizedVa != null && needsBankIdUpdate) {
      final accountId = normalizedVa['id'] as String? ?? '';
      if (accountId.isEmpty) {
        debugPrint(
          '[Settlement] ❌ Cannot fetch customer account - accountId is empty',
        );
        return null;
      }

      debugPrint(
        '[Settlement] 🔍 Fetching customer account to get missing bankId for accountId: $accountId',
      );

      try {
        final HttpsCallableResult result = await FirebaseFunctions.instance
            .httpsCallable('fetchCustomerAccount')
            .call({'accountId': accountId});

        debugPrint(
          '[Settlement] fetchCustomerAccount result type: ${result.data.runtimeType}',
        );
        debugPrint('[Settlement] fetchCustomerAccount result: ${result.data}');

        final dynamic responseData = result.data;
        Map<String, dynamic>? accountData;

        if (responseData is Map) {
          accountData = Map<String, dynamic>.from(responseData);
        } else if (responseData is String) {
          try {
            accountData = jsonDecode(responseData) as Map<String, dynamic>;
          } catch (e) {
            debugPrint(
              '[Settlement] Failed to parse response string as JSON: $e',
            );
            accountData = null;
          }
        }

        if (accountData == null) {
          debugPrint(
            '[Settlement] ❌ Could not parse fetchCustomerAccount response',
          );
          return normalizedVa;
        }

        debugPrint(
          '[Settlement] Parsed accountData keys: ${accountData.keys.toList()}',
        );

        Map<String, dynamic>? attributes;
        Map<String, dynamic>? bank;

        if (accountData.containsKey('data')) {
          final dataObj = accountData['data'];
          if (dataObj is Map) {
            attributes = Map<String, dynamic>.from(dataObj['attributes'] ?? {});
            if (attributes.containsKey('bank')) {
              final bankObj = attributes['bank'];
              if (bankObj is Map) bank = Map<String, dynamic>.from(bankObj);
            }
          }
        }

        if (bank == null && accountData.containsKey('attributes')) {
          attributes = Map<String, dynamic>.from(
            accountData['attributes'] ?? {},
          );
          if (attributes.containsKey('bank')) {
            final bankObj = attributes['bank'];
            if (bankObj is Map) bank = Map<String, dynamic>.from(bankObj);
          }
        }

        if (bank == null && accountData.containsKey('bank')) {
          final bankObj = accountData['bank'];
          if (bankObj is Map) bank = Map<String, dynamic>.from(bankObj);
        }

        final fetchedBankId = bank?['id']?.toString() ?? '';
        final fetchedBankName = bank?['name']?.toString() ?? '';

        if (fetchedBankId.isNotEmpty) {
          debugPrint('[Settlement] ✅ Retrieved bankId: $fetchedBankId');

          normalizedVa['bankId'] = fetchedBankId;
          if (existingBankName.isEmpty && fetchedBankName.isNotEmpty) {
            normalizedVa['bankName'] = fetchedBankName;
          }

          final Map<String, dynamic> updateData = {};
          updateData['safehavenData.virtualAccount.data.attributes.bank.id'] =
              fetchedBankId;
          updateData['bankId'] = fetchedBankId;

          if (existingBankName.isEmpty && fetchedBankName.isNotEmpty) {
            updateData['safehavenData.virtualAccount.data.attributes.bank.name'] =
                fetchedBankName;
            updateData['bankName'] = fetchedBankName;
          }

          final bDoc = await FirebaseFirestore.instance
              .collection('businesses')
              .doc(user.uid)
              .get();
          if (bDoc.exists) {
            await bDoc.reference.update(updateData);
            debugPrint(
              '[Settlement] ✅ Missing bankId saved to businesses collection',
            );
          } else {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update(updateData);
            debugPrint(
              '[Settlement] ✅ Missing bankId saved to users collection',
            );
          }

          return normalizedVa;
        } else {
          debugPrint(
            '[Settlement] ⚠️ No bankId found in customer account response',
          );
          return normalizedVa;
        }
      } catch (e, st) {
        debugPrint(
          '[Settlement] ❌ Error calling fetchCustomerAccount: $e\n$st',
        );
        return normalizedVa;
      }
    }
  } catch (e, st) {
    debugPrint('[Settlement] _fetchMerchantVirtualAccount ERROR: $e\n$st');
    return null;
  }
  return null;
}

// -----------------------------------------------------------------------------
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  double _rawAmount = 0;
  String _chargedAmount = '';
  String _merchantName = 'Padi Pay Business';
  final FlutterTappa _tappa = FlutterTappa();
  static const MethodChannel _nfcChannel = MethodChannel(
    'com.padipay/tappa_nfc',
  );
  // Raw channels for armTagDetection — bypasses the Dart wrapper so we can
  // use the published flutter_tappa 0.0.7-2 without needing a local fork.
  static const MethodChannel _tappaRawChannel = MethodChannel('flutter_tappa');
  static const EventChannel _tappaEventChannel = EventChannel(
    'com.mba.tappa/events',
  );
  StreamSubscription<dynamic>? _tagDetectionSub;

  bool _isTransactionActive = false;

  // ── Single source of truth for button disabled/loading state ──────────────
  bool _txActive = false;

  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  final TextEditingController _tagController = TextEditingController();

  _InitStatus _initStatus = _InitStatus.loading;
  String _initError = '';
  _TxStatus _txStatus = _TxStatus.idle;
  _TxFailure? _txFailure;
  String _txRrn = '';
  String _safeHavenRrn =
      ''; // retrievalReferenceNumber from Safe Haven's Kimono response
  String? _txDocId; // Firestore document ID of the saved ATM transaction
  bool _isReconciling = false;
  String? _reconcileResult; // 'success' | 'failed' | 'pending' | null

  // ── Eager settlement state ────────────────────────────────────────────────
  Map<String, dynamic>? _companyVa;
  Map<String, dynamic>? _merchantVa;
  String? _settlementCounterpartyId;
  bool _settlementReady = false;
  String _settlementSetupError = '';

  Completer<String>? _txCompleter;
  DateTime? _txStartTime; // when the 90s timeout began
  final StreamController<String?> _nfcStatusNotifier =
      StreamController<String?>.broadcast();

  bool _initializing = false;
  bool _isDisposed = false;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _autoInit();
    _lifecycleListener = AppLifecycleListener(
      onPause: _onAppPaused,
      onDetach: _stopNfc,
      onResume: _onAppResumed,
    );
  }

  /// Called when app moves to background. If a transaction is active it means
  /// the card was read and PinActivity is opening — fire the card-tap vibration.
  Future<void> _onAppPaused() async {
    if (_isTransactionActive) {
      debugPrint('[Tappa] App paused with active tx — card read vibration');
      _playCardDetectedFeedback();
    } else {
      await _stopNfc();
    }
  }

  /// Called when MainActivity comes back to foreground (e.g. after PinActivity
  /// closes). If Tappa's callback hasn't fired within 500 ms, that means the
  /// user cancelled — complete the completer as cancelled.
  // AFTER:

  // WITH THIS:
  Future<void> _onAppResumed() async {
    // Do NOT cancel the completer. Just log that we resumed.
    debugPrint(
      '[Tappa] App resumed, pending completer exists: ${_txCompleter != null && !_txCompleter!.isCompleted}',
    );
    // The callback will arrive via the TransactionService eventually.
    // If you need to handle the case where the PinActivity was dismissed without a callback,
    // the 90-second timeout will handle it.
  }

  Future<void> _stopNfc() async {
    if (_isTransactionActive) {
      debugPrint('[Tappa] NFC stop prevented - transaction active');
      return;
    }

    try {
      debugPrint('[Tappa] Disabling NFC reader mode (native)');
      await _nfcChannel.invokeMethod('disableReaderMode');
      debugPrint('[Tappa] ✅ NFC reader mode disabled');
    } catch (e) {
      debugPrint('[Tappa] Failed to disable reader mode: $e');
    }
  }

  Future<void> _onCharge() async {
    if (_isDisposed || !mounted) {
      debugPrint('[Tappa] Cannot charge - widget disposed or not mounted');
      return;
    }

    final double? naira = double.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );
    if (naira == null || naira < 50 || naira > 500000) return;

    final int kobo = (naira * 100).round();
    final String rrn = _generateRrn();
    final String txTagInput = _tagController.text.trim().toLowerCase();
    final bool simulateSlowNetwork = kDebugMode && txTagInput.contains('#slow');
    final bool simulateNetworkOutage =
        kDebugMode && txTagInput.contains('#outage');
    _txRrn = rrn;
    _rawAmount = naira;
    _chargedAmount = _formatAmountDisplay(naira.toString());

    // Start transaction in the global service BEFORE calling transact()
    TransactionService().startTransaction(
      rrn: rrn,
      amount: naira,
      chargedAmount: _chargedAmount,
      tag: _tagController.text.trim(),
    );

    // Store the Future – NOT a Completer
    final transactionFuture = TransactionService().future;

    // Still keep global vars for legacy references (optional; can remove)
    _globalTxRrn = rrn;
    _globalRawAmount = naira;
    _globalChargedAmount = _formatAmountDisplay(naira.toString());
    _globalTxTag = _tagController.text.trim();
    _isTransactionActive = true;

    setState(() {
      _txActive = true;
      _txStatus = _TxStatus.processing;
    });

    debugPrint(
      '[Tappa] Charge initiated — amount=NGN$_chargedAmount kobo=$kobo rrn=$rrn',
    );
    await _saveTappaLog(
      eventType: 'transaction_initiated',
      status: 'processing',
      amount: _chargedAmount,
      rrn: rrn,
      additionalData: {'koboAmount': kobo},
    );

    if (!mounted) return;

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return _NfcTapDialog(
          statusStream: _nfcStatusNotifier.stream,
          onCancel: () {
            debugPrint('[Tappa] Transaction cancelled by user');
            TransactionService().completeError(const _CancelledException());
          },
        );
      },
    );

    try {
      await _tappa.transact(
        amount: kobo.toString(),
        accountType: 'savings',
        rrn: rrn,
      );

      if (simulateSlowNetwork)
        await Future.delayed(const Duration(seconds: 15));
      if (simulateNetworkOutage) {
        _nfcStatusNotifier.add('__uncertain__');
        throw const _UncertainException();
      }

      // Arm tag detection (optional)
      _tagDetectionSub?.cancel();
      _tagDetectionSub = _tappaEventChannel.receiveBroadcastStream().listen((
        event,
      ) {
        if (event is Map && event['event'] == 'tag_detected') {
          _tagDetectionSub?.cancel();
          _tagDetectionSub = null;
          if (mounted && !_nfcStatusNotifier.isClosed) {
            _nfcStatusNotifier.add('__reading__');
          }
        }
      }, onError: (e) => debugPrint('[Tappa] tagDetection event error: $e'));
      _tappaRawChannel
          .invokeMethod<void>('armTagDetection', {
            'amount': kobo.toString(),
            'accountType': 'savings',
            'rrn': rrn,
          })
          .catchError(
            (e) => debugPrint('[Tappa] armTagDetection invoke failed: $e'),
          );

      debugPrint(
        '[Tappa] transact() armed NFC — waiting for result via callback...',
      );

      String cardData;
      _txStartTime = DateTime.now();
      cardData = await transactionFuture.timeout(
        const Duration(
          seconds: 105,
        ), // 90s shown to user + 15s grace for late callbacks
        onTimeout: () {
          debugPrint(
            '[Tappa] ⏰ 105s timeout — no late callback arrived, marking failed',
          );
          // completeError cleans up the service; safe to call even if already completed
          TransactionService().completeError(
            const _PaymentException(
              _TxFailure(
                title: 'Payment Failed',
                detail:
                    'Transaction timed out. If your customer was debited, please reconcile manually using the RRN.',
                icon: Icons.timer_off_rounded,
                color: Color(0xFFE74C3C),
              ),
            ),
          );
          // completeError threw via the future; this line is unreachable but
          // required to satisfy the onTimeout return type.
          throw const _PaymentException(
            _TxFailure(
              title: 'Payment Failed',
              detail: 'Timed out.',
              icon: Icons.timer_off_rounded,
              color: Color(0xFFE74C3C),
            ),
          );
        },
      );
      await _saveTappaLog(
        eventType: 'transaction_success',
        status: 'success',
        amount: _chargedAmount,
        rrn: rrn,
        cardData: cardData,
      );

      if (dialogContext != null && mounted) Navigator.of(dialogContext!).pop();
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        final savedAmount = _rawAmount.toStringAsFixed(0);
        final savedRef = _txRrn;

        // Parse fees for display only – transaction already saved by service
        Map<String, dynamic>? parsedCardData;
        int fees = 0;
        try {
          parsedCardData = jsonDecode(cardData) as Map<String, dynamic>;
          final dynamic rawFees = parsedCardData['data']?['fees'];
          fees = (rawFees as num?)?.toInt() ?? 0;
        } catch (e) {
          debugPrint('[Tappa] Failed to parse fees: $e');
        }

        _amountController.clear();
        _tagController.clear();
        // After showing the success modal (or before, but after the transaction Future completes)
        unawaited(_executeSettlement(amountNaira: _rawAmount, rrn: _txRrn));

        showModalBottomSheet(
          context: context,
          isDismissible: false,
          enableDrag: false,
          builder: (_) => AtmPaymentSuccessfulPage(
            amount: savedAmount,
            actionText: 'New Transaction',
            title: 'Payment Received',
            description: 'Contactless card payment processed successfully.',
            recipientName: '',
            bankName: '',
            bankCode: '',
            accountNumber: '',
            reference: savedRef,
            fees: fees.toString(),
            cardData: parsedCardData,
          ),
          isScrollControlled: true,
        );
      }
    } catch (e) {
      debugPrint('[Tappa] Transaction error: $e');
      final cancelled = e is _CancelledException;
      final uncertain = e is _UncertainException;

      await _saveTappaLog(
        eventType: uncertain
            ? 'transaction_pending'
            : cancelled
            ? 'transaction_cancelled'
            : 'transaction_failed',
        status: uncertain ? 'pending' : (cancelled ? 'cancelled' : 'failed'),
        amount: _chargedAmount,
        rrn: _txRrn,
        errorCode: cancelled
            ? 'CANCELLED'
            : uncertain
            ? 'PENDING'
            : e.toString(),
        errorMessage: cancelled
            ? 'User cancelled transaction'
            : uncertain
            ? 'Network dropped mid-transaction — payment status pending reconciliation. RRN: $_txRrn'
            : (e is _PaymentException ? e.failure.detail : e.toString()),
        additionalData: {
          'errorType': e.runtimeType.toString(),
          'cancelled': cancelled,
          'uncertain': uncertain,
        },
      );

      if (mounted) {
        if (dialogContext != null) Navigator.of(dialogContext!).pop();

        if (uncertain) {
          setState(() => _txStatus = _TxStatus.uncertain);
          // Service already saved pending; keep screen for reconciliation
          _reconcileCurrentTransaction();
        } else if (cancelled) {
          debugPrint('[Tappa] Reinitialising after PIN cancel...');
          TransactionService().completeError(
            const _CancelledException(),
          ); // ensure service cleans up
          _autoInit();
        } else {
          final failure = e is _PaymentException
              ? e.failure
              : _TxFailure(
                  title: 'Payment Declined',
                  detail: e.toString(),
                  icon: Icons.block_rounded,
                  color: const Color(0xFFE74C3C),
                );
          setState(() => _txFailure = failure);
        }
      }
    } finally {
      _tagDetectionSub?.cancel();
      _tagDetectionSub = null;
      _isTransactionActive = false;
      _nfcStatusNotifier.add(null);

      if (mounted) {
        setState(() {
          _txActive = false;
          if (_txFailure != null) {
            _txStatus = _TxStatus.failed;
          } else if (_txStatus == _TxStatus.uncertain) {
            // keep uncertain
          } else {
            _txStatus = _TxStatus.idle;
            _chargedAmount = '';
            _rawAmount = 0;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    debugPrint('[PaymentScreen] Disposing...');
    _lifecycleListener.dispose();

    // Do NOT stop NFC – let the native reader mode stay disabled, but keep the callback alive.
    // The plugin is already initialized and the errorCallback will still work.

    _tagDetectionSub?.cancel();
    _tagDetectionSub = null;
    _nfcStatusNotifier.add(null);
    _nfcStatusNotifier.close();

    _amountController.dispose();
    _amountFocus.dispose();
    _tagController.dispose();
    _initializing = false;
    _isDisposed = true;

    debugPrint('[PaymentScreen] Disposed (NFC callback preserved)');
    super.dispose();
  }

  Future<void> _autoInit() async {
    if (_initializing) return;
    debugPrint('[Init] ── _autoInit() ──────────────────────────────────────');
    setState(() {
      _initStatus = _InitStatus.loading;
      _settlementReady = false;
      _settlementSetupError = '';
    });
    _initializing = true;

    try {
      final settlementFuture = _prepareSettlement();

      await _tappa.initialize(
        errorCallback: (errorCode, errorMessage) async {
          debugPrint('[Tappa] CALLBACK: code=$errorCode message=$errorMessage');

          // Handle initialization phase errors
          if (_initializing) {
            debugPrint('[Tappa] Init-phase error received via callback');
            final failure = _tappaFailure(errorCode, errorMessage);
            await _saveTappaLog(
              eventType: 'terminal_initialization',
              status: 'failed',
              errorCode: errorCode.toString(),
              errorMessage: errorMessage,
              additionalData: {'phase': 'initialization_callback'},
            );
            if (mounted) {
              setState(() {
                _initializing = false;
                _initStatus = _InitStatus.error;
                _initError = failure.detail;
              });
            }
            return;
          }

          // No active transaction? ignore
          if (!TransactionService().hasPending) {
            debugPrint('[Tappa] Callback ignored - no active transaction');
            return;
          }

          // Parse the response
          bool isSuccess = false;
          String? failureReason;
          String? field39;
          String? statusCode;
          Map<String, dynamic>? parsedResponse;

          try {
            if (errorMessage.isNotEmpty) {
              parsedResponse = jsonDecode(errorMessage) as Map<String, dynamic>;
              statusCode = parsedResponse['statusCode']?.toString();

              final dataObj = parsedResponse['data'] as Map<String, dynamic>?;
              if (dataObj != null) {
                field39 = dataObj['field39'] as String?;
                final transactionStatus = dataObj['status'] as String?;
                failureReason = parsedResponse['message'] as String?;

                final description = dataObj['description'] as String?;
                if (description != null && description.isNotEmpty) {
                  failureReason = description;
                }

                isSuccess =
                    transactionStatus == 'SUCCESS' ||
                    transactionStatus == 'APPROVED';

                debugPrint(
                  '[Tappa] Parsed - statusCode=$statusCode, status=$transactionStatus, field39=$field39, isSuccess=$isSuccess',
                );
                debugPrint('[Tappa] failureReason=$failureReason');
              }
            }
          } catch (e) {
            debugPrint('[Tappa] Failed to parse response: $e');
          }

          if (isSuccess) {
            debugPrint('[Tappa] Transaction APPROVED - actual success');
            _playCardDetectedFeedback();

            // ── Late callback: UI timeout already fired ───────────────────
            if (TransactionService().isCompleted) {
              debugPrint(
                '[Tappa] ⚠️ Late success callback after UI timeout — handling directly',
              );

              // Snapshot screen state NOW before any async gap clears it
              final lateRrn = _txRrn;
              final lateAmount = _rawAmount;
              final lateTag = _tagController.text.trim();
              final lateCardData = errorMessage;

              await _saveTappaLog(
                eventType: 'transaction_success_late',
                status: 'success',
                amount: _chargedAmount,
                rrn: lateRrn,
                cardData: lateCardData,
                additionalData: {'note': 'arrived after UI timeout'},
              );

              final saved = await TransactionService().handleLateSuccess(
                cardData: lateCardData,
                rrn: lateRrn,
                amount: lateAmount,
                tag: lateTag,
              );

              if (saved) {
                // Settlement — customer was debited, merchant must receive funds
                unawaited(
                  _executeSettlement(amountNaira: lateAmount, rrn: lateRrn),
                );

                if (mounted) {
                  Map<String, dynamic>? parsedCardData;
                  int fees = 0;
                  try {
                    parsedCardData =
                        jsonDecode(lateCardData) as Map<String, dynamic>;
                    fees =
                        ((parsedCardData['data']?['fees'] as num?)?.toInt()) ??
                        0;
                  } catch (_) {}

                  // Clear any failed/uncertain UI state before showing success
                  setState(() {
                    _txStatus = _TxStatus.idle;
                    _txFailure = null;
                    _txActive = false;
                    _amountController.clear();
                    _tagController.clear();
                  });

                  showModalBottomSheet(
                    context: context,
                    isDismissible: false,
                    enableDrag: false,
                    isScrollControlled: true,
                    builder: (_) => AtmPaymentSuccessfulPage(
                      amount: lateAmount.toStringAsFixed(0),
                      actionText: 'New Transaction',
                      title: 'Payment Received',
                      description:
                          'Contactless card payment processed successfully.',
                      recipientName: '',
                      bankName: '',
                      bankCode: '',
                      accountNumber: '',
                      reference: lateRrn,
                      fees: fees.toString(),
                      cardData: parsedCardData,
                    ),
                  );
                }
              }
              return;
            }

            // ── Normal path: callback arrived before timeout ──────────────
            final elapsed = _txStartTime != null
                ? DateTime.now().difference(_txStartTime!).inSeconds
                : 0;
            final remaining = (90 - elapsed).clamp(5, 90);
            _nfcStatusNotifier.add('__processing__:$remaining');
            TransactionService().completeSuccess(errorMessage);
            return;
          }

          // Handle failures
          debugPrint('[Tappa] Transaction FAILED');

          // Code 32: uncertain or cancelled
          if (errorCode == 32) {
            final hasBankContact =
                parsedResponse != null &&
                (parsedResponse['statusCode'] != null ||
                    parsedResponse['data'] != null);
            if (hasBankContact) {
              debugPrint(
                '[Tappa] ⚠️ Code 32 with bank response — pending outcome',
              );
              await _saveTappaLog(
                eventType: 'transaction_pending',
                status: 'pending',
                amount: _chargedAmount,
                rrn: _txRrn,
                errorCode: '32',
                errorMessage:
                    'Network error mid-transaction — payment status pending reconciliation',
                additionalData: {
                  'statusCode': statusCode,
                  'full_response': errorMessage,
                },
              );
              _nfcStatusNotifier.add('__uncertain__');
              TransactionService().completeError(const _UncertainException());
            } else {
              debugPrint(
                '[Tappa] Code 32 with no bank data — treating as PIN cancel',
              );
              TransactionService().completeError(const _CancelledException());
            }
            return;
          }

          String errorDetail = 'Transaction failed';
          if (field39 != null && field39.isNotEmpty) {
            errorDetail = _getField39Message(field39);
            debugPrint('[Tappa] Using field39 ($field39): $errorDetail');
          } else if (failureReason != null && failureReason.isNotEmpty) {
            errorDetail = failureReason;
            debugPrint('[Tappa] Using failureReason: $errorDetail');
          } else if (parsedResponse != null) {
            final dataObj = parsedResponse['data'] as Map<String, dynamic>?;
            final message = parsedResponse['message'] as String?;
            if (message != null && message.isNotEmpty) {
              errorDetail = message;
            } else if (dataObj?['description'] != null) {
              errorDetail = dataObj!['description'].toString();
            }
          }

          await _saveTappaLog(
            eventType: 'transaction_failed',
            status: 'failed',
            amount: _chargedAmount,
            rrn: _txRrn,
            errorCode: errorCode.toString(),
            errorMessage: errorDetail,
            additionalData: {
              'field39': field39,
              'statusCode': statusCode,
              'full_response': errorMessage,
              'hard_failure': true,
            },
          );

          final elapsed2 = _txStartTime != null
              ? DateTime.now().difference(_txStartTime!).inSeconds
              : 0;
          final remaining2 = (90 - elapsed2).clamp(5, 90);
          _nfcStatusNotifier.add('__processing__:$remaining2');

          TransactionService().completeError(
            _PaymentException(
              _TxFailure(
                title: _getFailureTitle(field39),
                detail: errorDetail,
                icon: Icons.block_rounded,
                color: const Color(0xFFE74C3C),
              ),
            ),
          );
        },
        isSandBoxMode: false,
      );

      _merchantName = await _getMerchantName();
      debugPrint('[Tappa] Terminal merchant name: $_merchantName');

      await _tappa.initTerminal(
        terminalId: _kTerminalId,
        uniqueId: _kUniqueId,
        clientId: _kClientId,
        merchantLocation: _merchantName,
      );

      debugPrint('[Tappa] Terminal ready');
      _initializing = false;
      if (mounted) setState(() => _initStatus = _InitStatus.ready);

      await settlementFuture;
    } catch (e) {
      debugPrint('[Init] Auto-init failed: $e');
      _initializing = false;
      if (mounted) {
        setState(() {
          _initStatus = _InitStatus.error;
          _initError = e.toString();
        });
      }
    }
  }

  String _getFailureTitle(String? field39) {
    if (field39 == null) return 'Payment Declined';
    switch (field39) {
      case '01':
        return 'Contact Your Bank';
      case '05':
        return 'Payment Declined';
      case '12':
        return 'Invalid Transaction';
      case '13':
        return 'Invalid Amount';
      case '14':
        return 'Invalid Card';
      case '41':
      case '43':
        return 'Card Restricted';
      case '51':
        return 'Insufficient Funds';
      case '54':
        return 'Card Expired';
      case '55':
        return 'Incorrect PIN';
      case '57':
      case '58':
      case '59':
        return 'Transaction Not Allowed';
      case '61':
        return 'Limit Exceeded';
      case '65':
        return 'Too Many Transactions';
      case '75':
        return 'PIN Attempts Exceeded';
      case '91':
        return 'Bank Unavailable';
      case '96':
        return 'System Error';
      default:
        return 'Payment Declined';
    }
  }

  String _getField39Message(String field39) {
    switch (field39) {
      case '01':
        return 'Please ask the customer to contact their bank before trying again.';
      case '05':
        return 'The customer\'s bank declined this transaction. Try a different card.';
      case '12':
        return 'This transaction type is not supported for this card.';
      case '13':
        return 'The amount entered is not valid for this card.';
      case '14':
        return 'The card details could not be verified. Try tapping again.';
      case '41':
      case '43':
        return 'This card has been reported. Ask the customer to contact their bank.';
      case '51':
        return 'The customer doesn\'t have enough balance for this amount.';
      case '54':
        return 'This card has expired. Ask the customer to use a different card.';
      case '55':
        return 'The PIN entered was wrong. Ask the customer to try again.';
      case '57':
      case '58':
      case '59':
        return 'The customer\'s bank has not permitted this type of transaction.';
      case '61':
        return 'This amount exceeds the customer\'s daily withdrawal limit.';
      case '65':
        return 'The customer has exceeded their daily transaction limit. Try later.';
      case '75':
        return 'Too many PIN attempts. The card may be temporarily blocked.';
      case '91':
        return 'The customer\'s bank is temporarily unavailable. Try again shortly.';
      case '96':
        return 'A system error occurred at the bank. Please try again.';
      default:
        return 'Transaction declined. Please try again with a different card.';
    }
  }

  // ── Settlement pre-setup ──────────────────────────────────────────────────

  Future<void> _prepareSettlement() async {
    debugPrint('[Settlement] ══ _prepareSettlement() ══════════════════════');
    try {
      final results = await Future.wait([
        _fetchCompanyVirtualAccount(),
        _fetchMerchantVirtualAccount(),
      ]);

      final companyVa = results[0];
      final merchantVa = results[1];

      debugPrint('[Settlement] Company VA fetched: ${companyVa != null}');
      debugPrint('[Settlement] Merchant VA fetched: ${merchantVa != null}');

      if (companyVa == null || (companyVa['id'] as String).isEmpty) {
        throw Exception('Company VA not found or id is empty');
      }
      if (merchantVa == null) {
        throw Exception('Merchant VA not found');
      }

      if ((merchantVa['id'] as String? ?? '').isEmpty) {
        throw Exception(
          'Merchant account ID is empty. Full VA map: $merchantVa',
        );
      }

      _companyVa = companyVa;
      _merchantVa = merchantVa;

      debugPrint(
        '[Settlement] ✅ Settlement ready — company=${companyVa["id"]}, merchant=${merchantVa["id"]}',
      );
      if (mounted) setState(() => _settlementReady = true);
    } catch (e, st) {
      debugPrint('[Settlement] ❌ _prepareSettlement failed: $e\n$st');
      if (mounted) setState(() => _settlementSetupError = e.toString());
    }
    debugPrint('[Settlement] ══════════════════════════════════════════════');
  }

  Future<String> _resolveCounterparty({
    required Map<String, dynamic> companyVa,
    required String merchantAccountNumber,
    required String merchantBankId,
    required String merchantAccountName,
    required String merchantBankName,
  }) async {
    debugPrint('[Settlement] ── _resolveCounterparty() ─────────────────────');

    final queryCp = await FirebaseFirestore.instance
        .collection('counterparties')
        .where('ownerAccountId', isEqualTo: companyVa['id'])
        .where('recipientAccountNumber', isEqualTo: merchantAccountNumber)
        .where('recipientBankCode', isEqualTo: merchantBankId)
        .limit(1)
        .get();

    debugPrint('[Settlement] Query returned ${queryCp.docs.length} doc(s)');

    if (queryCp.docs.isNotEmpty) {
      final id = queryCp.docs.first.id;
      debugPrint('[Settlement] ✅ Existing counterparty → id=$id');
      return id;
    }

    final createCp = await callCloudFunctionLogged(
      'safehavenCreateCounterparty',
      source: 'business_app',
      payload: {
        'accountId': companyVa['id'],
        'bankId': merchantBankId,
        'accountType': companyVa['type'],
        'accountName': merchantAccountName,
        'bankName': merchantBankName,
        'accountNumber': merchantAccountNumber,
        'bankCode': merchantBankId,
      },
    );

    debugPrint('[Settlement] createCounterparty response: ${createCp.data}');

    final dynamic responseData = createCp.data;
    late final Map<String, dynamic> responseMap;

    if (responseData is Map) {
      responseMap = Map<String, dynamic>.from(responseData);
    } else if (responseData is String) {
      try {
        responseMap = jsonDecode(responseData) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[Settlement] Failed to parse response: $e');
        throw Exception('Invalid response from createCounterparty');
      }
    } else {
      throw Exception('Unexpected response type from createCounterparty');
    }

    late final Map<String, dynamic> dataMap;
    if (responseMap.containsKey('data')) {
      final dataObj = responseMap['data'];
      if (dataObj is Map) {
        dataMap = Map<String, dynamic>.from(dataObj);
      } else {
        throw Exception('Data object is not a Map');
      }
    } else {
      dataMap = responseMap;
    }

    final counterpartyId = dataMap['id']?.toString() ?? '';
    if (counterpartyId.isEmpty) {
      throw Exception('Missing id in createCounterparty response');
    }

    debugPrint('[Settlement] ✅ New counterparty id=$counterpartyId');

    final cpDoc = <String, dynamic>{
      ...responseMap,
      'userId': companyVa['uid'],
      'recipientAccountNumber': merchantAccountNumber,
      'recipientBankCode': merchantBankId,
      'ownerAccountId': companyVa['id'],
    };

    await FirebaseFirestore.instance
        .collection('counterparties')
        .doc(counterpartyId)
        .set(cpDoc);

    debugPrint('[Settlement] ✅ Counterparty saved');
    return counterpartyId;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _playCardDetectedFeedback() async {
    // Card read: vibrate only, no sound
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
    } catch (_) {}
  }

  Future<void> _playFailureFeedback() async {
    // Payment failed: ring + long vibrate
    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.triTone,
        volume: 1.0,
      );
    } catch (_) {}
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 400, 100, 400]);
      }
    } catch (_) {}
  }

  Future<String> _getMerchantName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Padi Pay Business';

    try {
      final businessDoc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(user.uid)
          .get();

      if (businessDoc.exists) {
        final data = businessDoc.data();
        if (data != null) {
          final name =
              (data['business_data'] as Map<String, dynamic>?)?['name']
                  as String?;
          if (name != null && name.trim().isNotEmpty) return name.trim();
        }
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final fullName = userDoc.data()?['fullName'] as String?;
        if (fullName != null && fullName.trim().isNotEmpty) {
          return fullName.trim();
        }
      }
    } catch (e) {
      debugPrint('[Tappa] Failed to fetch merchant name: $e');
    }

    return 'Padi Pay Business';
  }

  String _generateRrn() =>
      List.generate(12, (_) => Random().nextInt(10)).join();

  Future<void> _executeSettlement({
    required double amountNaira,
    required String rrn,
  }) async {
    debugPrint(
      '[Settlement] ══ _executeSettlement() amount=₦$amountNaira rrn=$rrn',
    );

    if (amountNaira <= 0) {
      debugPrint('[Settlement] Amount zero/negative — skipping');
      return;
    }

    final companyVa = _companyVa;
    final merchantVa = _merchantVa;

    if (companyVa == null || merchantVa == null) {
      debugPrint(
        '[Settlement] ❌ Pre-setup incomplete — running full fallback...',
      );
      await _saveTappaLog(
        eventType: 'settlement_pre_setup_failed',
        status: 'failed',
        amount: amountNaira.toString(),
        rrn: rrn,
        errorMessage:
            'Pre-setup incomplete - companyVA: ${companyVa != null}, merchantVA: ${merchantVa != null}',
      );
      await _fullSettlementFallback(amountNaira: amountNaira, rrn: rrn);
      return;
    }

    try {
      final amountKobo = (amountNaira * 100).round();
      final narration = 'NFC Payment Settlement - RRN $rrn';
      final idempotencyKey = const Uuid().v4();

      // Book transfer: company VA → merchant VA (both on Sudo)
      final result = await callCloudFunctionLogged(
        'safehavenTransferIntra',
        source: 'business_app',
        payload: {
          'fromAccountId': companyVa['id'],
          'toAccountId': merchantVa['id'],
          'amount': amountKobo,
          'currency': 'NGN',
          'type': 'va_settlement',
          'narration': narration,
          'idempotencyKey': idempotencyKey,
        },
      );

      debugPrint(
        '[Settlement] safehavenTransferIntra response: ${result.data}',
      );

      final dynamic responseData = result.data;
      Map<String, dynamic>? parsedResponse;

      if (responseData is Map) {
        parsedResponse = Map<String, dynamic>.from(responseData);
      } else if (responseData is String) {
        try {
          parsedResponse = jsonDecode(responseData) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('[Settlement] Failed to parse response string: $e');
          await _saveTappaLog(
            eventType: 'settlement_parsing_failed',
            status: 'failed',
            amount: amountNaira.toString(),
            rrn: rrn,
            errorCode: e.toString(),
            errorMessage: 'Failed to parse settlement response',
          );
          return;
        }
      } else {
        return;
      }

      Map<String, dynamic>? transferData;
      if (parsedResponse.containsKey('data')) {
        final dataObj = parsedResponse['data'];
        if (dataObj is Map) {
          transferData = Map<String, dynamic>.from(dataObj);
        } else {
          return;
        }
      } else {
        transferData = parsedResponse;
      }

      Map<String, dynamic>? attributes;
      if (transferData.containsKey('attributes')) {
        final attrsObj = transferData['attributes'];
        if (attrsObj is Map) attributes = Map<String, dynamic>.from(attrsObj);
      }

      final status = attributes?['status'] as String? ?? 'UNKNOWN';
      final failureReason = attributes?['failureReason'] as String?;
      final transferId = transferData['id'] as String? ?? 'N/A';

      if (status == 'FAILED') {
        final reason = failureReason ?? 'Unknown';
        debugPrint('[Settlement] ❌ Transfer FAILED — reason: $reason');
        await _saveTappaLog(
          eventType: 'settlement_failed',
          status: 'failed',
          amount: amountNaira.toString(),
          rrn: rrn,
          errorMessage: reason,
          additionalData: {'transferId': transferId, 'status': status},
        );
        await FirebaseFirestore.instance.collection('transactions').add({
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'type': 'va_settlement_failed',
          'amount': amountNaira,
          'isInternal': true,
          'rrn': rrn,
          'reference': transferId,
          'status': 'failed',
          'failureReason': reason,
          'currency': 'NGN',
          'api_response': result.data,
          'from': 'company_va',
          'to': 'merchant_va',
          'timestamp': FieldValue.serverTimestamp(),
        });
        return;
      }

      debugPrint('[Settlement] ✅ Settlement SUCCESS — transferId=$transferId');
      await _saveTappaLog(
        eventType: 'settlement_success',
        status: 'success',
        amount: amountNaira.toString(),
        rrn: rrn,
        additionalData: {'transferId': transferId},
      );
      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'type': 'va_settlement',
        'amount': amountNaira,
        'rrn': rrn,
        'isInternal': true,
        'reference': transferId,
        'status': 'success',
        'currency': 'NGN',
        'api_response': result.data,
        'from': 'company_va',
        'to': 'merchant_va',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      debugPrint('[Settlement] ❌ _executeSettlement EXCEPTION: $e\n$st');
      await _saveTappaLog(
        eventType: 'settlement_exception',
        status: 'failed',
        amount: amountNaira.toString(),
        rrn: rrn,
        errorCode: e.toString(),
        errorMessage: st.toString(),
      );
    }
  }

  Future<void> _fullSettlementFallback({
    required double amountNaira,
    required String rrn,
  }) async {
    debugPrint('[Settlement] ── _fullSettlementFallback() ──────────────────');
    try {
      final results = await Future.wait([
        _fetchCompanyVirtualAccount(),
        _fetchMerchantVirtualAccount(),
      ]);
      final companyVa = results[0];
      final merchantVa = results[1];

      if (companyVa == null || (companyVa['id'] as String).isEmpty) {
        debugPrint('[Settlement] ❌ Fallback: Company VA not found');
        return;
      }
      if (merchantVa == null) {
        debugPrint('[Settlement] ❌ Fallback: Merchant VA not found');
        return;
      }

      _companyVa = companyVa;
      _merchantVa = merchantVa;
      if (mounted) setState(() => _settlementReady = true);

      await _executeSettlement(amountNaira: amountNaira, rrn: rrn);
    } catch (e, st) {
      debugPrint('[Settlement] ❌ _fullSettlementFallback EXCEPTION: $e\n$st');
    }
  }

  Future<void> _saveAtmTransaction({
    required String status,
    required double amount,
    String? failureTitle,
    String? failureDetail,
    String? cardData,
    String? tag,
    int? feesKobo,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final docRef = await FirebaseFirestore.instance
          .collection('transactions')
          .add({
            'userId': user?.uid,
            'type': 'atm_payment',
            'amount': _rawAmount,
            'rrn': _txRrn,
            'reference': _txRrn,
            if (_safeHavenRrn.isNotEmpty) 'safeHavenRrn': _safeHavenRrn,
            'terminalId': _kTerminalId,
            'status': status,
            'currency': 'NGN',
            if (feesKobo != null) 'padipay_fee_kobo': feesKobo,
            if (feesKobo != null) 'padipay_fee_naira': feesKobo / 100.0,
            if (cardData != null) 'cardData': cardData,
            if (failureTitle != null) 'failureTitle': failureTitle,
            if (failureDetail != null) 'failureDetail': failureDetail,
            if (tag != null && tag.isNotEmpty) 'tag': tag,
            'timestamp': FieldValue.serverTimestamp(),
          });
      _txDocId = docRef.id;
      debugPrint('[Tappa] Saved ATM transaction docId=${docRef.id}');
    } catch (e) {
      debugPrint('[Tappa] Firestore save failed: $e');
    }
  }

  /// Calls Safe Haven Kimono reconciliation for the current pending transaction.
  Future<void> _reconcileCurrentTransaction() async {
    if (_txRrn.isEmpty || _isReconciling) return;
    setState(() {
      _isReconciling = true;
      _reconcileResult = null;
    });
    try {
      final rrnToUse = _safeHavenRrn.isNotEmpty ? _safeHavenRrn : _txRrn;
      debugPrint(
        '[Reconcile] Reconciling current tx rrnToUse=$rrnToUse (safeHavenRrn=$_safeHavenRrn appRrn=$_txRrn) docId=$_txDocId',
      );
      final result = await FirebaseFunctions.instance
          .httpsCallable('reconcileAtmTransaction')
          .call({
            'rrn': rrnToUse,
            if (_txDocId != null) 'transactionDocId': _txDocId,
          });
      debugPrint('[Reconcile] Raw response for rrn=$_txRrn: ${result.data}');
      final resultMap = result.data as Map? ?? {};
      final status = resultMap['status'] as String? ?? 'pending';
      final responseCode = resultMap['responseCode'];
      final safeHavenStatus = resultMap['safeHavenStatus'];
      debugPrint(
        '[Reconcile] rrn=$_txRrn → status=$status | responseCode=$responseCode | safeHavenStatus=$safeHavenStatus',
      );
      if (mounted) {
        setState(() {
          _isReconciling = false;
          _reconcileResult = status;
        });
      }
    } catch (e) {
      debugPrint('[Reconcile] Error: $e');
      if (mounted) {
        setState(() {
          _isReconciling = false;
          _reconcileResult = 'error';
        });
      }
    }
  }

  Future<void> _savePadiBookEntry({
    required double amount,
    required String rrn,
    required String tag,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final label = tag.isNotEmpty ? tag : 'Card Payment';
      await FirebaseFirestore.instance
          .collection('padiBook')
          .doc(user.uid)
          .collection('entries')
          .add({
            'label': label,
            'category': 'income',
            'amount': amount,
            'note': '',
            'date': Timestamp.now(),
            'isManual': false,
            'transactionId': rrn,
            'transactionTitle': 'NFC Card Payment',
          });
    } catch (e) {
      debugPrint('[Tappa] PadiBook save failed: $e');
    }
  }

  double _amountFontSize(String text) {
    final digits = text.replaceAll(',', '').replaceAll('.', '').length;
    if (digits <= 5) return 64;
    if (digits <= 7) return 54;
    if (digits <= 9) return 44;
    if (digits <= 11) return 36;
    return 28;
  }

  void _resetTransaction() {
    setState(() {
      _txStatus = _TxStatus.idle;
      _txFailure = null;
      _chargedAmount = '';
      _rawAmount = 0;
      _txActive = false;
      _txDocId = null;
      _txRrn = '';
      _safeHavenRrn = '';
      _isReconciling = false;
      _reconcileResult = null;
      _amountController.clear();
      _tagController.clear();
    });
    _amountFocus.requestFocus();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final inResultScreen =
        _txStatus == _TxStatus.failed || _txStatus == _TxStatus.uncertain;
    return PopScope(
      canPop: !inResultScreen,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          await _stopNfc();
        } else if (!didPop && _txStatus != _TxStatus.idle) {
          // When on result screen (failed/uncertain) and back pressed, reset
          _resetTransaction();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          surfaceTintColor: Colors.white,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
            onPressed: () {
              if (inResultScreen) {
                _resetTransaction();
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),
        body: SafeArea(
          bottom: true,
          child: switch (_initStatus) {
            _InitStatus.loading => _buildLoading(),
            _InitStatus.error => _buildError(),
            _InitStatus.ready => _buildPosScreen(),
          },
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: primaryColor),
          SizedBox(height: 20),
          Text(
            'Starting up terminal\u2026',
            style: TextStyle(color: Colors.grey, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            const Text(
              'Terminal Error',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _initError,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 28),
            InkWell(
              onTap: _autoInit,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Retry',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

  Widget _buildPosScreen() {
    return switch (_txStatus) {
      _TxStatus.failed => _buildFailedScreen(),
      _TxStatus.uncertain => _buildUncertainScreen(),
      _ => _buildAmountScreen(),
    };
  }

  Widget _buildAmountScreen() {
    final double? enteredNaira = double.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );
    final bool hasAmount =
        enteredNaira != null && enteredNaira >= 50 && enteredNaira <= 500000;
    final bool amountTooLow =
        enteredNaira != null && enteredNaira > 0 && enteredNaira < 50;
    final bool amountTooHigh = enteredNaira != null && enteredNaira > 500000;
    final isProcessing = _txStatus == _TxStatus.processing;
    final fontSize = _amountFontSize(_amountController.text.trim());

    return Column(
      children: [
        if (!_settlementReady && _settlementSetupError.isNotEmpty)
          _buildSettlementWarningBanner(),
        Expanded(
          child: GestureDetector(
            onTap: () => _amountFocus.requestFocus(),
            behavior: HitTestBehavior.opaque,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Text(
                    'Charge Customer',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),

                  SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                  // Optional tag field
                  TextField(
                    controller: _tagController,
                    textAlign: TextAlign.center,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'What is this for? (optional)',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                      prefixIcon: Icon(
                        Icons.label_outline_rounded,
                        size: 18,
                        color: Colors.grey.shade400,
                      ),
                      counterText: '',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 1.5),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.05),

                  const Text(
                    'Enter the amount to charge',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: fontSize * 0.14),
                        child: Text(
                          '\u20A6',
                          style: TextStyle(
                            fontSize: fontSize * 0.55,
                            fontWeight: FontWeight.w300,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: TextField(
                          controller: _amountController,
                          focusNode: _amountFocus,
                          autofocus: true,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[\d,.]'),
                            ),
                          ],
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w300,
                            letterSpacing: -2,
                            color: Colors.black,
                          ),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            hintStyle: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w300,
                              color: const Color(0xFFCCCCCC),
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (value) {
                            final cleanValue = value.replaceAll(',', '');
                            final formatted = _formatAmountDisplay(cleanValue);
                            if (_amountController.text != formatted) {
                              _amountController.value = _amountController.value
                                  .copyWith(
                                    text: formatted,
                                    selection: TextSelection.fromPosition(
                                      TextPosition(offset: formatted.length),
                                    ),
                                  );
                            }
                            setState(() {});
                          },
                          onSubmitted: (_) {
                            if (hasAmount && !isProcessing) _onCharge();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 1.5,
                    color: amountTooLow || amountTooHigh
                        ? Colors.red.shade400
                        : hasAmount
                        ? primaryColor
                        : Colors.grey.shade300,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    amountTooLow
                        ? 'Minimum amount is ₦50'
                        : amountTooHigh
                        ? 'Maximum amount is ₦500,000'
                        : '₦50 – ₦500,000',
                    style: TextStyle(
                      fontSize: 12,
                      color: (amountTooLow || amountTooHigh)
                          ? Colors.red.shade600
                          : Colors.grey.shade400,
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                ],
              ),
            ),
          ),
        ),
        _buildActionBar(hasAmount: hasAmount, isProcessing: isProcessing),
      ],
    );
  }

  Widget _buildSettlementWarningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.shade50,
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Auto-settlement setup incomplete — will retry after payment.',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
            ),
          ),
          GestureDetector(
            onTap: _prepareSettlement,
            child: Text(
              'Retry',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar({
    required bool hasAmount,
    required bool isProcessing,
  }) {
    // Use _txActive as the single source of truth for disabled/loading state
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: (hasAmount && !_txActive) ? _onCharge : null,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (hasAmount && !_txActive)
                      ? primaryColor
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: (isProcessing && _txActive)
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        hasAmount
                            ? 'Charge  \u20A6${_amountController.text.trim()}'
                            : 'Enter Amount',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUncertainScreen() {
    return RefreshIndicator(
      onRefresh: () async {
        await _reconcileCurrentTransaction();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
        children: [
          const SizedBox(height: 16),
          const SizedBox(height: 24),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Color(0xFFFFF3E0),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              size: 52,
              color: Color(0xFFF57C00),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Connection Lost',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'The network dropped while processing the payment.\nStatus will be reconciled automatically. Pull down to refresh anytime.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9C4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF9A825)),
            ),
            child: Column(
              children: [
                Text(
                  'Transaction Reference (RRN)',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _txRrn,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Reconcile result banner ─────────────────────────────────────
          if (_reconcileResult != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _reconcileResult == 'success'
                    ? const Color(0xFFE8F5E9)
                    : _reconcileResult == 'failed'
                    ? const Color(0xFFFFEBEE)
                    : const Color(0xFFFFF9C4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _reconcileResult == 'success'
                      ? const Color(0xFF4CAF50)
                      : _reconcileResult == 'failed'
                      ? const Color(0xFFE74C3C)
                      : const Color(0xFFF9A825),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _reconcileResult == 'success'
                        ? Icons.check_circle_rounded
                        : _reconcileResult == 'failed'
                        ? Icons.cancel_rounded
                        : Icons.help_outline_rounded,
                    color: _reconcileResult == 'success'
                        ? const Color(0xFF4CAF50)
                        : _reconcileResult == 'failed'
                        ? const Color(0xFFE74C3C)
                        : const Color(0xFFF9A825),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _reconcileResult == 'success'
                          ? 'Payment confirmed — the customer was debited. Settlement will proceed.'
                          : _reconcileResult == 'failed'
                          ? 'Payment failed — the customer was NOT debited.'
                          : _reconcileResult == 'error'
                          ? 'Could not reach network. Pull down to refresh and try again.'
                          : 'Status still pending — pull down to refresh.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _reconcileResult == 'success'
                            ? const Color(0xFF2E7D32)
                            : _reconcileResult == 'failed'
                            ? const Color(0xFFC62828)
                            : const Color(0xFFE65100),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isReconciling)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFF57C00),
                  ),
                ),
              ),
            ),
          InkWell(
            onTap: _resetTransaction,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Start New Transaction',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFailedScreen() {
    final failure =
        _txFailure ??
        const _TxFailure(
          title: 'Payment Failed',
          detail: 'The transaction could not be completed. Please try again.',
          icon: Icons.error_outline_rounded,
          color: Color(0xFFE74C3C),
        );

    final cleanAmount = _chargedAmount.replaceAll(',', '');
    final formattedAmount = cleanAmount.isNotEmpty
        ? _formatAmountDisplay(cleanAmount)
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.red.shade300, width: 1.5),
            ),
            child: Text(
              'TRANSACTION FAILED',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Colors.red.shade600,
                letterSpacing: 1.8,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: failure.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(failure.icon, size: 50, color: failure.color),
          ),
          const SizedBox(height: 20),
          if (formattedAmount.isNotEmpty) ...[
            Text(
              '₦$formattedAmount',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE74C3C),
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 20),
          Text(
            failure.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            failure.detail,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.55,
            ),
          ),
          const Spacer(flex: 3),
          InkWell(
            onTap: _resetTransaction,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
class _NfcTapDialog extends StatefulWidget {
  final Stream<String?> statusStream;
  final VoidCallback onCancel;
  const _NfcTapDialog({required this.statusStream, required this.onCancel});

  @override
  State<_NfcTapDialog> createState() => _NfcTapDialogState();
}

class _NfcTapDialogState extends State<_NfcTapDialog> {
  String? _retryMessage;
  bool _isProcessing = false;
  bool _isReadingCard = false;
  int _countdown = 90;
  Timer? _countdownTimer;
  late final StreamSubscription<String?> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.statusStream.listen((msg) {
      if (!mounted) return;
      if (msg != null &&
          (msg.startsWith('__processing__') || msg == '__uncertain__')) {
        int start = 90;
        if (msg.contains(':')) {
          start = int.tryParse(msg.split(':')[1]) ?? 90;
        }
        _countdownTimer?.cancel();
        _countdown = start;
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            if (_countdown > 0) _countdown--;
          });
        });
        setState(() {
          _isProcessing = true;
          _isReadingCard = false;
          _retryMessage = null;
        });
      } else if (msg == '__reading__') {
        setState(() {
          _isReadingCard = true;
          _isProcessing = false;
          _retryMessage = null;
        });
      } else {
        _countdownTimer?.cancel();
        setState(() {
          _retryMessage = msg;
          _isProcessing = false;
          _isReadingCard = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _retryMessage != null;

    return PopScope(
      canPop: !_isProcessing && !_isReadingCard,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon / spinner area
            if (_isProcessing)
              SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        strokeWidth: 6,
                        color: primaryColor,
                      ),
                    ),
                    Text(
                      '$_countdown',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              )
            else if (_isReadingCard)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.85, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOut,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.contactless_rounded,
                    size: 50,
                    color: primaryColor,
                  ),
                ),
              )
            else
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.88, end: 1.06),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOut,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Image.asset("assets/logo.png", width: 80, height: 80),
              ),

            const SizedBox(height: 20),

            if (_isReadingCard) ...[
              Text(
                'KEEP CARD STILL',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: primaryColor,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Reading card data — do not move the card',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              const LinearProgressIndicator(color: primaryColor),
            ] else if (!_isProcessing) ...[
              Text(
                hasError ? 'TAP AGAIN' : 'TAP YOUR CARD',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: hasError ? Colors.orange.shade700 : primaryColor,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasError
                    ? _retryMessage!
                    : 'Hold the back of the card to the back of the device',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: hasError ? Colors.orange.shade800 : Colors.grey,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              const LinearProgressIndicator(),
              const SizedBox(height: 24),
              InkWell(
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                    widget.onCancel();
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Please wait while we confirm your payment…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _countdown > 0
                    ? 'Timing out in $_countdown second${_countdown == 1 ? '' : 's'}'
                    : 'Finalising…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: _countdown <= 10
                      ? Colors.orange.shade600
                      : Colors.grey.shade400,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
