import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padi_pay_business/firebase_options.dart';
import 'package:padi_pay_business/kyb/business_upgrade_manager.dart';
import 'package:padi_pay_business/transfer/withdraw_for_customer.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:padi_pay_business/welcome_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final FlutterTts _flutterTts = FlutterTts();
final AudioPlayer _neuralAudioPlayer = AudioPlayer();
bool _ttsConfigured = false;
String? _ttsConfiguredVoicePreference;
String? _ttsConfiguredVoiceName;
String? _ttsConfiguredEnginePackage;
String? _ttsConfiguredEngineLabel;
double? _ttsConfiguredPitch;
double? _ttsConfiguredSpeechRate;
bool _ttsUsingSyntheticMaleProfile = false;
bool _ttsGoogleEngineAvailable = false;

const String _voiceAlertsPreferenceKey = 'voiceAlerts';
const String _voiceAlertSpeakAmountPreferenceKey = 'voiceAlertSpeakAmount';
const String _voiceAlertGenderPreferenceKey = 'voiceAlertGender';
const String _voiceAlertLanguagePreferenceKey = 'voiceAlertLanguage';

final ValueNotifier<String?> pendingApprovalNotifier = ValueNotifier(null);

// =========================================================
// BACKGROUND HANDLER
// =========================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _showNotification(message);

  if (message.data['type'] == 'kyc_awaiting_document') {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('open_kyb_upgrade', true);
  }
}

// =========================================================
// NOTIFICATION CHANNEL
// =========================================================
Future<void> _createNotificationChannel() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'padi_transactions_channel',
    'Transactions Notifications',
    description: 'This channel is used for transactions notifications.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  final androidPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(channel);
}

// =========================================================
// SHOW LOCAL NOTIFICATION
// =========================================================
Future<void> _showNotification(RemoteMessage message) async {
  final prefs = await SharedPreferences.getInstance();
  final bool enablePush = prefs.getBool('pushNotification') ?? true;
  if (!enablePush) return;

  final isIncomingPayment = _isIncomingPaymentPayloadLike(
    message.data,
    notificationTitle: message.notification?.title,
    notificationBody: message.notification?.body,
  );

  final senderName = _extractIncomingSenderName(message.data);
  final amountNaira = _parseAmountNairaFromPayload(
    message.data,
    fallbackBody: message.notification?.body,
  );
  final todayTotalNaira = await _resolveTodayReceivedTotalNaira(
    data: message.data,
  );

  final incomingBodyLine = amountNaira != null && amountNaira > 0
      ? '${_formatNaira(amountNaira)} received${senderName == null ? '' : ' from $senderName'}'
      : (message.data['body'] ??
                message.notification?.body ??
                'Payment received')
            .toString();
  final incomingSummaryLine = todayTotalNaira != null && todayTotalNaira > 0
      ? 'Total today: ${_formatNaira(todayTotalNaira)}'
      : null;
  const incomingTitle = 'Cash Just Landed! 💰';
  final incomingBigText = [
    '<b>$incomingBodyLine</b>',
    if (incomingSummaryLine != null) incomingSummaryLine,
    '<i>Tap to view transaction details</i>',
  ].join('<br/>');

  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'padi_transactions_channel',
    'Transactions Notifications',
    channelDescription: 'Used for transaction notifications.',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    enableVibration: true,
    autoCancel: true,
  );

  if (isIncomingPayment) {
    androidDetails = AndroidNotificationDetails(
      'padi_transactions_channel',
      'Transactions Notifications',
      channelDescription: 'Used for transaction notifications.',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
      category: AndroidNotificationCategory.message,
      color: const Color(0xFF16C79A),
      colorized: true,
      subText: 'Padi Pay Incoming',
      styleInformation: BigTextStyleInformation(
        incomingBigText,
        htmlFormatBigText: true,
        contentTitle: '<b>$incomingTitle</b>',
        htmlFormatContentTitle: true,
        summaryText: incomingSummaryLine ?? 'Padi Pay',
        htmlFormatSummaryText: true,
      ),
    );
  }

  if (message.data['type'] == 'withdrawal_request') {
    androidDetails = AndroidNotificationDetails(
      'padi_transactions_channel',
      'Transactions Notifications',
      channelDescription: 'Used for withdrawal notifications.',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    );
  }

  final NotificationDetails platform = NotificationDetails(
    android: androidDetails,
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  await flutterLocalNotificationsPlugin.show(
    Random().nextInt(2147483647),
    isIncomingPayment
        ? incomingTitle
        : (message.data['title'] ??
                  message.notification?.title ??
                  'Notification')
              .toString(),
    isIncomingPayment
        ? ([
            incomingBodyLine,
            if (incomingSummaryLine != null) incomingSummaryLine,
          ].join('\n'))
        : (message.data['body'] ?? message.notification?.body ?? '').toString(),
    platform,
    payload: jsonEncode(message.data),
  );
}

