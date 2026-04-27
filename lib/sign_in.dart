import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:padi_pay_business/ui/permission_explanation_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:padi_pay_business/create_account_page.dart';
import 'package:padi_pay_business/email_otp_verification_page.dart';
import 'package:padi_pay_business/forgot_password_page.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SignIn extends StatefulWidget {
  const SignIn({super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final FirebaseAuth _auth = FirebaseAuth.instance;
bool _hasShownPermissionSheet = false;
  
  // ... rest of your existing code ...

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeRequestNotificationPermission();
  }

  Future<void> _maybeRequestNotificationPermission() async {
    // Only show if not already granted AND not already shown
    if (_hasShownPermissionSheet) return;
    
    bool granted = true;
    try {
      final plugin = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
          >();
      if (plugin != null) {
        granted = await plugin.areNotificationsEnabled() ?? true;
      }
    } catch (_) {}
    
    if (!granted) {
      _hasShownPermissionSheet = true;
      
      final proceed = await showPermissionExplanationSheet(
        context,
        title: 'Notification Permission',
        explanation:
            'We use notifications to alert you about important account activity, transactions, and security updates. Please allow notifications to stay informed.',
        confirmText: 'Allow',
        cancelText: 'Not Now',
      );
      
      if (proceed == true) {
        await _requestNotificationPermission();
      }
      
      // Reset flag after sheet is closed
      _hasShownPermissionSheet = false;
    }
  }
  Future<void> _requestNotificationPermission() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await FirebaseMessaging.instance.requestPermission();
  }

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isBiometricLoading = false;
  bool _obscurePassword = true;
  bool _biometricEnabled = false;
  bool _deviceSupportsBiometrics = false;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadLastEmail();
    _checkBiometricCapability();
    _loadBiometricPreference();
  }

  Future<void> _loadLastEmail() async {
    String? lastEmail = await _storage.read(key: 'last_email');
    if (lastEmail != null) {
      setState(() {
        _emailController.text = lastEmail;
      });
    }
  }

  Future<void> _checkBiometricCapability() async {
    try {
      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics;
      final isSupported = await localAuth.isDeviceSupported();
      final supported = canCheck && isSupported;
      if (mounted) {
        setState(() {
          _deviceSupportsBiometrics = supported;
          if (supported && !_biometricEnabled) {
            _biometricEnabled = true;
            _storage.write(key: 'biometric_enabled', value: 'true');
          }
        });
      }
    } catch (e) {
      print('Biometric check error: $e');
      if (mounted) setState(() => _deviceSupportsBiometrics = false);
    }
  }

  Future<void> _loadBiometricPreference() async {
    try {
      final saved = await _storage.read(key: 'biometric_enabled');
      if (mounted) setState(() => _biometricEnabled = saved == 'true');
    } catch (e) {
      print('Error loading biometric pref: $e');
    }
  }

  Future<Map<String, dynamic>?> _getLocationData() async {
    try {
      final response = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'city': data['city'] ?? 'Unknown',
          'country': data['country_name'] ?? 'Unknown',
          'region': data['region'] ?? 'Unknown',
          'org': data['org'] ?? 'Unknown',
          'ip': data['ip'] ?? 'Unknown',
        };
      }
    } catch (e) {
      print('Error getting location: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return {
          'device': androidInfo.model,
          'os': 'Android ${androidInfo.version.release}',
          'manufacturer': androidInfo.manufacturer,
        };
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        return {
          'device': iosInfo.model,
          'os': 'iOS ${iosInfo.systemVersion}',
          'manufacturer': 'Apple',
        };
      }
    } catch (e) {
      print('Error getting device info: $e');
    }
    return {'device': 'Unknown', 'os': 'Unknown', 'manufacturer': 'Unknown'};
  }

  Future<String> _getDeviceType() async {
    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        if (androidInfo.model.toLowerCase().contains('tablet')) {
          return 'tablet';
        }
        return 'mobile';
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        if (iosInfo.model.toLowerCase().contains('ipad')) {
          return 'tablet';
        }
        return 'mobile';
      }
    } catch (e) {
      print('Error getting device type: $e');
    }
    return 'unknown';
  }

  Future<void> _saveLoginLog({
    required String email,
    required bool success,
    String? errorMessage,
    String? ipAddress,
    Map<String, dynamic>? location,
    String loginMethod = 'email_password',
    String? userId,
  }) async {
    try {
      Map<String, dynamic> deviceInfo = await _getDeviceInfo();
      var connectivityResult = await Connectivity().checkConnectivity();
      String networkType = connectivityResult.toString();
      String deviceType = await _getDeviceType();

      final logData = {
        'email': email,
        'success': success,
        'errorMessage': errorMessage,
        'ip': ipAddress ?? 'Unknown',
        'location':
            location ??
            {
              'city': 'Unknown',
              'country': 'Unknown',
              'region': 'Unknown',
              'org': 'Unknown',
            },
        'deviceInfo': deviceInfo,
        'deviceType': deviceType,
        'networkType': networkType,
        'timestamp': FieldValue.serverTimestamp(),
        'userAgent': 'Flutter Business App',
        'loginMethod': loginMethod,
        'appType': 'business',
        'userId': userId,
      };

      await _firestore.collection('loginLogs').add(logData);
      print('Login log saved successfully');
    } catch (e) {
      print('Error saving login log: $e');
      // Don't show error to user, just log it
    }
  }

  // Check if email is blocked
  Future<bool> _isEmailBlocked(String email) async {
    try {
      // Check blockedLogins collection
      final blockedDoc = await _firestore
          .collection('blockedLogins')
          .doc(email.toLowerCase())
          .get();

      if (!blockedDoc.exists) {
        return false;
      }

      final data = blockedDoc.data();
      if (data == null) return false;

      final blockedUntil = data['blockedUntil'] as Timestamp?;
      final failedAttempts = data['failedAttempts'] as int? ?? 0;

      // Check if block has expired
      if (blockedUntil != null) {
        final now = DateTime.now();
        if (now.isAfter(blockedUntil.toDate())) {
          // Block expired, remove it
          await _firestore
              .collection('blockedLogins')
              .doc(email.toLowerCase())
              .delete();
          return false;
        }
      }

      // Check if attempts exceed threshold
      return failedAttempts >= 3;
    } catch (e) {
      print('Error checking if email is blocked: $e');
      return false;
    }
  }

  // Get remaining blocked time
  Future<Duration?> _getRemainingBlockTime(String email) async {
    try {
      final blockedDoc = await _firestore
          .collection('blockedLogins')
          .doc(email.toLowerCase())
          .get();

      if (!blockedDoc.exists) return null;

      final data = blockedDoc.data();
      if (data == null) return null;

      final blockedUntil = data['blockedUntil'] as Timestamp?;
      if (blockedUntil == null) return null;

      final now = DateTime.now();
      final blockedUntilDate = blockedUntil.toDate();

      if (now.isAfter(blockedUntilDate)) return null;

      return blockedUntilDate.difference(now);
    } catch (e) {
      print('Error getting remaining block time: $e');
      return null;
    }
  }

  // Update failed login attempts
  Future<void> _updateFailedAttempts(String email, bool isSuccessful) async {
    try {
      final emailKey = email.toLowerCase();
      final blockedRef = _firestore.collection('blockedLogins').doc(emailKey);

      if (isSuccessful) {
        // Reset failed attempts on successful login
        await blockedRef.delete();
        return;
      }

      // Increment failed attempts
      final blockedDoc = await blockedRef.get();
      final now = DateTime.now();
      final blockedUntil = now.add(Duration(hours: 1));

      if (!blockedDoc.exists) {
        // First failed attempt
        await blockedRef.set({
          'email': email,
          'failedAttempts': 1,
          'firstFailedAt': FieldValue.serverTimestamp(),
          'lastFailedAt': FieldValue.serverTimestamp(),
          'blockedUntil': blockedUntil,
          'appType': 'business',
        });
      } else {
        final data = blockedDoc.data()!;
        final currentAttempts = (data['failedAttempts'] as int?) ?? 0;
        final newAttempts = currentAttempts + 1;

        await blockedRef.update({
          'failedAttempts': newAttempts,
          'lastFailedAt': FieldValue.serverTimestamp(),
          'blockedUntil': blockedUntil,
        });

        // If this is the 3rd failed attempt, send notification/email
        if (newAttempts == 3) {
          _sendBlockNotification(email);
        }
      }
    } catch (e) {
      print('Error updating failed attempts: $e');
    }
  }

  // Send notification about account being blocked
  Future<void> _sendBlockNotification(String email) async {
    try {
      // Log the block event
      await _firestore.collection('securityEvents').add({
        'type': 'login_blocked',
        'email': email,
        'reason': 'Too many failed login attempts',
        'blockedUntil': DateTime.now().add(Duration(hours: 1)),
        'timestamp': FieldValue.serverTimestamp(),
        'appType': 'business',
      });

      // TODO: Send email notification to user
      // You can implement Firebase Cloud Functions to send emails
      // or use a third-party email service
    } catch (e) {
      print('Error sending block notification: $e');
    }
  }

  // Better method: Check Firestore for user/business existence
  Future<bool> _checkUserExists(String email) async {
    try {
      // For business app
      final querySnapshot = await _firestore
          .collection('businesses')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      return querySnapshot.docs.isNotEmpty;

      // For user app:
      // final querySnapshot = await _firestore
      //     .collection('users')
      //     .where('email', isEqualTo: email)
      //     .limit(1)
      //     .get();
      // return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking user in Firestore: $e');
      return true; // Assume exists for safety
    }
  }

  Future<void> _signIn() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    // Check if email is blocked
    final isBlocked = await _isEmailBlocked(email);
    if (isBlocked) {
      final remainingTime = await _getRemainingBlockTime(email);
      String message =
          'This account has been temporarily blocked due to too many failed login attempts.';

      if (remainingTime != null) {
        final minutes = remainingTime.inMinutes;
        if (minutes > 0) {
          message +=
              '\nPlease try again in $minutes minute${minutes > 1 ? 's' : ''}.';
        } else {
          message += '\nPlease try again in a few moments.';
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: Duration(seconds: 5)),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    String? ipAddress;
    Map<String, dynamic>? location;
    String? userId;

    try {
      // Get location data before attempting login
      location = await _getLocationData();
      ipAddress = location?['ip'];
    } catch (e) {
      print('Error fetching location: $e');
    }

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      userId = userCredential.user?.uid;

      // Reset failed attempts on successful login
      await _updateFailedAttempts(email, true);

      // Check if email is verified — send OTP if not
      if (userCredential.user != null && !userCredential.user!.emailVerified) {
        try {
          final otpResult = await FirebaseFunctions.instance
              .httpsCallable('sendEmailOTP')
              .call({'email': email, 'purpose': 'verify'});
          final pinId = otpResult.data['pinId'] as String;

          await _auth.signOut();
          setState(() => _isLoading = false);

          if (!mounted) return;
          navigateTo(
            context,
            EmailOtpVerificationPage(
              email: email,
              pinId: pinId,
              onResend: () async {
                final res = await FirebaseFunctions.instance
                    .httpsCallable('sendEmailOTP')
                    .call({'email': email, 'purpose': 'verify'});
                return res.data['pinId'] as String;
              },
              onVerified: () async {
                // Re-sign in now that email is verified
                final pw = await _storage.read(key: 'last_password') ?? password;
                try {
                  await _auth.signInWithEmailAndPassword(
                    email: email,
                    password: pw,
                  );
                  if (mounted) navigateTo(context, HomePage());
                } catch (_) {
                  if (mounted) {
                    navigateTo(context, const SignIn(),
                        type: NavigationType.clearStack);
                  }
                }
              },
            ),
          );
          return;
        } catch (e) {
          await _auth.signOut();
          setState(() => _isLoading = false);
          showSimpleDialog(
              'Please verify your email. Failed to send OTP.', Colors.red);
          return;
        }
      }

      await _storage.write(key: 'last_email', value: email);
      await _storage.write(key: 'last_password', value: password);
      await _saveStandIdIfMatched();

      // Send success notification email (fire-and-forget)
      _sendLoginNotificationEmail(
        email: email,
        success: true,
        location: location,
      );

      // Log successful login
      await _saveLoginLog(
        email: email,
        success: true,
        errorMessage: null,
        ipAddress: ipAddress,
        location: location,
        userId: userId,
      );

      // Send login success notification email
      _sendLoginNotificationEmail(
        email: email,
        success: true,
        location: location,
      );

      navigateTo(context, HomePage());
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      bool shouldCountAsFailed = false;

      if (e.code == 'user-not-found') {
        errorMessage = 'No user found for that email.';
        // Check if user actually exists but we got user-not-found
        // This can happen with wrong email or non-existent user
        final userExists = await _checkUserExists(email);
        if (userExists) {
          shouldCountAsFailed = true;
        }
      } else if (e.code == 'wrong-password') {
        errorMessage = 'Wrong password provided.';
        shouldCountAsFailed = true;
      } else if (e.code == 'invalid-email') {
        errorMessage = 'Invalid email format.';
      } else if (e.code == 'user-disabled') {
        errorMessage = 'User account has been disabled.';
      } else {
        errorMessage = 'An error occurred: ${e.message}';
      }

      // Update failed attempts if this was a wrong password attempt
      // or user-not-found for an existing user
      if (shouldCountAsFailed) {
        await _updateFailedAttempts(email, false);

        // Check if account is now blocked
        final isNowBlocked = await _isEmailBlocked(email);
        if (isNowBlocked) {
          final remainingTime = await _getRemainingBlockTime(email);
          final failedAttempts = await _getFailedAttempts(email);

          if (failedAttempts >= 3) {
            errorMessage =
                'Too many failed attempts. Account is temporarily blocked. ';
            if (remainingTime != null) {
              errorMessage +=
                  'Please try again in ${remainingTime.inMinutes} minute${remainingTime.inMinutes > 1 ? 's' : ''}.';
            }
          }
        }
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));

      // Log failed login attempt
      await _saveLoginLog(
        email: email,
        success: false,
        errorMessage: errorMessage,
        ipAddress: ipAddress,
        location: location,
        userId: userId,
      );

      // Send login failure notification email
      _sendLoginNotificationEmail(
        email: email,
        success: false,
        reason: errorMessage,
        location: location,
      );
    } catch (e) {
      String errorMessage = 'An unexpected error occurred: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));

      // Log other errors
      await _saveLoginLog(
        email: email,
        success: false,
        errorMessage: errorMessage,
        ipAddress: ipAddress,
        location: location,
        userId: userId,
      );

      // Send login failure notification email
      _sendLoginNotificationEmail(
        email: email,
        success: false,
        reason: errorMessage,
        location: location,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendLoginNotificationEmail({
    required String email,
    required bool success,
    String? reason,
    Map<String, dynamic>? location,
  }) async {
    try {
      final now = DateTime.now();
      final timeStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final city = location?['city'] ?? 'Unknown';
      final country = location?['country'] ?? 'Unknown';
      final locationStr = '$city, $country';

      final String subject;
      final String html;

      if (success) {
        subject = '✅ Sign-in Confirmed — PadiPay Business';
        html = '<!DOCTYPE html><html><head><meta charset="UTF-8"/></head>'
            '<body style="margin:0;padding:0;background:#f0f2f5;font-family:\'Helvetica Neue\',Helvetica,Arial,sans-serif;">'
            '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;">'
            '<tr><td align="center"><table width="520" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;">'
            '<tr><td align="center" style="padding-bottom:24px;">'
            '<span style="font-size:26px;font-weight:700;color:#1a1a2e;letter-spacing:-0.5px;">Padi<span style="color:#4f46e5;">Pay</span> Business</span>'
            '</td></tr>'
            '<tr><td style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.07);">'
            '<table width="100%" cellpadding="0" cellspacing="0">'
            '<tr><td style="background:linear-gradient(135deg,#059669 0%,#10b981 100%);height:5px;font-size:0;line-height:0;">&nbsp;</td></tr>'
            '<tr><td style="padding:40px 48px;">'
            '<p style="margin:0 0 6px;font-size:13px;font-weight:600;letter-spacing:1.2px;text-transform:uppercase;color:#059669;">Security Notice</p>'
            '<h1 style="margin:0 0 16px;font-size:24px;font-weight:800;color:#0f0f1a;">Sign-in Confirmed ✅</h1>'
            '<p style="margin:0 0 24px;font-size:15px;color:#6b7280;line-height:1.6;">'
            'A successful sign-in was recorded on your PadiPay Business account.</p>'
            '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0fdf4;border-radius:10px;padding:20px;margin:0 0 24px;">'
            '<tr><td><p style="margin:0 0 10px;font-size:13px;color:#374151;"><strong>Account:</strong> $email</p>'
            '<p style="margin:0 0 10px;font-size:13px;color:#374151;"><strong>Time:</strong> $timeStr</p>'
            '<p style="margin:0;font-size:13px;color:#374151;"><strong>Location:</strong> $locationStr</p>'
            '</td></tr></table>'
            '<p style="margin:0;font-size:13px;color:#6b7280;">If this wasn\'t you, please change your password immediately and contact support.</p>'
            '</td></tr>'
            '<tr><td style="padding:0 48px;"><div style="border-top:1px solid #f3f4f6;"></div></td></tr>'
            '<tr><td style="padding:20px 48px;"><p style="margin:0;font-size:12px;color:#d1d5db;">&copy; 2026 PadiPay Business</p></td></tr>'
            '</table></td></tr>'
            '</table></td></tr>'
            '</table></body></html>';
      } else {
        subject = '⚠️ Failed Login Attempt — PadiPay Business';
        html = '<!DOCTYPE html><html><head><meta charset="UTF-8"/></head>'
            '<body style="margin:0;padding:0;background:#f0f2f5;font-family:\'Helvetica Neue\',Helvetica,Arial,sans-serif;">'
            '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;">'
            '<tr><td align="center"><table width="520" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;">'
            '<tr><td align="center" style="padding-bottom:24px;">'
            '<span style="font-size:26px;font-weight:700;color:#1a1a2e;letter-spacing:-0.5px;">Padi<span style="color:#4f46e5;">Pay</span> Business</span>'
            '</td></tr>'
            '<tr><td style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.07);">'
            '<table width="100%" cellpadding="0" cellspacing="0">'
            '<tr><td style="background:linear-gradient(135deg,#dc2626 0%,#ef4444 100%);height:5px;font-size:0;line-height:0;">&nbsp;</td></tr>'
            '<tr><td style="padding:40px 48px;">'
            '<p style="margin:0 0 6px;font-size:13px;font-weight:600;letter-spacing:1.2px;text-transform:uppercase;color:#dc2626;">Security Alert</p>'
            '<h1 style="margin:0 0 16px;font-size:24px;font-weight:800;color:#0f0f1a;">Failed Login Attempt ⚠️</h1>'
            '<p style="margin:0 0 24px;font-size:15px;color:#6b7280;line-height:1.6;">'
            'We detected a failed sign-in attempt on your PadiPay Business account.</p>'
            '<table width="100%" cellpadding="0" cellspacing="0" style="background:#fef2f2;border-radius:10px;padding:20px;margin:0 0 24px;">'
            '<tr><td><p style="margin:0 0 10px;font-size:13px;color:#374151;"><strong>Account:</strong> $email</p>'
            '<p style="margin:0 0 10px;font-size:13px;color:#374151;"><strong>Reason:</strong> ${reason ?? 'Invalid credentials'}</p>'
            '<p style="margin:0 0 10px;font-size:13px;color:#374151;"><strong>Time:</strong> $timeStr</p>'
            '<p style="margin:0;font-size:13px;color:#374151;"><strong>Location:</strong> $locationStr</p>'
            '</td></tr></table>'
            '<p style="margin:0;font-size:13px;color:#6b7280;">If this wasn\'t you, your account may be at risk. Please change your password immediately.</p>'
            '</td></tr>'
            '<tr><td style="padding:0 48px;"><div style="border-top:1px solid #f3f4f6;"></div></td></tr>'
            '<tr><td style="padding:20px 48px;"><p style="margin:0;font-size:12px;color:#d1d5db;">&copy; 2026 PadiPay Business</p></td></tr>'
            '</table></td></tr>'
            '</table></td></tr>'
            '</table></body></html>';
      }

      await FirebaseFunctions.instance.httpsCallable('sendEmail').call({
        'to': email,
        'subject': subject,
        'html': html,
      });
    } catch (e) {
      print('Login notification email error (non-fatal): $e');
    }
  }

  // Get current failed attempts count
  Future<int> _getFailedAttempts(String email) async {
    try {
      final blockedDoc = await _firestore
          .collection('blockedLogins')
          .doc(email.toLowerCase())
          .get();

      if (!blockedDoc.exists) return 0;

      final data = blockedDoc.data();
      return (data?['failedAttempts'] as int?) ?? 0;
    } catch (e) {
      print('Error getting failed attempts: $e');
      return 0;
    }
  }

  Future<void> _saveStandIdIfMatched() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final busSnap = await _firestore
          .collection('businesses')
          .doc(user.uid)
          .get();
      if (!busSnap.exists) return;

      final data = busSnap.data();
      if (data == null) return;

      final stands = data['posStands'];
      if (stands is! List) return;

      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      for (final stand in stands) {
        if (stand is Map<String, dynamic>) {
          final standEmail = stand['standLoginEmail'];
          final standPassword = stand['standLoginPassword'];
          final standId = stand['standId'];
          if (standEmail == email &&
              standPassword == password &&
              standId != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('activeStandId', standId.toString());
            return;
          }
        }
      }

      // Clear if no match to avoid stale value
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('activeStandId');
    } catch (e) {
      debugPrint('Error saving standId: $e');
    }
  }

  Future<void> _biometricAuth() async {
    if (_isLoading || _isBiometricLoading) return;

    setState(() => _isBiometricLoading = true);

    final LocalAuthentication auth = LocalAuthentication();

    String? ipAddress;
    Map<String, dynamic>? location;
    try {
      location = await _getLocationData();
      ipAddress = location?['ip'];
    } catch (_) {}

    bool authenticated = false;
    try {
      authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to sign in to PadiPay Business',
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      showSimpleDialog('Authentication error: $e', Colors.red);
      if (mounted) setState(() => _isBiometricLoading = false);
      return;
    }

    if (!authenticated) {
      if (mounted) setState(() => _isBiometricLoading = false);
      return;
    }

    final savedEmail = await _storage.read(key: 'last_email');
    final savedPassword = await _storage.read(key: 'last_password');

    if (savedEmail == null || savedPassword == null) {
      showSimpleDialog(
          'No saved account found. Please sign in with your password first.',
          Colors.orange);
      if (mounted) setState(() => _isBiometricLoading = false);
      return;
    }

    final isBlocked = await _isEmailBlocked(savedEmail);
    if (isBlocked) {
      final remaining = await _getRemainingBlockTime(savedEmail);
      _showBlockedDialog(savedEmail, remaining);
      if (mounted) setState(() => _isBiometricLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: savedEmail,
        password: savedPassword,
      );

      await _updateFailedAttempts(savedEmail, true);

      // Send success email (fire-and-forget)
      _sendLoginNotificationEmail(
        email: savedEmail,
        success: true,
        location: location,
      );

      // Check if email is verified — send OTP if not
      if (!_auth.currentUser!.emailVerified) {
        try {
          final otpResult = await FirebaseFunctions.instance
              .httpsCallable('sendEmailOTP')
              .call({'email': savedEmail, 'purpose': 'verify'});
          final pinId = otpResult.data['pinId'] as String;

          await _auth.signOut();
          setState(() => _isLoading = false);

          if (!mounted) return;
          navigateTo(
            context,
            EmailOtpVerificationPage(
              email: savedEmail,
              pinId: pinId,
              onResend: () async {
                final res = await FirebaseFunctions.instance
                    .httpsCallable('sendEmailOTP')
                    .call({'email': savedEmail, 'purpose': 'verify'});
                return res.data['pinId'] as String;
              },
              onVerified: () async {
                try {
                  await _auth.signInWithEmailAndPassword(
                    email: savedEmail,
                    password: savedPassword,
                  );
                  if (mounted) navigateTo(context, HomePage());
                } catch (_) {
                  if (mounted) {
                    navigateTo(context, const SignIn(),
                        type: NavigationType.clearStack);
                  }
                }
              },
            ),
          );
          return;
        } catch (e) {
          await _auth.signOut();
          setState(() => _isLoading = false);
          showSimpleDialog(
              'Please verify your email. Failed to send OTP.', Colors.red);
          return;
        }
      }

      await _saveLoginLog(
        email: savedEmail,
        success: true,
        ipAddress: ipAddress,
        location: location,
        loginMethod: 'biometric',
        userId: userCredential.user?.uid,
      );

      await _saveStandIdIfMatched();
      navigateTo(context, HomePage());
    } on FirebaseAuthException catch (e) {
      String msg = e.message ?? 'Authentication failed';
      await _updateFailedAttempts(savedEmail, false);
      _sendLoginNotificationEmail(
        email: savedEmail,
        success: false,
        reason: msg,
        location: location,
      );
      await _saveLoginLog(
        email: savedEmail,
        success: false,
        errorMessage: 'Biometric: $msg',
        ipAddress: ipAddress,
        location: location,
        loginMethod: 'biometric',
      );
      showSimpleDialog(msg, Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isBiometricLoading = false;
        });
      }
    }
  }

  void _showBlockedDialog(String email, Duration? remaining) {
    String msg =
        'Your account has been temporarily blocked due to too many failed login attempts.';
    if (remaining != null) {
      final mins = remaining.inMinutes;
      msg += mins > 0
          ? '\n\nPlease try again in $mins minute${mins > 1 ? 's' : ''}.'
          : '\n\nPlease try again in a few moments.';
    }
    showSimpleDialog(msg, Colors.red);
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Image.asset("assets/weird_img.png", width: double.infinity),
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          "Welcome Back",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Enter your credentials to access your account",
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 15,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 15),
                    Text(
                      "Email Address",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: "email@example.com",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: BorderSide(color: Colors.grey.shade400),
                        ),
                      ),
                    ),
                    SizedBox(height: 15),
                    Text(
                      "Password",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: "********",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: BorderSide(color: Colors.grey.shade400),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey,
                          ),
                          onPressed: _togglePasswordVisibility,
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () {
                            navigateTo(context, ForgotPasswordPage());
                          },
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 30),
                    GestureDetector(
                      onTap: _signIn,
                      child: Container(
                        alignment: Alignment.center,
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        width: MediaQuery.of(context).size.width,
                        child: _isLoading
                            ? CircularProgressIndicator(color: Colors.white)
                            : Text(
                                "Next",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(height: 20),
                    InkWell(
                      onTap: () {
                        navigateTo(context, CreateAccount());
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          RichText(
                            text: TextSpan(
                              text: "Don't have an account? ",
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                              ),
                              children: [
                                TextSpan(
                                  text: " Create Account",
                                  style: TextStyle(
                                    color: primaryColor,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_biometricEnabled && _deviceSupportsBiometrics) ...[  
                      const SizedBox(height: 30),
                      Center(
                        child: GestureDetector(
                          onTap: (_isLoading || _isBiometricLoading)
                              ? null
                              : _biometricAuth,
                          child: SizedBox(
                            height: 80,
                            width: 80,
                            child: Center(
                              child: _isBiometricLoading
                                  ? SizedBox(
                                      height: 32,
                                      width: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: primaryColor,
                                      ),
                                    )
                                  : Icon(
                                      Icons.fingerprint,
                                      size: 56,
                                      color: primaryColor,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
