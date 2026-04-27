
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
import 'package:padi_pay_business/kyb/identity_verification.dart';
import 'package:padi_pay_business/kyb/rep_details.dart';
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
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(user.uid)
        .get();

    if (!doc.exists) return;

    final data = doc.data()!;

    // Load user verification status (qoreIdData.verification) from users collection
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDoc.exists ? (userDoc.data() ?? <String, dynamic>{}) : <String, dynamic>{};
    final qoreData = userData['qoreIdData'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final verification = qoreData['verification'] as Map<String, dynamic>? ?? <String, dynamic>{};

    setState(() {
      contactFixed = data['contact_fixed'] ?? false;
      businessFixed = data['business_fixed'] ?? false;
      repFixed = data['rep_fixed'] ?? false;
      docsFixed = data['docs_fixed'] ?? false;

      // Identity verification flags
      idSubmitted = verification['submitted'] == true;
      // Use metadata.match as the authoritative verification boolean stored by QoreID
      final metadata = verification['metadata'] as Map<String, dynamic>? ?? <String, dynamic>{};
      idVerified = metadata['match'] == true;
      // If metadata.match exists and is false, mark it as a failed verification
      idFailed = metadata.containsKey('match') && metadata['match'] == false;

      // SAFE CAST: if requiredDocuments is null, not a list, or a map → treat as empty
      final requiredDocsRaw = data['requiredDocuments'];
      final List<dynamic> requiredDocsList = requiredDocsRaw is List
          ? requiredDocsRaw
          : [];
      showDocs = requiredDocsList.isNotEmpty;

      currentKycStatus = data['kycStatus'] as String?;
      kybVerificationExists = data['kybVerification'] != null;
    });
    // navigateTo(context, BusinessUpgradeManager(),type:NavigationType.replace);
  }

  bool get infoComplete => contactFixed && businessFixed && repFixed && idVerified;

  // ──────────────────────────────────────────────────────────────
  //  Your original methods – copied exactly from your working code
  // ──────────────────────────────────────────────────────────────
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
      navigateTo(context, HomePage(),type: NavigationType.clearStack);
    } catch (e) {
      print( e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => isLoading = false);
      await _loadFlags(); // webhook may have fired already
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  Submit documents using the anchorId saved by webhook
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
        final String? anchorId = rd['anchorId'] as String?;

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
          'documentId': anchorId,
          'textData': fileData['textData'] ?? '',
        };

        if (fileData['path'] != null) {
          callData['storagePath'] = fileData['path'];
        }
        if (fileData['name'] != null) {
          callData['fileName'] = fileData['name'];
        }

        await FirebaseFunctions.instance.httpsCallable('uploadDocument').call(callData);

        uploadedCount++;
      }

      // Only mark as uploaded if we actually uploaded something
      if (uploadedCount > 0) {
        await fsDoc.reference.set({'kybDocumentsUploaded': true}, SetOptions(merge: true));
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
        backgroundColor: Colors.green,
        content: Text(uploadedCount == 0
            ? "All documents already approved!"
            : "Successfully uploaded all document(s)"),
      ));

      navigateTo(context, HomePage(), type: NavigationType.clearStack);
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }
   Future<Map<String, dynamic>> _createBusinessUser(
    Map<String, dynamic> data,
  ) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('createGetanchorBusinessUser')
        .call(data);
    return res.data;
  }

  Future<Map<String, dynamic>> _verifyBusinessCustomer(
    String customerId,
  ) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('verifyBusinessCustomer')
        .call({'customerId': customerId});
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
                            builder: (_) => IdentityVerificationStep1Page(),
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
                                : (idFailed ? Colors.red[600] : (idSubmitted ? Colors.orange[700] : primaryColor)),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Text(
                            idVerified ? "Verified" : (idFailed ? "Failed, Tap to Retry" : (idSubmitted ? "Submitted" : "Fix Now")),
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
                        "Contact & Address Information",
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          if (!idVerified) {
                            showSnackBar(context, 'Please complete BVN verification first', Colors.orange);
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ContactAndAddress(),
                            ),
                          ).then((_) => _loadFlags());
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: contactFixed
                                ? Colors.green[600]
                                : (idVerified ? primaryColor : Colors.grey[400]),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Text(
                            contactFixed ? "Fixed" : (idVerified ? "Fix Now" : "Verify BVN"),
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
                            showSnackBar(context, 'Please complete BVN verification first', Colors.orange);
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
                                : (idVerified ? primaryColor : Colors.grey[400]),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Text(
                            businessFixed ? "Fixed" : (idVerified ? "Fix Now" : "Verify BVN"),
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

                  // ==================== DIRECTORS ====================
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
                        "Business Director Summary",
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          if (!idVerified) {
                            showSnackBar(context, 'Please complete BVN verification first', Colors.orange);
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => RepDetails()),
                          ).then((_) => _loadFlags());
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: repFixed ? Colors.green[600] : (idVerified ? primaryColor : Colors.grey[400]),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Text(
                            repFixed ? "Fixed" : (idVerified ? "Fix Now" : "Verify BVN"),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ==================== DOCUMENTS (only when Anchor tells us) ====================
                  if (currentKycStatus == "AWAITING_DOCUMENT") ...[
                    const SizedBox(height: 40),
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
                          "Official Business Documentation",
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            if (!idVerified) {
                              showSnackBar(context, 'Please complete BVN verification first', Colors.orange);
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => BusinessDocs()),
                            ).then((_) => _loadFlags());
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: docsFixed
                                  ? Colors.green[600]
                                  : (idVerified ? primaryColor : Colors.grey[400]),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Text(
                              docsFixed ? "Fixed" : (idVerified ? "Fix Now" : "Verify BVN"),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 60),

                  // ==================== SUBMIT BUTTON ====================
                  if ((!kybVerificationExists && infoComplete) ||
                      (currentKycStatus == "AWAITING_DOCUMENT" &&
                          showDocs &&
                          docsFixed))
                    GestureDetector(
                      onTap: isLoading
                          ? null
                          : (kybVerificationExists
                                ? _submitDocuments
                                : _submitDetails),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  kybVerificationExists
                                      ? "Submit Documents"
                                      : "Submit Business Details",
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ),

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