// =========================================================
// MAIN
// =========================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await _createNotificationChannel();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (response) {
      _handleNotificationTap(response.payload, response.actionId);
    },
  );


  FirebaseMessaging.onMessage.listen((message) async {
    await _showNotification(message);
    await _speakIncomingAlert(message);
  });

  // IMPORTANT FIX:
  // Handles taps when app is already open or in foreground.
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    _handleNotificationTap(jsonEncode(message.data), null);
  });

  preloadBanks();
  preloadBalance();

  runApp(const MainApp());
}

// =========================================================
// LOCAL PERMISSIONS
// =========================================================
Future<void> firebaseLocalPermission() async {
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);

  await FirebaseMessaging.instance.requestPermission();
}

// =========================================================
// UNIVERSAL NOTIFICATION TAP HANDLER
// =========================================================
Future<void> _handleNotificationTap(String? payload, String? actionId) async {
  if (payload == null) return;

  final data = jsonDecode(payload);
  final prefs = await SharedPreferences.getInstance();

  final type = data['type'];
  final requestId = data['requestId'];

  if (type == 'kyc_awaiting_document') {
    await prefs.setBool('open_kyb_upgrade', true);
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const BusinessUpgradeManager()),
    );
    return;
  }

  if (type == 'withdrawal_request') {
    if (actionId == null || actionId == 'APPROVE_ACTION') {
      pendingApprovalNotifier.value = requestId;
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => WithdrawalApprovalPage(requestId: requestId)),
      );
      return;
    }

    if (actionId == 'DECLINE_ACTION') {
      await FirebaseFunctions.instance
          .httpsCallable('cancelWithdrawalRequest')
          .call({'requestId': requestId, 'reason': 'declined_via_notification'});

      showToast('Withdrawal request declined.', Colors.orange);
    }
  }
}

// =========================================================
// PRELOADS
// =========================================================
Future<void> preloadBanks() async {
  try {
    final snapshot =
        await FirebaseFirestore.instance.collection('banks').get();
    if (snapshot.docs.isEmpty) {
      final result = await callCloudFunctionLogged('sudoBankList', source: 'business_app');

      final data = result.data['data'] as List;
      final batch = FirebaseFirestore.instance.batch();
      for (var item in data) {
        final doc =
            FirebaseFirestore.instance.collection('banks').doc(item['id'].toString());
        batch.set(doc, {'name': item['attributes']['name']});
      }
      await batch.commit();
    }
  } catch (_) {}
}

Future<void> preloadBalance() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final sudo = userDoc.data()?['sudoData'];
    if (sudo == null) return;

    final accountId =
        sudo['virtualAccount']?['data']?['id']?.toString();
    if (accountId == null) return;

    final result = await callCloudFunctionLogged(
      'sudoFetchAccountBalance',
      source: 'main.dart',
      payload: {'accountId': accountId},
    );

    double balance =
        result.data['data']['availableBalance']?.toDouble() ?? 0.0;
    balance /= 100;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cached_balance', balance);
  } catch (_) {}
}

// =========================================================
// VOICE ALERTS & NOTIFICATION HELPERS
// =========================================================
Future<void> _speakIncomingAlert(RemoteMessage message) async {
  final prefs = await SharedPreferences.getInstance();
  final enableVoice = prefs.getBool(_voiceAlertsPreferenceKey) ?? true;
  if (!enableVoice) return;

  final speakAmount =
      prefs.getBool(_voiceAlertSpeakAmountPreferenceKey) ?? true;
  final voiceLanguage = _normalizeVoiceLanguagePreference(
    prefs.getString(_voiceAlertLanguagePreferenceKey),
  );
  final spoken = _buildIncomingAlertSpeech(
    data: message.data,
    notificationTitle: message.notification?.title,
    notificationBody: message.notification?.body,
    speakAmount: speakAmount,
    voiceLanguage: voiceLanguage,
  );
  if (spoken == null) return;

  try {
    await _speakIncomingText(text: spoken, voiceLanguage: voiceLanguage);
  } catch (e) {
    debugPrint('TTS speak error: $e');
  }
}

