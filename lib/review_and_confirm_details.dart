import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:padi_pay_business/add_first_pos_stand.dart';
import 'package:padi_pay_business/create_account_page.dart';
import 'package:padi_pay_business/rep_details.dart';
import 'package:padi_pay_business/success_page.dart';
import 'package:padi_pay_business/utils.dart';

class ReviewAndConfirmDetails extends StatefulWidget {
  const ReviewAndConfirmDetails({super.key});

  @override
  State<ReviewAndConfirmDetails> createState() =>
      _ReviewAndConfirmDetailsState();
}

class _ReviewAndConfirmDetailsState extends State<ReviewAndConfirmDetails> {
  Map<String, dynamic>? data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          setState(() {
            data = doc.data() as Map<String, dynamic>?;
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching data: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (data == null) {
      return Scaffold(
        body: Center(child: Text('No data available')),
      );
    }

    Map<String, dynamic> posStand = data!.containsKey('posStands') &&
            data!['posStands'] is List &&
            (data!['posStands'] as List).isNotEmpty
        ? (data!['posStands'] as List)[0]
        : {};

    List<String> photoUrls = posStand.containsKey('photoUrls') &&
            posStand['photoUrls'] is List
        ? List<String>.from(posStand['photoUrls'])
        : (posStand.containsKey('photoUrl') && posStand['photoUrl'] != null
            ? [posStand['photoUrl']]
            : []);

    String repIdUrl = data!.containsKey('repIdUrl') ? data!['repIdUrl'] : '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Image.asset("assets/weird_img.png", width: double.infinity),
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          "Review & Confirm Your Details",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Ensure all info is correct",
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 30),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Business Information",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  fontSize: 16,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  navigateTo(
                                      context, CreateAccount());
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.2),
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        "Edit",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Icon(
                                        Icons.edit,
                                        color: Colors.black54,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 20),
                          _buildDetailRow(
                              "Business Name:", data!['businessName'] ?? ''),
                          _buildDetailRow(
                              "Business Type:", data!['businessType'] ?? ''),
                          _buildDetailRow("CAC Reg. Number:",
                              data!['cacRegistrationNumber'] ?? ''),
                          _buildDetailRow("Business Address:",
                              data!['businessAddress'] ?? ''),
                          _buildDetailRow("Business Phone:",
                              '${data!['countryCode'] ?? ''}${data!['businessPhone'] ?? ''}'),
                          _buildDetailRow(
                              "Business Email:", data!['businessEmail'] ?? ''),
                        ],
                      ),
                    ),
                    SizedBox(height: 24),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Representative Information",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  fontSize: 16,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  navigateTo(context,
                                      RepresentativeDetails());
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.2),
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        "Edit",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Icon(
                                        Icons.edit,
                                        color: Colors.black54,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          _buildDetailRow(
                              "Full Name:", data!['repFullName'] ?? ''),
                          _buildDetailRow(
                              "Date of Birth:", data!['repDob'] ?? ''),
                          if (data!.containsKey('gender'))
                            _buildDetailRow("Gender:", data!['gender'] ?? ''),
                          _buildDetailRow("Phone:", data!['repPhone'] ?? ''),
                          _buildDetailRow("Email:", data!['repEmail'] ?? ''),
                          _buildDetailRow("BVN:", data!['repBvn'] ?? ''),
                          if (repIdUrl.isNotEmpty) ...[
                            SizedBox(height: 16),
                            Text(
                              "ID Photo:",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                repIdUrl,
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: 24),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "POS Stand Information",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  fontSize: 16,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  navigateTo(
                                      context, AddPosStand());
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.2),
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        "Edit",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Icon(
                                        Icons.edit,
                                        color: Colors.black54,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          _buildDetailRow("Name:", posStand['name'] ?? ''),
                          _buildDetailRow(
                              "Location:", posStand['location'] ?? ''),
                          if (photoUrls.isNotEmpty) ...[
                            SizedBox(height: 16),
                            Text(
                              "Photos:",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 8),
                            SizedBox(
                              height: 120,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: photoUrls.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        photoUrls[index],
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: 40),
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (context) => const SuccessBottomSheet(
                            actionText: "Continue",
                            title: "Your Business Account is Ready",
                            description:
                                "You can now start accepting payments and manage your POS",
                          ),
                          isScrollControlled: true,
                        );
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        width: MediaQuery.of(context).size.width,
                        child: Text(
                          "Confirm & Create Account",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}