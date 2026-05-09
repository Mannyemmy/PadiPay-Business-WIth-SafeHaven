import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padi_pay_business/feedback.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/kyb/business_info.dart';
import 'package:padi_pay_business/profile/upgrade_tier.dart' show UpgradeTier;
import 'package:padi_pay_business/utils.dart';

extension StringExtension on String {
  String capitalize() {
    return isNotEmpty ? this[0].toUpperCase() + substring(1).toLowerCase() : '';
  }
}

class BusinessUpgradeManager extends StatefulWidget {
  const BusinessUpgradeManager({super.key});

  @override
  State<BusinessUpgradeManager> createState() => _BusinessUpgradeManagerState();
}

class _BusinessUpgradeManagerState extends State<BusinessUpgradeManager> {
  bool contactFixed = false;
  bool businessFixed = false;
  bool repFixed = false;
  bool docsFixed = false;

  bool idSubmitted = false;
  bool idVerified = false;
  bool idFailed = false;

  bool isLoading = false;
  bool showDocs = false;
  String? currentKycStatus;
  bool kybVerificationExists = false;

  // ✅ Tier from safehavenData (or fallback to sudoData)
  int userTier = 0;

  @override
  void initState() {
    super.initState();
    setState(() => isLoading = true);
    _loadFlags();
  }

  Future<void> _loadFlags({bool fromRefresh = false}) async {
    if (!fromRefresh) {
      setState(() => isLoading = true);
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(user.uid)
          .get();

      final data = doc.exists ? doc.data()! : <String, dynamic>{};
      final Map<String, dynamic>? businessSafehavenData =
          data['safehavenData'] as Map<String, dynamic>?;
      final bool hasBusinessSafehavenAccount =
          businessSafehavenData?['virtualAccount'] != null;

      if (hasBusinessSafehavenAccount) {
        currentKycStatus = "APPROVED";
      } else {
        currentKycStatus =
            data['kybVerification']?['status'] ?? currentKycStatus;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) return;

      final userData = userDoc.data() ?? <String, dynamic>{};
      final qoreData =
          userData['qoreIdData'] as Map<String, dynamic>? ??
          <String, dynamic>{};

      final bvnVerif =
          qoreData['bvnVerificationNoFace'] as Map<String, dynamic>?;
      final bool bvnVerifiedDirect = bvnVerif?['verified'] == true;
      final bool bvnVerifiedFieldExists =
          bvnVerif != null && bvnVerif.containsKey('verified');
      final bool bvnExplicitlyFalse =
          bvnVerifiedFieldExists && bvnVerif!['verified'] == false;

      final verification =
          qoreData['verification'] as Map<String, dynamic>? ??
          <String, dynamic>{};
      final metadata =
          verification['metadata'] as Map<String, dynamic>? ??
          <String, dynamic>{};

      final hasBvn =
          (userData['bvn']?.toString().trim().isNotEmpty == true) ||
          (metadata['idNumber']?.toString().trim().isNotEmpty == true) ||
          (metadata['bvn']?.toString().trim().isNotEmpty == true);

      final qoreVerified =
          verification['verified'] == true || metadata['match'] == true;
      final tierFromSudo =
          (userData['sudoData']?['tier'] as num?)?.toInt() ?? 0;
      final hasCustomerCreation =
          (userData['sudoData']
              as Map<String, dynamic>?)?['customerCreation'] !=
          null;

      final bool fallbackWouldFire =
          !bvnVerifiedFieldExists &&
          hasBvn &&
          (qoreVerified || tierFromSudo >= 1 || hasCustomerCreation);

      final bool effectiveVerified = bvnVerifiedDirect || fallbackWouldFire;
      final Map<String, dynamic>? userSafehavenData =
          userData['safehavenData'] as Map<String, dynamic>?;
      final bool hasUserSafehavenAccount =
          userSafehavenData?['virtualAccount'] != null;
      final bool hasSafehavenAccount =
          hasBusinessSafehavenAccount || hasUserSafehavenAccount;
      final bool effectiveVerifiedFinal = effectiveVerified || hasSafehavenAccount;
      final bool effectiveFailed = bvnExplicitlyFalse;

      // READ TIER FROM safehavenData (primary) or fallback to sudoData
      if (hasBusinessSafehavenAccount) {
        userTier = 3;
      } else {
        final int safehavenTier =
            (userSafehavenData?['tier'] as num?)?.toInt() ??
            (businessSafehavenData?['tier'] as num?)?.toInt() ??
            0;
        userTier = safehavenTier > 0 ? safehavenTier : tierFromSudo;
      }

      // Set initial flags from Firestore
      bool contactFixedLocal = data['contact_fixed'] ?? false;
      bool businessFixedLocal = data['business_fixed'] ?? false;
      bool repFixedLocal = data['rep_fixed'] ?? false;
      bool docsFixedLocal = data['docs_fixed'] ?? false;
      bool idVerifiedLocal = effectiveVerifiedFinal;
      bool idSubmittedLocal = effectiveVerifiedFinal;
      bool idFailedLocal = effectiveFailed;

      // --- TIER-BASED OVERRIDES ---
      if (userTier == 1) {
        // BVN should be marked as verified (even if not actually verified)
        idVerifiedLocal = true;
        idSubmittedLocal = true;
        idFailedLocal = false;
        // Business info is not considered fixed for tier 1
        businessFixedLocal = false;
      } else if (userTier == 2) {
        // BVN is considered verified (prerequisite)
        idVerifiedLocal = true;
        idSubmittedLocal = true;
        idFailedLocal = false;
        // Business info is still needed → force not fixed
        businessFixedLocal = false;
      }
      // For tier 3, keep original values (should be fully verified)
      // For tier 0, keep original values

      final requiredDocsRaw = data['requiredDocuments'];
      final List<dynamic> requiredDocsList = requiredDocsRaw is List
          ? requiredDocsRaw
          : [];
      final bool showDocsLocal = requiredDocsList.isNotEmpty;
      final bool kybVerificationExistsLocal = data['kybVerification'] != null;

      setState(() {
        contactFixed = contactFixedLocal;
        businessFixed = businessFixedLocal;
        repFixed = repFixedLocal;
        docsFixed = docsFixedLocal;

        idVerified = idVerifiedLocal;
        idSubmitted = idSubmittedLocal;
        idFailed = idFailedLocal;

        showDocs = showDocsLocal;
        kybVerificationExists = kybVerificationExistsLocal;
      });
    } catch (e) {
      print(e);
    } finally {
      if (mounted && !fromRefresh) {
        setState(() => isLoading = false);
      }
    }
  }

