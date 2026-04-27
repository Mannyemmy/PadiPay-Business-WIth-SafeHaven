import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:local_auth/local_auth.dart';
import 'package:padi_pay_business/utils/screen_security.dart';
import 'package:padi_pay_business/ui/keypad.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show File, Platform;

// global navigator key used for showing persistent UI elements like toasts/bottom sheets
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Secure storage helper (use for sensitive values instead of SharedPreferences)
const _secureStorage = FlutterSecureStorage();

Future<void> secureSet(String key, String value) async {
  try {
    await _secureStorage.write(key: key, value: value);
  } catch (e) {
    print('secureSet error: $e');
  }
}

Future<String?> secureGet(String key) async {
  try {
    return await _secureStorage.read(key: key);
  } catch (e) {
    print('secureGet error: $e');
    return null;
  }
}

Future<void> secureDelete(String key) async {
  try {
    await _secureStorage.delete(key: key);
  } catch (e) {
    print('secureDelete error: $e');
  }
}

/// Lightweight root/jailbreak detection without extra native plugin.
/// Returns true when common root/jailbreak indicators are found.
Future<bool> isDeviceRootedOrJailbroken() async {
  try {
    if (Platform.isAndroid) {
      final paths = [
        '/system/app/Superuser.apk',
        '/sbin/su',
        '/system/bin/su',
        '/system/xbin/su',
        '/data/local/xbin/su',
        '/data/local/bin/su',
        '/system/sd/xbin/su',
        '/system/bin/failsafe/su',
        '/data/local/su',
      ];
      for (final p in paths) {
        if (await File(p).exists()) return true;
      }
      return false;
    } else if (Platform.isIOS) {
      final iosPaths = [
        '/Applications/Cydia.app',
        '/Library/MobileSubstrate/MobileSubstrate.dylib',
        '/bin/bash',
        '/usr/sbin/sshd',
        '/etc/apt',
      ];
      for (final p in iosPaths) {
        if (await File(p).exists()) return true;
      }
      return false;
    }
  } catch (e) {
    print('root detection error: $e');
  }
  return false;
}

const Color primaryColor = Color(0xFF007AFF);
const Color darkBlue = Color(0xFF00008B);
const Color royalBlue = Color(0xFF002366);
const Color oxfordBlue = Color(0xFF14213D);
const Color midnightBlue = Color(0xFF191970);
const Color navyBlue = Color(0xFF242550);

Future<void> saveUserDeviceToken(String userId) async {
  // Only save device token for main user (not stand users)
  final businessDoc = await FirebaseFirestore.instance
      .collection('businesses')
      .doc(userId)
      .get();
  if (!businessDoc.exists) {
    print('Skipping device token save for stand user: $userId');
    return;
  }

  final FirebaseMessaging messaging = FirebaseMessaging.instance;
  // Request notification permission
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    // Get FCM token
    final String? token = await messaging.getToken();

    if (token != null) {
      // Check for other users with the same token and invalidate (remove) it
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('deviceToken', isEqualTo: token)
          .get();

      for (var doc in querySnapshot.docs) {
        if (doc.id != userId) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(doc.id)
              .update({'deviceToken': FieldValue.delete()});
        }
      }

      // Save token in user's document
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'deviceToken': token,
      }, SetOptions(merge: true));

      print('✅ Device token saved for user: $userId');
    } else {
      print('⚠️ Failed to get FCM token');
    }
  } else {
    print('🚫 Notification permission not granted');
  }
}

void navigateTo(
  BuildContext context,
  Widget page, {
  NavigationType type = NavigationType.push,
  Duration duration = const Duration(milliseconds: 300),
}) {
  final route = PageRouteBuilder(
    transitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0); // from right to left
      const end = Offset.zero;
      const curve = Curves.ease;

      final tween = Tween(
        begin: begin,
        end: end,
      ).chain(CurveTween(curve: curve));
      final offsetAnimation = animation.drive(tween);

      return SlideTransition(position: offsetAnimation, child: child);
    },
  );

  switch (type) {
    case NavigationType.push:
      Navigator.push(context, route);
      break;

    case NavigationType.replace:
      Navigator.pushReplacement(context, route);
      break;

    case NavigationType.clearStack:
      Navigator.pushAndRemoveUntil(context, route, (route) => false);
      break;
  }
}

