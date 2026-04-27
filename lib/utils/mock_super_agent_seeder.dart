import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Seeds mock Super Agent data for testing/demo purposes.
/// Call this function to populate a test super agent account with commission data.
Future<void> seedMockSuperAgentData({
  required String email,
  required String businessName,
}) async {
  try {
    // Find the user by email
    final userList = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (userList.docs.isEmpty) {
      debugPrint('❌ User not found with email: $email');
      return;
    }

    final userId = userList.docs.first.id;
    debugPrint('✅ Found user: $userId');

    // Generate a unique super agent referral code
    final referralCode = 'PADI-SA-${userId.substring(0, 6).toUpperCase()}';

    // Update the business document
    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(userId)
        .set({
      'isSuperAgent': true,
      'superAgentReferralCode': referralCode,
      'superAgentStars': 4,
      'superAgentTotalEarnings': 1250000, // ₦1.25M total
      'superAgentAvailableEarnings': 500000, // ₦500K available
      'businessName': businessName,
      'email': email,
    }, SetOptions(merge: true));

    debugPrint('✅ Updated business doc with super agent flag');

    // Create mock commission documents
    final mockCommissions = [
      {
        'superAgentBusinessId': userId,
        'businessId': 'bus_001_demo',
        'amount': 5.0,
        'type': 'nip_transfer',
        'status': 'credited',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 1))),
        'referralCode': referralCode,
      },
      {
        'superAgentBusinessId': userId,
        'businessId': 'bus_001_demo',
        'amount': 5000.0,
        'type': 'business_verified_bonus',
        'status': 'credited',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 2))),
        'referralCode': referralCode,
      },
      {
        'superAgentBusinessId': userId,
        'businessId': 'bus_002_demo',
        'amount': 5.0,
        'type': 'nip_transfer',
        'status': 'credited',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 3))),
        'referralCode': referralCode,
      },
      {
        'superAgentBusinessId': userId,
        'businessId': 'bus_002_demo',
        'amount': 5.0,
        'type': 'nip_transfer',
        'status': 'credited',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 4))),
        'referralCode': referralCode,
      },
      {
        'superAgentBusinessId': userId,
        'businessId': 'bus_002_demo',
        'amount': 5000.0,
        'type': 'business_verified_bonus',
        'status': 'credited',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 5))),
        'referralCode': referralCode,
      },
      {
        'superAgentBusinessId': userId,
        'businessId': 'bus_003_demo',
        'amount': 5.0,
        'type': 'nip_transfer',
        'status': 'credited',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 6))),
        'referralCode': referralCode,
      },
      {
        'superAgentBusinessId': userId,
        'businessId': 'bus_003_demo',
        'amount': 5.0,
        'type': 'nip_transfer',
        'status': 'credited',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 7))),
        'referralCode': referralCode,
      },
      {
        'superAgentBusinessId': userId,
        'businessId': 'bus_004_demo',
        'amount': 5000.0,
        'type': 'business_verified_bonus',
        'status': 'credited',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 8))),
        'referralCode': referralCode,
      },
      {
        'superAgentBusinessId': userId,
        'businessId': 'bus_005_demo',
        'amount': 5.0,
        'type': 'nip_transfer',
        'status': 'credited',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 9))),
        'referralCode': referralCode,
      },
      {
        'superAgentBusinessId': userId,
        'businessId': 'bus_001_demo',
        'amount': 5.0,
        'type': 'nip_transfer',
        'status': 'credited',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 10))),
        'referralCode': referralCode,
      },
    ];

    // Clear old mock commissions for this super agent
    final oldCommissions = await FirebaseFirestore.instance
        .collection('superAgentCommissions')
        .where('superAgentBusinessId', isEqualTo: userId)
        .get();

    for (final doc in oldCommissions.docs) {
      await doc.reference.delete();
    }

    // Add new mock commissions
    final batch = FirebaseFirestore.instance.batch();
    for (final commission in mockCommissions) {
      final docRef = FirebaseFirestore.instance
          .collection('superAgentCommissions')
          .doc();
      batch.set(docRef, commission);
    }
    await batch.commit();

    debugPrint('✅ Created ${mockCommissions.length} mock commission records');

    // Update settings if needed
    await FirebaseFirestore.instance
        .collection('settings')
        .doc('superAgentProgram')
        .set({
      'perNipTransferAmount': 5,
      'verifiedBusinessBonusAmount': 5000,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint('✅ Updated super agent program settings');
    debugPrint('✅ Mock data seeding complete!');
    debugPrint('📌 Referral Code: $referralCode');
    debugPrint('📊 Total Earnings: ₦1,250,000');
    debugPrint('💰 Available Earnings: ₦500,000');
    debugPrint('⭐ Stars: 4/5');
    debugPrint('🎯 Mock Referrals: 5 businesses');
  } catch (e, st) {
    debugPrint('❌ Error seeding mock data: $e');
    debugPrint(st.toString());
  }
}