  // ---------- Tier Limits (exact amounts from your user app) ----------
  String get _tier1Limit => '₦10,000';
  String get _tier1Daily => '₦50,000';
  String get _tier1Max => '₦50,000';

  String get _tier2Limit => '₦100,000';
  String get _tier2Daily => '₦500,000';
  String get _tier2Max => '₦500,000';

  String get _tier3Limit => '₦5,000,000';
  String get _tier3Daily => '₦10,000,000';
  String get _tier3Max => '₦100,000,000';

  String get _currentTierLimit {
    switch (userTier) {
      case 3:
        return _tier3Limit;
      case 2:
        return _tier2Limit;
      case 1:
        return _tier1Limit;
      default:
        return '₦0';
    }
  }

  String get _currentTierDaily {
    switch (userTier) {
      case 3:
        return _tier3Daily;
      case 2:
        return _tier2Daily;
      case 1:
        return _tier1Daily;
      default:
        return '₦0';
    }
  }

  String get _currentTierMax {
    switch (userTier) {
      case 3:
        return _tier3Max;
      case 2:
        return _tier2Max;
      case 1:
        return _tier1Max;
      default:
        return '₦0';
    }
  }

  // ---------- Business submission methods (unchanged) ----------
  Future<List<Map<String, dynamic>>> _buildOfficersList(
    Map<String, dynamic> rep,
    Map<String, dynamic> contact,
    Map<String, dynamic> business,
    String uid,
  ) async {
    final officersList = <Map<String, dynamic>>[];
    final directors = rep['directors'] as List<dynamic>? ?? [];
    for (final d in directors) {
      officersList.add({
        'role': d['role'],
        'firstName': d['firstName'],
        'lastName': d['lastName'],
        'nationality': 'NG',
        'addressCountry': 'NG',
        'addressState': (d['state'] as String?)?.toUpperCase() ?? '',
        'addressLine1': d['addressLine1'] ?? '',
        'addressCity': d['city'] ?? '',
        'addressPostalCode': d['postalCode'] ?? '',
        'dateOfBirth': d['dob'] ?? '',
        'email': d['email'] ?? '',
        'phoneNumber': d['phoneNumber'] ?? '',
        'bvn': d['bvn'] ?? '',
        'title': d['title'] ?? '',
        'percentageOwned': int.tryParse(d['percentage'] as String? ?? '0') ?? 0,
      });
    }

    if (officersList.isEmpty) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!userDoc.exists) throw Exception('User document not found');