enum NavigationType {
  push, // Navigate to a new page, keep history
  replace, // Replace the current page
  clearStack, // Clear all previous pages
}

void showToast(String msg, Color color) {
  Fluttertoast.showToast(
    msg: msg,
    toastLength: Toast.LENGTH_SHORT,
    gravity: ToastGravity.BOTTOM,
    timeInSecForIosWeb: 1,
    backgroundColor: color,
    textColor: Colors.white,
    fontSize: 14.0,
  );
}

void showSimpleDialog(String msg, Color color) {
  final BuildContext? context = navigatorKey.currentContext;
  if (context == null) return;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    builder: (ctx) {
      return SafeArea(
        bottom: true,
        child: Container(
          margin: const EdgeInsets.all(16.0),
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                msg,
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 16.0,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20.0),
              SizedBox(
                width: double.infinity,
                height: 48.0,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Check PIN and show appropriate passcode sheet
/// Returns true if PIN verification successful, false otherwise
Future<bool> verifyTransactionPin() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showSimpleDialog('User not authenticated', Colors.red);
      return false;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      showSimpleDialog('User document not found', Colors.red);
      return false;
    }

    final savedPasscode = userDoc.data()?['passcode'] as String?;
    final BuildContext? context = navigatorKey.currentContext;
    if (context == null) return false;

    if (savedPasscode == null || savedPasscode.isEmpty) {
      final result = await showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return const CreatePasscodeSheetForTransaction();
        },
      );
      return result ?? false;
    }

    final enteredPasscode = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return const EnterPasscodeSheetForTransaction();
      },
    );

    if (enteredPasscode == null) {
      return false;
    } else if (enteredPasscode == 'BIOMETRIC_SUCCESS') {
      return true;
    } else if (enteredPasscode == savedPasscode) {
      return true;
    } else {
      showSimpleDialog('Incorrect passcode. Please try again.', Colors.red);
      return false;
    }
  } catch (e) {
    print('Error verifying transaction PIN: $e');
    showSimpleDialog('Error verifying PIN', Colors.red);
    return false;
  }
}

/// Passcode sheet for entering existing PIN before transaction
class EnterPasscodeSheetForTransaction extends StatefulWidget {
  const EnterPasscodeSheetForTransaction({super.key});

  @override
  State<EnterPasscodeSheetForTransaction> createState() =>
      _EnterPasscodeSheetForTransactionState();
}

