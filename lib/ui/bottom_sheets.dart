import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:padi_pay_business/account_statement.dart';
import 'package:padi_pay_business/card_channels.dart';
import 'package:padi_pay_business/card_merchants.dart';
import 'package:padi_pay_business/card_details.dart';
import 'package:padi_pay_business/change_pin.dart';
import 'package:padi_pay_business/transfer/choose_transfer_type_page.dart';
import 'package:padi_pay_business/fund_card.dart';
import 'package:padi_pay_business/ui/keypad.dart';
import 'package:padi_pay_business/utils.dart';

class EnterPasscodeSheet extends StatefulWidget {
  final String title;
  final String subtitle;

  const EnterPasscodeSheet({
    super.key,
    this.title = 'Enter Account Passcode',
    this.subtitle = 'Enter your 4-digit passcode to view card details',
  });

  @override
  _EnterPasscodeSheetState createState() => _EnterPasscodeSheetState();
}

class _EnterPasscodeSheetState extends State<EnterPasscodeSheet> {
  String pin = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  bool isCurrent = index == pin.length;
                  bool isEntered = index < pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCurrent ? Colors.blue : Colors.grey,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isEntered
                          ? Text(
                              pin[index],
                              style: const TextStyle(fontSize: 20),
                            )
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              Keypad(
                onPressed: (val) {
                  setState(() {
                    if (val == null) {
                      if (pin.isNotEmpty) {
                        pin = pin.substring(0, pin.length - 1);
                      }
                    } else if (pin.length < 4) {
                      pin += val;
                      if (pin.length == 4) {
                        Navigator.pop(context, pin);
                      }
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CreatePasscodeSheet extends StatefulWidget {
  Map<String, dynamic> card = {};
  CreatePasscodeSheet({super.key, required this.card});
  @override
  _CreatePasscodeSheetState createState() => _CreatePasscodeSheetState();
}

class _CreatePasscodeSheetState extends State<CreatePasscodeSheet> {
  String pin = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Create Account Passcode',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              const Text(
                'Enter a 4-digit passcode to secure your account',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  bool isCurrent = index == pin.length;
                  bool isEntered = index < pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCurrent ? Colors.blue : Colors.grey,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isEntered
                          ? Text(
                              pin[index],
                              style: const TextStyle(fontSize: 20),
                            )
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              Keypad(
                onPressed: (val) async {
                  if (val == null) {
                    setState(() {
                      if (pin.isNotEmpty) {
                        pin = pin.substring(0, pin.length - 1);
                      }
                    });
                  } else if (pin.length < 4) {
                    setState(() {
                      pin += val;
                    });

                    if (pin.length == 4) {
                      User? user = FirebaseAuth.instance.currentUser;
                      await FirebaseFirestore.instance
                          .collection('businesses')
                          .doc(user!.uid)
                          .set({"passcode": pin}, SetOptions(merge: true));

                      showToast("Passcode set successfully", Colors.green);
                      Navigator.pop(context, true);
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CardDetailsBottomSheet extends StatefulWidget {
  final List<Map<String, dynamic>> cards;
  final int initialIndex;
  String selectedCurrency;

  CardDetailsBottomSheet({
    super.key,
    required this.cards,
    required this.selectedCurrency,
    required this.initialIndex,
  });

  @override
  State<CardDetailsBottomSheet> createState() => _CardDetailsBottomSheetState();
}

class _CardDetailsBottomSheetState extends State<CardDetailsBottomSheet> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: widget.initialIndex,
      viewportFraction: 0.9,
    );
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final duration = const Duration(milliseconds: 200);
      _pageController
          .animateTo(
            _currentIndex + 0.2,
            duration: duration,
            curve: Curves.easeOut,
          )
          .then((_) {
            _pageController.animateTo(
              _currentIndex.toDouble(),
              duration: duration,
              curve: Curves.easeIn,
            );
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    final double viewportWidth = MediaQuery.of(context).size.width;
    const double cardAspectRatio = 1.6;
    final double pageHeight = (viewportWidth * 0.9) / cardAspectRatio;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: pageHeight,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: widget.cards.length,
                      onPageChanged: (index) =>
                          setState(() => _currentIndex = index),
                      itemBuilder: (context, index) {
                        var card = widget.cards[index];
                        String asset = '';
                        switch (card['design']) {
                          case 'Neon Magenta':
                            asset = 'assets/card_neon_magenta_flat.png';
                            break;
                          case 'Cyber Aqua':
                            asset = 'assets/card_cyber_aqua_flat.png';
                            break;
                          case 'Solar Glow':
                            asset = 'assets/card_solar_glow_flat.png';
                            break;
                        }
                        return AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, child) {
                            double value = 1.0;
                            if (_pageController.position.haveDimensions) {
                              value = (_pageController.page! - index).abs();
                              value = (1 - (value * 0.1)).clamp(0.9, 1.0);
                            }
                            return Transform.scale(scale: value, child: child);
                          },
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final double cardWidth = constraints.maxWidth;
                              final double cardHeight = constraints.maxHeight;
                              final double cardNumberFontSize =
                                  cardWidth * 0.05;
                              final double labelFontSize = cardWidth * 0.03;
                              final double textFontSize = cardWidth * 0.04;
                              final double leftPadding = math.max(
                                15.0,
                                cardWidth * 0.04,
                              );
                              return Center(
                                child: SizedBox(
                                  width: cardWidth,
                                  height: cardHeight,
                                  child: Stack(
                                    children: [
                                      // Background card image
                                      Center(
                                        child: Image.asset(
                                          asset,
                                          width: cardWidth,
                                          fit: BoxFit.fitWidth,
                                        ),
                                      ),
                                      // Visa logo centered
                                      Positioned(
                                        top: 0,
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Align(
                                          alignment: Alignment.center,
                                          child: Image.asset(
                                            "assets/visa_card.png",
                                            width:
                                                cardWidth *
                                                0.5 /
                                                0.9, // Adjust relative to card width
                                          ),
                                        ),
                                      ),
                                      // Card number center left
                                      Positioned(
                                        top: 0,
                                        bottom: 0,
                                        left: leftPadding,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 5.0,
                                            ),
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                '4532 1234 5678 9012',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: cardNumberFontSize,
                                                  letterSpacing:
                                                      cardWidth * 0.005,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Card holder bottom left
                                      Positioned(
                                        bottom: 15,
                                        left: leftPadding,
                                        child: Align(
                                          alignment: Alignment.bottomLeft,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'CARD HOLDER',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: labelFontSize,
                                                ),
                                              ),
                                              Text(
                                                'John Doe',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: textFontSize,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Expires bottom right
                                      Positioned(
                                        bottom: 15,
                                        right: leftPadding,
                                        child: Align(
                                          alignment: Alignment.bottomRight,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'EXPIRES',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: labelFontSize,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                '12/29',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: textFontSize,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: widget.cards.asMap().entries.map((e) {
                      return Container(
                        height: e.key == _currentIndex ? 25 : 18,
                        width: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: e.key == _currentIndex
                              ? Colors.white
                              : Colors.grey[500],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        navigateTo(context, SendFundsPage());
                      },
                      child: Container(
                        padding: const EdgeInsets.only(
                          top: 7,
                          bottom: 7,
                          left: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(55),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              padding: EdgeInsets.only(left: 0, right: 5),
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(
                                  FontAwesomeIcons.paperPlane,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              "Withdraw",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final currentCard = widget.cards[_currentIndex];
                        navigateTo(
                          context,
                          FundCard(
                            card: currentCard,
                            currency: widget.selectedCurrency,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.only(
                          top: 7,
                          bottom: 7,
                          left: 8,
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(55),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Image.asset(
                                  "assets/deposit_card.png",
                                  width: 25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              "Deposit",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recent Activity',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (context) => MoreActionsBottomSheet(),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Icon(Icons.more_vert, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Container(
                          height: 200,
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.withAlpha(10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.grey.withAlpha(50),
                            ),
                          ),
                          child: ListView(
                            children: [
                              _buildTransactionRow(
                                '+₦44675.67',
                                'Card Funding Transaction',
                                '14:35 • June 2, 2024',
                                Colors.orange,
                                'Pending',
                              ),
                              _buildTransactionRow(
                                '+₦44675.67',
                                'Card Funding Transaction',
                                '14:35 • June 2, 2024',
                                Colors.red,
                                'Failed',
                              ),
                              _buildTransactionRow(
                                '+₦44675.67',
                                'Card Funding Transaction',
                                '14:35 • June 2, 2024',
                                Colors.green,
                                'Successful',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionRow(
    String amount,
    String title,
    String date,
    Color statusColor,
    String status,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),

                Row(
                  children: [
                    Icon(Icons.schedule, size: 12, color: Colors.grey),
                    Text(
                      date,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount, style: TextStyle(fontWeight: FontWeight.bold)),

              Text(status, style: TextStyle(color: statusColor, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class MoreActionsBottomSheet extends StatefulWidget {
  const MoreActionsBottomSheet({super.key});

  @override
  State<MoreActionsBottomSheet> createState() => _MoreActionsBottomSheetState();
}

class _MoreActionsBottomSheetState extends State<MoreActionsBottomSheet> {
  bool _isFrozen = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    color: Colors.black54,
                    size: 25,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 16),
                const Text(
                  'More Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 40),
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('Card Details'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                // Handle action
                navigateTo(context, CardDetailsPage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Account Statement'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                // Handle action
                navigateTo(context, AccountStatementPage());
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(FontAwesomeIcons.snowflake, size: 20),
                      SizedBox(width: 12),
                      Text('Freeze Card', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                  FlutterSwitch(
                    width: 50,
                    height: 25,
                    toggleSize: 20,
                    borderRadius: 20,
                    padding: 3,
                    value: _isFrozen,
                    activeColor: primaryColor,
                    inactiveColor: Colors.grey.shade300,
                    onToggle: (val) => setState(() => _isFrozen = val),
                  ),
                ],
              ),
            ),

            ListTile(
              leading: const Icon(Icons.pin),
              title: const Text('Send Card Default PIN'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                // Handle action
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Change Card Channels'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                // Handle action
                navigateTo(context, ChangeCardChannelsPage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.storefront),
              title: const Text('Manage Merchants'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                navigateTo(context, ManageMerchantsPage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Change PIN'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                // Handle action
                navigateTo(context, ChangePinPage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Terminate Card'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                // Handle action
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CardTypeBottomSheet extends StatefulWidget {
  const CardTypeBottomSheet({super.key});
  @override
  State<CardTypeBottomSheet> createState() => _CardTypeBottomSheetState();
}

class _CardTypeBottomSheetState extends State<CardTypeBottomSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 30),
                Row(
                  children: [
                    const Text(
                      'Choose Your Card Type',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Image.asset("assets/cards.png"),
                const SizedBox(height: 20),
                const Text(
                  textAlign: TextAlign.center,
                  'Select the type of card that works\nbest for you',
                  style: TextStyle(color: Colors.black38),
                ),
                const SizedBox(height: 20),
                _buildOption(
                  icon: "assets/physical_card_icon.png",
                  title: 'Get a Physical Card',
                  subtitle: 'Have your card shipped right to your door!',
                  value: 'Physical',
                ),
                _buildOption(
                  icon: "assets/virtual_card_icon.png",
                  title: 'Create a Virtual Card',
                  subtitle: 'A digital card for online use',
                  value: 'Virtual',
                ),
                _buildOption(
                  icon: "assets/anon_card_icon.png",
                  title: 'Create Anonymous Card',
                  subtitle: 'No personal details shown, ideal for privacy',
                  value: 'Anonymous',
                ),
                _buildOption(
                  icon: "assets/map_physical_card.png",
                  title: 'Map a Physical Card',
                  subtitle: 'Have a physical card? Link it!',
                  value: 'Map',
                ),
                _buildOption(
                  icon: "assets/credit_card_icon.png",
                  title: 'Request a Credit Card',
                  subtitle: 'Flexible Credit Experience',
                  value: 'Credit',
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption({
    required String icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context, value);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(icon, width: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w200,
                      fontSize: 12,
                    ),
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

class BasicDetailsBottomSheet extends StatefulWidget {
  final String cardType;
  const BasicDetailsBottomSheet({super.key, required this.cardType});
  @override
  State<BasicDetailsBottomSheet> createState() =>
      _BasicDetailsBottomSheetState();
}

class _BasicDetailsBottomSheetState extends State<BasicDetailsBottomSheet> {
  String _selectedScheme = 'Visa';
  String _selectedCardType = 'Debit';
  String? _selectedState;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _address1Controller = TextEditingController();
  final TextEditingController _address2Controller = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  String selectedCurrency = 'United States Dollar (USD)';
  bool agreeWithTerms = false;
  final List<String> _states = [
    'Lagos',
    'Abuja',
    'Kano',
    'Oyo',
    'Rivers',
  ]; // Example states
  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    DocumentSnapshot snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (snap.exists) {
      var data = snap.data() as Map<String, dynamic>;
      setState(() {
        _nameController.text = '${data['firstName']} ${data['lastName']}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 40),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  child: Icon(
                    Icons.arrow_back_ios,
                    size: 20,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 30),
                const Text(
                  'Basic Details',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Set up your card details',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                const Text('Step 1 of 3'),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: 1 / 3,
                  backgroundColor: Colors.grey.shade300,
                  color: primaryColor,
                ),
                const SizedBox(height: 20),
                const Text('Scheme'),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.05),
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                         if (selectedCurrency.contains("USD")) ...[
                          _buildSchemeOption(
                            'assets/visa.png',
                            "Visa",
                            primaryColor,
                            comingSoon: true,
                          ),
                          const SizedBox(width: 10),
                          _buildSchemeOption(
                            'assets/mastercard.png',
                            "Mastercard",
                            Colors.orange,
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (selectedCurrency.contains("NGN")) ...[
                          _buildSchemeOption(
                            'assets/verve.png',
                            "Verve",
                            Colors.green,
                          ),
                          const SizedBox(width: 10),
                          _buildSchemeOption(
                            'assets/afrigo.png',
                            "AfriGo",
                            Colors.green,
                          ),
                        ],

                        const SizedBox(width: 10),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Name on Card'),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  readOnly: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    hintText: 'John Doe',
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Select Currency'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    hintText: 'Select currency',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 15,
                    ),
                  ),
                  initialValue: selectedCurrency,
                  dropdownColor:
                      Colors.white, // sets dropdown item background color
                  items: ['United States Dollar (USD)', 'Nigerian Naira (NGN)']
                      .map(
                        (name) =>
                            DropdownMenuItem(value: name, child: Text(name)),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCurrency = value!;
                    });
                  },
                ),
                SizedBox(height: 20),

                const Text('Card Type'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildCardTypeOption(
                        "assets/card_type_debit.png",
                        'Debit',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCardTypeOption(
                        "assets/card_type_prepaid.png",
                        'Prepaid',
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Transform.translate(
                  offset: Offset(-15, 0),
                  child: Row(
                    children: [
                      Checkbox(
                        value: agreeWithTerms,
                        onChanged: (value) {
                          setState(() {
                            agreeWithTerms = value!;
                          });
                        },
                        shape: const CircleBorder(),
                        activeColor: Colors.blue, // optional
                      ),
                      Expanded(
                        child: Wrap(
                          children: [
                            const Text('Agree with '),
                            GestureDetector(
                              onTap: () {
                                // Navigate or show dialog
                                print('Terms and Conditions tapped');
                              },
                              child: Text(
                                'Terms and Conditions',
                                style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.cardType == 'Physical') ...[
                  const SizedBox(height: 20),
                  const Text('Shipping Address'),
                  const SizedBox(height: 20),
                  const Text('Address Line 1'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _address1Controller,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      hintText: 'eg. 456 Main Land',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Address Line 2'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _address2Controller,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      hintText: 'eg. 456 Main Land',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('City'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cityController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      hintText: 'Enter City',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('State'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedState,
                    hint: const Text('Select State'),
                    onChanged: (value) =>
                        setState(() => _selectedState = value),
                    items: _states
                        .map(
                          (state) => DropdownMenuItem(
                            value: state,
                            child: Text(state),
                          ),
                        )
                        .toList(),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    if (_selectedScheme == "") {
                      showToast("Select a card scheme", Colors.red);
                      return;
                    }
                    if (!agreeWithTerms) {
                      showToast("Agree with terms and conditions", Colors.red);
                      return;
                    }

                    if (_selectedScheme.isEmpty ||
                        _selectedCardType.isEmpty ||
                        _nameController.text.isEmpty) {
                      showToast("Please fill in all details", Colors.red);
                      return;
                    }
                    if (widget.cardType == 'Physical' &&
                        (_address1Controller.text.isEmpty ||
                            _cityController.text.isEmpty ||
                            _selectedState == null)) {
                      showToast('Please fill shipping details', Colors.red);
                      return;
                    }
                    Map<String, dynamic> data = {
                      'scheme': _selectedScheme,
                      'nameOnCard': _nameController.text,
                      'selectedCurrency': selectedCurrency,
                      'cardFinancialType': _selectedCardType,
                      'selectedScheme': _selectedScheme,
                    };
                    if (widget.cardType == 'Physical') {
                      data['shippingAddress'] = {
                        'address1': _address1Controller.text,
                        'address2': _address2Controller.text,
                        'city': _cityController.text,
                        'state': _selectedState,
                      };
                    }
                    Navigator.pop(context, data);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSchemeOption(
    String icon,
    String label,
    Color color, {
    bool comingSoon = false,
  }) {
    final isSelected = _selectedScheme == label && !comingSoon;
    return GestureDetector(
      onTap: comingSoon ? null : () => setState(() => _selectedScheme = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Image.asset(icon, width: 50),
            if (isSelected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, color: primaryColor, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCardTypeOption(String icon, String value) {
    final isSelected = _selectedCardType == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedCardType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withAlpha(100) : Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Image.asset(icon, width: 20),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
            const Spacer(),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? primaryColor : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

class ReviewConfirmBottomSheet extends StatelessWidget {
  final String cardType;
  final Map<String, dynamic> basicData;
  final String selectedDesign;
  final String selectedCurrency;
  final String selectedScheme;
  const ReviewConfirmBottomSheet({
    super.key,
    required this.cardType,
    required this.basicData,
    required this.selectedDesign,
    required this.selectedCurrency,
    required this.selectedScheme,
  });
  @override
  Widget build(BuildContext context) {
    final Map<String, String> designs = {
      'Neon Magenta': 'assets/card_neon_magenta.png',
      'Cyber Aqua': 'assets/card_cyber_aqua.png',
      'Solar Glow': 'assets/card_solar_glow.png',
    };
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 15),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const Text(
                  'Review & Confirm',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Double-check your card details before creating',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                const Text('Step 3 of 3'),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: 1.0),
                const SizedBox(height: 20),
                const Text(
                  'Your New Card',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Transform.rotate(
                    angle: -0.1,
                    child: Image.asset(
                      designs[selectedDesign]!,
                      width: MediaQuery.of(context).size.width,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.shade100, // inner border color
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    margin: EdgeInsets.all(6),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.02),
                      border: Border.all(
                        color: Colors.grey.shade100, // inner border color
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Summary',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            selectedCurrency.contains("USD")
                                ? Text(
                                    "\$3 Fee",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : SizedBox.shrink(),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildSummaryRow(
                          'Scheme',
                          selectedScheme.toUpperCase(),
                        ),
                        _buildSummaryRow('CARD TYPE', cardType),
                        _buildSummaryRow(
                          'CARDHOLDER NAME',
                          basicData['nameOnCard'],
                        ),
                        _buildSummaryRow('DESIGN', selectedDesign),
                        _buildSummaryRow('Currency', selectedCurrency),
                        _buildSummaryRow(
                          'DELIVERY',
                          cardType == 'Physical'
                              ? '3-5 Business Days'
                              : 'Instant',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.security, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            "Secure & Protected",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(width: 30),
                          Expanded(
                            child: Text(
                              'YOUR CARD WILL BE SECURED WITH INDUSTRY-STANDARD ENCRYPTION AND FRAUD PROTECTION.',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'I want this Card',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}

class CustomizeCardBottomSheet extends StatefulWidget {
  const CustomizeCardBottomSheet({super.key});
  @override
  State<CustomizeCardBottomSheet> createState() =>
      _CustomizeCardBottomSheetState();
}

class _CustomizeCardBottomSheetState extends State<CustomizeCardBottomSheet> {
  String _selectedDesign = 'Neon Magenta';
  final Map<String, String> _designs = {
    'Neon Magenta': 'assets/card_neon_magenta.png',
    'Cyber Aqua': 'assets/card_cyber_aqua.png',
    'Solar Glow': 'assets/card_solar_glow.png',
  };
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const Text(
                'Customize Your Card',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Set up your card preference',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              const Text('Step 2 of 3'),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: 2 / 3,
                backgroundColor: Colors.grey.shade300,
              ),
              const SizedBox(height: 20),
              Center(
                child: Image.asset(
                  _designs[_selectedDesign]!,
                  height: 200,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _selectedDesign,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildColorOption(
                    const LinearGradient(colors: [Colors.purple, Colors.pink]),
                    'Neon Magenta',
                  ),
                  const SizedBox(width: 16),
                  _buildColorOption(
                    const LinearGradient(colors: [Colors.cyan, primaryColor]),
                    'Cyber Aqua',
                  ),
                  const SizedBox(width: 16),
                  _buildColorOption(
                    const LinearGradient(colors: [Colors.orange, Colors.red]),
                    'Solar Glow',
                  ),
                ],
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, _selectedDesign);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'I want this Card',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorOption(LinearGradient gradient, String design) {
    final isSelected = _selectedDesign == design;
    return GestureDetector(
      onTap: () => setState(() => _selectedDesign = design),
      child: Container(
        width: 48, // slightly larger to create spacing
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: Colors.grey.shade300, width: 1)
              : null,
        ),
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              border: isSelected
                  ? Border.all(color: Colors.grey.shade300, width: 1)
                  : null,
            ),
            child: isSelected
                ? const Icon(
                    FontAwesomeIcons.check,
                    color: Colors.white,
                    size: 16,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