bool _isIncomingPaymentPayloadLike(
  Map<String, dynamic> data, {
  String? notificationTitle,
  String? notificationBody,
}) {
  final type = (data['type'] ?? '').toString().toLowerCase();
  final title = (data['title'] ?? notificationTitle ?? '')
      .toString()
      .toLowerCase();
  final body = (data['body'] ?? notificationBody ?? '')
      .toString()
      .toLowerCase();
  final text = '$type $title $body';

  final includesIncomingKeyword = [
    'received',
    'credited',
    'deposit',
    'payment received',
    'transfer received',
  ].any(text.contains);

  final includesOutgoingKeyword = [
    'debited',
    'withdrawal',
    'declined',
    'failed',
  ].any(text.contains);

  if (type == 'payment_received' || type == 'deposit') {
    return true;
  }

  return includesIncomingKeyword && !includesOutgoingKeyword;
}

String? _buildIncomingAlertSpeech({
  required Map<String, dynamic> data,
  String? notificationTitle,
  String? notificationBody,
  required bool speakAmount,
  required String voiceLanguage,
}) {
  if (!_isIncomingPaymentPayloadLike(
    data,
    notificationTitle: notificationTitle,
    notificationBody: notificationBody,
  )) {
    return null;
  }

  final amount = _parseAmountNairaFromPayload(
    data,
    fallbackBody: notificationBody,
  );

  if (speakAmount && amount != null && amount > 0) {
    final rounded = amount.round();
    if (voiceLanguage == 'pidgin') {
      return '${_numberToWords(rounded)} naira don land for your PadiPay account';
    }
    return '${_numberToWords(rounded)} naira received in your PadiPay account';
  }

  if (voiceLanguage == 'pidgin') {
    return 'Payment don land for your PadiPay account';
  }

  return 'Payment received in your PadiPay account';
}