class _EnterPasscodeSheetForTransactionState
    extends State<EnterPasscodeSheetForTransaction> {
  String pin = '';
  bool _useBiometric = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricAttempted = false;
  bool _showPinKeypad = false;
  bool _biometricLoading = false;

  final _localAuth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    ScreenSecurity.secureOn();
    _initializeBiometric();
  }

  @override
  void dispose() {
    ScreenSecurity.secureOff();
    super.dispose();
  }

  Future<void> _initializeBiometric() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final biometricEnabled =
          await _storage.read(key: 'biometric_enabled') == 'true';

      if (mounted) {
        setState(() {
          _biometricAvailable = canCheckBiometrics && isDeviceSupported;
          _biometricEnabled = biometricEnabled;
          _useBiometric = _biometricAvailable && _biometricEnabled;
        });

        if (_useBiometric) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _authenticateWithBiometric();
          });
        } else {
          if (mounted) setState(() => _showPinKeypad = true);
        }
      }
    } catch (e) {
      print('Error initializing biometric: $e');
      if (mounted) setState(() => _showPinKeypad = true);
    }
  }

  Future<void> _authenticateWithBiometric() async {
    if (_biometricAttempted || !_useBiometric) return;

    setState(() {
      _biometricLoading = true;
      _biometricAttempted = true;
    });

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to proceed with transaction',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated && mounted) {
        Navigator.pop(context, 'BIOMETRIC_SUCCESS');
      } else if (mounted) {
        setState(() => _showPinKeypad = true);
      }
    } on PlatformException catch (e) {
      print('Biometric error: ${e.code} - ${e.message}');
      if (mounted) setState(() => _showPinKeypad = true);
    } catch (e) {
      print('Biometric authentication error: $e');
      if (mounted) setState(() => _showPinKeypad = true);
    } finally {
      if (mounted) setState(() => _biometricLoading = false);
    }
  }

  void _switchToPin() {
    setState(() {
      _useBiometric = false;
      _showPinKeypad = true;
      pin = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isComplete = pin.length == 4;

    if (_biometricLoading || (_useBiometric && !_showPinKeypad)) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 32),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context, null),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.grey.shade500,
                        size: 26,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.fingerprint, color: primaryColor, size: 40),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Authenticating',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Use your fingerprint or face to verify',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 32),
                const CircularProgressIndicator(color: primaryColor),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _switchToPin,
                  child: Text(
                    'Use PIN instead',
                    style: TextStyle(
                      fontSize: 13,
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 32),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, null),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.grey.shade500,
                      size: 26,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter Passcode',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your 4-digit passcode to continue',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final bool isFilled = index < pin.length;
                  final bool isCurrent = index == pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: isCurrent ? 18 : 16,
                    height: isCurrent ? 18 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? primaryColor : Colors.transparent,
                      border: Border.all(
                        color: isFilled
                            ? primaryColor
                            : isCurrent
                            ? primaryColor
                            : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 28),
              Keypad(
                onPressed: (val) {
                  setState(() {
                    if (val == null) {
                      if (pin.isNotEmpty) {
                        pin = pin.substring(0, pin.length - 1);
                      }
                    } else if (pin.length < 4) {
                      pin += val;
                    }
                  });
                },
                rightChild: AnimatedScale(
                  scale: isComplete ? 1.0 : 0.85,
                  duration: const Duration(milliseconds: 180),
                  child: GestureDetector(
                    onTap: isComplete
                        ? () => Navigator.pop(context, pin)
                        : null,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isComplete ? Colors.green : Colors.grey.shade200,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: isComplete ? Colors.white : Colors.grey.shade400,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_biometricAvailable && _biometricEnabled && _showPinKeypad)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _useBiometric = true;
                        _showPinKeypad = false;
                        _biometricLoading = false;
                        _biometricAttempted = false;
                      });
                      _authenticateWithBiometric();
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fingerprint, size: 18, color: primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Use Biometric',
                          style: TextStyle(
                            fontSize: 13,
                            color: primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Passcode sheet for creating new PIN before transaction
class CreatePasscodeSheetForTransaction extends StatefulWidget {
  const CreatePasscodeSheetForTransaction({super.key});

  @override
  State<CreatePasscodeSheetForTransaction> createState() =>
      _CreatePasscodeSheetForTransactionState();
}

class _CreatePasscodeSheetForTransactionState
    extends State<CreatePasscodeSheetForTransaction> {
  String pin = '';
  String confirmPin = '';
  bool isConfirming = false;

  void _showConfirmScreen() {
    setState(() {
      isConfirming = true;
      confirmPin = '';
    });
  }

  Future<void> _savePasscode() async {
    if (pin == confirmPin) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({"passcode": pin}, SetOptions(merge: true));
          Navigator.pop(context, true);
        }
      } catch (e) {
        print('Error saving passcode: $e');
        showSimpleDialog('Error saving passcode', Colors.red);
      }
    } else {
      showSimpleDialog('Passcodes do not match. Please try again.', Colors.red);
      setState(() {
        isConfirming = false;
        pin = '';
        confirmPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = isConfirming ? confirmPin : pin;
    final title = isConfirming ? 'Confirm Passcode' : 'Create Passcode';
    final subtitle = isConfirming
        ? 'Re-enter your 4-digit passcode'
        : 'Create a 4-digit passcode to secure your transactions';
    final bool isComplete = currentPin.length == 4;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 32),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.grey.shade500,
                      size: 26,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConfirming
                      ? Icons.lock_outline_rounded
                      : Icons.lock_open_outlined,
                  color: primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  title,
                  key: ValueKey(title),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  subtitle,
                  key: ValueKey(subtitle),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final bool isFilled = index < currentPin.length;
                  final bool isCurrent = index == currentPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: isCurrent ? 18 : 16,
                    height: isCurrent ? 18 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? primaryColor : Colors.transparent,
                      border: Border.all(
                        color: isFilled
                            ? primaryColor
                            : isCurrent
                            ? primaryColor
                            : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 28),
              Keypad(
                onPressed: (val) {
                  setState(() {
                    if (val == null) {
                      if (currentPin.isNotEmpty) {
                        if (isConfirming) {
                          confirmPin = confirmPin.substring(
                            0,
                            confirmPin.length - 1,
                          );
                        } else {
                          pin = pin.substring(0, pin.length - 1);
                        }
                      }
                    } else if (currentPin.length < 4) {
                      if (isConfirming) {
                        confirmPin += val;
                      } else {
                        pin += val;
                      }
                    }
                  });
                },
                rightChild: AnimatedScale(
                  scale: isComplete ? 1.0 : 0.85,
                  duration: const Duration(milliseconds: 180),
                  child: GestureDetector(
                    onTap: isComplete
                        ? () {
                            if (isConfirming) {
                              _savePasscode();
                            } else {
                              _showConfirmScreen();
                            }
                          }
                        : null,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isComplete ? Colors.green : Colors.grey.shade200,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: isComplete ? Colors.white : Colors.grey.shade400,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> fetchAndPrintCustomer() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('ERROR: No authenticated user');
      return;
    }

    final uid = user.uid;

    final snapshot = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(uid)
        .get();
    final snapshotuser = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (!snapshot.exists) {
      print('ERROR: No businesses document found for uid $uid');
    }
    if (!snapshotuser.exists) {
      print('ERROR: No users document found for uid $uid');
      return;
    }

    final customerId =
        (snapshot.data()?['getAnchorData']['kybCreation']
                as Map<String, dynamic>?)?['data']?['id']
            as String?;

    if (customerId == null || customerId.isEmpty) {
      print('ERROR: customerId not found at kybCreation.data.id');
    }
    final customerIdUser =
        (snapshotuser.data()?['getAnchorData']['customerCreation']
                as Map<String, dynamic>?)?['data']?['id']
            as String?;

    if (customerIdUser == null || customerIdUser.isEmpty) {
      print('ERROR: customerId not found at customerCreation.data.id');
      return;
    }

    print('Calling fetchCustomer with customerId: $customerIdUser');

    final callable = FirebaseFunctions.instance.httpsCallable('fetchCustomer');

    final result = await callable.call({'customerId': customerIdUser});

    // Pretty-print the full response so you can see everything
    // Pretty-print the full response so you can see everything
    print('\n=== FETCH CUSTOMER SUCCESS ===');
    String jsonString = JsonEncoder.withIndent('  ').convert(result.data);

    // Print in chunks to avoid truncation
    const int chunkSize = 800; // Safe margin below typical 1024 limit
    for (int i = 0; i < jsonString.length; i += chunkSize) {
      int end = (i + chunkSize < jsonString.length)
          ? i + chunkSize
          : jsonString.length;
      print(jsonString.substring(i, end));
    }
    print('================================\n');
  } on FirebaseFunctionsException catch (e) {
    print('\n=== FETCH CUSTOMER FUNCTION ERROR ===');
    print('Code: ${e.code}');
    print('Message: ${e.message}');
    print('Details: ${e.details}');
    print('=====================================\n');
  } catch (e, stack) {
    print('\n=== UNEXPECTED ERROR ===');
    print(e);
    print(stack);
    print('=========================\n');
  }
}

Future<Map<String, String?>> getCurrentAccountIdAndType() async {
  final String? uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    return {
      'accountId': null,
      'accountType': null,
      'accountNumber': null,
      'bankId': null,
    };
  }
  // 0. If this auth user is a stand user, prefer the stand account
  try {
    final DocumentSnapshot<Map<String, dynamic>> standSnap =
        await FirebaseFirestore.instance
            .collection('standUsers')
            .doc(uid)
            .get();
    if (standSnap.exists && standSnap.data() != null) {
      final sdata = standSnap.data()!;
      final String? parentBusinessId = sdata['parentBusinessId'] as String?;
      final String? standId = sdata['standId'] as String?;
      if (parentBusinessId != null && standId != null) {
        final parentSnap = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(parentBusinessId)
            .get();
        if (parentSnap.exists && parentSnap.data() != null) {
          final pdata = parentSnap.data() as Map<String, dynamic>;
          final List<dynamic> posStands = pdata['posStands'] ?? [];
          for (var s in posStands) {
            if (s is Map<String, dynamic> && s['standId'] == standId) {
              final accountData = s['accountData'];
              if (accountData is Map<String, dynamic> &&
                  accountData.containsKey('data')) {
                final dataMap = accountData['data'] as Map<String, dynamic>?;
                final accountId = dataMap?['id']?.toString();
                final accountType =
                    dataMap?['type'] as String? ??
                    accountData['type'] as String?;
                String? accountNumber;
                String? bankId;
                final attributes =
                    dataMap?['attributes'] as Map<String, dynamic>?;
                String? bankName;
                if (attributes != null) {
                  accountNumber = attributes['accountNumber']?.toString();
                  final bank = attributes['bank'] as Map<String, dynamic>?;
                  bankId = bank?['id']?.toString();
                  bankName = bank?['name']?.toString();
                }
                if (accountId != null) {
                  return {
                    'accountId': accountId,
                    'accountType': accountType,
                    'accountNumber': accountNumber,
                    'bankId': bankId,
                    'bankName': bankName,
                  };
                }
              }
            }
          }
        }
      }
    }
  } catch (e) {
    // ignore and fall back to normal logic
  }

  // 1. Check business (same logic as in _fetchBusinessData)
  final DocumentSnapshot<Map<String, dynamic>> busSnap = await FirebaseFirestore
      .instance
      .collection('businesses')
      .doc(uid)
      .get();

  if (busSnap.exists && busSnap.data() != null) {
    final data = busSnap.data()!;
    final String kycStatus = data['kycStatus'] ?? '';

    if (kycStatus == 'APPROVED') {
      final Map<String, dynamic>? virtualAccData =
          data['getAnchorData']?['virtualAccount']?['data']
              as Map<String, dynamic>?;

      if (virtualAccData != null && virtualAccData['id'] != null) {
        final String accountId = virtualAccData['id'].toString();
        final String? accountType = virtualAccData['type'] as String?;
        final Map<String, dynamic>? attributes =
            virtualAccData['attributes'] as Map<String, dynamic>?;
        String? accountNumber;
        String? bankId;
        String? bankName;
        if (attributes != null) {
          accountNumber = attributes['accountNumber']?.toString();
          final bank = attributes['bank'] as Map<String, dynamic>?;
          bankId = bank?['id']?.toString();
          bankName = bank?['name']?.toString();
        }
        return {
          'accountId': accountId,
          'accountType': accountType,
          'accountNumber': accountNumber,
          'bankId': bankId,
          'bankName': bankName,
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
        data['getAnchorData']?['virtualAccount']?['data']
            as Map<String, dynamic>?;

    if (virtualAccData != null && virtualAccData['id'] != null) {
      final String accountId = virtualAccData['id'].toString();
      final String? accountType = virtualAccData['type'] as String?;
      final Map<String, dynamic>? attributes =
          virtualAccData['attributes'] as Map<String, dynamic>?;
      String? accountNumber;
      String? bankId;
      String? bankName;
      if (attributes != null) {
        accountNumber = attributes['accountNumber']?.toString();
        final bank = attributes['bank'] as Map<String, dynamic>?;
        bankId = bank?['id']?.toString();
        bankName = bank?['name']?.toString();
      }
      return {
        'accountId': accountId,
        'accountType': accountType,
        'accountNumber': accountNumber,
        'bankId': bankId,
        'bankName': bankName,
      };
    }
  }

  return {
    'accountId': null,
    'accountType': null,
    'accountNumber': null,
    'bankId': null,
    'bankName': null,
  };
}

// Resolve a bank id given either a candidate bankId or a bankName. If bankId is present
// it is returned; otherwise we try an equality query on bank name followed by
// a case-insensitive scan. Returns null if not found.
Future<String?> resolveBankId({String? bankId, String? bankName}) async {
  try {
    if (bankId != null && bankId.isNotEmpty) return bankId;
    if (bankName == null || bankName.isEmpty) return null;

    // Exact name match first
    final bankQuery = await FirebaseFirestore.instance
        .collection('banks')
        .where('name', isEqualTo: bankName)
        .limit(1)
        .get();
    if (bankQuery.docs.isNotEmpty) {
      return bankQuery.docs.first.id;
    }

    // Fallback: case-insensitive search
    final allBanks = await FirebaseFirestore.instance.collection('banks').get();
    for (var bdoc in allBanks.docs) {
      final bname = (bdoc.data()['name'] as String?) ?? '';
      if (bname.toLowerCase() == bankName.toLowerCase()) return bdoc.id;
    }
  } catch (e) {
    print('resolveBankId error: $e');
  }
  return null;
}

/// Resolve bank id by bank name. Tries an exact match first, then a case-insensitive scan.
Future<String?> resolveBankIdByName(String? bankName) async {
  if (bankName == null || bankName.trim().isEmpty) return null;
  try {
    final exact = await FirebaseFirestore.instance
        .collection('banks')
        .where('name', isEqualTo: bankName)
        .limit(1)
        .get();
    if (exact.docs.isNotEmpty) return exact.docs.first.id;

    final snapshot = await FirebaseFirestore.instance.collection('banks').get();
    final target = bankName.trim().toLowerCase();
    for (var doc in snapshot.docs) {
      final name = doc.data()['name']?.toString() ?? '';
      if (name.trim().toLowerCase() == target) return doc.id;
    }
  } catch (e) {
    debugPrint('resolveBankIdByName error: $e');
  }
  return null;
}

/// Fetch account balance for the given account id using the backend function
/// `fetchAccountBalance`. Returns the balance in the main currency unit
/// (e.g. Naira) or 0.0 on error.
Future<double> fetchAccountBalance(String accountId) async {
  if (accountId.isEmpty) return 0.0;
  try {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'fetchAccountBalance',
    );
    final result = await callable.call({'accountId': accountId});
    double balance = result.data['data']['availableBalance']?.toDouble() ?? 0.0;
    balance /= 100;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cached_balance', balance);
    } catch (_) {}
    return balance;
  } catch (e) {
    debugPrint('utils.fetchAccountBalance error: $e');
    return 0.0;
  }
}

/// Resolve the current account id (prefers stand account when applicable)
/// and return its balance. Useful when callers just want the currently
/// active account's balance without resolving the id themselves.
Future<double> fetchCurrentAccountBalance() async {
  try {
    final details = await getCurrentAccountIdAndType();
    final String? accountId = details['accountId'];
    if (accountId == null) return 0.0;
    return await fetchAccountBalance(accountId);
  } catch (e) {
    debugPrint('utils.fetchCurrentAccountBalance error: $e');
    return 0.0;
  }
}

Future<void> createStroWalletUserIfNeeded(BuildContext context) async {
  // Mapping of full Nigerian state names to two-letter ISO codes (lowercase)
  const Map<String, String> stateToCode = {
    'Abia': 'ab',
    'Adamawa': 'ad',
    'Akwa Ibom': 'ak',
    'Anambra': 'an',
    'Bauchi': 'ba',
    'Bayelsa': 'by',
    'Benue': 'be',
    'Borno': 'bo',
    'Cross River': 'cr',
    'Delta': 'de',
    'Ebonyi': 'eb',
    'Edo': 'ed',
    'Ekiti': 'ek',
    'Enugu': 'en',
    'Gombe': 'go',
    'Imo': 'im',
    'Jigawa': 'ji',
    'Kaduna': 'kd',
    'Kano': 'kn',
    'Katsina': 'kt',
    'Kebbi': 'ke',
    'Kogi': 'ko',
    'Kwara': 'kw',
    'Lagos': 'la',
    'Nasarawa': 'na',
    'Niger': 'ni',
    'Ogun': 'og',
    'Ondo': 'on',
    'Osun': 'os',
    'Oyo': 'oy',
    'Plateau': 'pl',
    'Rivers': 'ri',
    'Sokoto': 'so',
    'Taraba': 'ta',
    'Yobe': 'yo',
    'Zamfara': 'za',
    'Abuja Federal Capital Territory': 'fc',
  };

  // Helper to format DOB to YYYY/MM/DD for payload
  String formatDateToSlash(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      // Handle YYYY-MM-DD
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        return '${parts[0]}/${parts[1]}/${parts[2]}';
      }
      // If already YYYY/MM/DD, return as is
      if (dateStr.contains('/')) {
        return dateStr;
      }
    } catch (e) {
      print('Date format error: $e');
    }
    return dateStr; // Fallback
  }

  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      print('No authenticated user; skipping StroWallet creation');
      return;
    }

    // If this auth user is a POS stand user, do not create a StroWallet user.
    try {
      final standSnap = await FirebaseFirestore.instance
          .collection('standUsers')
          .doc(uid)
          .get();
      if (standSnap.exists) {
        print('Skipping StroWallet user creation for POS stand user: $uid');
        return;
      }
    } catch (e) {
      // Ignore errors checking standUsers and continue with normal flow
      debugPrint('Error checking standUsers for StroWallet skip: $e');
    }

    final userDocSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!userDocSnap.exists) {
      throw Exception('User document not found');
    }
    final userData = userDocSnap.data()!;
    if (userData.containsKey('stroWalletUser')) {
      print('StroWallet user already exists');
      return;
    }

    // Extract fields
    final firstname = userData['firstName'] ?? '';
    final lastname = userData['lastName'] ?? '';
    final email = userData['email'] ?? '';
    String phone = (userData['phone'] ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      throw Exception('Invalid phone number: empty after cleaning');
    }
    if (phone.length == 13 && phone.startsWith('234')) {
      // Already in international format
    } else if (phone.length == 11 && phone.startsWith('0')) {
      phone = '234${phone.substring(1)}';
    } else if (phone.length == 10 &&
        (phone.startsWith('7') ||
            phone.startsWith('8') ||
            phone.startsWith('9'))) {
      phone = '234$phone';
    } else {
      throw Exception(
        'Invalid phone number format: $phone (must be 10-13 digits, starting appropriately for Nigeria)',
      );
    }
    String nin = userData['nin'] ?? '';
    String dob = userData['dateOfBirth'] ?? '';
    final name = userData['userName'] ?? '$firstname $lastname';
    String line1 = userData['address']?['street'] ?? '';
    String city = userData['address']?['city'] ?? '';
    String state = userData['address']?['state'] ?? '';

    // Check if all required fields are present, exit if any are missing
    if (nin.isEmpty ||
        dob.isEmpty ||
        line1.isEmpty ||
        city.isEmpty ||
        state.isEmpty) {
      print('Missing required fields for StroWallet user creation. Exiting.');
      return;
    }

    // Format DOB for payload
    dob = formatDateToSlash(dob);

    // Get state code for payload
    final String stateCode = stateToCode[state.trim()] ?? '';
    if (stateCode.isEmpty) {
      throw Exception(
        'Invalid state: $state. Please enter a valid Nigerian state name.',
      );
    }

    final functions = FirebaseFunctions.instance;
    final cardFunc = functions.httpsCallable('createStrowalletNairaCardUser');
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
      'state': stateCode, // Use two-letter code (lowercase)
    };
    print('Sending createStrowalletNairaCardUser payload: $cardPayload');
    final cardResult = await cardFunc.call(cardPayload);
    print('Create Strowallet Naira Card User Response: ${cardResult.data}');

    // Update user doc
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await userDocRef.update({'stroWalletUser': cardResult.data});

    print('StroWallet user created and saved successfully');
  } catch (e) {
    print('Error creating StroWallet user: $e');
    rethrow;
  }
}

