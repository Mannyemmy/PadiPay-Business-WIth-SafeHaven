
import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettings extends StatefulWidget {
  const NotificationSettings({super.key});

  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings> {
  String? firstName;
  String? lastName;
  String? phone;
  String? email;
  String? dob;
  String? address1;
  String? state;
  String? country;
  String? profilePhotoUrl;
  bool pushNotification = false;
  bool loginNotification = false;
  bool paymentConfirmation = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      pushNotification = prefs.getBool('pushNotification') ?? false;
      loginNotification = prefs.getBool('loginNotification') ?? false;
      paymentConfirmation = prefs.getBool('paymentConfirmation') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: SizedBox.expand(
          child: Stack(
            children: [
              Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: navyBlue,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 100),
                        Text(
                          'Notification Settings',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
           
                  Padding(
                    padding: const EdgeInsets.all(0.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
           
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Push Notification',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      "Get instant transaction push notifications on this device",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              FlutterSwitch(
                                width: 50,
                                height: 25,
                                toggleSize: 20,
                                borderRadius: 20,
                                padding: 3,
                                value: pushNotification,
                                activeColor: primaryColor,
                                inactiveColor: Colors.grey.shade300,
                                onToggle: (val) async {
                                  setState(() => pushNotification = val);
                                  final prefs = await SharedPreferences.getInstance();
                                  prefs.setBool('pushNotification', val);
                                },
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Login Notification',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      "Enable login notifications on your email each time you login",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              FlutterSwitch(
                                width: 50,
                                height: 25,
                                toggleSize: 20,
                                borderRadius: 20,
                                padding: 3,
                                value: loginNotification,
                                activeColor: primaryColor,
                                inactiveColor: Colors.grey.shade300,
                                onToggle: (val) async {
                                  setState(() => loginNotification = val);
                                  final prefs = await SharedPreferences.getInstance();
                                  prefs.setBool('loginNotification', val);
                                },
                              ),
                            ],
                          ),
                        ),
                      Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Payment Confirmation',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      "Require approval before accepting incoming wifi payments",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              FlutterSwitch(
                                width: 50,
                                height: 25,
                                toggleSize: 20,
                                borderRadius: 20,
                                padding: 3,
                                value: paymentConfirmation,
                                activeColor: primaryColor,
                                inactiveColor: Colors.grey.shade300,
                                onToggle: (val) async {
                                  setState(() => paymentConfirmation = val);
                                  final prefs = await SharedPreferences.getInstance();
                                  prefs.setBool('paymentConfirmation', val);
                                },
                              ),
                            ],
                          ),
                        ),
                     
                      ],
                    ),
                  ),
                ],
              ),
              // Positioned(
              //   bottom: 25,
              //   left: 0,
              //   right: 0,
              //   child: Align(
              //     alignment: Alignment.bottomCenter,
              //     child: BottomNavBar(
              //       currentIndex: _selectedIndex,
              //       onTap: (index) {
              //         if (index == 0) {
              //           navigateTo(
              //             context,
              //             HomePage(),
              //             type: NavigationType.clearStack,
              //           );
              //         } else {
              //           setState(() => _selectedIndex = index);
              //         }
              //       },
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}