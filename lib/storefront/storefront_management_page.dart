import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:url_launcher/url_launcher.dart';

class StorefrontManagementPage extends StatefulWidget {
  const StorefrontManagementPage({
    super.key,
    required this.username,
    required this.initialEnabled,
  });

  final String username;
  final bool initialEnabled;

  @override
  State<StorefrontManagementPage> createState() =>
      _StorefrontManagementPageState();
}

class _StorefrontManagementPageState extends State<StorefrontManagementPage> {
  late bool _enabled;
  bool _saving = false;

  String get _storefrontUrl =>
      'https://${widget.username.trim().toLowerCase()}.padipay.co';

  @override
  void initState() {
    super.initState();
    _enabled = widget.initialEnabled;
  }

  Future<void> _setStorefrontEnabled(bool enabled) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showToast('User not signed in', Colors.red);
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('businesses').doc(user.uid).set({
        'storefront': {
          'enabled': enabled,
          'url': _storefrontUrl,
          'updatedAt': FieldValue.serverTimestamp(),
          if (enabled) 'activatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _enabled = enabled);
      showToast(
        enabled ? 'Storefront activated' : 'Storefront deactivated',
        Colors.green,
      );
    } catch (error) {
      showToast('Failed to update storefront: $error', Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openStorefront() async {
    final uri = Uri.parse(_storefrontUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      showToast('Could not open storefront', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(
          'Storefront',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your public data-selling site',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Customers can visit your unique link, buy data, and pay directly to your business.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _storefrontUrl,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _storefrontUrl));
                      showToast('Storefront link copied', Colors.green);
                      Future.delayed(const Duration(seconds: 15), () async {
                        await Clipboard.setData(const ClipboardData(text: ''));
                      });
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy link'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Storefront status',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _enabled
                                  ? 'Your storefront is live and shareable.'
                                  : 'Your storefront is currently turned off.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enabled,
                        activeColor: primaryColor,
                        onChanged: _saving ? null : _setStorefrontEnabled,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _enabled ? _openStorefront : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Open site'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Perks',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '• A unique business web link\n• Public data sales without needing the app\n• Payments still reflect in your transaction history\n• A simple shareable channel for customer acquisition',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}