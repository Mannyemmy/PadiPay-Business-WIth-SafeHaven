

import 'package:flutter/material.dart';
import 'package:padi_pay_business/utils.dart';

class ChangeCardChannelsPage extends StatefulWidget {
  const ChangeCardChannelsPage({super.key});

  @override
  State<ChangeCardChannelsPage> createState() => _ChangeCardChannelsPageState();
}

class _ChangeCardChannelsPageState extends State<ChangeCardChannelsPage> {
  bool _posEnabled = false;
  bool _atmEnabled = false;
  bool _webEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
     
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                color: navyBlue,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.arrow_back_ios,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  SizedBox(height: 60),
                  Text(
                    'Account Statement',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                 
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.payment, color: Colors.white, size: 20),
                    ),
                    title: const Text('POS'),
                    subtitle: const Text('Allow this card to work on POS'),
                    value: _posEnabled,
                    onChanged: (bool value) {
                      setState(() {
                        _posEnabled = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.atm, color: Colors.white, size: 20),
                    ),
                    title: const Text('ATM'),
                    subtitle: const Text('Allow this card to work on ATMs'),
                    value: _atmEnabled,
                    onChanged: (bool value) {
                      setState(() {
                        _atmEnabled = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.web, color: Colors.white, size: 20),
                    ),
                    title: const Text('Web'),
                    subtitle: const Text('Allow this card to work on Online stores and web online'),
                    value: _webEnabled,
                    onChanged: (bool value) {
                      setState(() {
                        _webEnabled = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}