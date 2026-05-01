import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/my_business/my_business.dart';
import 'package:padi_pay_business/padi_book/padi_book_page.dart';
import 'package:padi_pay_business/profile/profile_page.dart';
import 'package:padi_pay_business/success_page.dart';
import 'package:padi_pay_business/transactions_history.dart';
import 'package:padi_pay_business/ui/bottom_nav_bar.dart';
import 'package:padi_pay_business/ui/bottom_sheets.dart';
import 'package:padi_pay_business/ui/keypad.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:uuid/uuid.dart';

class CardsPage extends StatefulWidget {
  const CardsPage({super.key});
  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  List<Map<String, dynamic>> _cards = [];
  String _currentCategory = 'NGN';
  final PageController _pageController = PageController();
  bool _isLoading = true;
  double _balance = 0.0;
  double _usdFundingRequiredNGN = 0.0;

  Widget _shimmerPlaceholder({required double width, double height = 16.0}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
      );

  @override
  void initState() {
    super.initState();
    _fetchCards();
    _fetchBalanceAndFx();
  }

  Future<void> _fetchBalanceAndFx() async {
    try {
      double balance = await _fetchBalance();
      HttpsCallable fxCallable = FirebaseFunctions.instance.httpsCallable(
        'bridgecardGetFxRate',
      );
      var fxResponse = await fxCallable.call();
      if (fxResponse.data['status'] != 'success') {
        print('Failed to get FX rate: ${fxResponse.data['message']}');
        return;
      }
      double rate = fxResponse.data['data']['NGN-USD'].toDouble() / 100;
      double required = 3 * rate;
      setState(() {
        _balance = balance;
        _usdFundingRequiredNGN = required;
      });
    } catch (e) {
      print('Error fetching balance and FX: $e');
    }
  }

