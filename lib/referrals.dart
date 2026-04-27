import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  String _referralCode = '';
  int _totalReferrals = 0;
  bool _loading = true;
  bool _isGenerating = false;
  List<Map<String, dynamic>> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      setState(() {
        _referralCode = (data['referralCode'] ?? '').toString();
        _totalReferrals = (data['referralCount'] ?? 0) as int;
      });

      final q = await FirebaseFirestore.instance
          .collection('referrals')
          .where('referrerUid', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
      setState(() {
        _recent = q.docs.map((d) => d.data()).cast<Map<String, dynamic>>().toList();
      });
    } catch (e) {
      print('Error loading referrals: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _referralCode));
    showToast('Referral code copied', Colors.green);
    Future.delayed(const Duration(seconds: 15), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  Future<void> _generateAndSaveReferralCode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isGenerating = true);
    try {
      final code = await generateUniqueReferralCode();
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userRef.set({'referralCode': code, 'referralCount': 0}, SetOptions(merge: true));
      setState(() {
        _referralCode = code;
        _totalReferrals = 0;
      });
      showToast('Referral code generated', Colors.green);
    } catch (e) {
      print('Error generating referral code: $e');
      showToast('Error generating referral code', Colors.red);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _shareCode() async {
    if (_isGenerating) return;
    if (_referralCode.isEmpty) {
      await _generateAndSaveReferralCode();
    }
    if (_referralCode.isNotEmpty) {
      Share.share('Join Padi Pay and use my referral code $_referralCode to sign up!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final earningsPerReferral = 500; // mock value
    final totalEarned = _totalReferrals * earningsPerReferral;

    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(bottom: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Icon(
                      Icons.arrow_back_ios,
                      color: Colors.black45,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Text(
                    "Referrals",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: primaryColor.withValues(alpha: 0.07),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            _loading
                                ? SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                                  )
                                : Text(
                                    '$_totalReferrals',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor,
                                    ),
                                  ),
                            Text(
                              'Total Referrals',
                              style: TextStyle(
                                fontSize: 12,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 10.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                       
                          Text(
                            'Your Referral Code',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                border: Border.all(color: Colors.grey.shade50),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _referralCode.isNotEmpty ? _referralCode : '—',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              border: Border.all(color: Colors.grey.shade50),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: IconButton(
                              icon: Icon(
                                FontAwesomeIcons.copy,
                                color: Colors.grey,
                              ),
                              onPressed: _referralCode.isNotEmpty ? _copyCode : null,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _shareCode,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: _isGenerating ? Colors.grey : primaryColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: _isGenerating
                                    ? Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        ),
                                      )
                                    : Row(mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _referralCode.isEmpty ? Icons.add : Icons.share_outlined,
                                            size: 17,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            _referralCode.isEmpty ? "Generate Code" : "Share Code",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
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
                      SizedBox(height: 12),
                      Text(
                        'Earn up to 0.25% of your referrals\' monthly transaction volume',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(width: 15),
                          Text(
                            'Earnings Summary',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          Transform.translate(
                            offset: Offset(2, -2),
                            child: Image.asset(
                              "assets/arrow.png",
                              width: MediaQuery.of(context).size.width * 0.2,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Total Earned',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              Text(
                                '₦${totalEarned.toString()}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Text(
                                'This Month',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              Text(
                                '₦${(_recent.length * earningsPerReferral).toString()}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Container(
                        margin: EdgeInsets.all(16),
                        padding: EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Pending Rewards',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: primaryColor.withValues(alpha: 0.6),
                              ),
                            ),
                            Spacer(),
                            Text(
                              '₦${(totalEarned * 0.1).toInt()}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),              SizedBox(height: 16),
              if (_recent.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recent Referrals', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height:8),
                    ..._recent.map((r) {
                      final ts = r['createdAt'] as Timestamp?;
                      final date = ts?.toDate();
                      final dateStr = date != null ? '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}' : '';
                      final name = (r['referredName'] ?? 'Unknown').toString();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.person_outline),
                        title: Text(name),
                        subtitle: Text(dateStr),
                      );
                    }),
                  ],
                )
              else if (!_loading)
                Text('No referrals yet', style: TextStyle(color: Colors.grey)),            ],
          ),
        ),
      ),
    );
  }
}
