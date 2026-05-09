import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/receipt_page.dart';
import 'package:padi_pay_business/utils.dart';


class TransactionItem extends StatefulWidget {
  final String docId;
  final IconData icon;
  final String otherId;
  final String amount;
  final Color amountColor;
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
  final Map<String, dynamic>? cardData;

  const TransactionItem({
    super.key,
    required this.docId,
    required this.icon,
    required this.otherId,
    required this.amount,
    required this.amountColor,
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
    this.cardData,
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
      case 'anonymous_transfer':
        return 'Anonymous Transfer';
      case 'bill_payment':
        return 'Bill Payment for $otherName';
      case 'atm_payment':
        return 'Card Payment';
      case 'card_debit':
        return 'Virtual Card Payment at $otherName';
      case 'card_declined':
        return 'Virtual Card Payment at $otherName';
      case 'card_refund':
        return 'Card Refund from $otherName';
      case 'cashback_earned':
        return 'Cashback Earned';
      case 'cashback_spent':
        return 'Cashback Spent';
      default:
        return otherName != 'Unknown'
            ? '$type for $otherName'
            : type.toUpperCase();
    }
  }

  void _showCardDetail(BuildContext context) {
    final data = widget.cardData!;
    final type = data['type']?.toString() ?? '';
    final currency = data['currency']?.toString() ?? 'NGN';
    final merchant = data['merchant']?.toString() ?? 'Unknown';
    final channel = data['channel']?.toString() ?? '';
    final reference = data['reference']?.toString() ?? '';
    final status =
        data['status']?.toString() ??
        (type == 'card_declined' ? 'declined' : 'approved');
    final ts = data['timestamp'] as Timestamp?;
    final date = ts != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate())
        : '';
    final isDeclined = type == 'card_declined' || status == 'declined';
    final isRefund = type == 'card_refund';
    final statusLabel = isDeclined
        ? 'Declined'
        : isRefund
        ? 'Refunded'
        : 'Successful';
    final statusColor = isDeclined
        ? Colors.red
        : isRefund
        ? Colors.blue
        : Colors.green;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.amount,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: GoogleFonts.inter(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _detailRow('Merchant', merchant),
            if (channel.isNotEmpty)
              _detailRow('Channel', channel.toUpperCase()),
            _detailRow('Currency', currency),
            if (date.isNotEmpty) _detailRow('Date', date),
            if (reference.isNotEmpty) _detailRow('Reference', reference),
            if (data['reason'] != null)
              _detailRow('Reason', data['reason'].toString()),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _fetchedName ?? widget.otherName;
    final title = _getTitle(widget.type, displayName, widget.isOutgoing);

    return GestureDetector(
      onTap: () {
        navigateTo(
          context,
          ReceiptPage(reference: widget.reference, cardData: widget.cardData),
          type: NavigationType.push,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 0, right: 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: widget.bgColor,
              child: Transform.translate(
                offset: widget.offset,
                child: Icon(widget.icon, color: widget.iconColor, size: 16),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:  GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Colors.grey.shade500,
                        size: 10,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.formattedTime,
                          style:  GoogleFonts.inter(
                          color: Colors.grey.shade600,
                          fontSize: 10,
                          fontWeight: FontWeight.w500
                        ),
                      ),
                      Text(
                        ' • ',
                         style:  GoogleFonts.inter(
                          color: Colors.grey.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.w500
                        ),
                      ),
                      Text(
                        widget.formattedDate,
                          style:  GoogleFonts.inter(
                          color: Colors.grey.shade600,
                          fontSize: 10,
                          fontWeight: FontWeight.w500
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  widget.amount,
                   style:  GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: widget.amountColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.status,
                   style:  GoogleFonts.inter(
                    color: widget.statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

