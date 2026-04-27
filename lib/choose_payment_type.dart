import 'package:flutter/material.dart';
import 'package:padi_pay_business/nfc_prompt_bottom_sheet.dart';
import 'package:padi_pay_business/transfer/bank_transfer_page.dart';
import 'package:padi_pay_business/ui/permission_explanation_sheet copy.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:padi_pay_business/wifi_payment.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChoosePaymentTypeBottomSheet extends StatefulWidget {
  final Map<String, dynamic> card;
  const ChoosePaymentTypeBottomSheet({super.key, required this.card});
  @override
  State<ChoosePaymentTypeBottomSheet> createState() =>
      _ChoosePaymentTypeBottomSheetState();
}

class _ChoosePaymentTypeBottomSheetState
    extends State<ChoosePaymentTypeBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showScanPromptBottomSheet(BuildContext ctx, Map<String, dynamic> card) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (context) =>
          const DevicesListScreen(deviceType: DeviceType.browser),
    );
  }

  Future<void> _requirePrivacyConsent(
    PermissionType type,
    String prefKey,
    void Function(BuildContext rootCtx) action,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyConsented = prefs.getBool(prefKey) ?? false;
    if (alreadyConsented) {
      if (!mounted) return;
      Navigator.of(context).pop();
      action(navigatorKey.currentContext!);
      return;
    }
    final rootCtx = navigatorKey.currentContext!;
    await showModalBottomSheet(
      context: rootCtx,
      isDismissible: true,
      builder: (ctx) => PermissionExplanationSheet(
        type: type,
        onContinue: () async {
          await prefs.setBool(prefKey, true);
          if (!mounted) return;
          Navigator.of(context).pop();
          action(navigatorKey.currentContext!);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose Payment Type',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        // TODO: Implement bank transfer
                        navigateTo(context, BankTransferPage());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.account_balance,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Send via bank transfer',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Use bank transfer to send money to a previous or new recipient',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        _requirePrivacyConsent(
                          PermissionType.nfc,
                          'privacy_consent_nfc',
                          (rootCtx) => showModalBottomSheet(
                            context: rootCtx,
                            builder: (context) => const NFCPromptBottomSheet(),
                            isScrollControlled: true,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.touch_app,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tap to Pay',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Make payments instantly using your phone\'s NFC chip.',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        _requirePrivacyConsent(
                          PermissionType.wifiPayment,
                          'privacy_consent_wifi_payment',
                          (rootCtx) => _showScanPromptBottomSheet(rootCtx, widget.card),
                        );
                      },
                      onLongPress: () {
                        _requirePrivacyConsent(
                          PermissionType.wifiPayment,
                          'privacy_consent_wifi_payment',
                          (rootCtx) => showModalBottomSheet(
                            context: rootCtx,
                            isScrollControlled: true,
                            builder: (context) => const DevicesListScreen(
                              deviceType: DeviceType.advertiser,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.wifi,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scan to Pay',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Send or receive money instantly through a secure Wi-Fi connection.',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
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

class ChooseTransferTypeBottomSheet extends StatefulWidget {
  const ChooseTransferTypeBottomSheet({super.key});
  @override
  State<ChooseTransferTypeBottomSheet> createState() =>
      _ChooseTransferTypeBottomSheetState();
}

class _ChooseTransferTypeBottomSheetState
    extends State<ChooseTransferTypeBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showScanPromptBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          const DevicesListScreen(deviceType: DeviceType.browser),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose Payment Type',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        // TODO: Implement bank transfer
                         navigateTo(context, BankTransferPage());

                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.account_balance,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Send via bank transfer',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Use bank transfer to send money to a previous or new recipient',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 21),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        showModalBottomSheet(
                          context: context,
                          builder: (context) =>
                              const NFCPromptBottomSheet(isReader: true),
                          isScrollControlled: true,
                        );
                      },
                      onLongPress: () {
                        Navigator.of(context).pop();
                        showModalBottomSheet(
                          context: context,
                          builder: (context) =>
                              const NFCPromptBottomSheet(isReader: false),
                          isScrollControlled: true,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.touch_app,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tap to Pay',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Make payments instantly using your phone\'s NFC chip.',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        _showScanPromptBottomSheet();
                      },
                      onLongPress: () {
                        Navigator.of(context).pop();
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (context) => const DevicesListScreen(
                            deviceType: DeviceType.advertiser,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.wifi,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scan to Pay',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Send or receive money instantly through a secure Wi-Fi connection.',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
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



