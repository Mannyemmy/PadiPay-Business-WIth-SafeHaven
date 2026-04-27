import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:padi_pay_business/email_otp_verification_page.dart';
import 'package:padi_pay_business/sign_in.dart';
import 'package:padi_pay_business/utils.dart';

class CreateAccount extends StatefulWidget {
  const CreateAccount({super.key});

  @override
  State<CreateAccount> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<CreateAccount>
    with WidgetsBindingObserver {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController referralCodeController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String countryCode = '+234';
  bool isLoading = false;

  // Username validation
  bool _isUsernameValid = false;
  bool _isCheckingUsername = false;
  List<String> _usernameSuggestions = [];
  Timer? _usernameDebounce;

  // Referral validation
  bool _isCheckingReferral = false;
  bool _isReferralValid = false;
  String? _referrerName;
  String? _referrerUid;
  int _referrerCount = 0;

  // BRM referral
  bool _isReferralBrm = false;
  String? _referrerBrmId;
  String? _referrerBrmName;

  // Super Agent referral
  bool _isReferralSuperAgent = false;
  String? _referrerSuperAgentId;
  String? _referrerSuperAgentName;

  // Password validation states
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSymbol = false;
  bool _passwordsMatch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupListeners();
  }

  void _setupListeners() {
    passwordController.addListener(_validatePassword);
    confirmPasswordController.addListener(_validatePasswordMatch);
    usernameController.addListener(_checkUsernameAvailability);
    referralCodeController.addListener(_onReferralCodeChanged);
  }

  void _validatePassword() {
    final password = passwordController.text;
    setState(() {
      _hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
      _hasLowercase = RegExp(r'[a-z]').hasMatch(password);
      _hasNumber = RegExp(r'\d').hasMatch(password);
      _hasSymbol = RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
    });
    _validatePasswordMatch();
  }

  void _validatePasswordMatch() {
    final pass = passwordController.text;
    final confirm = confirmPasswordController.text;
    setState(() {
      _passwordsMatch =
          pass.isNotEmpty && confirm.isNotEmpty && pass == confirm;
    });
  }

