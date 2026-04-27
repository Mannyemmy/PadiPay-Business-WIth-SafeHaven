import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/utils.dart';

/// A standalone page for tagging existing transactions in PadiBook.
/// Uses the same data-loading logic as TransactionsHistory.
class TagTransactionsPage extends StatefulWidget {
  const TagTransactionsPage({super.key});

  @override
  State<TagTransactionsPage> createState() => _TagTransactionsPageState();
}

class _TagTransactionsPageState extends State<TagTransactionsPage> {
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  final _currencyFormat =
      NumberFormat.currency(symbol: '₦', decimalDigits: 2);

  // â”€â”€ Same streams as TransactionsHistory â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  late StreamSubscription<QuerySnapshot> _sentSub;
  late StreamSubscription<QuerySnapshot> _cpSub;
  StreamSubscription<QuerySnapshot>? _receivedCpSub;

  List<QueryDocumentSnapshot> sentDocs = [];
  List<QueryDocumentSnapshot> receivedCpDocs = [];
  List<String> cpIds = [];

  // â”€â”€ Business logic (mirrors TransactionsHistory) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<String> posStandAccountIds = [];
  String? userAccountId;
  bool isPosStandUser = false;
  bool isBusinessOwner = false;
  bool _isInitialized = false;

  // â”€â”€ Tagged transaction IDs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Set<String> _taggedTransactionIds = {};
  StreamSubscription<QuerySnapshot>? _taggedSub;

  // â”€â”€ Recent labels (for tag suggestions) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<String> _recentLabels = [];

  // â”€â”€ Search â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Tag + date filter ──────────────────────────────────────────────────────────────
  String _tagFilter = 'all'; // 'all' | 'tagged' | 'untagged'
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();

    _initBusinessLogic()
        .catchError((e, st) {
          debugPrint('[TagTxns] _initBusinessLogic error: $e\n$st');
        })
        .whenComplete(() {
          if (mounted) setState(() => _isInitialized = true);
        });

    // Transactions stream (same filter as TransactionsHistory)
    _sentSub = FirebaseFirestore.instance
        .collection('transactions')
        .where(
          Filter.or(
            Filter('userId', isEqualTo: uid),
            Filter('actualSender', isEqualTo: uid),
          ),
        )
        .snapshots()
        .listen(
          (snap) {
            const excludedTypes = {'va_settlement', 'va_settlement_failed'};
            final filtered = snap.docs
                .where((d) => !excludedTypes.contains(d.data()['type']))
                .toList();
            if (mounted) setState(() => sentDocs = filtered);
          },
          onError: (e, st) =>
              debugPrint('[TagTxns] sentDocs stream error: $e\n$st'),
        );

