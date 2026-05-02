import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padi_pay_business/feedback.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/kyb/business_docs.dart';
import 'package:padi_pay_business/kyb/business_info.dart';
import 'package:padi_pay_business/kyb/contact_and_address.dart';
import 'package:padi_pay_business/kyb/rep_details.dart';
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

  // Identity verification flags (from users.qoreIdData.verification)
  bool idSubmitted = false;
  bool idVerified = false;
  // When QoreID metadata.match is explicitly false the verification failed
  bool idFailed = false;

  bool isLoading = false;
  bool showDocs = false;
  String? currentKycStatus;
  bool kybVerificationExists = false;

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(user.uid)
        .get();

    // Don't bail out — business doc may not exist yet, but BVN still needs checking
    final data = doc.exists ? doc.data()! : <String, dynamic>{};
    if (data['safehavenData']['virtualAccount']!=null) {
      currentKycStatus = "APPROVED";
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      return;
    }

    final userData = userDoc.data() ?? <String, dynamic>{};
    final qoreData =
        userData['qoreIdData'] as Map<String, dynamic>? ?? <String, dynamic>{};

    final bvnVerif = qoreData['bvnVerificationNoFace'] as Map<String, dynamic>?;

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

    final userTier = (userData['sudoData']?['tier'] as num?)?.toInt() ?? 0;

    final hasCustomerCreation =
        (userData['sudoData'] as Map<String, dynamic>?)?['customerCreation'] !=
        null;

    final bool fallbackWouldFire =
        !bvnVerifiedFieldExists &&
        hasBvn &&
        (qoreVerified || userTier >= 1 || hasCustomerCreation);

    final bool effectiveVerified = bvnVerifiedDirect || fallbackWouldFire;
    final bool effectiveFailed = bvnExplicitlyFalse;

    setState(() {
      contactFixed = data['contact_fixed'] ?? false;
      businessFixed = data['business_fixed'] ?? false;
      repFixed = data['rep_fixed'] ?? false;
      docsFixed = data['docs_fixed'] ?? false;

      idVerified = effectiveVerified;
      idSubmitted = effectiveVerified;
      idFailed = effectiveFailed;

      final requiredDocsRaw = data['requiredDocuments'];
      final List<dynamic> requiredDocsList = requiredDocsRaw is List
          ? requiredDocsRaw
          : [];
      showDocs = requiredDocsList.isNotEmpty;

      kybVerificationExists = data['kybVerification'] != null;
    });
  }

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

  // ──────────────────────────────────────────────────────────────
  //  Submit business details (create + verify) → triggers webhook → shows docs
  // ──────────────────────────────────────────────────────────────
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
      setState(() => isLoading = false);
      await _loadFlags(); // webhook may have fired already
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  Submit documents using the sudoId saved by webhook
  // ──────────────────────────────────────────────────────────────── ───────────────────────

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

        // SKIP if this document is already approved
        if (rd['status'] == "approved") {
          continue;
        }

        final fileData = dataMap[type] as Map<String, dynamic>?;
        if (fileData == null) {
          throw Exception("Missing data for $type");
        }

        final callData = {
          'customerId': customerId,
          'documentId': sudoId,
          'textData': fileData['textData'] ?? '',
        };

        if (fileData['path'] != null) {
          callData['storagePath'] = fileData['path'];
        }
        if (fileData['name'] != null) {
          callData['fileName'] = fileData['name'];
        }

        await FirebaseFunctions.instance
            .httpsCallable('uploadDocument')
            .call(callData);

        uploadedCount++;
      }

      // Only mark as uploaded if we actually uploaded something
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
      setState(() => isLoading = false);
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
    final isApproved = currentKycStatus == "APPROVED";

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          color: primaryColor,
          backgroundColor: Colors.white,
          onRefresh: _loadFlags,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 30),
                  Center(child: Image.asset("assets/image.png", width: 150)),
                  const SizedBox(height: 30),

                  Center(
                    child: Text(
                      isApproved ? "KYB Verified" : "KYB Update Needed",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (!isApproved)
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

                  // Show banner asking user to complete BVN if not verified
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
                  // ==================== CONTACT ====================
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

                  // const SizedBox(height: 40),

                  // ==================== CONTACT ====================
                  // Row(
                  //   children: [
                  //     Container(
                  //       padding: const EdgeInsets.all(12),
                  //       decoration: BoxDecoration(
                  //         color: primaryColor.withOpacity(0.1),
                  //         shape: BoxShape.circle,
                  //       ),
                  //       child: Icon(
                  //         Icons.file_copy,
                  //         size: 16,
                  //         color: primaryColor,
                  //       ),
                  //     ),
                  //     const SizedBox(width: 10),
                  //     Text(
                  //       "Contact & Address Information",
                  //       style: TextStyle(
                  //         color: Colors.grey.shade500,
                  //         fontSize: 12,
                  //       ),
                  //     ),
                  //     const Spacer(),
                  //     GestureDetector(
                  //       onTap: () {
                  //         if (!idVerified) {
                  //           showSnackBar(
                  //             context,
                  //             'Please complete BVN verification first',
                  //             Colors.orange,
                  //           );
                  //           return;
                  //         }
                  //         Navigator.push(
                  //           context,
                  //           MaterialPageRoute(
                  //             builder: (_) => ContactAndAddress(),
                  //           ),
                  //         ).then((_) => _loadFlags());
                  //       },
                  //       child: Container(
                  //         padding: const EdgeInsets.symmetric(
                  //           horizontal: 13,
                  //           vertical: 8,
                  //         ),
                  //         decoration: BoxDecoration(
                  //           color: contactFixed
                  //               ? Colors.green[600]
                  //               : (idVerified
                  //                     ? primaryColor
                  //                     : Colors.grey[400]),
                  //           borderRadius: BorderRadius.circular(25),
                  //         ),
                  //         child: Text(
                  //           contactFixed
                  //               ? "Fixed"
                  //               : (idVerified ? "Fix Now" : "Fix Previous"),
                  //           style: const TextStyle(
                  //             color: Colors.white,
                  //             fontSize: 12,
                  //           ),
                  //         ),
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  const SizedBox(height: 40),

                  // ==================== BUSINESS INFO ====================
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

                  // const SizedBox(height: 40),

                  // ==================== DIRECTORS ====================
                  // Row(
                  //   children: [
                  //     Container(
                  //       padding: const EdgeInsets.all(12),
                  //       decoration: BoxDecoration(
                  //         color: primaryColor.withOpacity(0.1),
                  //         shape: BoxShape.circle,
                  //       ),
                  //       child: Icon(
                  //         Icons.file_copy,
                  //         size: 16,
                  //         color: primaryColor,
                  //       ),
                  //     ),
                  //     // const SizedBox(width: 10),
                  //     Text(
                  //       "Business Director Summary",
                  //       style: TextStyle(
                  //         color: Colors.grey.shade500,
                  //         fontSize: 12,
                  //       ),
                  //     ),
                  //     const Spacer(),
                  //     GestureDetector(
                  //       onTap: () {
                  //         if (!idVerified) {
                  //           showSnackBar(
                  //             context,
                  //             'Please complete BVN verification first',
                  //             Colors.orange,
                  //           );
                  //           return;
                  //         }
                  //         Navigator.push(
                  //           context,
                  //           MaterialPageRoute(builder: (_) => RepDetails()),
                  //         ).then((_) => _loadFlags());
                  //       },
                  //       child: Container(
                  //         padding: const EdgeInsets.symmetric(
                  //           horizontal: 13,
                  //           vertical: 8,
                  //         ),
                  //         decoration: BoxDecoration(
                  //           color: repFixed
                  //               ? Colors.green[600]
                  //               : (idVerified
                  //                     ? primaryColor
                  //                     : Colors.grey[400]),
                  //           borderRadius: BorderRadius.circular(25),
                  //         ),
                  //         child: Text(
                  //           repFixed
                  //               ? "Fixed"
                  //               : (idVerified ? "Fix Now" : "Fix Previous"),
                  //           style: const TextStyle(
                  //             color: Colors.white,
                  //             fontSize: 12,
                  //           ),
                  //         ),
                  //       ),
                  //     ),
                  //   ],
                  // ),

                  // ==================== DOCUMENTS (only when Sudo tells us) ====================
                  // if (currentKycStatus == "AWAITING_DOCUMENT") ...[
                  //   const SizedBox(height: 40),
                  //   Row(
                  //     children: [
                  //       Container(
                  //         padding: const EdgeInsets.all(12),
                  //         decoration: BoxDecoration(
                  //           color: primaryColor.withOpacity(0.1),
                  //           shape: BoxShape.circle,
                  //         ),
                  //         child: Icon(
                  //           Icons.file_copy,
                  //           size: 16,
                  //           color: primaryColor,
                  //         ),
                  //       ),
                  //       const SizedBox(width: 10),
                  //       Text(
                  //         "Official Business Documentation",
                  //         style: TextStyle(
                  //           color: Colors.grey.shade500,
                  //           fontSize: 12,
                  //         ),
                  //       ),
                  //       const Spacer(),
                  //       GestureDetector(
                  //         onTap: () {
                  //           if (!idVerified) {
                  //             showSnackBar(
                  //               context,
                  //               'Please complete BVN verification first',
                  //               Colors.orange,
                  //             );
                  //             return;
                  //           }
                  //           Navigator.push(
                  //             context,
                  //             MaterialPageRoute(builder: (_) => BusinessDocs()),
                  //           ).then((_) => _loadFlags());
                  //         },
                  //         child: Container(
                  //           padding: const EdgeInsets.symmetric(
                  //             horizontal: 13,
                  //             vertical: 8,
                  //           ),
                  //           decoration: BoxDecoration(
                  //             color: docsFixed
                  //                 ? Colors.green[600]
                  //                 : (idVerified
                  //                       ? primaryColor
                  //                       : Colors.grey[400]),
                  //             borderRadius: BorderRadius.circular(25),
                  //           ),
                  //           child: Text(
                  //             docsFixed
                  //                 ? "Fixed"
                  //                 : (idVerified ? "Fix Now" : "Fix Previous"),
                  //             style: const TextStyle(
                  //               color: Colors.white,
                  //               fontSize: 12,
                  //             ),
                  //           ),
                  //         ),
                  //       ),
                  //     ],
                  //   ),
                  // ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
