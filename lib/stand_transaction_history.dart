import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/receipt_page.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:shimmer/shimmer.dart';

class StandTransactionHistory extends StatefulWidget {
  final String accountId;
  final String standName;
  final String type; // e.g. 'Airtime', 'Outgoing Transfer', etc.
  const StandTransactionHistory({
    super.key,
    required this.accountId,
    required this.standName,
    required this.type,
  });

  @override
  State<StandTransactionHistory> createState() =>
      _StandTransactionHistoryState();
}

class _StandTransactionHistoryState extends State<StandTransactionHistory> {
  bool _loading = true;
  List<QueryDocumentSnapshot> _docs = [];

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      _loading = true;
    });
    try {
      String filterType = '';
      if (widget.type == 'Outgoing Transfer') {
        filterType = 'transfer';
      } else if (widget.type == 'Incoming Transfer') {
        filterType = 'deposit';
      } else if (widget.type == 'Airtime') {
        filterType = 'airtime';
      } else if (widget.type == 'Data') {
        filterType = 'data';
      } else {
        filterType = widget.type;
      }
      print('[StandTransactionHistory] Fetching transactions for accountId: \'${widget.accountId}\', displayType: \'${widget.type}\', filterType: \'$filterType\'');
      final query = await FirebaseFirestore.instance
          .collection('transactions')
          .where(
            'api_response.data.relationships.account.data.id',
            isEqualTo: widget.accountId,
          )
          .orderBy('timestamp', descending: true)
          .get();
      print('[StandTransactionHistory] Total docs fetched: \'${query.docs.length}\'');
      for (var doc in query.docs) {
        final data = doc.data();
        final type = (data['type'] ?? '').toString().toLowerCase();
        print('[StandTransactionHistory] Transaction docId: \'${doc.id}\', type: \'$type\', amount: \'${_getAmount(data)}\'');
      }
      final filtered = query.docs.where((doc) {
        final data = doc.data();
        final type = (data['type'] ?? '').toString().toLowerCase();
        bool match = false;
        if (widget.type == 'Outgoing Transfer') {
          match = type == 'transfer';
        } else if (widget.type == 'Incoming Transfer') {
          match = type == 'deposit';
        } else if (widget.type == 'Airtime') {
          match = type == 'airtime';
        } else if (widget.type == 'Data') {
          match = type == 'data';
        }
        print('[StandTransactionHistory] Filter check for docId: \'${doc.id}\', type: \'$type\', match: $match');
        return match;
      }).toList();
      print('[StandTransactionHistory] Filtered docs count: \'${filtered.length}\'');
      setState(() {
        _docs = filtered;
        _loading = false;
      });
    } catch (e) {
      print('[StandTransactionHistory] Error fetching transactions: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        itemCount: 5,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 25, left: 5, right: 5),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 120,
                        height: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 60,
                            height: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 12,
                            height: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 80,
                            height: 12,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 60,
                      height: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 40,
                      height: 10,
                      color: Colors.white,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SizedBox.expand(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
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
                    const SizedBox(height: 12),
                    Text(
                      "${widget.standName} ${widget.type}",
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _loading
                          ? _buildShimmerList()
                          : _docs.isEmpty
                              ? Center(
                                  child: Text(
                                    'No transactions found.',
                                    style: GoogleFonts.inter(),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _docs.length,
                                  itemBuilder: (context, index) {
                                    final doc = _docs[index];
                                    final data = doc.data() as Map<String, dynamic>;
                                    final amount = _getAmount(data);
                                    final timestamp =
                                        data['timestamp'] as Timestamp?;
                                    final dt = timestamp?.toDate();
                                    final formattedTime = dt != null
                                        ? DateFormat('hh:mm a').format(dt)
                                        : '';
                                    final formattedDate = dt != null
                                        ? DateFormat('dd MMM yyyy').format(dt)
                                        : '';
                                    final status = _getStatus(data);
                                    final statusColor = _getStatusColor(status);
                                    final isOutgoing =
                                        widget.type == 'Outgoing Transfer';
                                    final otherName =
                                        data['recipientName']?.toString() ??
                                        'Unknown';
                                    final reference =
                                        data['reference']?.toString() ?? '';
                                    final icon = _getIcon(widget.type, isOutgoing);
                                    final bgColor = Colors.blue[50]!;
                                    final iconColor = Colors.blue;
                                    final offset = Offset(0, 0);
                                    return TransactionItem(
                                      docId: doc.id,
                                      icon: icon,
                                      otherId: '',
                                      amount:
                                          '₦${NumberFormat('#,##0').format(amount)}',
                                      formattedTime: formattedTime,
                                      formattedDate: formattedDate,
                                      status: status,
                                      statusColor: statusColor,
                                      isOutgoing: isOutgoing,
                                      otherName: otherName,
                                      type: widget.type,
                                      reference: reference,
                                      bgColor: bgColor,
                                      iconColor: iconColor,
                                      offset: offset,
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
               
              ],
            ),
          ),
        ),
      ),
    );
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

  String _getStatus(Map<String, dynamic> data) {
    if (data['api_response']?['data']?['attributes']?['status'] != null) {
      return data['api_response']['data']['attributes']['status']
          .toString()
          .toLowerCase();
    }
    if (data['fullData']?['attributes']?['status'] != null) {
      return data['fullData']['attributes']['status'].toString().toLowerCase();
    }
    if (data['status'] != null) {
      return data['status'].toString().toLowerCase();
    }
    return 'unknown';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'success':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getIcon(String type, bool isOutgoing) {
    switch (type.toLowerCase()) {
      case 'outgoing transfer':
        return isOutgoing ? Icons.arrow_upward : Icons.arrow_downward;
      case 'incoming transfer':
        return Icons.arrow_downward;
      case 'airtime':
        return Icons.phone_android;
      case 'data':
        return Icons.wifi;
      default:
        return Icons.payment;
    }
  }
}

class TransactionItem extends StatelessWidget {
  final String docId;
  final IconData icon;
  final String otherId;
  final String amount;
  final String formattedTime;
  final String formattedDate;
  final String status;
  final Color statusColor;
  final bool isOutgoing;
  final String otherName;
  final String type;
  final String reference;
  final Color bgColor;
  final Color iconColor;
  final Offset offset;

  const TransactionItem({
    super.key,
    required this.docId,
    required this.icon,
    required this.otherId,
    required this.amount,
    required this.formattedTime,
    required this.formattedDate,
    required this.status,
    required this.statusColor,
    required this.isOutgoing,
    required this.otherName,
    required this.type,
    required this.reference,
    required this.bgColor,
    required this.iconColor,
    required this.offset,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        navigateTo(
          context,
          ReceiptPage(reference: reference),
          type: NavigationType.push,
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 25, left: 5, right: 5),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: bgColor,
              child: Transform.translate(
                offset: offset,
                child: Icon(icon, color: iconColor, size: 18),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        color: Colors.grey,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formattedTime,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        ' • ',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}