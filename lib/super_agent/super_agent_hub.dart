import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class SuperAgentHubPage extends StatefulWidget {
  const SuperAgentHubPage({super.key});

  @override
  State<SuperAgentHubPage> createState() => _SuperAgentHubPageState();
}

class _SuperAgentHubPageState extends State<SuperAgentHubPage> {
  final NumberFormat _nairaFormatter = NumberFormat.currency(
    locale: 'en_NG',
    symbol: '₦',
    decimalDigits: 0,
  );

  bool _loading = true;
  bool _isSuperAgent = false;

  String _referralCode = '';
  int _stars = 0;
  num _totalEarnings = 0;
  num _availableEarnings = 0;
  num _perTransferAmount = 5;
  num _verifiedBusinessBonusAmount = 5000;
  Map<int, num> _starThresholds = {
    1: 0,
    2: 10000,
    3: 30000,
    4: 70000,
    5: 150000,
  };

  List<Map<String, dynamic>> _commissions = [];
  List<Map<String, dynamic>> _referralSummaries = [];
  bool _showAllCommissions = false;

  @override
  void initState() {
    super.initState();
    _loadSuperAgentData();
  }

  Future<void> _loadSuperAgentData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final isMockSuperAgent =
        (user.email ?? '').trim().toLowerCase() == 'justefe99@gmail.com';

    if (isMockSuperAgent) {
      if (mounted) {
        setState(() {
          _isSuperAgent = true;
          _referralCode = 'PADI-SA-MOCK99';
          _stars = 4;
          _totalEarnings = 245000;
          _availableEarnings = 86500;
          _perTransferAmount = 5;
          _verifiedBusinessBonusAmount = 5000;
          _starThresholds = {
            1: 0,
            2: 10000,
            3: 30000,
            4: 70000,
            5: 150000,
          };
          _commissions = [
            {
              'id': 'mock-1',
              'type': 'business_verified_bonus',
              'amount': 5000,
              'businessId': 'biz_mock_alpha',
              'status': 'credited',
              'createdAt': DateTime.now().subtract(const Duration(days: 1)),
            },
            {
              'id': 'mock-2',
              'type': 'nip_transfer',
              'amount': 5,
              'businessId': 'biz_mock_alpha',
              'status': 'credited',
              'createdAt': DateTime.now().subtract(const Duration(hours: 4)),
            },
            {
              'id': 'mock-3',
              'type': 'nip_transfer',
              'amount': 5,
              'businessId': 'biz_mock_bravo',
              'status': 'credited',
              'createdAt': DateTime.now().subtract(const Duration(hours: 2)),
            },
          ];
          _referralSummaries = [
            {
              'businessId': 'biz_mock_alpha',
              'totalEarned': 15350,
              'nipTransfers': 1070,
              'hasVerificationBonus': true,
              'firstSeen': DateTime.now().subtract(const Duration(days: 21)),
            },
            {
              'businessId': 'biz_mock_bravo',
              'totalEarned': 7280,
              'nipTransfers': 456,
              'hasVerificationBonus': true,
              'firstSeen': DateTime.now().subtract(const Duration(days: 12)),
            },
          ];
          _loading = false;
        });
      }
      return;
    }