  void _checkUsernameAvailability() {
    _usernameDebounce?.cancel();
    _usernameDebounce = Timer(Duration(milliseconds: 500), () async {
      final username = usernameController.text.trim().toLowerCase();
      if (username.isEmpty) {
        setState(() {
          _isUsernameValid = false;
          _usernameSuggestions = [];
          _isCheckingUsername = false;
        });
        return;
      }

      if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username)) {
        setState(() {
          _isUsernameValid = false;
          _usernameSuggestions = [];
          _isCheckingUsername = false;
        });
        return;
      }
      setState(() {
        _isCheckingUsername = true;
      });

      try {
        final doc = await FirebaseFirestore.instance
            .collection('usernames')
            .doc(username)
            .get();

        if (!doc.exists) {
          setState(() {
            _isUsernameValid = true;
            _usernameSuggestions = [];
            _isCheckingUsername = false;
          });
        } else {
          // Generate suggestions
          List<String> suggestions = [];
          for (int i = 1; i <= 3; i++) {
            suggestions.add('$username$i');
            suggestions.add('$username${Random().nextInt(100)}');
            suggestions.add('${username}_${Random().nextInt(1000)}');
          }
          setState(() {
            _isUsernameValid = false;
            _usernameSuggestions = suggestions;
            _isCheckingUsername = false;
          });
        }
      } catch (e) {
        setState(() {
          _isUsernameValid = false;
          _usernameSuggestions = [];
          _isCheckingUsername = false;
        });
        showToast("Error checking username: $e", Colors.red);
      }
    });
  }

  void _onReferralCodeChanged() {
    final code = referralCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _referrerName = null;
        _referrerUid = null;
        _referrerCount = 0;
        _isReferralValid = false;
        _isReferralBrm = false;
        _referrerBrmId = null;
        _referrerBrmName = null;
        _isReferralSuperAgent = false;
        _referrerSuperAgentId = null;
        _referrerSuperAgentName = null;
      });
      return;
    }
    _findReferrerByCode(code);
  }

  Future<void> _findReferrerByCode(String code) async {
    setState(() {
      _isCheckingReferral = true;
      _referrerName = null;
      _referrerUid = null;
      _referrerCount = 0;
      _isReferralValid = false;
      _isReferralBrm = false;
      _referrerBrmId = null;
      _referrerBrmName = null;
      _isReferralSuperAgent = false;
      _referrerSuperAgentId = null;
      _referrerSuperAgentName = null;
    });
    try {
      // ── Super Agent referral code (format: PADI-SA-XXXXXX) ───────────
      if (RegExp(r'^padi-sa-', caseSensitive: false).hasMatch(code)) {
        final upperCode = code.toUpperCase();
        // New model: super agents are business accounts with isSuperAgent=true.
        final businessSaSnap = await FirebaseFirestore.instance
            .collection('businesses')
            .where('superAgentReferralCode', isEqualTo: upperCode)
            .where('isSuperAgent', isEqualTo: true)
            .limit(1)
            .get();

        if (businessSaSnap.docs.isNotEmpty) {
          final saData = businessSaSnap.docs.first.data();
          setState(() {
            _isReferralSuperAgent = true;
            _referrerSuperAgentId = businessSaSnap.docs.first.id;
            _referrerSuperAgentName =
                (saData['businessName'] ?? saData['full_name'] ?? 'Super Agent')
                    as String;
            _isReferralValid = true;
          });
          setState(() => _isCheckingReferral = false);
          return;
        }

        // Backward compatibility: support legacy superAgents collection during migration.
        final legacySaSnap = await FirebaseFirestore.instance
            .collection('superAgents')
            .where('referral_code', isEqualTo: upperCode)
            .where('status', isEqualTo: 'active')
            .limit(1)
            .get();

        if (legacySaSnap.docs.isNotEmpty) {
          final saData = legacySaSnap.docs.first.data();
          setState(() {
            _isReferralSuperAgent = true;
            _referrerSuperAgentId = legacySaSnap.docs.first.id;
            _referrerSuperAgentName =
                (saData['full_name'] ?? 'Super Agent') as String;
            _isReferralValid = true;
          });
        } else {
          setState(() => _isReferralValid = false);
        }
        setState(() => _isCheckingReferral = false);
        return;
      }

      // ── BRM referral code (format: PADI-BRM-XXXXXX) ──────────────────
      if (RegExp(r'^padi-brm-', caseSensitive: false).hasMatch(code)) {
        final upperCode = code.toUpperCase();
        final brmSnap = await FirebaseFirestore.instance
            .collection('brms')
            .where('referral_code', isEqualTo: upperCode)
            .limit(1)
            .get();
        if (brmSnap.docs.isNotEmpty) {
          final brmData = brmSnap.docs.first.data();
          setState(() {
            _isReferralBrm = true;
            _referrerBrmId = brmSnap.docs.first.id;
            _referrerBrmName = brmData['full_name'] as String? ?? 'BRM Agent';
            _isReferralValid = true;
          });
        } else {
          setState(() => _isReferralValid = false);
        }
        setState(() => _isCheckingReferral = false);
        return;
      }

      // ── User referral: check usernames collection first (public) ──────
      final usernameDoc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(code.toLowerCase())
          .get();

      if (usernameDoc.exists) {
        final referrerId = (usernameDoc.data() ?? {})['uid'] as String?;
        if (referrerId != null && referrerId != FirebaseAuth.instance.currentUser?.uid) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(referrerId)
              .get();
          if (userDoc.exists) {
            final data = userDoc.data();
            setState(() {
              _referrerUid = referrerId;
              _referrerName = '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim();
              _referrerCount = (data?['referralCount'] ?? 0) as int;
              _isReferralValid = true;
            });
            return;
          }
        }
      }

      // ── User referral: fallback query by referralCode field ───────────
      final byReferralCode = await FirebaseFirestore.instance
          .collection('users')
          .where('referralCode', isEqualTo: code)
          .limit(1)
          .get();

      if (byReferralCode.docs.isNotEmpty) {
        final doc = byReferralCode.docs.first;
        final data = doc.data();
        final referrerId = doc.id;
        if (referrerId != FirebaseAuth.instance.currentUser?.uid) {
          setState(() {
            _referrerUid = referrerId;
            _referrerName = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
            _referrerCount = (data['referralCount'] ?? 0) as int;
            _isReferralValid = true;
          });
          return;
        }
      }

      setState(() {
        _referrerName = null;
        _referrerUid = null;
        _referrerCount = 0;
        _isReferralValid = false;
      });
    } catch (e) {
      print('Referral lookup error: $e');
      setState(() {
        _referrerName = null;
        _referrerUid = null;
        _referrerCount = 0;
        _isReferralValid = false;
      });
    } finally {
      if (mounted) setState(() => _isCheckingReferral = false);
    }
  }

  void _showVerificationEmailBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        bottom: true,
        child: Container(
          padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mail_outline, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            Text(
              'Verify your email',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'We sent a verification link to your email. Please check your inbox and click the link to verify your account.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                navigateTo(context, const SignIn());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
    );
  }

  @override
  void dispose() {
    passwordController.removeListener(_validatePassword);
    confirmPasswordController.removeListener(_validatePasswordMatch);
    usernameController.removeListener(_checkUsernameAvailability);
    referralCodeController.removeListener(_onReferralCodeChanged);
    super.dispose();
  }

  bool _isPasswordValid() {
    return _hasUppercase &&
        _hasLowercase &&
        _hasNumber &&
        _hasSymbol &&
        passwordController.text.length >= 8 &&
        _passwordsMatch;
  }

  Future<void> _completeSignUp() async {
    // Validate all fields
    if (!_isUsernameValid) {
      showToast("Please choose a valid username", Colors.red);
      return;
    }

    if (!_isPasswordValid()) {
      showToast("Please enter a valid password", Colors.red);
      return;
    }

    if (emailController.text.isEmpty ||
        firstNameController.text.isEmpty ||
        lastNameController.text.isEmpty ||
        phoneController.text.isEmpty) {
      showToast("Please fill in all required fields", Colors.red);
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // 1. Create user with Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text,
          );

      final String myUid = userCredential.user!.uid;
      final String myUsername = usernameController.text.trim().toLowerCase();
      final String generatedCode = await generateUniqueReferralCode();

      // 2. Save user data to Firestore and reserve username atomically
      Map<String, dynamic> userData = {
        'email': emailController.text.trim(),
        'firstName': firstNameController.text,
        'lastName': lastNameController.text,
        'userName': myUsername,
        'countryCode': countryCode,
        'phone': phoneController.text,
        'phoneVerified': false,
        'emailVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
        'referralCode': generatedCode,
        'referralCount': 0,
      };

      if (_referrerUid != null) {
        userData['referredBy'] = _referrerUid;
      }
      if (_isReferralBrm && _referrerBrmId != null) {
        userData['referredByBrm'] = _referrerBrmId;
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      DocumentReference newUserRef = FirebaseFirestore.instance.collection('users').doc(myUid);
      batch.set(newUserRef, userData);

      // Reserve username (create mapping)
      DocumentReference usernameRef = FirebaseFirestore.instance.collection('usernames').doc(myUsername);
      batch.set(usernameRef, {
        'uid': myUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Add to referrer's referrals if valid
      if (_isReferralValid && _referrerUid != null && _referrerUid != myUid) {
        DocumentReference referrerRef = FirebaseFirestore.instance.collection('users').doc(_referrerUid);
        batch.update(referrerRef, {
          'referralCount': FieldValue.increment(1),
        });

        // Log referral
        DocumentReference referralRef = FirebaseFirestore.instance.collection('referrals').doc();
        batch.set(referralRef, {
          'referrerUid': _referrerUid,
          'referrerName': _referrerName ?? '',
          'referredUid': myUid,
          'referredName': '${firstNameController.text} ${lastNameController.text}',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // BRM referral — create merchants doc so BRM commission system tracks this merchant
      if (_isReferralBrm && _referrerBrmId != null) {
        final merchantRef = FirebaseFirestore.instance.collection('merchants').doc(myUid);
        batch.set(merchantRef, {
          'referring_brm_id': _referrerBrmId,
          'brm_referral_code': referralCodeController.text.trim().toUpperCase(),
          'owner_name': '${firstNameController.text.trim()} ${lastNameController.text.trim()}',
          'business_name': '${firstNameController.text.trim()} ${lastNameController.text.trim()}',
          'phone': phoneController.text.trim(),
          'activation_status': 'signed_up',
          'activation_transaction_count': 0,
          'referral_bonus_paid': false,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      // Super Agent referral — store referral code on businesses doc so NIP commission hook can find it
      if (_isReferralSuperAgent && _referrerSuperAgentId != null) {
        final businessRef = FirebaseFirestore.instance.collection('businesses').doc(myUid);
        batch.set(businessRef, {
          'superAgentReferralCode': referralCodeController.text.trim().toUpperCase(),
          'email': emailController.text.trim(),
        }, SetOptions(merge: true));
      }

      await batch.commit();

      // Send welcome email
      final welcomeEmail = emailController.text.trim();
      final welcomeName = firstNameController.text.trim();
      try {
        await FirebaseFunctions.instance.httpsCallable('sendEmail').call({
          'to': welcomeEmail,
          'subject': '🎉 Welcome to PadiPay Business, $welcomeName!',
          'html':
              '<!DOCTYPE html><html><head><meta charset="UTF-8"/></head>'
              '<body style="margin:0;padding:0;background:#f0f2f5;font-family:\'Helvetica Neue\',Helvetica,Arial,sans-serif;">'
              '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;">'
              '<tr><td align="center"><table width="520" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;">'
              '<tr><td align="center" style="padding-bottom:24px;">'
              '<span style="font-size:26px;font-weight:700;color:#1a1a2e;letter-spacing:-0.5px;">Padi<span style="color:#4f46e5;">Pay</span> Business</span>'
              '</td></tr>'
              '<tr><td style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.07);">'
              '<table width="100%" cellpadding="0" cellspacing="0">'
              '<tr><td style="background:linear-gradient(135deg,#4f46e5 0%,#7c3aed 100%);height:5px;font-size:0;line-height:0;">&nbsp;</td></tr>'
              '<tr><td style="padding:48px 48px 36px;">'
              '<p style="margin:0 0 6px;font-size:13px;font-weight:600;letter-spacing:1.2px;text-transform:uppercase;color:#4f46e5;">Welcome Aboard</p>'
              '<h1 style="margin:0 0 16px;font-size:28px;font-weight:800;color:#0f0f1a;line-height:1.2;">Hi $welcomeName, welcome to PadiPay Business! 🎉</h1>'
              '<p style="margin:0 0 28px;font-size:15px;color:#6b7280;line-height:1.7;">'
              'We\'re excited to have you join the PadiPay Business family. You now have access to fast, secure, and seamless payment solutions built for your business.'
              '</p>'
              '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f5f3ff;border-radius:12px;padding:24px;margin:0 0 28px;">'
              '<tr><td>'
              '<p style="margin:0 0 16px;font-size:15px;font-weight:700;color:#1a1a2e;">Get started in 2 easy steps:</p>'
              '<table width="100%" cellpadding="0" cellspacing="0">'
              '<tr><td style="padding:10px 0;border-bottom:1px solid #e0d9ff;">'
              '<p style="margin:0;font-size:14px;color:#374151;">'
              '<span style="display:inline-block;background:#4f46e5;color:#fff;font-weight:700;font-size:12px;border-radius:50%;width:22px;height:22px;text-align:center;line-height:22px;margin-right:10px;">1</span>'
              '<strong>Complete your KYC</strong> &mdash; Verify your identity on your dashboard to unlock full business account access.'
              '</p></td></tr>'
              '<tr><td style="padding:10px 0;">'
              '<p style="margin:0;font-size:14px;color:#374151;">'
              '<span style="display:inline-block;background:#4f46e5;color:#fff;font-weight:700;font-size:12px;border-radius:50%;width:22px;height:22px;text-align:center;line-height:22px;margin-right:10px;">2</span>'
              '<strong>Create your bank account</strong> &mdash; Get a dedicated account number to receive payments from customers and partners.'
              '</p></td></tr>'
              '</table>'
              '</td></tr></table>'
              '<p style="margin:0 0 28px;font-size:14px;color:#6b7280;line-height:1.7;">'
              'Once set up, enjoy transfers, bill payments, airtime top-ups, and POS solutions &mdash; all in one place, built for the Padi experience.'
              '</p>'
              '<table cellpadding="0" cellspacing="0"><tr><td style="background:#4f46e5;border-radius:10px;">'
              '<a style="display:inline-block;padding:14px 32px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;letter-spacing:0.3px;">Open PadiPay Business</a>'
              '</td></tr></table>'
              '</td></tr>'
              '<tr><td style="padding:0 48px;"><div style="border-top:1px solid #f3f4f6;"></div></td></tr>'
              '<tr><td style="padding:24px 48px;">'
              '<p style="margin:0;font-size:12px;color:#d1d5db;">&copy; 2026 PadiPay Business</p>'
              '</td></tr>'
              '</table></td></tr>'
              '</table></td></tr>'
              '</table></body></html>',
        });
      } catch (e) {
        print('Welcome email error (non-fatal): $e');
      }

      // 3. Send email OTP for verification
      final verifyEmail = emailController.text.trim();
      final otpResult = await FirebaseFunctions.instance
          .httpsCallable('sendEmailOTP')
          .call({'email': verifyEmail, 'purpose': 'verify'});
      final pinId = otpResult.data['pinId'] as String;

      // 4. Sign out user
      await FirebaseAuth.instance.signOut();

      // 5. Navigate to OTP verification page
      if (!mounted) return;
      setState(() => isLoading = false);
      navigateTo(
        context,
        EmailOtpVerificationPage(
          email: verifyEmail,
          pinId: pinId,
          onResend: () async {
            final res = await FirebaseFunctions.instance
                .httpsCallable('sendEmailOTP')
                .call({'email': verifyEmail, 'purpose': 'verify'});
            return res.data['pinId'] as String;
          },
          onVerified: () {
            navigateTo(context, const SignIn(),
                type: NavigationType.clearStack);
          },
        ),
      );
      return;
    } on FirebaseAuthException catch (e) {
      String errorMsg = 'Error creating account';
      if (e.code == 'email-already-in-use') {
        errorMsg = 'Email already registered';
      } else if (e.code == 'weak-password') {
        errorMsg = 'Password is too weak';
      }
      showToast(errorMsg, Colors.red);
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('permission_denied') || lower.contains('permission-denied') || lower.contains('already exists') || lower.contains('already-exists') || lower.contains('duplicate')) {
        showToast('Username not available, please choose another', Colors.red);
      } else {
        showToast("Error: $e", Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Widget _buildPasswordValidation() {
    return Column(
      children: [
        const SizedBox(height: 10),
        _buildValidationItem(
          'One uppercase letter',
          Icons.check_circle_outline,
          _hasUppercase,
        ),
        _buildValidationItem(
          'One lowercase letter',
          Icons.check_circle_outline,
          _hasLowercase,
        ),
        _buildValidationItem(
          'One number',
          Icons.check_circle_outline,
          _hasNumber,
        ),
        _buildValidationItem(
          'One special character',
          Icons.check_circle_outline,
          _hasSymbol,
        ),
        _buildValidationItem(
          'Passwords match',
          Icons.check_circle_outline,
          _passwordsMatch,
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildValidationItem(String text, IconData icon, bool isValid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: isValid ? Colors.green : Colors.grey, size: 15),
          SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: isValid ? Colors.green : Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
          child: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 10),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(
                        Icons.arrow_back_ios,
                        size: 20,
                        color: Colors.black.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 50),
                    Text(
                      "Create Account",
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "Enter your information just as it's shown on your identity document.",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // First Name
                    Text(
                      "First Name",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontSize: 14),
                      controller: firstNameController,
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter your first name",
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Last Name
                    Text(
                      "Last Name",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontSize: 14),
                      controller: lastNameController,
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter your last name",
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Username
                    Text(
                      "Username",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
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
                        hintText: "Enter your username",
                        prefixIcon: Icon(
                          Icons.alternate_email,
                          color: Colors.grey.shade600,
                        ),
                        suffixIcon: usernameController.text.isEmpty
                            ? null
                            : Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: _isCheckingUsername
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    primaryColor,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Checking...",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: primaryColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      )
                                    : _isUsernameValid
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle,
                                                  color: Colors.green, size: 18),
                                              const SizedBox(width: 6),
                                              const Text(
                                                "Available",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.close,
                                                  color: Colors.red, size: 18),
                                              const SizedBox(width: 6),
                                              const Text(
                                                "Taken",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                              ),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                      ],
                    ),
                    if (_usernameSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Suggestions:",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: _usernameSuggestions
                            .take(3)
                            .map(
                              (suggestion) => GestureDetector(
                                onTap: () {
                                  usernameController.text = suggestion;
                                  _checkUsernameAvailability();
                                },
                                child: Chip(
                                  label: Text(suggestion),
                                  backgroundColor: Colors.grey.shade200,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 15),

                    // Email
                    Text(
                      "Email Address",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontSize: 14),
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter your email",
                      ),
                    ),

                    SizedBox(height: 15),

                    // Phone
                    Text(
                      "Phone Number",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    SizedBox(height: 5),
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: CountryCodePicker(
                              padding: EdgeInsetsGeometry.all(0),
                              onChanged: (country) =>
                                  countryCode = country.dialCode!,
                              initialSelection: 'NG',
                              favorite: ['+234', 'NG'],
                              showCountryOnly: false,
                              showOnlyCountryWhenClosed: false,
                              alignLeft: true,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              textInputAction: TextInputAction.next,
                              style: TextStyle(fontSize: 14),
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                hintText: "70 123 45678",
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Referral Code (optional)
                    Text(
                      "Referral Code (optional)",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.none,
                      style: TextStyle(fontSize: 14),
                      controller: referralCodeController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter referral code",
                        suffixIcon: referralCodeController.text.isEmpty
                            ? null
                            : Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: _isCheckingReferral
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Checking...",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: primaryColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      )
                                    : _isReferralValid
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle, color: Colors.green, size: 18),
                                              const SizedBox(width: 6),
                                              const Text(
                                                "Found",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.close, color: Colors.red, size: 18),
                                              const SizedBox(width: 6),
                                              const Text(
                                                "Not found",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                              ),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\-]')),
                      ],
                    ),
                    if (_referrerSuperAgentName != null) ...[
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.star, size: 14, color: Colors.indigo),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Super Agent: $_referrerSuperAgentName',
                              style: TextStyle(fontSize: 12, color: Colors.indigo[700], fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ] else if (_referrerBrmName != null) ...[
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.verified_user, size: 14, color: Colors.green),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'BRM Agent: $_referrerBrmName',
                              style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ] else if (_referrerName != null) ...[
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.grey),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Referred by $_referrerName • $_referrerCount referrals',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 15),

                    // Password
                    Text(
                      "Password",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontSize: 14),
                      controller: passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter your password",
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                    _buildPasswordValidation(),
                    const SizedBox(height: 10),

                    // Confirm Password
                    Text(
                      "Confirm Password",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      textInputAction: TextInputAction.done,
                      style: TextStyle(fontSize: 14),
                      controller: confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Re-enter password",
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirmPassword =
                                !_obscureConfirmPassword,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Continue Button
                    InkWell(
                      onTap:
                          _isPasswordValid() &&
                              _isUsernameValid
                          ? _completeSignUp
                          : null,
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color:
                              _isPasswordValid() &&
                                  _isUsernameValid
                              ? Colors.blue
                              : Colors.grey,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: isLoading
                              ? SizedBox(
                                  height: 30,
                                  width: 30,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  "Continue",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),

                    // Login link
                    Center(
                      child: InkWell(
                        onTap: () => navigateTo(context, SignIn()),
                        child: RichText(
                          text: TextSpan(
                            text: "Already have an account? ",
                            style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w400,
                            ),
                            children: [
                              TextSpan(
                                text: "Login",
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