Future<Map<String, dynamic>> _speakIncomingText({
  required String text,
  required String voiceLanguage,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final voicePreference = _normalizeVoicePreference(
    prefs.getString(_voiceAlertGenderPreferenceKey),
  );

  await _flutterTts.stop();
  final speakResult = await _flutterTts.speak(text);
  return {
    'ok': true,
    'engineUsed': 'device',
    'voicePreference': voicePreference,
    'speakResult': speakResult?.toString(),
  };
}

String _normalizeVoicePreference(String? value) {
  final normalized = (value ?? 'female').trim().toLowerCase();
  if (normalized == 'male') return 'male';
  return 'female';
}

String _normalizeVoiceLanguagePreference(String? value) {
  final normalized = (value ?? 'english').trim().toLowerCase();
  if (normalized == 'pidgin') return 'pidgin';
  return 'english';
}

double? _parseAmountNairaFromPayload(
  Map<String, dynamic> data, {
  String? fallbackBody,
}) {
  final directCandidates = [
    data['amount'],
    data['amountNaira'],
    data['amount_naira'],
    data['displayAmount'],
    data['value'],
  ];

  for (final candidate in directCandidates) {
    if (candidate == null) continue;
    if (candidate is num) return candidate.toDouble();
    final cleaned = candidate.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    final parsed = double.tryParse(cleaned);
    if (parsed != null && parsed > 0) return parsed;
  }

  final body = (data['body'] ?? fallbackBody ?? '').toString();
  final match = RegExp(r'([0-9][0-9,]*\.?[0-9]*)').firstMatch(body);
  if (match != null) {
    final parsed = double.tryParse(match.group(1)!.replaceAll(',', ''));
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

String _numberToWords(int number) {
  const ones = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
  ];
  const teens = [
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  const tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];

  if (number < 10) return ones[number];
  if (number < 20) return teens[number - 10];
  if (number < 100) {
    final t = number ~/ 10;
    final r = number % 10;
    return r == 0 ? tens[t] : '${tens[t]} ${ones[r]}';
  }
  if (number < 1000) {
    final h = number ~/ 100;
    final r = number % 100;
    return r == 0
        ? '${ones[h]} hundred'
        : '${ones[h]} hundred ${_numberToWords(r)}';
  }
  if (number < 1000000) {
    final th = number ~/ 1000;
    final r = number % 1000;
    return r == 0
        ? '${_numberToWords(th)} thousand'
        : '${_numberToWords(th)} thousand ${_numberToWords(r)}';
  }
  if (number < 1000000000) {
    final m = number ~/ 1000000;
    final r = number % 1000000;
    return r == 0
        ? '${_numberToWords(m)} million'
        : '${_numberToWords(m)} million ${_numberToWords(r)}';
  }
  return number.toString();
}

String? _extractIncomingSenderName(Map<String, dynamic> data) {
  const senderKeys = ['senderName', 'fromName', 'sender', 'payerName', 'name'];
  for (final key in senderKeys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String _formatNaira(double amount) {
  return '\u20A6${NumberFormat('#,##0').format(amount)}';
}

Future<double?> _resolveTodayReceivedTotalNaira({
  required Map<String, dynamic> data,
}) async {
  const totalKeys = [
    'todayTotalReceived',
    'today_total_received',
    'totalTodayReceived',
    'total_today',
  ];
  for (final key in totalKeys) {
    final value = data[key];
    if (value == null) continue;
    if (value is num && value > 0) return value.toDouble();
    final parsed = double.tryParse(value.toString().replaceAll(',', ''));
    if (parsed != null && parsed > 0) return parsed;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));

  try {
    final query = await FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .get();

    double total = 0;
    for (final doc in query.docs) {
      final tx = doc.data();
      if (!_isIncomingTransactionLike(tx)) continue;
      final amount = _parseAmountNairaFromPayload(tx);
      if (amount != null && amount > 0) {
        total += amount;
      }
    }
    return total > 0 ? total : null;
  } catch (_) {
    return null;
  }
}

bool _isIncomingTransactionLike(Map<String, dynamic> tx) {
  final status = (tx['status'] ?? tx['rawStatus'] ?? '')
      .toString()
      .toLowerCase();
  if (status.contains('failed') || status.contains('declined')) {
    return false;
  }

  final text = [
    tx['type'],
    tx['category'],
    tx['title'],
    tx['description'],
    tx['narration'],
  ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');

  final incomingHit = [
    'received',
    'credit',
    'credited',
    'deposit',
    'incoming',
  ].any(text.contains);
  final outgoingHit = [
    'debit',
    'debited',
    'withdraw',
    'transfer sent',
    'payment sent',
    'airtime',
    'bill',
  ].any(text.contains);

  return incomingHit && !outgoingHit;
}

// =========================================================
// MAIN APP
// =========================================================
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
       theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
        ),
        textTheme: GoogleFonts.interTextTheme(),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          disabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: primaryColor, width: 2),
          ),
        ),
      ),
      home: const AppLauncher(),
      // home:const PaymentScreen(),
    );
  }
}

// =========================================================
// LAUNCHER
// =========================================================
class AppLauncher extends StatefulWidget {
  const AppLauncher({super.key});

  @override
  State<AppLauncher> createState() => _AppLauncherState();
}

class _AppLauncherState extends State<AppLauncher> with WidgetsBindingObserver {
  bool _showPrivacyOverlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Lightweight root/jailbreak detection on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final compromised = await isDeviceRootedOrJailbroken();
        if (compromised && mounted) {
          showDialog(
            context: navigatorKey.currentContext!,
            barrierDismissible: false,
            builder: (ctx) {
              return AlertDialog(
                title: const Text('Security Warning'),
                content: const Text('This device appears to be rooted or jailbroken. For your security, certain features may be disabled.'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Continue'),
                  ),
                  TextButton(
                    onPressed: () {
                      // Exit app
                      SystemNavigator.pop();
                    },
                    child: const Text('Exit'),
                  ),
                ],
              );
            },
          );
        }
      } catch (e) {
        print('Root/jailbreak check failed: $e');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final shouldShow = state != AppLifecycleState.resumed;
    if (mounted && _showPrivacyOverlay != shouldShow) {
      setState(() {
        _showPrivacyOverlay = shouldShow;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const WelcomePage(),
        if (_showPrivacyOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.white,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                child: const Center(
                  child: SizedBox.shrink(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