    try {
      final businessSnap = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(user.uid)
          .get();

      if (!businessSnap.exists) {
        if (mounted) {
          setState(() {
            _isSuperAgent = false;
            _loading = false;
          });
        }
        return;
      }

      final businessData = businessSnap.data() ?? {};
      final isSuperAgent = businessData['isSuperAgent'] == true;

      if (!isSuperAgent) {
        if (mounted) {
          setState(() {
            _isSuperAgent = false;
            _loading = false;
          });
        }
        return;
      }

      final settingsSnap = await FirebaseFirestore.instance
          .collection('settings')
          .doc('superAgentProgram')
          .get();
      final settingsData = settingsSnap.data() ?? {};
        final thresholds = _parseStarThresholds(settingsData['starThresholds']);

      final byBusinessId = await FirebaseFirestore.instance
          .collection('superAgentCommissions')
          .where('superAgentBusinessId', isEqualTo: user.uid)
          .get();

      final byLegacyId = await FirebaseFirestore.instance
          .collection('superAgentCommissions')
          .where('superAgentId', isEqualTo: user.uid)
          .get();

      final mergedMap = <String, Map<String, dynamic>>{};

      for (final doc in byBusinessId.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        mergedMap[doc.id] = data;
      }
      for (final doc in byLegacyId.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        mergedMap[doc.id] = data;
      }

      final commissions = mergedMap.values.toList()
        ..sort((a, b) {
          final ad = _toDateTime(a['createdAt']);
          final bd = _toDateTime(b['createdAt']);
          return bd.compareTo(ad);
        });

      final referralByBusiness = <String, Map<String, dynamic>>{};
      for (final item in commissions) {
        final businessId = (item['businessId'] ?? '').toString();
        if (businessId.isEmpty) continue;

        final amount = _toNum(item['amount']);
        final type = (item['type'] ?? '').toString();
        final createdAt = _toDateTime(item['createdAt']);

        final existing = referralByBusiness[businessId];
        if (existing == null) {
          referralByBusiness[businessId] = {
            'businessId': businessId,
            'totalEarned': amount,
            'nipTransfers': type == 'nip_transfer' ? 1 : 0,
            'hasVerificationBonus':
                type == 'business_verified_bonus' ||
                type == 'first_transaction_bonus',
            'firstSeen': createdAt,
          };
        } else {
          existing['totalEarned'] = _toNum(existing['totalEarned']) + amount;
          if (type == 'nip_transfer') {
            existing['nipTransfers'] = (existing['nipTransfers'] as int) + 1;
          }
          if (type == 'business_verified_bonus' ||
              type == 'first_transaction_bonus') {
            existing['hasVerificationBonus'] = true;
          }
          final firstSeen = _toDateTime(existing['firstSeen']);
          if (createdAt.isBefore(firstSeen)) {
            existing['firstSeen'] = createdAt;
          }
        }
      }

      final referralSummaries = referralByBusiness.values.toList()
        ..sort((a, b) {
          final ad = _toDateTime(a['firstSeen']);
          final bd = _toDateTime(b['firstSeen']);
          return bd.compareTo(ad);
        });

      if (mounted) {
        setState(() {
          _isSuperAgent = true;
          _referralCode = (businessData['superAgentReferralCode'] ?? '').toString();
          _stars = (businessData['superAgentStars'] ?? 0) as int;
          _totalEarnings = _toNum(businessData['superAgentTotalEarnings']);
          _availableEarnings = _toNum(businessData['superAgentAvailableEarnings']);
          _perTransferAmount = _toNum(settingsData['perNipTransferAmount'], fallback: 5);
          _verifiedBusinessBonusAmount =
              _toNum(settingsData['verifiedBusinessBonusAmount'], fallback: 5000);
          _starThresholds = thresholds;
          _commissions = commissions;
          _referralSummaries = referralSummaries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSuperAgent = false;
          _loading = false;
        });
      }
    }
  }

  DateTime _toDateTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  num _toNum(dynamic raw, {num fallback = 0}) {
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw) ?? fallback;
    return fallback;
  }

  String _formatNaira(num amount) {
    return _nairaFormatter.format(amount);
  }

  Map<int, num> _parseStarThresholds(dynamic raw) {
    final defaults = {
      1: 0,
      2: 10000,
      3: 30000,
      4: 70000,
      5: 150000,
    };
    if (raw is! Map) return defaults;

    final parsed = <int, num>{};
    for (int i = 1; i <= 5; i++) {
      final dynamic v = raw[i] ?? raw['$i'];
      parsed[i] = _toNum(v, fallback: defaults[i]!);
    }
    return parsed;
  }

  String _typeLabel(String type) {
    if (type == 'nip_transfer') return 'NIP Transfer Commission';
    if (type == 'business_verified_bonus' || type == 'first_transaction_bonus') {
      return 'Business Verification Bonus';
    }
    return 'Commission';
  }

  String _superAgentTierName(int stars) {
    if (stars >= 5) return 'My Padi';
    if (stars == 4) return 'Who Goes';
    if (stars == 3) return 'Clear Road';
    if (stars == 2) return 'Boss Man';
    if (stars == 1) return 'Sharp Guy';
    return 'Unranked';
  }

  Map<String, dynamic> _nextTierProgress() {
    final current = _totalEarnings;
    final currentStar = _stars.clamp(0, 5);

    if (currentStar >= 5) {
      return {
        'hasNext': false,
        'nextStar': 5,
        'nextTierName': _superAgentTierName(5),
        'remaining': 0,
        'progress': 1.0,
      };
    }

    final nextStar = currentStar + 1;
    final currentThreshold = _starThresholds[currentStar == 0 ? 1 : currentStar] ?? 0;
    final nextThreshold = _starThresholds[nextStar] ?? currentThreshold;
    final span = (nextThreshold - currentThreshold).toDouble();
    final covered = (current - currentThreshold).toDouble();
    final progress = span <= 0 ? 0.0 : (covered / span).clamp(0.0, 1.0);
    final remaining = (nextThreshold - current).clamp(0, 1 << 62);

    return {
      'hasNext': true,
      'nextStar': nextStar,
      'nextTierName': _superAgentTierName(nextStar),
      'remaining': remaining,
      'progress': progress,
    };
  }

  Future<void> _copyCode() async {
    if (_referralCode.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _referralCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Referral code copied')),
    );
    Future.delayed(const Duration(seconds: 15), () async {
      await Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  Future<void> _shareCode() async {
    if (_referralCode.isEmpty) return;
    await Share.share(
      'Use my PadiPay Super Agent code $_referralCode to sign up your business account.',
    );
  }

  num _thresholdForTier(int tier) {
    return _starThresholds[tier] ??
        _toNum(_starThresholds['$tier'], fallback: tier == 1 ? 0 : 0);
  }

  void _showProgramRewardsInfo() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How Program Rewards Work',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  'Transfer Reward: You earn ${_formatNaira(_perTransferAmount)} each time a referred business completes a NIP transfer that qualifies.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Verification Reward: You earn a one-time ${_formatNaira(_verifiedBusinessBonusAmount)} when a referred business gets verified.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Recent Commissions shows your latest earnings events. Available is what can be withdrawn now.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTierLadder() {
    final currentTier = _stars.clamp(0, 5);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tier Ladder',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                ...List.generate(5, (index) {
                  final tier = index + 1;
                  final unlocked = currentTier >= tier;
                  final current = currentTier == tier;
                  final threshold = _thresholdForTier(tier);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: current
                          ? const Color(0xFFEFF6FF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: current
                            ? const Color(0xFF2563EB)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          unlocked ? Icons.verified_rounded : Icons.lock_outline,
                          color: unlocked
                              ? const Color(0xFF16A34A)
                              : Colors.grey.shade500,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$tier★ ${_superAgentTierName(tier)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Milestone: ${_formatNaira(threshold)} total earned',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (current)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              'Current',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tierProgress = _nextTierProgress();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        title: const Text('Super Agent Hub'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_isSuperAgent
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'This account is not enabled as a Super Agent yet. Contact admin to enable Super Agent status.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSuperAgentData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF173EA8), Color(0xFF4C2FB8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Referral Code',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _referralCode.isEmpty ? 'Not available' : _referralCode,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _copyCode,
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: Colors.white.withValues(alpha: 0.7),
                                      ),
                                    ),
                                    child: const Text(
                                      'Copy Code',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _shareCode,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: const Color(0xFF1E3A8A),
                                    ),
                                    child: const Text('Share Code'),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tier Progress',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            if (tierProgress['hasNext'] == true) ...[
                              Text(
                                '${_formatNaira(tierProgress['remaining'] as num)} to reach ${tierProgress['nextTierName']} (${tierProgress['nextStar']}★)',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: tierProgress['progress'] as double,
                                  minHeight: 10,
                                  backgroundColor: const Color(0xFFE2E8F0),
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            ] else ...[
                              const Text(
                                'You reached the highest tier. Keep building your referral empire.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: _showTierLadder,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFFBEB), Color(0xFFFFF7D6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFCD34D)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.workspace_premium_rounded,
                                color: Colors.amber.shade700,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Current Tier',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_superAgentTierName(_stars)} (${_stars.clamp(0, 5)}★) • Tap to view all tiers',
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _starsCard(),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metricCard('Total Earned', _formatNaira(_totalEarnings)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _metricCard('Available', _formatNaira(_availableEarnings)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metricCard('Referrals', '${_referralSummaries.length}'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Program Rewards',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: _showProgramRewardsInfo,
                                  child: Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('Per NIP transfer: ${_formatNaira(_perTransferAmount)}'),
                            const SizedBox(height: 4),
                            Text(
                              'Verified business bonus: ${_formatNaira(_verifiedBusinessBonusAmount)}',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recent Commissions',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          if (_commissions.length > 5)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _showAllCommissions = !_showAllCommissions;
                                });
                              },
                              child: Text(_showAllCommissions ? 'Show less' : 'View all'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_commissions.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('No commissions yet.'),
                        )
                      else
                        ..._commissions
                            .take(_showAllCommissions ? _commissions.length : 5)
                            .map((c) {
                          final type = (c['type'] ?? '').toString();
                          final amount = _toNum(c['amount']);
                          final createdAt = _toDateTime(c['createdAt']);
                          final status = (c['status'] ?? 'credited').toString();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _typeLabel(type),
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '+${_formatNaira(amount)}',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      status,
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 12),
                      const Text(
                        'Referral Performance',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      if (_referralSummaries.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('No referred businesses yet.'),
                        )
                      else
                        ..._referralSummaries.take(20).map((r) {
                          final businessId = (r['businessId'] ?? '').toString();
                          final totalEarned = _toNum(r['totalEarned']);
                          final nipTransfers = (r['nipTransfers'] ?? 0) as int;
                          final hasBonus = r['hasVerificationBonus'] == true;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  businessId,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text('NIP transfers: $nipTransfers'),
                                Text('Verification bonus: ${hasBonus ? 'Paid' : 'Not yet'}'),
                                Text('Total earned: ${_formatNaira(totalEarned)}'),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }

  Widget _metricCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _starsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tier',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(
              5,
              (index) => Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  index < _stars ? Icons.star : Icons.star_outline,
                  color: Colors.amber.shade300,
                  size: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _superAgentTierName(_stars),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