    // Counterparties stream
    _cpSub = FirebaseFirestore.instance
        .collection('counterparties')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) {
              setState(() {
                cpIds = snap.docs.map((d) => d.id).toList();
                _updateCpStream();
              });
            }
          },
          onError: (e, st) =>
              debugPrint('[TagTxns] counterparties stream error: $e\n$st'),
        );

    // Tagged transactions stream
    _taggedSub = FirebaseFirestore.instance
        .collection('padiBook')
        .doc(uid)
        .collection('entries')
        .where('isManual', isEqualTo: false)
        .snapshots()
        .listen(
          (snap) {
            final tagged = <String>{};
            for (final doc in snap.docs) {
              final tid = doc.data()['transactionId'] as String?;
              if (tid != null) tagged.add(tid);
            }
            if (mounted) setState(() => _taggedTransactionIds = tagged);
          },
          onError: (e, st) =>
              debugPrint('[TagTxns] tagged stream error: $e\n$st'),
        );

    // Load recent labels for suggestions
    FirebaseFirestore.instance
        .collection('padiBook')
        .doc(uid)
        .collection('entries')
        .orderBy('date', descending: true)
        .limit(100)
        .get()
        .then((snap) {
      final seen = <String>{};
      final labels = <String>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final lbl = (d['label'] as String?)?.trim() ?? '';
        if (lbl.isNotEmpty && seen.add(lbl)) labels.add(lbl);
      }
      if (mounted) setState(() => _recentLabels = labels);
    }).catchError((e) {
      debugPrint('[TagTxns] load labels error: $e');
    });
  }

  Future<void> _initBusinessLogic() async {
    try {
      final userEmail = FirebaseAuth.instance.currentUser!.email;

      final standSnap = await FirebaseFirestore.instance
          .collection('standUsers')
          .where('email', isEqualTo: userEmail)
          .get();

      if (standSnap.docs.isNotEmpty) {
        isPosStandUser = true;
        final standData = standSnap.docs.first.data();
        final parentBusinessId = standData['parentBusinessId'];
        final bizSnap = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(parentBusinessId)
            .get();
        if (bizSnap.exists) {
          final posStands = (bizSnap.data()!['posStands'] as List?) ?? [];
          final posStand = posStands.firstWhere(
            (e) => e['standLoginEmail'] == userEmail,
            orElse: () => null,
          );
          if (posStand != null) {
            userAccountId = posStand['accountData']?['data']?['id'];
          }
        }
        debugPrint('[TagTxns] isPosStandUser=true, userAccountId=$userAccountId');
      } else {
        final bizSnap = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(uid)
            .get();
        if (bizSnap.exists) {
          final data = bizSnap.data()!;
          final posStands = (data['posStands'] as List?) ?? [];
          if (posStands.isNotEmpty) {
            isBusinessOwner = true;
            posStandAccountIds = posStands
                .map((e) => (e['accountData']?['data']?['id'] ?? '') as String)
                .where((id) => id.isNotEmpty)
                .toList();
            userAccountId =
                data['getAnchorData']?['virtualAccount']?['data']?['id'];
            debugPrint('[TagTxns] isBusinessOwner=true, posStandAccountIds=$posStandAccountIds, userAccountId=$userAccountId');
          } else {
            userAccountId =
                data['getAnchorData']?['virtualAccount']?['data']?['id'];
            debugPrint('[TagTxns] regular biz user, userAccountId=$userAccountId');
          }
        } else {
          debugPrint('[TagTxns] no business doc found for uid=$uid');
        }
      }
    } catch (e, st) {
      debugPrint('[TagTxns] _initBusinessLogic error: $e\n$st');
    }
  }

  void _updateCpStream() {
    _receivedCpSub?.cancel();
    if (cpIds.isEmpty) {
      receivedCpDocs = [];
      return;
    }
    _receivedCpSub = FirebaseFirestore.instance
        .collection('transactions')
        .where(
          'api_response.data.relationships.counterParty.data.id',
          whereIn: cpIds,
        )
        .snapshots()
        .listen(
          (snap) {
            if (mounted) setState(() => receivedCpDocs = snap.docs);
          },
          onError: (e, st) =>
              debugPrint('[TagTxns] receivedCpDocs stream error: $e\n$st'),
        );
  }

  @override
  void dispose() {
    _sentSub.cancel();
    _cpSub.cancel();
    _receivedCpSub?.cancel();
    _taggedSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // â”€â”€ Filtered & sorted list (matches TransactionsHistory logic) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<QueryDocumentSnapshot> _getDisplayDocs() {
    List<QueryDocumentSnapshot> docs = [];

    if (isPosStandUser) {
      docs = sentDocs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final accountId =
            data['api_response']?['data']?['relationships']?['account']?['data']?['id'];
        return accountId == userAccountId;
      }).toList();
    } else if (isBusinessOwner) {
      docs = sentDocs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final accountId =
            data['api_response']?['data']?['relationships']?['account']?['data']?['id'];
        if (accountId != null && posStandAccountIds.contains(accountId)) {
          return true;
        }
        return accountId == userAccountId;
      }).toList();
    } else {
      if (userAccountId == null) {
        docs = sentDocs.toList();
      } else {
        docs = sentDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final accountId =
              data['api_response']?['data']?['relationships']?['account']?['data']?['id'];
          return accountId == null || accountId == userAccountId;
        }).toList();
      }
    }

    docs = [...docs, ...receivedCpDocs];

    // Deduplicate
    final Map<String, QueryDocumentSnapshot> unique = {};
    for (final doc in docs) {
      unique[doc.id] = doc;
    }

    // Sort by date descending
    final sorted = unique.values.toList()
      ..sort((a, b) {
        final aDate = _getDate(a.data() as Map<String, dynamic>);
        final bDate = _getDate(b.data() as Map<String, dynamic>);
        return bDate.compareTo(aDate);
      });

    // Apply search filter
    var filtered = _searchQuery.isEmpty
        ? sorted
        : sorted.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final fields = [
              data['recipientName']?.toString().toLowerCase() ?? '',
              data['phoneNumber']?.toString().toLowerCase() ?? '',
              data['meterNumber']?.toString().toLowerCase() ?? '',
              data['account_number']?.toString().toLowerCase() ?? '',
              data['reference']?.toString().toLowerCase() ?? '',
              (data['type'] ?? '').toString().toLowerCase(),
            ];
            return fields.any((f) => f.contains(_searchQuery));
          }).toList();

    // Apply tag status filter
    if (_tagFilter != 'all') {
      filtered = filtered.where((doc) {
        final isTagged = _taggedTransactionIds.contains(doc.id);
        return _tagFilter == 'tagged' ? isTagged : !isTagged;
      }).toList();
    }

    // Apply date filter
    if (_dateFrom != null || _dateTo != null) {
      filtered = filtered.where((doc) {
        final dt = _getDate(doc.data() as Map<String, dynamic>);
        if (_dateFrom != null && dt.isBefore(_dateFrom!)) return false;
        if (_dateTo != null && dt.isAfter(_dateTo!)) return false;
        return true;
      }).toList();
    }

    return filtered;
  }

  Future<void> _showDateFilter() async {
    DateTime? tempFrom = _dateFrom;
    DateTime? tempTo = _dateTo;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SafeArea(
          bottom: true,
          child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 36, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 20),
                Text('Filter by Date', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: tempFrom ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setModal(() => tempFrom = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Text(
                            tempFrom != null
                                ? '${tempFrom!.day}/${tempFrom!.month}/${tempFrom!.year}'
                                : 'From date',
                            style: TextStyle(
                                color: tempFrom != null ? Colors.black87 : Colors.grey.shade400,
                                fontSize: 13),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: tempTo ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setModal(() => tempTo = DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Text(
                            tempTo != null
                                ? '${tempTo!.day}/${tempTo!.month}/${tempTo!.year}'
                                : 'To date',
                            style: TextStyle(
                                color: tempTo != null ? Colors.black87 : Colors.grey.shade400,
                                fontSize: 13),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() { _dateFrom = null; _dateTo = null; });
                        Navigator.pop(ctx);
                      },
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() { _dateFrom = tempFrom; _dateTo = tempTo; });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  // â”€â”€ Helpers (same as TransactionsHistory) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  DateTime _getDate(Map<String, dynamic> data) {
    final dynamic ts =
        data['timestamp'] ??
        data['createdAtFirestore'] ??
        data['createdAt'] ??
        data['createdAtUtc'];
    if (ts == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is String) {
      try {
        return DateTime.parse(ts);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  IconData _getIcon(String type, bool isOutgoing) {
    switch (type.toLowerCase()) {
      case 'transfer':
        return isOutgoing ? FontAwesomeIcons.paperPlane : Icons.arrow_downward;
      case 'airtime':
        return FontAwesomeIcons.phone;
      case 'data':
      case 'mobile_data':
        return FontAwesomeIcons.wifi;
      case 'electricity':
        return FontAwesomeIcons.bolt;
      case 'cable':
        return Icons.tv;
      case 'add_money':
      case 'fund':
        return Icons.add;
      case 'giveaway_claim':
        return FontAwesomeIcons.gift;
      case 'giveaway_create':
        return FontAwesomeIcons.gift;
      case 'ghost_transfer':
        return FontAwesomeIcons.ghost;
      case 'atm_payment':
        return FontAwesomeIcons.creditCard;
      case 'bill_payment':
        return FontAwesomeIcons.fileInvoiceDollar;
      case 'loan':
      case 'loans':
        return FontAwesomeIcons.handHoldingDollar;
      default:
        return FontAwesomeIcons.exchangeAlt;
    }
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

  String _getTitle(
    String type,
    String otherName,
    bool isOutgoing,
  ) {
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
        return 'Ghost Transfer';
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

  // ── Tag sheet ─────────────────────────────────────────────────────────────

  void _showTagSheet(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final txnId = doc.id;
    final type = (data['type'] ?? '').toString().toLowerCase();
    final isOutgoing = data['userId'] == uid || data['actualSender'] == uid;
    final otherName = data['recipientName'] ??
        data['phoneNumber'] ??
        data['meterNumber'] ??
        data['account_number'] ??
        'Unknown';
    final title = _getTitle(type, otherName, isOutgoing);
    final amount =
        ((data['amount'] as num?) ?? (data['debitAmount'] as num? ?? 0))
            .toDouble();
    final date = _getDate(data);

    String selectedCategory =
        ['add_money', 'fund', 'deposit', 'giveaway_claim', 'atm_payment'].contains(type)
            ? 'income'
            : 'expense';

    final labelCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final quantityCtrl = TextEditingController();
    bool saving = false;
    bool showQty = false;
    bool showNote = false;

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade200),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: primaryColor, width: 1.5),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModal) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Scrollable body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Hero question
                        Text(
                          'What was this for?',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Transaction context — lightweight, not a card
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getIcon(type, isOutgoing),
                                color: primaryColor,
                                size: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _currencyFormat.format(amount),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: selectedCategory == 'income'
                                    ? Colors.green.shade700
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        // Label field — center stage
                        TextField(
                          controller: labelCtrl,
                          autofocus: true,
                          textCapitalization: TextCapitalization.sentences,
                          style: GoogleFonts.inter(fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'bread, fuel, salary…',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: focusedBorder,
                            suffixIcon: IconButton(
                              icon: Icon(
                                Icons.clear,
                                size: 18,
                                color: Colors.grey.shade400,
                              ),
                              onPressed: () => setModal(() => labelCtrl.clear()),
                            ),
                          ),
                        ),
                        // Recent chips — horizontal scroll
                        if (_recentLabels.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 32,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _recentLabels.length.clamp(0, 15),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final lbl = _recentLabels[i];
                                return GestureDetector(
                                  onTap: () =>
                                      setModal(() => labelCtrl.text = lbl),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withValues(alpha: 0.07),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: primaryColor.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Text(
                                      lbl,
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        // Income / Expense segmented control
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                              _SegmentTab(
                                label: '+ Income',
                                isSelected: selectedCategory == 'income',
                                color: Colors.green,
                                onTap: () => setModal(
                                  () => selectedCategory = 'income',
                                ),
                              ),
                              _SegmentTab(
                                label: '− Expense',
                                isSelected: selectedCategory == 'expense',
                                color: Colors.red.shade400,
                                onTap: () => setModal(
                                  () => selectedCategory = 'expense',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Optional extras
                        Row(
                          children: [
                            _OptionalToggle(
                              label: 'Quantity',
                              active: showQty,
                              onTap: () => setModal(() => showQty = !showQty),
                            ),
                            const SizedBox(width: 20),
                            _OptionalToggle(
                              label: 'Note',
                              active: showNote,
                              onTap: () =>
                                  setModal(() => showNote = !showNote),
                            ),
                          ],
                        ),
                        if (showQty) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: quantityCtrl,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.inter(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'How many? (e.g. 3)',
                              hintStyle:
                                  TextStyle(color: Colors.grey.shade400),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: inputBorder,
                              enabledBorder: inputBorder,
                              focusedBorder: focusedBorder,
                            ),
                          ),
                        ],
                        if (showNote) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: noteCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            style: GoogleFonts.inter(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Add a note…',
                              hintStyle:
                                  TextStyle(color: Colors.grey.shade400),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: inputBorder,
                              enabledBorder: inputBorder,
                              focusedBorder: focusedBorder,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                // Sticky Save button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final label = labelCtrl.text.trim();
                              if (label.isEmpty) {
                                showToast(
                                  'Enter what this was for',
                                  Colors.orange,
                                );
                                return;
                              }
                              setModal(() => saving = true);
                              try {
                                final qty = int.tryParse(
                                  quantityCtrl.text.trim(),
                                );
                                await FirebaseFirestore.instance
                                    .collection('padiBook')
                                    .doc(uid)
                                    .collection('entries')
                                    .add({
                                  'label': label,
                                  'category': selectedCategory,
                                  'amount': amount,
                                  'note': noteCtrl.text.trim(),
                                  'date': Timestamp.fromDate(date),
                                  'isManual': false,
                                  'transactionId': txnId,
                                  'transactionTitle': title,
                                  if (qty != null) 'quantity': qty,
                                });
                                debugPrint(
                                  '[TagTxns] tagged txn $txnId as "$label"',
                                );
                                if (!_recentLabels.contains(label)) {
                                  setState(
                                    () => _recentLabels = [
                                      label,
                                      ..._recentLabels,
                                    ],
                                  );
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                                showToast('Tagged!', Colors.green);
                              } catch (e, st) {
                                debugPrint(
                                  '[TagTxns] save tag error: $e\n$st',
                                );
                                showToast('Failed to save: $e', Colors.red);
                              } finally {
                                setModal(() => saving = false);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        disabledBackgroundColor:
                            primaryColor.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Save',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Tag Transactions',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black87,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search transactions...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor, width: 1.5),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final entry in [
                        ('all', 'All'),
                        ('untagged', 'Untagged'),
                        ('tagged', 'Tagged'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _tagFilter = entry.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _tagFilter == entry.$1 ? primaryColor : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _tagFilter == entry.$1 ? primaryColor : Colors.grey.shade300,
                                ),
                              ),
                              child: Text(
                                entry.$2,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _tagFilter == entry.$1 ? Colors.white : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: _showDateFilter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (_dateFrom != null || _dateTo != null)
                                ? primaryColor
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: (_dateFrom != null || _dateTo != null)
                                  ? primaryColor
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(children: [
                            Icon(Icons.calendar_today, size: 14,
                                color: (_dateFrom != null || _dateTo != null)
                                    ? Colors.white
                                    : Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              (_dateFrom != null || _dateTo != null) ? 'Date ✓' : 'Date',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: (_dateFrom != null || _dateTo != null)
                                    ? Colors.white
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : _buildList(),
    );
  }

  Widget _buildList() {
    final docs = _getDisplayDocs();

    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _tagFilter != 'all' || _dateFrom != null || _dateTo != null
                  ? 'No transactions match your filter'
                  : 'No transactions found',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: docs.length,
      itemBuilder: (ctx, i) {
        final doc = docs[i];
        final data = doc.data() as Map<String, dynamic>;
        final txnId = doc.id;
        final isTagged = _taggedTransactionIds.contains(txnId);

        final type = (data['type'] ?? '').toString().toLowerCase();
        final isOutgoing =
            data['userId'] == uid || data['actualSender'] == uid;
        final otherName = data['recipientName'] ??
            data['phoneNumber'] ??
            data['meterNumber'] ??
            data['account_number'] ??
            'Unknown';
        final title = _getTitle(type, otherName, isOutgoing);
        final amountRaw =
            (data['amount'] as num?) ?? (data['debitAmount'] as num? ?? 0);
        final amount = amountRaw.toDouble();
        final date = _getDate(data);
        final status = _getStatus(data);

        final amountSign =
            (!isOutgoing ||
                type == 'deposit' ||
                type == 'giveaway_claim' ||
                (type == 'atm_payment' &&
                    ['success', 'completed', 'successful'].contains(status)))
            ? '+'
            : '-';

        Color statusColor = Colors.grey;
        if (['success', 'completed', 'successful'].contains(status)) {
          statusColor = Colors.green;
        } else if (['pending', 'to be paid'].contains(status)) {
          statusColor = Colors.orange;
        } else if (['failed', 'unsuccessful'].contains(status)) {
          statusColor = Colors.red;
        } else if (status == 'reversed') {
          statusColor = Colors.grey;
        }

        Color bgColor = Colors.blue.withValues(alpha: 0.1);
        Color iconColor = Colors.blue;
        Offset offset = Offset.zero;
        if (type == 'transfer') {
          bgColor = isOutgoing
              ? const Color(0xFFFDC3F5).withValues(alpha: .49)
              : Colors.green.withValues(alpha: 0.1);
          iconColor =
              isOutgoing ? const Color(0xFFE103E5) : Colors.green;
          if (isOutgoing) offset = const Offset(-2, 2);
        }
        if (type.contains('ghost')) {
          bgColor = Colors.grey.shade200;
          iconColor = Colors.grey.shade600;
        }
        if (type.contains('giveaway')) {
          bgColor = Colors.yellow.shade200;
          iconColor = Colors.yellow.shade900;
        }

        final icon = _getIcon(type, isOutgoing);
        final formattedAmount =
            NumberFormat('#,##0.00').format(amount);
        final formattedTime = DateFormat('HH:mm').format(date);
        final formattedDate = DateFormat('MMMM d, yyyy').format(date);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isTagged ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: isTagged
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Transaction info (tappable area)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: isTagged
                            ? Colors.grey.shade200
                            : bgColor,
                        child: Transform.translate(
                          offset: offset,
                          child: Icon(
                            icon,
                            color: isTagged ? Colors.grey : iconColor,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: isTagged
                                    ? Colors.grey.shade500
                                    : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  color: Colors.grey.shade400,
                                  size: 12,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$formattedTime · $formattedDate',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$amountSign₦$formattedAmount',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: isTagged
                                    ? Colors.grey.shade400
                                    : statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Tag button
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: isTagged
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check,
                              size: 13,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Tagged',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GestureDetector(
                        onTap: () => _showTagSheet(doc),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Tag',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Supporting widgets ───────────────────────────────────────────────────────

/// iOS-style segmented tab used for the income/expense toggle.
class _SegmentTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _SegmentTab({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey.shade500,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small tap-to-show toggle for optional fields (Quantity, Note).
class _OptionalToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _OptionalToggle({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.remove_circle_outline : Icons.add_circle_outline,
            size: 15,
            color: Colors.grey.shade500,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
