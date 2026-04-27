import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/stand_transaction_history.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:shimmer/shimmer.dart';

class StandDetailsPage extends StatefulWidget {
  final String accountId;
  final String standName;
  const StandDetailsPage({super.key, required this.accountId, required this.standName});

  @override
  State<StandDetailsPage> createState() => _StandDetailsPageState();
}

class _StandDetailsPageState extends State<StandDetailsPage> {
  bool _loading = true;
  double totalEarnings = 0.0;
  Map<String, double> earningsByType = {};
  String standName = '';
  String _selectedTimeFrame = 'Day';
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails({bool showShimmer = true}) async {
    if (showShimmer) {
      setState(() { _loading = true; });
    }
    try {
      final now = DateTime.now();
      DateTime start;
      if (_selectedTimeFrame == 'Day') {
        start = DateTime(now.year, now.month, now.day);
      } else if (_selectedTimeFrame == 'Week') {
        start = now.subtract(Duration(days: now.weekday - 1));
        start = DateTime(start.year, start.month, start.day);
      } else if (_selectedTimeFrame == 'Month') {
        start = DateTime(now.year, now.month, 1);
      } else {
        // Custom Range: fallback to last 30 days
        start = _startDate ?? now.subtract(const Duration(days: 30));
      }
      var q = FirebaseFirestore.instance
          .collection('transactions')
          .where(
            'api_response.data.relationships.account.data.id',
            isEqualTo: widget.accountId,
          )
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
          );
      if (_selectedTimeFrame == 'Custom Range' && _endDate != null) {
        q = q.where(
          'timestamp',
          isLessThan: Timestamp.fromDate(_endDate!.add(const Duration(days: 1))),
        );
      }
      final query = await q.get();

      double total = 0.0;
      Map<String, double> byType = {
        'Outgoing Transfer': 0.0,
        'Incoming Transfer': 0.0,
        'Airtime': 0.0,
        'Data':0.0
        
      };
      String name = '';
      for (var doc in query.docs) {
        final data = doc.data();
        final type = (data['type'] ?? '').toString().toLowerCase();
        final amount = _getAmount(data);
        total += amount;
        if (type == 'transfer' || type.contains('bank')) {
          byType['Outgoing Transfer'] = (byType['Outgoing Transfer'] ?? 0) + amount;
        } else if (type.contains('airtime')) {
          byType['Airtime'] =
              (byType['Airtime'] ?? 0) + amount;
        } else if (type.contains('deposit')) {
          byType['Incoming Transfer'] =
              (byType['Incoming Transfer'] ?? 0) + amount;
        }
        else if (type.contains('data')) {
          byType['Data'] =
              (byType['Data'] ?? 0) + amount;
        }

        if (name.isEmpty && data['recipientName'] != null) {
          name = data['recipientName'].toString();
        }
      }
      if (mounted) {
        setState(() {
          totalEarnings = total;
          earningsByType = byType;
          standName = name;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
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

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 50),
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: 150,
            height: 24,
            color: Colors.white,
          ),
          const SizedBox(height: 4),
          Container(
            width: 120,
            height: 15,
            color: Colors.white,
          ),
          const SizedBox(height: 20),
          Container(
            width: 80,
            height: 16,
            color: Colors.white,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(4, (index) => Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              )),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: 0,
              horizontal: 12,
            ),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.blue, width: 5),
              ),
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 100,
                        height: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: 80,
                        height: 22,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 90,
                  height: 90,
                  color: Colors.white,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(4, (index) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 100,
                        height: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 60,
                        height: 14,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 80,
                  height: 16,
                  color: Colors.white,
                ),
              ],
            ),
          )),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  void _onTimeFrameSelected(String label) {
    if (label == 'Custom Range') {
      final now = DateTime.now();
      final initialRange = DateTimeRange(
        start: now.subtract(const Duration(days: 30)),
        end: now,
      );
      showDateRangePicker(
        context: context,
        firstDate: now.subtract(const Duration(days: 365)),
        lastDate: now,
        initialDateRange: _startDate != null && _endDate != null
            ? DateTimeRange(start: _startDate!, end: _endDate!)
            : initialRange,
      ).then((range) {
        if (range != null && mounted) {
          setState(() {
            _startDate = range.start;
            _endDate = range.end;
            _selectedTimeFrame = label;
          });
          _fetchDetails(showShimmer: false);
        }
      });
    } else {
      if (_selectedTimeFrame != label) {
        setState(() {
          _selectedTimeFrame = label;
        });
        _fetchDetails(showShimmer: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _loading
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SingleChildScrollView(
                child: _buildShimmer(),
              ),
            )
          : SafeArea(
            bottom: true,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 50),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.arrow_back_ios,
                                size: 20,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "My Earnings",
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Transaction summary',
                        style: GoogleFonts.inter(
                          color: Colors.grey[500],
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Time-Frame',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _TimeFrameButton(
                              label: 'Day',
                              selected: _selectedTimeFrame == 'Day',
                              onTap: () => _onTimeFrameSelected('Day'),
                            ),
                            _TimeFrameButton(
                              label: 'Week',
                              selected: _selectedTimeFrame == 'Week',
                              onTap: () => _onTimeFrameSelected('Week'),
                            ),
                            _TimeFrameButton(
                              label: 'Month',
                              selected: _selectedTimeFrame == 'Month',
                              onTap: () => _onTimeFrameSelected('Month'),
                            ),
                            _TimeFrameButton(
                              label: 'Custom Range',
                              selected: _selectedTimeFrame == 'Custom Range',
                              onTap: () => _onTimeFrameSelected('Custom Range'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 12,
                        ),
            
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: Colors.blue, width: 5),
                          ),
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Earnings',
                                    style: GoogleFonts.inter(
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '₦${NumberFormat('#,##0').format(totalEarnings)}',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 22,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(0, 8),
                              child: SizedBox(
                                width: 90,
                                height: 90,
                                child: Image.asset("assets/Group.png"),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ...earningsByType.entries.map(
                        (entry) => _EarningsTypeCard(
                          type: entry.key,
                          amount: entry.value,
                          onViewHistory: () {
                            navigateTo(
                              context,
                              StandTransactionHistory(
                                accountId: widget.accountId,
                                standName: widget.standName,
                                type: entry.key,
                              ),
                              type: NavigationType.push,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50),
                            backgroundColor: Colors.grey[200],
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.shade400),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 32,
                            ),
                          ),
                          onPressed: () {},
                          child: Text(
                            'View all history',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600,color:Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ),
    );
  }
}

class _TimeFrameButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _TimeFrameButton({required this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 18),
          decoration: BoxDecoration(
            color: selected ? Colors.blue[100] : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? Colors.blue : Colors.grey[300]!),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.blue : Colors.black54,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}


class _EarningsTypeCard extends StatelessWidget {
  final String type;
  final double amount;
  final VoidCallback? onViewHistory;
  const _EarningsTypeCard({
    required this.type,
    required this.amount,
    this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (type.toLowerCase()) {
      case 'bank transfer':
        icon = Icons.account_balance;
        break;
      case 'card payment received':
        icon = Icons.credit_card;
        break;
      case 'cash payment fulfillment':
        icon = Icons.money;
        break;
      default:
        icon = Icons.payment;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [SizedBox(width: 12),
          CircleAvatar(radius: 16,
            backgroundColor: Colors.white,
            child: Icon(icon, color: Colors.black54,size: 14,),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '₦${NumberFormat('#,##0').format(amount)}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onViewHistory,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View History',
                  style: GoogleFonts.inter(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.open_in_new, color: Colors.blue, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}