      final firstName = userDoc.data()?['firstName'] ?? '';
      final lastName = userDoc.data()?['lastName'] ?? '';

      if (firstName.isEmpty || lastName.isEmpty) {
        throw Exception('No name available for default officer');
      }

      officersList.add({
        'role': 'OWNER',
        'firstName': firstName,
        'lastName': lastName,
        'nationality': 'NG',
        'addressCountry': 'NG',
        'addressState': (contact['state'] as String?)?.toUpperCase() ?? '',
        'addressLine1': contact['address'] ?? '',
        'addressCity': contact['city'] ?? '',
        'addressPostalCode': contact['postal'] ?? '',
        'dateOfBirth': '1990-01-01',
        'email': contact['email'] ?? '',
        'phoneNumber': contact['phone'] ?? '',
        'bvn': business['bvn'] ?? '',
        'title': 'CEO',
        'percentageOwned': 100,
      });
    }
    return officersList;
  }

  Map<String, dynamic> _prepareBusinessData(
    Map<String, dynamic> contact,
    Map<String, dynamic> business,
    List<Map<String, dynamic>> officersList,
  ) {
    return {
      'industry': business['industry'] ?? '',
      'registrationType': business['regType'] ?? '',
      'country': 'NG',
      'businessName': business['name'] ?? '',
      'businessBvn': business['bvn'] ?? '',
      'dateOfRegistration': business['regDate'] ?? '',
      'description': business['desc'] ?? '',
      'email': contact['email'] ?? '',
      'mainAddressCountry': 'NG',
      'mainAddressState': (contact['state'] as String?)?.toUpperCase() ?? '',
      'mainAddressLine1': contact['address'] ?? '',
      'mainAddressCity': contact['city'] ?? '',
      'mainAddressPostalCode': contact['postal'] ?? '',
      'registeredAddressCountry': 'NG',
      'registeredAddressState':
          (business['regState'] as String?)?.toUpperCase() ?? '',
      'registeredAddressLine1': business['bizAddress'] ?? '',
      'registeredAddressCity': business['regCity'] ?? '',
      'phoneNumber': contact['phone'] ?? '',
      'officers': officersList,
    };
  }

  Future<void> _submitDetails() async {
    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;

      final fsDoc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(uid)
          .get();
      final dataMap = fsDoc.data()!;

      final contact = dataMap['contact_data'] as Map<String, dynamic>? ?? {};
      final business = dataMap['business_data'] as Map<String, dynamic>? ?? {};
      final rep = dataMap['rep_data'] as Map<String, dynamic>? ?? {};

      final officersList = await _buildOfficersList(
        rep,
        contact,
        business,
        uid,
      );
      final preparedData = _prepareBusinessData(
        contact,
        business,
        officersList,
      );

      String customerId;

      if (dataMap['kybCreation'] == null) {
        final createResponse = await _createBusinessUser(preparedData);
        await fsDoc.reference.set({
          'kybCreation': createResponse,
        }, SetOptions(merge: true));
        customerId = createResponse['data']['id'];
      } else {
        customerId = dataMap['kybCreation']['data']['id'];
      }

      if (dataMap['kybVerification'] == null) {
        final verifyResponse = await _verifyBusinessCustomer(customerId);
        await fsDoc.reference.set({
          'kybVerification': verifyResponse,
        }, SetOptions(merge: true));
      }
      showSnackBar(
        context,
        'Business details submitted. Waiting for document requirements...',
        Colors.green,
      );
      navigateTo(context, HomePage(), type: NavigationType.clearStack);
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _submitDocuments() async {
    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;
      final fsDoc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(uid)
          .get();

      final dataMap = fsDoc.data()!;
      final List<dynamic> requiredDocsRaw = dataMap['requiredDocuments'] ?? [];
      if (requiredDocsRaw.isEmpty) throw Exception("No required documents");

      final customerId = dataMap['kybCreation']['data']['id'] as String;
      int uploadedCount = 0;

      for (var rd in requiredDocsRaw) {
        final String type = rd['type'];
        final String? sudoId = rd['sudoId'] as String?;
        if (rd['status'] == "approved") continue;

        final fileData = dataMap[type] as Map<String, dynamic>?;
        if (fileData == null) throw Exception("Missing data for $type");

        final callData = {
          'customerId': customerId,
          'documentId': sudoId,
          'textData': fileData['textData'] ?? '',
        };
        if (fileData['path'] != null)
          callData['storagePath'] = fileData['path'];
        if (fileData['name'] != null) callData['fileName'] = fileData['name'];

        await FirebaseFunctions.instance
            .httpsCallable('uploadDocument')
            .call(callData);
        uploadedCount++;
      }

      if (uploadedCount > 0) {
        await fsDoc.reference.set({
          'kybDocumentsUploaded': true,
        }, SetOptions(merge: true));
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            uploadedCount == 0
                ? "All documents already approved!"
                : "Successfully uploaded all document(s)",
          ),
        ),
      );
      navigateTo(context, HomePage(), type: NavigationType.clearStack);
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _createBusinessUser(
    Map<String, dynamic> data,
  ) async {
    final res = await callCloudFunctionLogged(
      'sudoCreateBusinessUser',
      source: 'business_app',
      payload: data,
    );
    return res.data;
  }

  Future<Map<String, dynamic>> _verifyBusinessCustomer(
    String customerId,
  ) async {
    final res = await callCloudFunctionLogged(
      'sudoVerifyBusinessCustomer',
      source: 'business_app',
      payload: {'customerId': customerId},
    );
    return res.data;
  }

  @override
  Widget build(BuildContext context) {
    final bool isApproved =
        userTier == 3; // instead of currentKycStatus == "APPROVED"
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          color: primaryColor,
          backgroundColor: Colors.white,
          onRefresh: () => _loadFlags(fromRefresh: true),
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 30),
                    Center(child: Image.asset("assets/image.png", width: 150)),
                    const SizedBox(height: 30),

                    if (isApproved) ...[
                      // ✅ KYB VERIFIED – SHOW LIMITS CARD
                      Center(
                        child: Text(
                          "✓ KYB Verified",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.green[700],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          "Your business is fully verified. You can now transact up to:",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.black.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildLimitsCard(),
                      const SizedBox(height: 80),
                    ] else ...[
                      // ❌ NOT VERIFIED – SHOW UPGRADE STEPS
                      Center(
                        child: Text(
                          "KYB Update Needed",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          "To comply with CBN regulations, please\ncomplete the steps below.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.black.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (currentKycStatus == "AWAITING_DOCUMENT")
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              "Additional business documents required",
                              style: TextStyle(
                                color: Colors.orange[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 40),

                      // BVN Verification row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.file_copy,
                              size: 16,
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "BVN Verification",
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const UpgradeTier(tier: 1),
                              ),
                            ).then((_) => _loadFlags()),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: idVerified
                                    ? Colors.green[600]
                                    : (idFailed
                                          ? Colors.red[600]
                                          : (idSubmitted
                                                ? Colors.orange[700]
                                                : primaryColor)),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: Text(
                                idVerified
                                    ? "Fixed"
                                    : (idFailed
                                          ? "Failed, Tap to Retry"
                                          : (idSubmitted
                                                ? "Submitted"
                                                : "Fix Now")),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),

                      // Business Identification row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.file_copy,
                              size: 16,
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "Business Identification",
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              if (!idVerified) {
                                showSnackBar(
                                  context,
                                  'Please complete BVN verification first',
                                  Colors.orange,
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BusinessInformation(),
                                ),
                              ).then((_) => _loadFlags());
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: businessFixed
                                    ? Colors.green[600]
                                    : (idVerified
                                          ? primaryColor
                                          : Colors.grey[400]),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: Text(
                                businessFixed
                                    ? "Fixed"
                                    : (idVerified ? "Fix Now" : "Fix Previous"),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 80),
                    ],
                  ],
                ),
              ),

              // Loading overlay
              if (isLoading)
                Container(
                  color: Colors.black.withOpacity(0.4),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Limits card – now uses the actual userTier (1,2,3)
  Widget _buildLimitsCard() {
    // If for some reason userTier is 0 but KYB is approved, default to Tier 1
    final displayTier = userTier >= 1 ? userTier : 1;
    final tierLabel = displayTier == 1
        ? "Tier 1"
        : (displayTier == 2 ? "Tier 2" : "Tier 3");

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Text(
                "Your Transaction Limits",
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildLimitRow("Tier", tierLabel),
          _buildLimitRow("Per Transaction", _currentTierLimit),
          _buildLimitRow("Daily Limit", _currentTierDaily),
          _buildLimitRow("Max Account Balance", _currentTierMax),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "These limits apply to all transactions from your business wallet.",
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