class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text.replaceAll('/', '');
    if (newText.length > 8) return oldValue;

    String formatted = '';
    // Year (positions 0-3)
    if (newText.isNotEmpty) formatted += newText.substring(0, 1);
    if (newText.length >= 2) formatted += newText.substring(1, 2);
    if (newText.length >= 3) formatted += newText.substring(2, 3);
    if (newText.length >= 4) formatted += newText.substring(3, 4);
    if (newText.length >= 5) formatted += '/';
    // Month (positions 4-5)
    if (newText.length >= 5) formatted += newText.substring(4, 5);
    if (newText.length >= 6) formatted += newText.substring(5, 6);
    if (newText.length >= 7) formatted += '/';
    // Day (positions 6-7)
    if (newText.length >= 7) formatted += newText.substring(6, 7);
    if (newText.length >= 8) formatted += newText.substring(7, 8);

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class MissingDataBottomSheet extends StatefulWidget {
  final Map<String, String> missingFields;

  const MissingDataBottomSheet({super.key, required this.missingFields});

  @override
  State<MissingDataBottomSheet> createState() => _MissingDataBottomSheetState();
}

class _MissingDataBottomSheetState extends State<MissingDataBottomSheet> {
  late TextEditingController ninController;
  late TextEditingController dobController;
  late TextEditingController line1Controller;
  late TextEditingController cityController;
  late TextEditingController stateController;

