import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/add_first_pos_stand.dart';
import 'package:padi_pay_business/cards_page.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/my_business/shimmer_card.dart';
import 'package:padi_pay_business/padi_book/padi_book_page.dart';
import 'package:padi_pay_business/profile/profile_page.dart';
import 'package:padi_pay_business/stand_details.dart';
import 'package:padi_pay_business/transactions_history.dart';
import 'package:padi_pay_business/ui/bottom_nav_bar.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:url_launcher/url_launcher.dart';

class MyBusiness extends StatefulWidget {
  const MyBusiness({super.key});

  @override
  State<MyBusiness> createState() => _MyBusinessState();
}

class _MyBusinessState extends State<MyBusiness> with TickerProviderStateMixin {
  /// Fetches real account number and bank name for a stand and updates Firestore
  /// Fetches real account number and bank name for a stand when displayed
  Future<void> _deleteStand(int index) async {
    final stand = posStands[index];
    final standId = stand['standId'];
    final standEmail = stand['standLoginEmail'];
    final parentBusinessId = stand['parentBusinessId'];
    if (standId == null || standEmail == null || parentBusinessId == null) {
      showToast('Missing stand info', Colors.red);
      return;
    }
    try {
      setState(() {
        posStands.removeAt(index);
      });
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(parentBusinessId)
          .update({'posStands': posStands});
      final functions = FirebaseFunctions.instance;
      final deleteStandUserFunc = functions.httpsCallable('deleteStandUser');
      await deleteStandUserFunc.call({'email': standEmail});
      showToast('Stand deleted', Colors.green);
    } catch (e) {
      showToast('Error deleting stand: $e', Colors.red);
    }
  }
  /// Fetches real account number and bank name for stands that need it


  /// Fetches real account number and bank name for stands that need it
  Future<void> _enrichStandAccountData(int index) async {
    if (index < 0 || index >= posStands.length) return;

    final stand = posStands[index];
    final accountData = stand['accountData'] as Map<String, dynamic>?;
    if (accountData == null) return;

    final accountId = accountData['data']?['id']?.toString();
    if (accountId == null) return;

    final attributes = accountData['data']?['attributes'] as Map<String, dynamic>?;

    // Improved skip condition: only skip if we have a REAL account number (usually 10 digits for Nigeria)
    final existingAccountNumber = attributes?['accountNumber']?.toString() ?? '';
    if (existingAccountNumber.length >= 10 && 
        !existingAccountNumber.contains('anc_acc') && 
        !existingAccountNumber.startsWith('temp')) {
      print('⏭️  Skipping enrichment for ${stand['name']} - already has real account number');
      return;
    }

    try {
      print('🔄 Enriching account for stand: ${stand['name']} | accountId: $accountId');

      final callable = FirebaseFunctions.instance.httpsCallable('fetchAccountNumber');
      final result = await callable.call({'accountId': accountId});

      dynamic resp = result.data;
      String? accountNumber;
      String? bankName;

      if (resp is Map) {
        final safeResp = Map<String, dynamic>.from(resp);

        accountNumber = safeResp['accountNumber']?.toString() ??
                        safeResp['data']?['attributes']?['accountNumber']?.toString() ??
                        safeResp['data']?['accountNumber']?.toString();

        if (safeResp['bank'] != null) {
          if (safeResp['bank'] is Map) {
            bankName = (safeResp['bank'] as Map)['name']?.toString();
          } else {
            bankName = safeResp['bank']?.toString();
          }
        }
        bankName ??= safeResp['data']?['attributes']?['bank']?['name']?.toString();
      }

      if (accountNumber != null && accountNumber.length >= 8) {
        // Update local stand
        final updatedStand = Map<String, dynamic>.from(stand);
        final dataMap = (updatedStand['accountData']?['data'] as Map<String, dynamic>?) ?? {};
        final attrMap = (dataMap['attributes'] as Map<String, dynamic>?) ?? {};

        attrMap['accountNumber'] = accountNumber;
        if (bankName != null) {
          attrMap['bank'] = {'name': bankName};
        }

        // Update UI
        setState(() {
          posStands[index] = updatedStand;
        });

        // Save to Firestore
        final parentBusinessId = stand['parentBusinessId'];
        if (parentBusinessId != null) {
          await FirebaseFirestore.instance
              .collection('businesses')
              .doc(parentBusinessId)
              .update({'posStands': posStands});
        }

        print('✅ Successfully enriched "${stand['name']}" → Account: $accountNumber | Bank: $bankName');
      } else {
        print('⚠️  No valid accountNumber returned from API for ${stand['name']}');
      }
    } catch (e) {
      debugPrint('Failed to enrich stand "${stand['name']}": $e');
      if (e.toString().contains('not-found')) {
        print('⚠️  Cloud Function said Account number not found - likely still processing');
      }
    }
  }