  Future<double> _fetchBalance() async {
    try {
      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];

      if (accountId == null) throw Exception('Account ID not found');

      final balance = await sudoFetchAccountBalance(accountId);
      return balance;
    } catch (e) {
      print('Error fetching account balance: $e');
      throw Exception('Failed to fetch account balance: $e');
    }
  }

  Future<Map<String, dynamic>> _fetchCardDetails(String cardId, String currency) async {
    if (currency == 'USD') {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'bridgecardGetCardDetails',
      );
      final response = await callable.call({'card_id': cardId});

      if (response.data['status'] != 'success') {
        throw 'Failed to fetch card details: ${response.data['message']}';
      }

      return Map<String, dynamic>.from(response.data['data']);
    } else {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'fetchStrowalletNairaCard',
      );
      final response = await callable.call({'card_id': cardId});
      print('Card details response for $cardId: ${response.data}');

      return Map<String, dynamic>.from(response.data['data']);
    }
  }

  Future<void> _fetchCards() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Prioritize business cards

    QuerySnapshot<Map<String, dynamic>> cardsSnap;

    // Fallback to personal
    cardsSnap = await FirebaseFirestore.instance
        .collection('users/${user.uid}/cards')
        .get();

    List<Map<String, dynamic>> cards = [];
    for (QueryDocumentSnapshot doc in cardsSnap.docs) {
      final Map<String, dynamic> docData = doc.data() as Map<String, dynamic>;
     

      // Skip docs with null type or selectedCurrency
      if (docData['type'] == null || docData['selectedCurrency'] == null) {
        continue;
      }

      final Map<String, dynamic> card = {
        ...docData,
        'id': doc.id,
        'details': null,
      };
      cards.add(card);
    }

    // Deduplicate cards by card_id to prevent UI showing extras if Firestore has duplicates
    Map<String, Map<String, dynamic>> uniqueCardsMap = {};
    for (var card in cards) {
      final String? cardId = card['card_id']?.toString();
      if (cardId != null && !uniqueCardsMap.containsKey(cardId)) {
        uniqueCardsMap[cardId] = card;
      }
    }
    cards = uniqueCardsMap.values.toList();


   

    // Initialize showNumber to true for all cards
    for (var card in cards) {
      card['showNumber'] = true;
    }

    if (mounted) {
      setState(() {
        _cards = cards;
        _isLoading = false;
      });
    }

    for (var card in cards) {
      final cardId = card['card_id'] as String?;
      final cardCurrency = _getCardCurrency(card);
      if (cardId == null) continue;

      _fetchCardDetails(cardId, cardCurrency)
          .then((details) {
        
            if (mounted) {
              setState(() {
                card['details'] = details;
              });
            }
          })
          .catchError((e) {
            print('Error fetching details for card $cardId: $e');
            if (mounted) {
              setState(() {
                card['details'] = {};
              });
            }
          });
    }
  }

  String _getCardCurrency(Map<String, dynamic> card) {
    final dynamic selectedCurrencyRaw = card['selectedCurrency'];
    String selectedCurrency = 'Nigerian Naira (NGN)';
    if (selectedCurrencyRaw != null) {
      selectedCurrency = selectedCurrencyRaw.toString();
    }
  
    // Extract currency code from parentheses if present, or check for USD/NGN keywords
    RegExp codeRegex = RegExp(r'\(([A-Z]{3})\)');
    Match? match = codeRegex.firstMatch(selectedCurrency.toUpperCase());
    if (match != null) {
      final code = match.group(1)!;
      return code;
    } else if (selectedCurrency.toUpperCase().contains('USD')) {
      return 'USD';
    } else if (selectedCurrency.toUpperCase().contains('NGN')) {
      return 'NGN';
    } else {
      return 'NGN'; // Default fallback
    }
  }

  int _selectedIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: InkWell(
        onTap: _startCardCreation,
        child: Container(
          margin: EdgeInsets.only(bottom: 120),
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor,
          ),
          child: Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: SizedBox.expand(
          child: Stack(
            children: [
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: primaryColor),
                )
              else
                RefreshIndicator(
                  color: primaryColor,
                  onRefresh: _fetchCards,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: 20),
                        Row(
                          children: [
                            SizedBox(width: 15),
                            Text(
                              "My Cards",
                              style: TextStyle(
                                fontSize: 22,
                                color: Colors.black,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildCategoryChip('NGN', primaryColor),
                                  _buildCategoryChip('USD', Colors.green),
                                ],
                              ),
                            ),
                          ],
                        ),
                        _buildCardsView(),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              Positioned(
                bottom: 25,
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: BottomNavBar(
                    currentIndex: _selectedIndex,
                    onTap: (index) {
                      if (index == 0) {
                        navigateTo(
                          context,
                          HomePage(),
                          type: NavigationType.push,
                        );
                      }
                      if (index == 2) {
                        navigateTo(
                          context,
                          MyBusiness(),
                          type: NavigationType.push,
                        );
                      }
                      if (index == 3) {
                        navigateTo(
                          context,
                          TransactionsHistory(),
                          type: NavigationType.clearStack,
                        );
                      }
                      if (index == 4) {
                        navigateTo(
                          context,
                          ProfilePage(),
                          type: NavigationType.push,
                        );
                      }
                      if (index == 5) {
                        navigateTo(
                          context,
                          const PadiBookPage(),
                          type: NavigationType.push,
                        );
                      } else {
                        setState(() => _selectedIndex = index);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String category, Color color) {
    bool isSelected = _currentCategory == category;
    int count = _cards
        .where((card) => _getCardCurrency(card) == category)
        .length;
    return GestureDetector(
      onTap: () => setState(() => _currentCategory = category),
      child: Container(
        margin: EdgeInsets.only(left: 10),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          children: [
            Text(
              category,
              style: TextStyle(color: isSelected ? Colors.white : Colors.black),
            ),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCardsView() {
    List<Map<String, dynamic>> filtered = _cards
        .where((card) => _getCardCurrency(card) == _currentCategory)
        .toList();   

    if (filtered.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 50),
              Text(
                "No Cards Yet.",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text("Create your first card to get started."),
              const SizedBox(height: 50),
              GestureDetector(
                onTap: _startCardCreation,
                child: DottedBorder(
                  options: CircularDottedBorderOptions(
                    color: Colors.grey,
                    strokeWidth: 2,
                    dashPattern: const [15, 3],
                    padding: EdgeInsets.zero,
                  ),
                  child: Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                    ),
                    child: const Icon(Icons.add, size: 30, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 760,
          child: PageView.builder(
            controller: _pageController,
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              var card = filtered[index];
              var details = card['details'] as Map<String, dynamic>?;
              bool isLoadingDetails = details == null || details.isEmpty;

              String asset = switch (card['design']) {
                'Neon Magenta' => 'assets/card_neon_magenta_flat.png',
                'Cyber Aqua' => 'assets/card_cyber_aqua_flat.png',
                'Solar Glow' => 'assets/card_solar_glow_flat.png',
                _ => 'assets/card_neon_magenta_flat.png',
              };

              final double cardWidth = MediaQuery.of(context).size.width * 0.85;
              final double cardNumberFontSize = cardWidth * 0.05;
              final double labelFontSize = cardWidth * 0.03;
              final double textFontSize = cardWidth * 0.04;
              final double leftPadding = math.max(15.0, cardWidth * 0.14);

              String currencyCode = _getCardCurrency(card);
              String currencySymbol = currencyCode == 'USD' ? '\$' : '₦';

              double availBalance = 0.0;
              if (currencyCode == 'NGN') {
                availBalance = (card['balance'] ?? 0.0).toDouble();
              } else if (!isLoadingDetails && details.isNotEmpty) {
                availBalance =
                    (double.tryParse(
                          details['available_balance']?.toString() ?? '0',
                        ) ??
                        0.0) /
                    100;
              }
              var formatter = NumberFormat('#,###.00', 'en_US');
              String balanceStr =
                  '$currencySymbol${formatter.format(availBalance)}';

              String financialType = card['cardFinancialType'] ?? 'Debit';
              String cardNumber =
                  (details?['card_number'] ?? '0000000000000000').toString();
              String last4 = (details?['last_4'] ?? cardNumber.substring(cardNumber.length - 4)).toString();
              String cardTypeStr = '$financialType | **** $last4';

              String formattedNumber = cardNumber
                  .replaceAllMapped(
                    RegExp(r'.{4}'),
                    (match) => '${match.group(0)} ',
                  )
                  .trim();
              String displayedNumber = isLoadingDetails
                  ? '•••• •••• •••• ••••'
                  : (card['showNumber'] ?? true)
                      ? formattedNumber
                      : '•••• •••• •••• ••••';

              String cardName =
                  details?['card_name'] ?? card['nameOnCard'] ?? 'JOHN DOE';
              String displayedCardName = isLoadingDetails
                  ? 'CARD HOLDER'
                  : cardName;

              String expiryMonth = (details?['expiry_month'] ?? 'MM')
                  .toString()
                  .padLeft(2, '0');
              String expiryYear = (details?['expiry_year'] ?? 'YY').toString();
              String expiry =
                  '$expiryMonth/${expiryYear.substring(expiryYear.length - 2)}';
              String displayedExpiry = isLoadingDetails ? 'MM/YY' : expiry;

              String logoAsset =
                  ((details?['brand'] ?? card['scheme'] ?? 'Visa')
                      .toString()
                      .toLowerCase()
                      .contains('master'))
                  ? 'assets/mastercard.png'
                  : 'assets/visa_card.png';

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(vertical:10),
                        width: MediaQuery.of(context).size.width,
                       decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SizedBox(width: 20),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Total Balance",
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    (currencyCode == 'USD' && isLoadingDetails)
                                        ? _shimmerPlaceholder(
                                            width: 220,
                                            height: 36,
                                          )
                                        : Text(
                                            balanceStr,
                                            style: TextStyle(
                                              color: Colors.black87,
                                              fontSize: 25,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                    const SizedBox(height: 6),
                                    isLoadingDetails
                                        ? _shimmerPlaceholder(
                                            width: 180,
                                            height: 20,
                                          )
                                        : Text(
                                            cardTypeStr,
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                    const SizedBox(height: 30),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _showPinForCard(card),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Stack(
                          children: [
                            Center(
                              child: Image.asset(
                                asset,
                                width: cardWidth,
                                fit: BoxFit.fitWidth,
                              ),
                            ),
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Align(
                                alignment: Alignment.center,
                                child: Image.asset(
                                  logoAsset,
                                  width: cardWidth * 0.5 / 0.9,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: leftPadding,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    displayedNumber,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(
                                        isLoadingDetails ? 0.5 : 1,
                                      ),
                                      fontSize: cardNumberFontSize,
                                      letterSpacing: cardWidth * 0.005,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              bottom: 0,
                              right: MediaQuery.of(context).size.width * 0.25,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      card['showNumber'] = !(card['showNumber'] ?? true);
                                    });
                                  },
                                  child: Icon(
                                    (card['showNumber'] ?? true) ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 15,
                              left: leftPadding,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CARD HOLDER',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: labelFontSize,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  isLoadingDetails
                                      ? _shimmerPlaceholder(
                                          width: 200,
                                          height: textFontSize,
                                        )
                                      : Text(
                                          displayedCardName,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: textFontSize,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ],
                              ),
                            ),
                            Positioned(
                              bottom: 15,
                              right: leftPadding,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'EXPIRES',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: labelFontSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  isLoadingDetails
                                      ? _shimmerPlaceholder(
                                          width: 80,
                                          height: textFontSize,
                                        )
                                      : Text(
                                          displayedExpiry,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: textFontSize,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Container(
                          width: MediaQuery.of(context).size.width * 0.4,
                          height: 15,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(50),
                              bottomRight: Radius.circular(50),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _showPinForCard(Map<String, dynamic> card) async {
    showModalBottomSheet<String?>(
      context: context,
      builder: (context) => EnterPinBottomSheet(
        title: 'Enter Card PIN',
        description: 'Enter your 4-digit card PIN',
      ),
      isScrollControlled: true,
    ).then((enteredPin) {
      if (enteredPin == card['pin']) {
        _showCardDetails(card);
      } else if (enteredPin != null) {
        showToast("Incorrect PIN", Colors.red);
      }
    });
  }


  void _showCardDetails(Map<String, dynamic> card) {
    List<Map<String, dynamic>> filtered = _cards
        .where((c) => _getCardCurrency(c) == _currentCategory)
        .toList();
    int index = filtered.indexWhere((c) => c['id'] == card['id']);
    showModalBottomSheet(
      context: context,
      builder: (context) => CardDetailsBottomSheet(
        cards: filtered,
        initialIndex: index,
        selectedCurrency: card['selectedCurrency'],
      ),
      isScrollControlled: true,
    );
  }

  void _startCardCreation() {
    showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const CardTypeBottomSheet(),
      isScrollControlled: true,
    ).then((type) {
      if (type == null) return;
      if (type != "Virtual") {
        showToast("$type card is unavailable at the moment", Colors.red);
        return;
      }
      showModalBottomSheet<Map<String, dynamic>?>(
        context: context,
        builder: (context) => BasicDetailsBottomSheet(cardType: type),
        isScrollControlled: true,
      ).then((basicData) {
        if (basicData == null) return;
        showModalBottomSheet<String?>(
          context: context,
          builder: (context) => const CustomizeCardBottomSheet(),
          isScrollControlled: true,
        ).then((design) {
          if (design == null) return;
          showModalBottomSheet<bool?>(
            context: context,
            builder: (context) => ReviewConfirmBottomSheet(
              cardType: type,
              basicData: basicData,
              selectedDesign: design,
              selectedCurrency: basicData["selectedCurrency"],
              selectedScheme: basicData["selectedScheme"],
            ),
            isScrollControlled: true,
          ).then((confirm) {
            if (confirm == true) {
              _createCard(type, basicData, design);
            }
          });
        });
      });
    });
  }

  Future<Map<String, dynamic>?> getCompanyVirtualAccount() async {
    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('company')
          .doc('account_details')
          .get();
      if (!docSnap.exists) return null;
      final data = docSnap.data()!;
      return {
        'uid': data['uid']?.toString() ?? '',
        'id': data['accountId']?.toString() ?? '',
        'type': data['accountType']?.toString() ?? '',
        'bankId': data['bankId']?.toString() ?? '',
        'bankName': data['bankName']?.toString() ?? '',
        'accountNumber': data['accountNumber']?.toString() ?? '',
        'accountName': data['accountName']?.toString() ?? '',
      };
    } catch (e) {
      print('getCompanyVirtualAccount error: $e');
      return null;
    }
  }

  Future<bool> _refundToUser(
    Map<String, dynamic> userDetails,
    Map<String, dynamic> companyVa,
    double amountNGN,
  ) async {
    try {
      final String? userAccountId = userDetails['accountId'];
      if (userAccountId == null || userAccountId.isEmpty) {
        print('Refund skipped: Missing user accountId');
        return false;
      }

      // Refund: company → user (book transfer — both on Sudo)
      final refundResult = await callCloudFunctionLogged('sudoTransferIntra', source: 'business_app', payload: {
            'fromAccountId': companyVa['id'],
            'toAccountId': userAccountId,
            'amount': (amountNGN * 100).toInt(),
            'currency': 'NGN',
            'narration': 'Refund for failed card creation/funding',
            'idempotencyKey': const Uuid().v4(),
          });

      if (refundResult.data['data']['attributes']['status'] == 'FAILED') {
        print('Refund transfer failed: ${refundResult.data['message']}');
        return false;
      }
      return true;
    } catch (e) {
      print('Refund error: $e');
      return false;
    }
  }

  Future<void> _createCard(
    String type,
    Map<String, dynamic> basicData,
    String design,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: primaryColor)),
    );
    bool funded = false;
    double amountNGN = 0.0;
    Map<String, dynamic>? userDetails;
    Map<String, dynamic>? companyVa;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'User not logged in';

      userDetails = await getCurrentAccountIdAndType();
      final String? accountId = userDetails['accountId'];
      final String? accountType = userDetails['accountType'];
      final String? bankId = userDetails['bankId'];

      if (accountId == null || accountType == null || bankId == null) {
        Navigator.pop(context);
        showToast("Please create a bank account first", Colors.red);
        return;
      }

     
      Map<String, dynamic>? userData;
     
        // Fallback to personal
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        userData = userSnap.data();
      

      String? pin = await showModalBottomSheet<String?>(
        context: context,
        builder: (context) => const EnterPinBottomSheet(
          title: 'Create Card PIN',
          description: 'Enter a 4-digit PIN to secure your card',
        ),
        isScrollControlled: true,
      );

      if (pin == null) {
        Navigator.pop(context);
        return;
      }

      String cardCurrency =
          basicData['selectedCurrency'].toString().toUpperCase().contains('USD')
          ? 'USD'
          : 'NGN';

      if (cardCurrency == 'USD' && _balance < _usdFundingRequiredNGN) {
        Navigator.pop(context);
        showToast("Insufficient funds to create card", Colors.red);
        return;
      }

      String callableName = cardCurrency == 'USD'
          ? 'bridgecardCreateUsdCard'
          : 'createStrowalletNairaCard';
      HttpsCallable cardCallable = FirebaseFunctions.instance.httpsCallable(
        callableName,
      );
      Map<String, dynamic> body;
      if (cardCurrency == "USD") {
        body = {
          'cardholder_id': userData!['bridgeCard']['cardholder_id'],
          'card_type': type.toLowerCase(),
          'card_brand': basicData['scheme'],
          'card_currency': cardCurrency,
          'pin': pin,
          'meta_data': {'user_id': user.uid},
        };
      } else {
        body = {
          'customerId': userData!['stroWalletUser']['data']['customer_id'],
          'type': type.toLowerCase(),
          'brand': basicData['scheme'],
        };
      }

      if (cardCurrency == 'USD') {
        body['card_limit'] = 500000;
        body['funding_amount'] = 300;

        HttpsCallable fxCallable = FirebaseFunctions.instance.httpsCallable(
          'bridgecardGetFxRate',
        );
        var fxResponse = await fxCallable.call();
        double rate = fxResponse.data['data']['NGN-USD'].toDouble() / 100;
        amountNGN = 3 * rate;

        companyVa = await getCompanyVirtualAccount();
        if (companyVa == null) throw 'Company account not found';

        // Fund company account (book transfer — both on Sudo)
        var transferResult = await callCloudFunctionLogged('sudoTransferIntra', source: 'business_app', payload: {
              'fromAccountId': accountId,
              'toAccountId': companyVa['id'],
              'amount': (amountNGN * 100).toInt(),
              'currency': 'NGN',
              'narration': 'USD Card Funding',
              'idempotencyKey': const Uuid().v4(),
            });

        if (transferResult.data['data']['attributes']['status'] == 'FAILED') {
          throw 'Funding transfer failed';
        }

        funded = true;
      }

      print('Creating card with body: $body');

      var response = await cardCallable.call(body);
      String cardId = response.data["data"]["card_id"];

      Map<String, dynamic> cardData = {
        'type': type,
        'scheme': basicData['scheme'],
        'cardFinancialType': basicData['cardFinancialType'],
        'nameOnCard': basicData['nameOnCard'],
        'selectedCurrency': basicData['selectedCurrency'],
        'design': design,
        'status': "active",
        'card_id': cardId,
        'pin': pin,
      };
      if (type == 'Physical') {
        cardData['shippingAddress'] = basicData['shippingAddress'];
      }

     
        await FirebaseFirestore.instance
            .collection('users/${user.uid}/cards')
            .add(cardData);
      

      Navigator.pop(context);
      showModalBottomSheet(
        context: context,
        builder: (context) => const SuccessBottomSheet(
          actionText: 'Go to Home',
          title: 'Your card will be ready soon!',
          description: 'Estimated delivery: 2-5 minutes.',
        ),
        isScrollControlled: true,
      ).then((_) => _fetchCards());
    } catch (e) {
      if (funded && userDetails != null && companyVa != null) {
        bool refunded = await _refundToUser(userDetails, companyVa, amountNGN);
        if (refunded) {
          showToast('Card creation failed, but funds refunded', Colors.orange);
        } else {
          showToast(
            'Card creation and refund failed - contact support',
            Colors.red,
          );
        }
      }
      Navigator.pop(context);
      if (e.toString().toLowerCase().contains("insufficient")) {
        showToast("Insufficient Funds", Colors.red);
      }
      print('Error creating card: $e');
    }
  }
}

class EnterPinBottomSheet extends StatefulWidget {
  final String title;
  final String description;

  const EnterPinBottomSheet({
    super.key,
    this.title = 'Create Card PIN',
    this.description = 'Enter a 4-digit PIN to secure your card',
  });

  @override
  State<EnterPinBottomSheet> createState() => _EnterPinBottomSheetState();
}

class _EnterPinBottomSheetState extends State<EnterPinBottomSheet> {
  String pin = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
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
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text(
                widget.description,
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
                    setState(() => pin += val);

                    if (pin.length == 4) {
                      Navigator.pop(context, pin);
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