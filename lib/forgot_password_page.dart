import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:padi_pay_business/sign_in.dart';
import 'package:padi_pay_business/utils.dart';

/// Three-step password reset flow using OTP via email:
///  Step 1 — user enters email → `sendPasswordResetOTP` called
///  Step 2 — user enters 6-digit OTP → `verifyPasswordResetOTP` returns resetToken
///  Step 3 — user enters new password → `resetPasswordWithOTP` called
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  int _step = 1;

  // Step 1
  final _emailController = TextEditingController();
  String _pinId = '';
  String _resetEmail = '';

  // Step 2
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  String _resetToken = '';

  // Step 3
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Step 1: send OTP ────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showSimpleDialog('Please enter a valid email address', Colors.red);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('sendPasswordResetOTP')
          .call({'email': email});
      _pinId = result.data['pinId'] as String;
      _resetEmail = email.toLowerCase().trim();
      setState(() {
        _step = 2;
        _isLoading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog(e.message ?? 'Failed to send reset code', Colors.red);
    } catch (_) {
      setState(() => _isLoading = false);
      showSimpleDialog('Something went wrong. Please try again.', Colors.red);
    }
  }

  // ── Step 2: verify OTP ──────────────────────────────────────────────
  String get _enteredOtp =>
      _otpControllers.map((c) => c.text.trim()).join();

  Future<void> _verifyOtp() async {
    final code = _enteredOtp;
    if (code.length != 6) {
      showSimpleDialog('Please enter the full 6-digit code', Colors.red);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyPasswordResetOTP')
          .call({'pinId': _pinId, 'code': code});
      if (result.data['verified'] != true) {
        setState(() => _isLoading = false);
        showSimpleDialog(
            'Incorrect or expired code. Please try again.', Colors.red);
        return;
      }
      _resetToken = result.data['resetToken'] as String;
      setState(() {
        _step = 3;
        _isLoading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog(e.message ?? 'Verification failed', Colors.red);
    } catch (_) {
      setState(() => _isLoading = false);
      showSimpleDialog('Verification failed. Please try again.', Colors.red);
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _isLoading = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('sendPasswordResetOTP')
          .call({'email': _resetEmail});
      _pinId = result.data['pinId'] as String;
      if (mounted) {
        setState(() => _isLoading = false);
        for (final c in _otpControllers) {
          c.clear();
        }
        FocusScope.of(context).requestFocus(_focusNodes[0]);
        showSimpleDialog('Code resent to $_resetEmail', Colors.green);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        showSimpleDialog('Failed to resend code. Try again.', Colors.red);
      }
    }
  }

  // ── Step 3: reset password ──────────────────────────────────────────
  Future<void> _resetPassword() async {
    final newPw = _newPasswordController.text;
    final confirmPw = _confirmPasswordController.text;
    if (newPw.isEmpty) {
      showSimpleDialog('Please enter a new password', Colors.red);
      return;
    }
    if (newPw.length < 6) {
      showSimpleDialog('Password must be at least 6 characters', Colors.red);
      return;
    }
    if (newPw != confirmPw) {
      showSimpleDialog('Passwords do not match', Colors.red);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('resetPasswordWithOTP').call({
        'email': _resetEmail,
        'resetToken': _resetToken,
        'newPassword': newPw,
      });
      if (!mounted) return;
      setState(() => _isLoading = false);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 60),
              const SizedBox(height: 16),
              const Text(
                'Password Reset Successfully',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Your password has been updated. Please sign in with your new password.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    navigateTo(context, const SignIn(),
                        type: NavigationType.clearStack);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Sign In',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog(e.message ?? 'Failed to reset password', Colors.red);
    } catch (_) {
      setState(() => _isLoading = false);
      showSimpleDialog('Failed to reset password. Please try again.', Colors.red);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────
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
                padding: const EdgeInsets.all(16),
                child: _step == 1
                    ? _buildStep1()
                    : _step == 2
                        ? _buildStep2()
                        : _buildStep3(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Forgot Password',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 25,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Enter your account email and we\'ll send you a one-time code to reset your password.',
          style: TextStyle(
            color: Colors.black54,
            fontSize: 15,
            fontWeight: FontWeight.w300,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Email Address',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'email@example.com',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
          ),
        ),
        const SizedBox(height: 30),
        GestureDetector(
          onTap: _isLoading ? null : _sendOtp,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isLoading ? primaryColor.withValues(alpha: 0.5) : primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            width: double.infinity,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text(
                    'Send Reset Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.mail_outline, size: 48, color: primaryColor),
        const SizedBox(height: 16),
        const Text(
          'Check your email',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            text: 'We sent a 6-digit code to ',
            style: const TextStyle(
                fontSize: 15, color: Colors.black54, height: 1.5),
            children: [
              TextSpan(
                text: _resetEmail,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const TextSpan(text: '. Enter it below.'),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            return SizedBox(
              width: 46,
              height: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _otpControllers[i],
                  focusNode: _focusNodes[i],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  cursorColor: primaryColor,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                  ),
                  onChanged: (val) {
                    if (val.length == 1 && i < 5) {
                      FocusScope.of(context).requestFocus(_focusNodes[i + 1]);
                    }
                    if (val.isEmpty && i > 0) {
                      FocusScope.of(context).requestFocus(_focusNodes[i - 1]);
                    }
                    if (_otpControllers.every((c) => c.text.length == 1)) {
                      FocusScope.of(context).unfocus();
                      _verifyOtp();
                    }
                  },
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: _isLoading ? null : _verifyOtp,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isLoading ? primaryColor.withValues(alpha: 0.5) : primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            width: double.infinity,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text(
                    'Verify Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Didn't receive the code? ",
                style: TextStyle(fontSize: 14, color: Colors.black54)),
            GestureDetector(
              onTap: _isLoading ? null : _resendOtp,
              child: Text(
                'Resend',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _isLoading ? Colors.grey : primaryColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.lock_reset, size: 48, color: primaryColor),
        const SizedBox(height: 16),
        const Text(
          'Set New Password',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'Enter and confirm your new password below.',
          style: TextStyle(
              fontSize: 15, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 24),
        const Text('New Password',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        TextField(
          controller: _newPasswordController,
          obscureText: _obscureNew,
          decoration: InputDecoration(
            hintText: '••••••••',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureNew ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Confirm Password',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            hintText: '••••••••',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        const SizedBox(height: 30),
        GestureDetector(
          onTap: _isLoading ? null : _resetPassword,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isLoading ? primaryColor.withValues(alpha: 0.5) : primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            width: double.infinity,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text(
                    'Reset Password',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