  @override
  void initState() {
    super.initState();
    ninController = TextEditingController(
      text: widget.missingFields['nin'] ?? '',
    );
    dobController = TextEditingController(
      text: widget.missingFields['dob'] ?? '',
    );
    line1Controller = TextEditingController(
      text: widget.missingFields['line1'] ?? '',
    );
    cityController = TextEditingController(
      text: widget.missingFields['city'] ?? '',
    );
    stateController = TextEditingController(
      text: widget.missingFields['state'] ?? '',
    );
  }

  @override
  void dispose() {
    ninController.dispose();
    dobController.dispose();
    line1Controller.dispose();
    cityController.dispose();
    stateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Complete Your Profile',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 30),
          if (widget.missingFields.containsKey('nin')) ...[
            const Text('NIN (National Identification Number):'),
            const SizedBox(height: 10),
            TextField(
              maxLength: 11,
              controller: ninController,
              decoration: const InputDecoration(
                counterText: "",
                hintText: 'Enter your NIN',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
          ],
          if (widget.missingFields.containsKey('dob')) ...[
            const Text('Date of Birth (YYYY/MM/DD):'),
            const SizedBox(height: 10),
            TextField(
              controller: dobController,
              inputFormatters: [DateInputFormatter()],
              decoration: const InputDecoration(hintText: 'e.g., 2000/10/27'),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: 16),
          ],
          if (widget.missingFields.containsKey('line1')) ...[
            const Text('Street Address:'),
            const SizedBox(height: 10),
            TextField(
              controller: line1Controller,
              decoration: const InputDecoration(
                hintText: 'Enter street address',
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.missingFields.containsKey('city')) ...[
            const Text('City:'),
            const SizedBox(height: 10),
            TextField(
              controller: cityController,
              decoration: const InputDecoration(hintText: 'Enter city'),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.missingFields.containsKey('state')) ...[
            const Text('State:'),
            const SizedBox(height: 10),
            TextField(
              controller: stateController,
              decoration: const InputDecoration(hintText: 'Enter state'),
            ),
            const SizedBox(height: 16),
          ],
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (widget.missingFields.containsKey('nin')) {
                      widget.missingFields['nin'] = ninController.text;
                    }
                    if (widget.missingFields.containsKey('dob')) {
                      widget.missingFields['dob'] = dobController.text;
                    }
                    if (widget.missingFields.containsKey('line1')) {
                      widget.missingFields['line1'] = line1Controller.text;
                    }
                    if (widget.missingFields.containsKey('city')) {
                      widget.missingFields['city'] = cityController.text;
                    }
                    if (widget.missingFields.containsKey('state')) {
                      widget.missingFields['state'] = stateController.text;
                    }
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Generate a unique referral code for a user (tries a few times to avoid collisions)
Future<String> generateUniqueReferralCode({
  String prefix = 'BIZ',
  int len = 6,
}) async {
  final rand = Random();
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  for (int i = 0; i < 10; i++) {
    final code =
        prefix +
        List.generate(len, (index) => chars[rand.nextInt(chars.length)]).join();
    final q = await FirebaseFirestore.instance
        .collection('users')
        .where('referralCode', isEqualTo: code)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return code;
  }
  return prefix +
      DateTime.now().millisecondsSinceEpoch.toString().substring(0, 6);
}

Future<void> _showCustomMissingDataBottomSheet(
  BuildContext context,
  Map<String, String> missingFields,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext bottomSheetContext) =>
        MissingDataBottomSheet(missingFields: missingFields),
  );
}
