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

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

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
   //   actions: [approveAction, declineAction],
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
    message.data['title'] ??
        message.notification?.title ??
        'Notification',
    message.data['body'] ??
        message.notification?.body ??
        '',
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


  FirebaseMessaging.onMessage.listen(_showNotification);

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