  Future<void> _editStand(int index) async {
    final stand = posStands[index];
    final TextEditingController nameController = TextEditingController(
      text: stand['name'] ?? '',
    );
    final TextEditingController locationController = TextEditingController(
      text: stand['location'] ?? '',
    );
    final TextEditingController emailController = TextEditingController(
      text: stand['standLoginEmail'] ?? '',
    );
    final TextEditingController passwordController = TextEditingController(
      text: stand['standLoginPassword'] ?? '',
    );
    bool isPasswordVisible = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.7,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Edit Stand',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Stand Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: locationController,
                  decoration: InputDecoration(
                    labelText: 'Stand Location',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Login Email',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: 'Login Password',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () => setState(
                        () => isPasswordVisible = !isPasswordVisible,
                      ),
                    ),
                  ),
                  obscureText: !isPasswordVisible,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (nameController.text.trim().isEmpty ||
                            locationController.text.trim().isEmpty ||
                            emailController.text.trim().isEmpty ||
                            passwordController.text.trim().isEmpty) {
                          showToast('All fields are required', Colors.red);
                          return;
                        }
                        final updatedStand = {
                          ...stand,
                          'name': nameController.text.trim(),
                          'location': locationController.text.trim(),
                          'standLoginEmail': emailController.text.trim(),
                          'standLoginPassword': passwordController.text.trim(),
                        };
                        try {
                          setState(() {
                            posStands[index] = updatedStand;
                          });
                          await FirebaseFirestore.instance
                              .collection('businesses')
                              .doc(stand['parentBusinessId'])
                              .update({'posStands': posStands});
                          final oldEmail = stand['standLoginEmail'];
                          final newEmail = emailController.text.trim();
                          final newPassword = passwordController.text.trim();
                          if (oldEmail != newEmail ||
                              stand['standLoginPassword'] != newPassword) {
                            final functions = FirebaseFunctions.instance;
                            final updateStandUserFunc = functions.httpsCallable(
                              'updateStandUser',
                            );
                            await updateStandUserFunc.call({
                              'oldEmail': oldEmail,
                              'newEmail': newEmail,
                              'newPassword': newPassword,
                            });
                          }
                          Navigator.of(ctx).pop();
                          showToast('Stand updated', Colors.green);
                        } catch (e) {
                          showToast('Error updating stand: $e', Colors.red);
                        }
                      },
                      child: Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    nameController.dispose();
    locationController.dispose();
    emailController.dispose();
    passwordController.dispose();
  }

  int _selectedIndex = 2;
  String firstName = '';
  String businessName = '';
  String industry = '';
  List<dynamic> posStands = [];
  List<Map<String, dynamic>> standMetrics = [];
  double monthlyRevenue = 0;
  bool isUserLoaded = false;
  bool isBusinessLoaded = false;
  bool isRevenueLoaded = false;
  bool isMetricsLoaded = false;
  bool hasBusiness = false; // New flag to track if business document exists

  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _loadUserAndBusiness();
    _loadRevenue();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  double _getAmount(Map<String, dynamic> doc) {
    final apiAmount = doc['api_response']?['data']?['attributes']?['amount'];
    if (apiAmount != null && apiAmount is num) {
      return (apiAmount / 100).toDouble();
    }
    final topAmount = doc['amount'];
    if (topAmount != null && topAmount is num) {
      return (topAmount / 100).toDouble();
    }
    return 0.0;
  }

   Future<void> _loadUserAndBusiness() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final busFuture = FirebaseFirestore.instance
          .collection('businesses')
          .doc(user.uid)
          .get();

      final results = await Future.wait([userFuture, busFuture]);
      DocumentSnapshot userDoc = results[0];
      DocumentSnapshot busDoc = results[1];

      String loadedFirstName = '';
      String loadedBusinessName = '';
      String loadedIndustry = '';
      List<dynamic> loadedPosStands = [];

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>?;
        if (userData != null) {
          loadedFirstName = userData['firstName'] ?? '';
        }
      }

      bool businessExists = busDoc.exists;
      if (businessExists) {
        final busDataMap = busDoc.data() as Map<String, dynamic>?;
        if (busDataMap != null) {
          final businessData = busDataMap['business_data'] as Map<String, dynamic>?;
          if (businessData != null) {
            loadedBusinessName = businessData['name'] ?? '';
            loadedIndustry = businessData['industry'] ?? '';
          }
          loadedPosStands = List.from(busDataMap['posStands'] ?? []);
        }
      }

      if (mounted) {
        setState(() {
          firstName = loadedFirstName;
          businessName = loadedBusinessName;
          industry = loadedIndustry;
          posStands = loadedPosStands;
          hasBusiness = businessExists;
          isUserLoaded = true;
          isBusinessLoaded = true;
        });

        await _loadMetrics();

        // Enrich stands AFTER setState and list is stable
        if (posStands.isNotEmpty) {
          print('🔄 Starting enrichment for ${posStands.length} stands...');
          for (int i = 0; i < posStands.length; i++) {
            await _enrichStandAccountData(i);
          }
          print('✅ Enrichment loop completed');
        }
      }
    } catch (e) {
      debugPrint('Error loading user/business: $e');
    }
  }
   Future<void> _openAddStand() async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AddPosStand(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.ease;
          final tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          final offsetAnimation = animation.drive(tween);
          return SlideTransition(position: offsetAnimation, child: child);
        },
      ),
    );
    if (!mounted) return;
    await _loadUserAndBusiness();
  }

  Future<void> _loadRevenue() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final now = DateTime.now();
      final monthStart = Timestamp.fromDate(DateTime(now.year, now.month, 1));
      final monthEnd = Timestamp.fromDate(DateTime(now.year, now.month + 1, 1));

      Query depositQuery = FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'deposit')
          .where('status', isEqualTo: 'SUCCESSFUL')
          .where('timestamp', isGreaterThanOrEqualTo: monthStart)
          .where('timestamp', isLessThan: monthEnd);

      QuerySnapshot depositSnap = await depositQuery.get();
      double depositSum = 0;
      for (var doc in depositSnap.docs) {
        depositSum += _getAmount(doc.data() as Map<String, dynamic>);
      }

      Query transferQuery = FirebaseFirestore.instance
          .collection('transactions')
          .where('recipientName', isEqualTo: businessName)
          .where('type', isEqualTo: 'transfer')
          .where('status', isEqualTo: 'SUCCESSFUL')
          .where('timestamp', isGreaterThanOrEqualTo: monthStart)
          .where('timestamp', isLessThan: monthEnd);

      QuerySnapshot transferSnap = await transferQuery.get();
      double transferSum = 0;
      for (var doc in transferSnap.docs) {
        transferSum += _getAmount(doc.data() as Map<String, dynamic>);
      }

      if (mounted) {
        setState(() {
          monthlyRevenue = depositSum + transferSum;
          isRevenueLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading revenue: $e');
      if (mounted) setState(() => isRevenueLoaded = true);
    }
  }

  Future<void> _loadMetrics() async {
    if (posStands.isEmpty) {
      setState(() => isMetricsLoaded = true);
      return;
    }
    try {
      final now = DateTime.now();
      final todayStart = Timestamp.fromDate(
        DateTime(now.year, now.month, now.day),
      );
      List<Map<String, dynamic>> metrics = [];

      for (var stand in posStands) {
        final accountId = stand['accountData']?['data']?['id'];
        if (accountId == null) {
          metrics.add({'count': 0, 'total': 0.0, 'last': 'N/A'});
          continue;
        }
        final query = FirebaseFirestore.instance
            .collection('transactions')
            .where(
              'api_response.data.relationships.account.data.id',
              isEqualTo: accountId,
            )
            .where('timestamp', isGreaterThanOrEqualTo: todayStart);

        final snap = await query.get();
        int count = snap.docs.length;
        double total = 0.0;
        Timestamp? lastTs;
        for (var doc in snap.docs) {
          final data = doc.data();
          total += _getAmount(data);
          final ts = data['timestamp'] as Timestamp?;
          if (ts != null && (lastTs == null || ts.compareTo(lastTs) > 0)) {
            lastTs = ts;
          }
        }
        String lastActivity = lastTs != null
            ? DateFormat('HH:mm').format(lastTs.toDate())
            : 'N/A';
        metrics.add({'count': count, 'total': total, 'last': lastActivity});
      }

      if (mounted) {
        setState(() {
          standMetrics = metrics;
          isMetricsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading metrics: $e');
      if (mounted) setState(() => isMetricsLoaded = true);
    }
  }

  final List<Color> _dotColors = [Colors.green, Colors.deepOrange, Colors.blue];

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final headerHeight = screenHeight * 0.35;
    const double positionToBusinessTop = 170.0;
    const double overlap = 20.0;
    final formattedRevenue = NumberFormat('#,##0').format(monthlyRevenue);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SizedBox.expand(
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      height: headerHeight + overlap,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: headerHeight,
                            child: Stack(
                              children: [
                                Container(
                                  width: double.infinity,
                                  color: Colors.black,
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SvgPicture.asset(
                                      'assets/Group (1).svg',
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 16,
                                    top: 30,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      !isUserLoaded
                                          ? ShimmerEffect(
                                              child: ShimmerText(
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.8),
                                                  fontWeight: FontWeight.w100,
                                                ),
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  "Welcome, $firstName! 😀",
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.8),
                                                    fontWeight: FontWeight.w100,
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: () {
                                                    launchUrl(
                                                      Uri.parse(
                                                        "https://www.padipay.co",
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          right: 16,
                                                        ),
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 1.5,
                                                      ),
                                                    ),
                                                    child: Icon(
                                                      Icons
                                                          .question_mark_rounded,
                                                      color: Colors.white,
                                                      size: 15,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                      const SizedBox(height: 20),
                                      const Text(
                                        "Ready to manage\nyour business?",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 24,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 40),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: positionToBusinessTop,
                            left: 20,
                            right: 20,
                            child: Container(
                              padding: const EdgeInsets.only(left: 16, top: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  width: 0.5,
                                  color: const Color(0xFFEAECF0),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      !isBusinessLoaded
                                          ? Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.grey[300],
                                              ),
                                              width: 48,
                                              height: 48,
                                            )
                                          : Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: primaryColor.withOpacity(
                                                  0.1,
                                                ),
                                              ),
                                              child: Text(
                                                businessName.isNotEmpty
                                                    ? businessName
                                                          .substring(0, 1)
                                                          .toUpperCase()
                                                    : "MB",
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: primaryColor,
                                                ),
                                              ),
                                            ),
                                      const SizedBox(width: 6),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          !isBusinessLoaded
                                              ? ShimmerEffect(
                                                  child: ShimmerText(
                                                    style: GoogleFonts.inter(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                )
                                              : Text(
                                                  businessName,
                                                  style: GoogleFonts.inter(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                          !isBusinessLoaded
                                              ? ShimmerEffect(
                                                  child: ShimmerText(
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w100,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                )
                                              : Text(
                                                  industry,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w100,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 25),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        children: [
                                          Text(
                                            "Monthly Revenue",
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Colors.black54,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          !isRevenueLoaded
                                              ? ShimmerEffect(
                                                  child: ShimmerText(
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      fontSize: 12,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                )
                                              : Text(
                                                  "₦$formattedRevenue",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w400,
                                                    fontSize: 12,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                          SizedBox(height: 20),
                                        ],
                                      ),
                                      Transform.translate(
                                        offset: Offset(5, 0),
                                        child: Column(
                                          children: [
                                            Text(
                                              "POS Stands",
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: Colors.black54,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            !isBusinessLoaded
                                                ? ShimmerEffect(
                                                    child: ShimmerText(
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w400,
                                                        fontSize: 12,
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                  )
                                                : Text(
                                                    "${posStands.length}",
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      fontSize: 12,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                            SizedBox(height: 20),
                                          ],
                                        ),
                                      ),
                                      Transform.translate(
                                        offset: Offset(0, 8),
                                        child: SvgPicture.asset(
                                          "assets/Vector.svg",
                                          width: 70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          SizedBox(height: 100 - overlap),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "POS Stands",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.black,
                                ),
                              ),
                              // Only show Add Stand button if business exists
                              // if (hasBusiness)
                              InkWell(
                                onTap: _openAddStand,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.add,
                                        size: 18,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        "Add Stand",
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 50),
                          if (!isBusinessLoaded)
                            Column(
                              children: List.generate(
                                3,
                                (index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 15),
                                  child: const ShimmerStandCard(),
                                ),
                              ),
                            )
                          // else if (!hasBusiness)
                          //   Center(
                          //     child: Column(
                          //       children: [
                          //         const Text(
                          //           'No business created yet.',
                          //           style: TextStyle(
                          //             color: Colors.black54,
                          //             fontSize: 14,
                          //           ),
                          //           textAlign: TextAlign.center,
                          //         ),
                          //         const SizedBox(height: 20),
                          //         SizedBox(
                          //           width: 200,
                          //           child: ElevatedButton(
                          //             onPressed: () {
                          //               navigateTo(
                          //                 context,
                          //                 HomePage(),
                          //                 type: NavigationType.replace,
                          //               );
                          //             },
                          //             style: ElevatedButton.styleFrom(
                          //               backgroundColor: primaryColor,
                          //               shape: RoundedRectangleBorder(
                          //                 borderRadius: BorderRadius.circular(
                          //                   8,
                          //                 ),
                          //               ),
                          //             ),
                          //             child: const Padding(
                          //               padding: EdgeInsets.symmetric(
                          //                 vertical: 12,
                          //               ),
                          //               child: Text(
                          //                 'Create Business',
                          //                 style: TextStyle(
                          //                   fontSize: 14,
                          //                   color: Colors.white,
                          //                   fontWeight: FontWeight.bold,
                          //                 ),
                          //               ),
                          //             ),
                          //           ),
                          //         ),
                          //       ],
                          //     ),
                          //   )
                          else if (posStands.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'No POS stands added yet. Tap "Add Stand" to get started.',
                                style: TextStyle(color: Colors.black54),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: posStands.length,
                              itemBuilder: (context, index) {
                                final stand = posStands[index];
                                final name = stand['name'] ?? '';
                                final location = stand['location'] ?? '';
                                final accountData = stand['accountData'];

                                final accountAttributes =
                                    (accountData is Map<String, dynamic>)
                                    ? (accountData['data']?['attributes']
                                              as Map<String, dynamic>?) ??
                                          {}
                                    : {};

                                final accountNumber =
                                    accountAttributes['accountNumber'] ??
                                    'Loading...';
                                final accountName =
                                    accountAttributes['accountName'] ??
                                    'Unavailable';
                                final bankName =
                                    (accountAttributes['bank']
                                        is Map<String, dynamic>)
                                    ? accountAttributes['bank']['name'] ??
                                          'Unavailable'
                                    : 'Unavailable';

                                final dotColor =
                                    _dotColors[index % _dotColors.length];

                                // Auto-enrich account data when this stand is displayed
                              

                                return GestureDetector(
                                  onTap: () {
                                    final accountId =
                                        stand['accountData']?['data']?['id'];
                                    if (accountId != null) {
                                      navigateTo(
                                        context,
                                        StandDetailsPage(
                                          accountId: accountId,
                                          standName: name,
                                        ),
                                      );
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 15),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: Colors.grey.shade100,
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  top: 6,
                                                ),
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: dotColor,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      name,
                                                      style: GoogleFonts.inter(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      location,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w100,
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete,
                                                  color: Colors.red,
                                                ),
                                                tooltip: 'Delete Stand',
                                                onPressed: () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      title: const Text(
                                                        'Delete Stand',
                                                      ),
                                                      content: const Text(
                                                        'Are you sure you want to delete this stand and its user?',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                ctx,
                                                              ).pop(false),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                ctx,
                                                              ).pop(true),
                                                          child: Text(
                                                            'Delete',
                                                            style: TextStyle(
                                                              color: Colors.red,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm == true) {
                                                    await _deleteStand(index);
                                                  }
                                                },
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.edit,
                                                  color: Colors.blue,
                                                ),
                                                tooltip: 'Edit Stand',
                                                onPressed: () =>
                                                    _editStand(index),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 25),
                                          const Divider(),
                                          const SizedBox(height: 25),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "Account Name",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w100,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    accountName,
                                                    style: GoogleFonts.inter(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "Account Number",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w100,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    accountNumber,
                                                    style: GoogleFonts.inter(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 20),
                                          Row(
                                            children: [
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "Bank",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w100,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    bankName,
                                                    style: GoogleFonts.inter(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 25),
                                          const Divider(),
                                          const SizedBox(height: 25),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "Today's Sales",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w100,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  !isMetricsLoaded
                                                      ? ShimmerText(
                                                          style:
                                                              GoogleFonts.inter(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14,
                                                              ),
                                                        )
                                                      : Text(
                                                          "₦${NumberFormat('#,##0.00').format(standMetrics[index]['total'])}",
                                                          style:
                                                              GoogleFonts.inter(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14,
                                                                color: Colors
                                                                    .black54,
                                                              ),
                                                        ),
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "Transactions Today",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w100,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  !isMetricsLoaded
                                                      ? ShimmerText(
                                                          style:
                                                              GoogleFonts.inter(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14,
                                                              ),
                                                        )
                                                      : Text(
                                                          "${standMetrics[index]['count']}",
                                                          style:
                                                              GoogleFonts.inter(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14,
                                                                color: Colors
                                                                    .black54,
                                                              ),
                                                        ),
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "Last Activity",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w100,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  !isMetricsLoaded
                                                      ? ShimmerText(
                                                          style:
                                                              GoogleFonts.inter(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14,
                                                              ),
                                                        )
                                                      : Text(
                                                          standMetrics[index]['last'],
                                                          style:
                                                              GoogleFonts.inter(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14,
                                                                color: Colors
                                                                    .black54,
                                                              ),
                                                        ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 150),
                        ],
                      ),
                    ),
                  ],
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
                        navigateTo(context, HomePage());
                        return;
                      }
                      if (index == 1) {
                        navigateTo(
                          context,
                          CardsPage(),
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
                          type: NavigationType.push,
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
}

class ShimmerEffect extends StatelessWidget {
  final Widget child;
  final AnimationController? controller;

  const ShimmerEffect({super.key, required this.child, this.controller});

  @override
  Widget build(BuildContext context) {
    final shimmerController =
        controller ??
        (context
            .findAncestorStateOfType<_MyBusinessState>()
            ?._shimmerController);
    if (shimmerController == null) return child;

    return AnimatedBuilder(
      animation: shimmerController,
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.4,
                  child: FractionallySizedBox(
                    widthFactor: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            Colors.white.withOpacity(0.4),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: shimmerController.value * 200,
              top: 0,
              bottom: 0,
              child: ClipRect(
                child: Container(
                  width: 100,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(4),
        ),
        child: child,
      ),
    );
  }
}
