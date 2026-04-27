import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:padi_pay_business/receipt_page.dart';
import 'package:padi_pay_business/utils.dart';

class TransactionItem extends StatefulWidget {
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
  State<TransactionItem> createState() => _TransactionItemState();
}

class _TransactionItemState extends State<TransactionItem> {
  String? _fetchedName;

  @override
  void initState() {
    super.initState();
    if (widget.type.toLowerCase() == 'transfer' &&
        !widget.isOutgoing &&
        widget.otherId.isNotEmpty) {
      _fetchName();
    }
  }

  Future<void> _fetchName() async {
    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherId)
          .get();
      if (docSnap.exists) {
        final data = docSnap.data()!;
        final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
            .trim();
        if (name.isNotEmpty) {
          setState(() {
            _fetchedName = name;
          });
        }
      }
    } catch (e) {
      // ignore
    }
  }

  String _getTitle(String type, String otherName, bool isOutgoing) {
    switch (type) {
      case 'transfer':
        return isOutgoing
            ? 'Transfer to $otherName'
            : 'Transfer from $otherName';
      case 'airtime':
        return otherName != 'Unknown'
            ? 'Airtime for $otherName'
            : 'Airtime Purchase';
      case 'data':
      case 'mobile_data':
        return otherName != 'Unknown'
            ? 'Data Bundle for $otherName'
            : 'Data Purchase';
      case 'electricity':
        return 'Electricity Bill';
      case 'cable':
        return 'Cable Subscription';
      case 'add_money':
      case 'fund':
        return 'Add Money';
      case 'giveaway_claim':
        return 'Giveaway Claim';
      case 'giveaway_create':
        return 'Giveaway Created';
      case 'deposit':
        return 'Transfer from $otherName';
      case 'loans':
        return isOutgoing ? 'Loan Disbursed' : 'Loan Received';
      case 'ghost_transfer':
        return "Ghost Transfer";
      case 'va_settlement':
        return 'ATM Settlement';
      case 'va_settlement_failed':
        return 'ATM Settlement';
      case 'atm_payment':
        return 'ATM Payment';
      case 'anonymous_transfer':
        return 'Anonymous Transfer';
      case 'bill_payment':
        return 'Bill Payment for $otherName';
      default:
        return otherName != 'Unknown'
            ? '$type for $otherName'
            : type.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _fetchedName ?? widget.otherName;
    final title = _getTitle(widget.type, displayName, widget.isOutgoing);

    return GestureDetector(
      onTap: () {
        navigateTo(
          context,
          ReceiptPage(reference: widget.reference),
          type: NavigationType.push,
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 25, left: 5, right: 5),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: widget.bgColor,
              child: Transform.translate(
                offset: widget.offset,
                child: Icon(widget.icon, color: widget.iconColor, size: 18),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
                        widget.formattedTime,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        ' • ',
                        style: const TextStyle(
                          color: primaryColor,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        widget.formattedDate,
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
                  widget.amount,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  widget.status,
                  style: TextStyle(color: widget.statusColor, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
