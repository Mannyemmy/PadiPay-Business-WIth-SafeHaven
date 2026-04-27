import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/my_business/my_business.dart';
import 'package:padi_pay_business/padi_book/pos_agent_settings_page.dart';
import 'package:padi_pay_business/padi_book/tag_transactions_page.dart';
import 'package:padi_pay_business/profile/profile_page.dart';
import 'package:padi_pay_business/transactions_history.dart';
import 'package:padi_pay_business/ui/bottom_nav_bar.dart';
import 'package:padi_pay_business/utils.dart';

/// Unified entry model for PadiBook — covers both manual entries (from
/// padiBook/entries) and auto-generated rows from the transactions collection.
class _Entry {
  final String key;           // unique widget key
  final String? padiDocId;    // non-null when backed by a padiBook Firestore doc
  final String label;
  final String category;      // 'income' | 'expense'
  final double amount;
  final DateTime? date;
  final String note;
  final bool isManual;        // manually typed entry
  final bool isAutoTx;        // auto-generated from transactions (no padiBook doc)
  final String? txnTitle;
  final int? qty;
  final Map<String, dynamic>? padiData; // raw padiBook doc data, for edit sheet

  const _Entry({
    required this.key,
    this.padiDocId,
    required this.label,
    required this.category,
    required this.amount,
    this.date,
    required this.note,
    required this.isManual,
    required this.isAutoTx,
    this.txnTitle,
    this.qty,
    this.padiData,
  });
}

class PadiBookPage extends StatefulWidget {
  const PadiBookPage({super.key});

  @override
  State<PadiBookPage> createState() => _PadiBookPageState();
}

class _PadiBookPageState extends State<PadiBookPage> {
  int _selectedIndex = 5;
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  final _currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);

  // stream subscriptions
  StreamSubscription<QuerySnapshot>? _padiSub;
  StreamSubscription<QuerySnapshot>? _txSub;

  // live state from streams
  List<QueryDocumentSnapshot> _padiDocs = [];
  List<QueryDocumentSnapshot> _txDocs = [];
  Set<String> _taggedTxIds = {}; // transactionIds already tagged in padiBook
  bool _padiLoading = true;
  bool _txLoading = true;

  List<String> _recentLabels = [];

  // ── POS Agent state ──────────────────────────────────────────────────────
  StreamSubscription<DocumentSnapshot>? _posSub;
  StreamSubscription<QuerySnapshot>? _posExclusionSub;
  StreamSubscription<QuerySnapshot>? _posDailyLogSub;
  bool _posEnabled = false;
  List<Map<String, dynamic>> _posTiers = [];
  double _posCashAtHand = 0;
  DateTime? _posCashAtHandDate;
  Set<String> _posExcludedIds = {}; // tx IDs excluded from POS tracking
  // key: 'YYYY-MM-DD' → {cashAtHand: double, note: String}
  Map<String, Map<String, dynamic>> _posDailyLog = {};
  DateTime _posDashboardDate = DateTime.now(); // which day the POS dashboard shows

  // filters
  final _searchController = TextEditingController();
  Set<String> _selectedLabels = {};
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void dispose() {
    _padiSub?.cancel();
    _txSub?.cancel();
    _posSub?.cancel();
    _posExclusionSub?.cancel();
    _posDailyLogSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // — padiBook entries stream —
    _padiSub = FirebaseFirestore.instance
        .collection('padiBook')
        .doc(_uid)
        .collection('entries')
        .orderBy('date', descending: true)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        final tagged = <String>{};
        final seen = <String>{};
        final labels = <String>[];
        for (final doc in snap.docs) {
          final d = doc.data();
          final txId = d['transactionId'] as String?;
          if (txId != null && txId.isNotEmpty) tagged.add(txId);
          final lbl = (d['label'] as String?)?.trim() ?? '';
          if (lbl.isNotEmpty && seen.add(lbl)) labels.add(lbl);
        }
        setState(() {
          _padiDocs = snap.docs;
          _taggedTxIds = tagged;
          _recentLabels = labels;
          _padiLoading = false;
        });
      },
      onError: (e, st) => debugPrint('[PadiBook] entries stream error: $e\n$st'),
    );

    // — transactions stream (same filter as TagTransactionsPage) —
    _txSub = FirebaseFirestore.instance
        .collection('transactions')
        .where(
          Filter.or(
            Filter('userId', isEqualTo: _uid),
            Filter('actualSender', isEqualTo: _uid),
          ),
        )
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        const excluded = {'va_settlement', 'va_settlement_failed'};
        final filtered = snap.docs
            .where((d) =>
                !excluded.contains(d.data()['type']))
            .toList();
        setState(() {
          _txDocs = filtered;
          _txLoading = false;
        });
      },
      onError: (e, st) => debugPrint('[PadiBook] tx stream error: $e\n$st'),
    );

    // — POS agent settings stream —
    _posSub = FirebaseFirestore.instance
        .collection('posAgent')
        .doc(_uid)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        if (!snap.exists) return;
        final d = snap.data() as Map<String, dynamic>;
        final rawTiers = d['chargeTiers'];
        setState(() {
          _posEnabled = d['enabled'] as bool? ?? false;
          _posCashAtHand = (d['cashAtHand'] as num?)?.toDouble() ?? 0;
          final ts = d['cashAtHandUpdatedAt'];
          _posCashAtHandDate = ts is Timestamp ? ts.toDate() : null;
          if (rawTiers is List) {
            _posTiers = rawTiers
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        });
      },
      onError: (e, st) => debugPrint('[PadiBook] pos stream error: $e\n$st'),
    );

    // — POS exclusions stream —
    _posExclusionSub = FirebaseFirestore.instance
        .collection('posAgent')
        .doc(_uid)
        .collection('exclusions')
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _posExcludedIds = snap.docs.map((d) => d.id).toSet();
        });
      },
      onError: (e, st) =>
          debugPrint('[PadiBook] pos exclusions stream error: $e\n$st'),
    );

    // — POS daily log stream (cash-at-hand snapshots per day) —
    _posDailyLogSub = FirebaseFirestore.instance
        .collection('posAgent')
        .doc(_uid)
        .collection('dailyLog')
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        final log = <String, Map<String, dynamic>>{};
        for (final doc in snap.docs) {
          log[doc.id] = Map<String, dynamic>.from(doc.data());
        }
        setState(() => _posDailyLog = log);
      },
      onError: (e, st) =>
          debugPrint('[PadiBook] pos daily log stream error: $e\n$st'),
    );
  }

  // ── Auto-categorisation helpers ───────────────────────────────────────────

  static String _txStatusString(Map<String, dynamic> d) {
    if (d['api_response']?['data']?['attributes']?['status'] != null) {
      return d['api_response']['data']['attributes']['status']
          .toString()
          .toLowerCase();
    }
    if (d['fullData']?['attributes']?['status'] != null) {
      return d['fullData']['attributes']['status'].toString().toLowerCase();
    }
    if (d['status'] != null) {
      return d['status'].toString().toLowerCase();
    }
    return 'unknown';
  }

  static bool _isSuccessfulStatus(String status) {
    // Anchor statuses: 'approved', 'successful', 'success', 'processed'
    // Our NFC statuses: 'success'
    // Exclude: 'failed', 'pending', 'cancelled', 'reversed', 'unknown'
    const successStates = {'approved', 'successful', 'success', 'processed'};
    return successStates.contains(status);
  }

  /// Returns the POS charge for [amount] given [tiers], or 0 if no tier matches.
  double _calcPosCharge(double amount, List<Map<String, dynamic>> tiers) {
    for (final tier in tiers) {
      final min = (tier['minAmount'] as num).toDouble();
      final max = (tier['maxAmount'] as num).toDouble();
      if (amount >= min && amount <= max) {
        return (tier['charge'] as num).toDouble();
      }
    }
    return 0;
  }

  static String _categoryFromType(String type, bool isOutgoing) {
    const incomeTypes = {
      'add_money', 'fund', 'deposit', 'giveaway_claim', 'atm_payment',
    };
    if (incomeTypes.contains(type)) return 'income';
    if (!isOutgoing &&
        (type == 'transfer' ||
            type == 'ghost_transfer' ||
            type == 'anonymous_transfer')) {
      return 'income';
    }
    return 'expense';
  }

  static String _labelFromType(
      String type, String otherName, bool isOutgoing) {
    switch (type) {
      case 'transfer':
        return isOutgoing
            ? (otherName.isNotEmpty ? 'Transfer to $otherName' : 'Transfer')
            : (otherName.isNotEmpty ? 'Transfer from $otherName' : 'Transfer');
      case 'airtime':
        return otherName.isNotEmpty ? 'Airtime for $otherName' : 'Airtime Purchase';
      case 'data':
      case 'mobile_data':
        return otherName.isNotEmpty ? 'Data for $otherName' : 'Data Purchase';
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
      case 'atm_payment':
        return 'Card Payment';
      case 'loans':
        return isOutgoing ? 'Loan Disbursed' : 'Loan Received';
      case 'ghost_transfer':
        return 'Ghost Transfer';
      case 'anonymous_transfer':
        return 'Anonymous Transfer';
      case 'bill_payment':
        return otherName.isNotEmpty ? 'Bill – $otherName' : 'Bill Payment';
      case 'deposit':
        return otherName.isNotEmpty ? 'Transfer from $otherName' : 'Deposit';
      default:
        return otherName.isNotEmpty
            ? otherName
            : type.replaceAll('_', ' ');
    }
  }

  static DateTime _txDate(Map<String, dynamic> d) {
    final ts = d['timestamp'] ??
        d['createdAtFirestore'] ??
        d['createdAt'] ??
        d['createdAtUtc'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is String) {
      try {
        return DateTime.parse(ts);
      } catch (_) {}
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ── Merged entry list ─────────────────────────────────────────────────────

  List<_Entry> _getMergedEntries() {
    final entries = <_Entry>[];

    // 1. All padiBook entries (tagged + manual)
    for (final doc in _padiDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final ts = d['date'];
      DateTime? date;
      if (ts is Timestamp) date = ts.toDate();
      entries.add(_Entry(
        key: 'padi_${doc.id}',
        padiDocId: doc.id,
        label: d['label'] as String? ?? '',
        category: d['category'] as String? ?? 'expense',
        amount: (d['amount'] as num?)?.toDouble() ?? 0,
        date: date,
        note: d['note'] as String? ?? '',
        isManual: d['isManual'] as bool? ?? true,
        isAutoTx: false,
        txnTitle: d['transactionTitle'] as String?,
        qty: d['quantity'] as int?,
        padiData: d,
      ));
    }

    // 2. Auto entries from transactions not yet tagged in padiBook
    for (final doc in _txDocs) {
      if (_taggedTxIds.contains(doc.id)) continue;
      if (_posExcludedIds.contains(doc.id)) continue; // excluded from POS tracking
      final d = doc.data() as Map<String, dynamic>;

      // Only include completed/successful transactions
      final status = _txStatusString(d);
      if (!_isSuccessfulStatus(status)) continue;

      final type = (d['type'] ?? '').toString().toLowerCase();
      final isOutgoing = d['userId'] == _uid || d['actualSender'] == _uid;
      final amt =
          ((d['amount'] as num?) ?? (d['debitAmount'] as num? ?? 0)).toDouble();
      if (amt <= 0) continue;
      final otherName = (d['recipientName'] ??
              d['phoneNumber'] ??
              d['meterNumber'] ??
              d['account_number'] ??
              '') as String;
      entries.add(_Entry(
        key: 'tx_${doc.id}',
        padiDocId: null,
        label: _labelFromType(type, otherName, isOutgoing),
        category: _categoryFromType(type, isOutgoing),
        amount: amt,
        date: _txDate(d),
        note: '',
        isManual: false,
        isAutoTx: true,
        txnTitle: null,
        qty: null,
        padiData: null,
      ));
    }

    // 3. Sort by date descending
    entries.sort((a, b) {
      final ad = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return entries;
  }

  (double, double) _computeTotals(List<_Entry> entries) {
    double income = 0, expense = 0;
    for (final e in entries) {
      if (e.category == 'income') {
        income += e.amount;
      } else {
        expense += e.amount;
      }
    }
    return (income, expense);
  }

  void _showAddEntryChoiceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
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
              Text('Add to PadiBook',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 8),
              Text('Choose how you want to log this entry',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 24),
              _ChoiceCard(
                icon: Icons.history_outlined,
                title: 'Tag a Transaction',
                subtitle: 'Label what an existing transaction was for',
                onTap: () {
                  Navigator.pop(ctx);
                  navigateTo(context, const TagTransactionsPage(), type: NavigationType.push);
                },
              ),
              const SizedBox(height: 12),
              _ChoiceCard(
                icon: Icons.edit_note_outlined,
                title: 'Add Manual Entry',
                subtitle: 'Record an income or expense not in your history',
                onTap: () {
                  Navigator.pop(ctx);
                  _showManualEntrySheet();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showManualEntrySheet() {
    final amountCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String selectedCategory = 'expense';
    bool saving = false;
    bool showNote = false;
    bool showQty = false;
    final quantityCtrl = TextEditingController();

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
                        // Hero question — same as tag transaction
                        Text(
                          'What was this for?',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Log income or expense manually',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 22),
                        // Label field — first and autofocused, same as tag transaction
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
                              onPressed: () =>
                                  setModal(() => labelCtrl.clear()),
                            ),
                          ),
                        ),
                        // Recent chips
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
                                      color: primaryColor
                                          .withValues(alpha: 0.07),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      border: Border.all(
                                        color: primaryColor
                                            .withValues(alpha: 0.25),
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
                        // Amount field — after label, matches tag transaction flow
                        TextField(
                          controller: amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                            prefixText: '₦ ',
                            prefixStyle: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: selectedCategory == 'income'
                                  ? Colors.green.shade700
                                  : Colors.black87,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: focusedBorder,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Optional extras
                        Row(
                          children: [
                            _OptionalToggle(
                              label: 'Quantity',
                              active: showQty,
                              onTap: () =>
                                  setModal(() => showQty = !showQty),
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
                              final amountText = amountCtrl.text.trim();
                              final label = labelCtrl.text.trim();
                              if (amountText.isEmpty) {
                                showToast('Enter an amount', Colors.orange);
                                return;
                              }
                              if (label.isEmpty) {
                                showToast(
                                  'Enter what this was for',
                                  Colors.orange,
                                );
                                return;
                              }
                              final amount =
                                  double.tryParse(amountText) ?? 0;
                              if (amount <= 0) {
                                showToast(
                                  'Enter a valid amount',
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
                                    .doc(_uid)
                                    .collection('entries')
                                    .add({
                                  'label': label,
                                  'category': selectedCategory,
                                  'amount': amount,
                                  'note': noteCtrl.text.trim(),
                                  'date': Timestamp.now(),
                                  'isManual': true,
                                  'transactionId': null,
                                  if (qty != null) 'quantity': qty,
                                });
                                debugPrint(
                                  '[PadiBook] manual entry saved: "$label" category=$selectedCategory amount=$amount',
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
                                showToast('Entry saved!', Colors.green);
                              } catch (e, st) {
                                debugPrint(
                                  '[PadiBook] save manual entry error: $e\n$st',
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

  void _showEntriesFilter() {
    DateTime? tempFrom = _dateFrom;
    DateTime? tempTo = _dateTo;
    Set<String> tempLabels = Set.from(_selectedLabels);
    final addLabelCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModal) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Filter Entries',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 20),
                Text('Labels',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 10),
                // Recent label chips (multi-select)
                if (_recentLabels.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _recentLabels.take(20).map((lbl) {
                      final selected = tempLabels.contains(lbl.toLowerCase());
                      return GestureDetector(
                        onTap: () => setModal(() {
                          if (selected) {
                            tempLabels.remove(lbl.toLowerCase());
                          } else {
                            tempLabels.add(lbl.toLowerCase());
                          }
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? primaryColor : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? primaryColor : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            lbl,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: selected ? Colors.white : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                // Selected label tags (custom typed ones)
                if (tempLabels.any((l) => !_recentLabels.map((r) => r.toLowerCase()).contains(l))) ...[  
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tempLabels
                        .where((l) => !_recentLabels.map((r) => r.toLowerCase()).contains(l))
                        .map((lbl) => GestureDetector(
                          onTap: () => setModal(() => tempLabels.remove(lbl)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(lbl, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                              const SizedBox(width: 6),
                              const Icon(Icons.close, size: 13, color: Colors.white),
                            ]),
                          ),
                        )).toList(),
                  ),
                ],
                const SizedBox(height: 10),
                // Type to add a custom label
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: addLabelCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a label to add…',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: primaryColor, width: 1.5)),
                      ),
                      onSubmitted: (val) {
                        final v = val.trim().toLowerCase();
                        if (v.isNotEmpty) {
                          setModal(() { tempLabels.add(v); addLabelCtrl.clear(); });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      final v = addLabelCtrl.text.trim().toLowerCase();
                      if (v.isNotEmpty) {
                        setModal(() { tempLabels.add(v); addLabelCtrl.clear(); });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 20),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                Text('Date range',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: tempFrom ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          builder: (c, child) => Theme(
                            data: Theme.of(c).copyWith(
                              colorScheme: const ColorScheme.light(primary: primaryColor),
                            ),
                            child: child!,
                          ),
                        );
                        if (d != null) setModal(() => tempFrom = d);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tempFrom != null ? primaryColor : Colors.grey.shade200),
                        ),
                        child: Row(children: [
                          Icon(Icons.calendar_today, size: 15,
                              color: tempFrom != null ? primaryColor : Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Text(
                            tempFrom != null
                                ? '${tempFrom!.day}/${tempFrom!.month}/${tempFrom!.year}'
                                : 'From',
                            style: TextStyle(
                              color: tempFrom != null ? primaryColor : Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: tempTo ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          builder: (c, child) => Theme(
                            data: Theme.of(c).copyWith(
                              colorScheme: const ColorScheme.light(primary: primaryColor),
                            ),
                            child: child!,
                          ),
                        );
                        if (d != null) setModal(() => tempTo = d);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tempTo != null ? primaryColor : Colors.grey.shade200),
                        ),
                        child: Row(children: [
                          Icon(Icons.calendar_today, size: 15,
                              color: tempTo != null ? primaryColor : Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Text(
                            tempTo != null
                                ? '${tempTo!.day}/${tempTo!.month}/${tempTo!.year}'
                                : 'To',
                            style: TextStyle(
                              color: tempTo != null ? primaryColor : Colors.grey.shade500,
                              fontSize: 14,
                            ),
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
                        setState(() { _dateFrom = null; _dateTo = null; _selectedLabels = {}; });
                        Navigator.pop(ctx);
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Clear all', style: TextStyle(color: Colors.black54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _dateFrom = tempFrom;
                          _dateTo = tempTo != null
                              ? DateTime(tempTo!.year, tempTo!.month, tempTo!.day, 23, 59, 59)
                              : null;
                          _selectedLabels = tempLabels;
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
        });
      },
    );
  }

  void _showEntryOptions(_Entry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              if (entry.isAutoTx)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.label_outline, color: primaryColor),
                      title: const Text('Tag this transaction'),
                      subtitle: const Text('Add a custom label and category'),
                      onTap: () {
                        Navigator.pop(ctx);
                        navigateTo(context, const TagTransactionsPage(), type: NavigationType.push);
                      },
                    ),
                    if (_posEnabled)
                      ListTile(
                        leading: const Icon(Icons.block_outlined, color: Colors.orange),
                        title: const Text('Exclude from POS tracking'),
                        subtitle: const Text('Personal transfer — not a POS transaction'),
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await FirebaseFirestore.instance
                                .collection('posAgent')
                                .doc(_uid)
                                .collection('exclusions')
                                .doc(entry.key.replaceFirst('tx_', ''))
                                .set({
                              'excludedAt': FieldValue.serverTimestamp(),
                            });
                            showToast('Excluded from POS', Colors.orange);
                          } catch (e) {
                            showToast('Error: $e', Colors.red);
                          }
                        },
                      ),
                  ],
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: Colors.black87),
                  title: const Text('Edit entry'),
                  onTap: () { Navigator.pop(ctx); _showEditEntrySheet(entry); },
                ),
                if (!entry.isManual)
                  ListTile(
                    leading: const Icon(Icons.label_off_outlined, color: Colors.orange),
                    title: const Text('Untag transaction'),
                    subtitle: const Text('Removes this label from the transaction'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await FirebaseFirestore.instance
                            .collection('padiBook').doc(_uid).collection('entries').doc(entry.padiDocId!).delete();
                        debugPrint('[PadiBook] untagged entry ${entry.padiDocId}');
                        showToast('Transaction untagged', Colors.orange);
                      } catch (e, st) {
                        debugPrint('[PadiBook] untag error: $e\n$st');
                        showToast('Error: $e', Colors.red);
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete entry', style: TextStyle(color: Colors.red)),
                  onTap: () { Navigator.pop(ctx); _showDeleteConfirm(entry.padiDocId!); },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showEditEntrySheet(_Entry entry) {
    final labelCtrl = TextEditingController(text: entry.label);
    final noteCtrl = TextEditingController(text: entry.note);
    final existingQty = entry.qty;
    final quantityCtrl = TextEditingController(text: existingQty?.toString() ?? '');
    String selectedCategory = entry.category;
    bool showQty = existingQty != null;
    bool saving = false;


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
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Edit entry', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 20)),
                        const SizedBox(height: 20),
                        TextField(
                          controller: labelCtrl,
                          textCapitalization: TextCapitalization.sentences,
                          style: GoogleFonts.inter(fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'What was it for?',
                            filled: true, fillColor: Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: inputBorder, enabledBorder: inputBorder, focusedBorder: focusedBorder,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.all(4),
                          child: Row(children: [
                            _SegmentTab(label: '+ Income', isSelected: selectedCategory == 'income',
                                color: Colors.green, onTap: () => setModal(() => selectedCategory = 'income')),
                            _SegmentTab(label: '− Expense', isSelected: selectedCategory == 'expense',
                                color: Colors.red.shade400, onTap: () => setModal(() => selectedCategory = 'expense')),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        _OptionalToggle(
                          label: '+ Quantity',
                          active: showQty,
                          onTap: () => setModal(() => showQty = !showQty),
                        ),
                        if (showQty) ...[const SizedBox(height: 10),
                          TextField(
                            controller: quantityCtrl,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.inter(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Quantity',
                              filled: true, fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: inputBorder, enabledBorder: inputBorder, focusedBorder: focusedBorder,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextField(
                          controller: noteCtrl,
                          textCapitalization: TextCapitalization.sentences,
                          style: GoogleFonts.inter(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Note (optional)',
                            filled: true, fillColor: Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: inputBorder, enabledBorder: inputBorder, focusedBorder: focusedBorder,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: saving ? null : () async {
                        final label = labelCtrl.text.trim();
                        if (label.isEmpty) { showToast('Enter a label', Colors.orange); return; }
                        setModal(() => saving = true);
                        try {
                          final qty = int.tryParse(quantityCtrl.text.trim());
                          await FirebaseFirestore.instance
                              .collection('padiBook').doc(_uid).collection('entries').doc(entry.padiDocId!)
                              .update({
                            'label': label,
                            'category': selectedCategory,
                            'note': noteCtrl.text.trim(),
                            if (showQty && qty != null) 'quantity': qty
                            else ...{'quantity': FieldValue.delete()},
                          });
                          debugPrint('[PadiBook] edited entry ${entry.padiDocId}');
                          if (ctx.mounted) Navigator.pop(ctx);
                          showToast('Saved!', Colors.green);
                        } catch (e, st) {
                          debugPrint('[PadiBook] edit error: $e\n$st');
                          showToast('Error: $e', Colors.red);
                        } finally {
                          setModal(() => saving = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor, elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: saving
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text('Save', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
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

  // ── POS Agent Dashboard ───────────────────────────────────────────────────

  void _showPosCashOutSheet(
    List<Map<String, dynamic>> rows,
    double totalCashOut,
    String dayLabel,
  ) {
    final cf = _currencyFormat;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_upward,
                          color: Colors.red.shade400, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Cash Given Out — $dayLabel',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Total summary
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Text('Total disbursed',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600)),
                      const Spacer(),
                      Text(cf.format(totalCashOut),
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.red.shade600)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Column headers
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 3,
                          child: Text('Amount / Sender',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w600))),
                      Expanded(
                          flex: 2,
                          child: Text('Received',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w600))),
                      Expanded(
                          flex: 2,
                          child: Text('Cash Out',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
                const Divider(height: 12, indent: 20, endIndent: 20),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                              'No POS transactions for this day',
                              style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 13)))
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding:
                              const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final row = rows[i];
                            final amt =
                                (row['amount'] as num).toDouble();
                            final charge =
                                (row['charge'] as num).toDouble();
                            final cashOut =
                                (amt - charge).clamp(0.0, double.infinity);
                            final sender =
                                (row['sender'] as String);
                            final date = (row['date'] as DateTime);
                            final timeStr =
                                DateFormat('h:mm a').format(date);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(cf.format(amt),
                                            style: GoogleFonts.inter(
                                                fontWeight:
                                                    FontWeight.w600,
                                                fontSize: 13,
                                                color:
                                                    Colors.black87)),
                                        Text(
                                          sender.isNotEmpty
                                              ? sender
                                              : timeStr,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors
                                                  .grey.shade500),
                                        ),
                                        if (sender.isNotEmpty)
                                          Text(timeStr,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors
                                                      .grey.shade400)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(cf.format(amt),
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                        '−${cf.format(cashOut)}',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.red.shade500,
                                            fontWeight:
                                                FontWeight.w600)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPosTxBreakdown(
    List<Map<String, dynamic>> rows,
    double totalCharges,
    double totalBankCharges,
    double netProfit,
    String dayLabel,
  ) {
    final cf = _currencyFormat;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.trending_up, color: primaryColor, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Charges Breakdown — $dayLabel',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Summary totals bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _BreakdownSummaryChip(label: 'Gross', value: cf.format(totalCharges), color: Colors.blueGrey),
                      const Text('−', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      _BreakdownSummaryChip(label: 'Bank 0.25%', value: cf.format(totalBankCharges), color: Colors.red.shade400),
                      const Text('=', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      _BreakdownSummaryChip(label: 'Net', value: cf.format(netProfit), color: Colors.green),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Column headers
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text('Amount / Sender', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600))),
                      Expanded(flex: 2, child: Text('Gross', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                      Expanded(flex: 2, child: Text('Bank', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                      Expanded(flex: 2, child: Text('Net', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                    ],
                  ),
                ),
                const Divider(height: 12, indent: 20, endIndent: 20),
                // List
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text('No POS transactions for this day',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)))
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final row = rows[i];
                            final amt = (row['amount'] as num).toDouble();
                            final charge = (row['charge'] as num).toDouble();
                            final bank = (row['bankCharge'] as num).toDouble();
                            final net = (row['net'] as num).toDouble();
                            final sender = (row['sender'] as String);
                            final date = (row['date'] as DateTime);
                            final timeStr = DateFormat('h:mm a').format(date);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(cf.format(amt),
                                            style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: Colors.black87)),
                                        Text(
                                          sender.isNotEmpty ? sender : timeStr,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500),
                                        ),
                                        if (sender.isNotEmpty)
                                          Text(timeStr,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade400)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(cf.format(charge),
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.blueGrey)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text('−${cf.format(bank)}',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.red.shade400)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text('+${cf.format(net)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.green,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Format a DateTime as the daily log key: 'YYYY-MM-DD'
  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _buildPosDashboard() {
    final cf = _currencyFormat;
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);
    final selNorm = DateTime(
        _posDashboardDate.year, _posDashboardDate.month, _posDashboardDate.day);
    final isToday = selNorm == todayNorm;
    final dayKey = _dayKey(selNorm);

    // Resolve cash at hand for the selected day.
    // For today: use live _posCashAtHand. For past days: use daily log snapshot.
    double cashAtHand;
    String cashDateLabel;
    if (isToday) {
      cashAtHand = _posCashAtHand;
      cashDateLabel = _posCashAtHandDate != null
          ? 'Updated ${DateFormat('h:mm a').format(_posCashAtHandDate!)}'
          : 'Not set today';
    } else {
      final entry = _posDailyLog[dayKey];
      cashAtHand = (entry?['cashAtHand'] as num?)?.toDouble() ?? 0;
      final ts = entry?['setAt'];
      cashDateLabel = ts is Timestamp
          ? 'Set ${DateFormat('h:mm a').format(ts.toDate())}'
          : 'No record';
    }

    // Filter transactions for the selected day
    final selStart = selNorm;
    final selEnd = selNorm.add(const Duration(days: 1));

    double totalCashOut = 0;
    double totalCharges = 0;
    double totalBankCharges = 0;
    int txCount = 0;

    // Per-transaction breakdown for the detail sheet
    final List<Map<String, dynamic>> posTxRows = [];

    for (final doc in _txDocs) {
      if (_taggedTxIds.contains(doc.id)) continue;
      if (_posExcludedIds.contains(doc.id)) continue;
      final d = doc.data() as Map<String, dynamic>;
      final status = _txStatusString(d);
      if (!_isSuccessfulStatus(status)) continue;
      final type = (d['type'] ?? '').toString().toLowerCase();
      // atm_payment: userId is the merchant who received the card payment
      final isOutgoing = type != 'atm_payment' &&
          (d['userId'] == _uid || d['actualSender'] == _uid);
      if (isOutgoing) continue;
      if (type != 'transfer' && type != 'ghost_transfer' &&
          type != 'anonymous_transfer' && type != 'deposit' &&
          type != 'atm_payment') {
        continue;
      }
      final amt = ((d['amount'] as num?) ?? 0).toDouble();
      if (amt <= 0) continue;
      final date = _txDate(d);
      if (date.isBefore(selStart) || !date.isBefore(selEnd)) continue;
      final charge = _calcPosCharge(amt, _posTiers);
      final bankCharge = amt * 0.0025;
      final txNet = (charge - bankCharge).clamp(0.0, double.infinity).toDouble();
      totalCharges += charge;
      totalBankCharges += bankCharge;
      totalCashOut += (amt - charge).clamp(0.0, double.infinity).toDouble();
      txCount++;
      posTxRows.add({
        'amount': amt,
        'charge': charge,
        'bankCharge': bankCharge,
        'net': txNet,
        'sender': (d['senderName'] ?? d['sender'] ?? d['senderUsername'] ?? '').toString(),
        'date': date,
      });
    }

    final netProfit = (totalCharges - totalBankCharges).clamp(0.0, double.infinity).toDouble();
    final expectedCash = (cashAtHand - totalCashOut).clamp(0.0, double.infinity).toDouble();
    final dayLabel = isToday
        ? 'Today, ${DateFormat('d MMM').format(selNorm)}'
        : DateFormat('EEE d MMM yyyy').format(selNorm);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: primaryColor.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header with day navigation ──────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.point_of_sale, color: primaryColor, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('POS Agent',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: primaryColor)),
                ),
                // ◀ prev day
                GestureDetector(
                  onTap: () => setState(() => _posDashboardDate =
                      _posDashboardDate.subtract(const Duration(days: 1))),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.chevron_left,
                        color: primaryColor, size: 16),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _posDashboardDate,
                        firstDate: DateTime(2024),
                        lastDate: today,
                        builder: (c, child) => Theme(
                          data: Theme.of(c).copyWith(
                              colorScheme: const ColorScheme.light(
                                  primary: primaryColor)),
                          child: child!,
                        ),
                      );
                      if (picked != null && mounted) {
                        setState(() => _posDashboardDate = picked);
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today,
                            color: primaryColor, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          dayLabel,
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: primaryColor),
                        ),
                      ],
                    ),
                  ),
                ),
                // ▶ next day (disabled on today)
                GestureDetector(
                  onTap: isToday
                      ? null
                      : () => setState(() => _posDashboardDate =
                          _posDashboardDate.add(const Duration(days: 1))),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: isToday
                          ? Colors.grey.withValues(alpha: 0.1)
                          : primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.chevron_right,
                        color: isToday ? Colors.grey.shade400 : primaryColor,
                        size: 16),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => navigateTo(
                      context, const PosAgentSettingsPage(),
                      type: NavigationType.push),
                  child: const Icon(Icons.settings_outlined,
                      color: primaryColor, size: 17),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _PosStatTile(
                        label: 'Opening Cash',
                        value: cf.format(cashAtHand),
                        sub: cashDateLabel,
                        icon: Icons.account_balance_wallet_outlined,
                        iconColor: Colors.blueGrey,
                        onTap: isToday
                            ? () => navigateTo(
                                context, const PosAgentSettingsPage(),
                                type: NavigationType.push)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PosStatTile(
                        label: 'POS Txns',
                        value: '$txCount',
                        sub: 'received',
                        icon: Icons.swap_horiz,
                        iconColor: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _PosStatTile(
                        label: 'Cash Given Out',
                        value: cf.format(totalCashOut),
                        sub: 'tap to see per-txn',
                        icon: Icons.arrow_upward,
                        iconColor: Colors.red.shade400,
                        onTap: () => _showPosCashOutSheet(
                            posTxRows, totalCashOut, dayLabel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PosStatTile(
                        label: 'Net Profit',
                        value: '+${cf.format(netProfit)}',
                        sub: 'tap to see breakdown',
                        icon: Icons.trending_up,
                        iconColor: Colors.green,
                        onTap: () => _showPosTxBreakdown(
                          posTxRows, totalCharges, totalBankCharges, netProfit.toDouble(), dayLabel),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Charges breakdown row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined, size: 15, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Gross ${cf.format(totalCharges)}  −  Bank 0.25% ${cf.format(totalBankCharges)}  =  Net ${cf.format(netProfit)}',
                          style: TextStyle(fontSize: 11, color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Reconciliation row
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withValues(alpha: 0.08),
                        primaryColor.withValues(alpha: 0.03)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: primaryColor.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calculate_outlined,
                          color: primaryColor, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Expected Cash at Hand',
                                style: TextStyle(
                                    color: primaryColor.withValues(alpha: 0.8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(
                              '${cf.format(cashAtHand)} − ${cf.format(totalCashOut)} = ${cf.format(expectedCash)}',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: primaryColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_posTiers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: GestureDetector(
                      onTap: () => navigateTo(
                          context, const PosAgentSettingsPage(),
                          type: NavigationType.push),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_outlined,
                                size: 15, color: Colors.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No charge tiers set — tap to configure',
                                style: TextStyle(
                                    color: Colors.amber.shade800,
                                    fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  void _showDeleteConfirm(String docId) {    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.delete_outline, color: Colors.red, size: 40),
              const SizedBox(height: 12),
              Text('Delete Entry',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 8),
              const Text('Are you sure you want to delete this entry?',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        await FirebaseFirestore.instance
                            .collection('padiBook').doc(_uid).collection('entries').doc(docId).delete();
                        debugPrint('[PadiBook] deleted entry $docId');
                        showToast('Entry deleted', Colors.orange);
                      } catch (e, st) {
                        debugPrint('[PadiBook] delete error: $e\n$st');
                        showToast('Error: $e', Colors.red);
                      }
                    },
                    child: const Text('Delete', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.book_outlined, color: primaryColor, size: 26),
                      const SizedBox(width: 10),
                      Text('PadiBook',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black87)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => navigateTo(
                            context, const PosAgentSettingsPage(),
                            type: NavigationType.push),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _posEnabled
                                ? primaryColor.withValues(alpha: 0.12)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.point_of_sale,
                                  size: 15,
                                  color: _posEnabled ? primaryColor : Colors.grey.shade500),
                              const SizedBox(width: 5),
                              Text(
                                _posEnabled ? 'POS Agent Mode On' : 'POS',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _posEnabled
                                        ? primaryColor
                                        : Colors.grey.shade500,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Builder(builder: (_) {
                    final all = _getMergedEntries();
                    final (income, expense) = _computeTotals(all);
                    return _SummaryCard(
                      totalIncome: income,
                      totalExpense: expense,
                      currencyFormat: _currencyFormat,
                      dateFrom: _dateFrom,
                      dateTo: _dateTo,
                    );
                  }),
                ),
                const SizedBox(height: 16),
                // ── POS Agent Dashboard (only when enabled) ───────────────
                if (_posEnabled)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildPosDashboard(),
                  ),
                if (_posEnabled) const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: () => navigateTo(context, const TagTransactionsPage(), type: NavigationType.push),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.history_outlined, color: primaryColor, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Tag Transactions',
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600, fontSize: 14, color: primaryColor)),
                                Text('Label what your transactions were for',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: primaryColor),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Row(
                    children: [
                      Text('Book Entries',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                      const Spacer(),
                      if (_dateFrom != null || _dateTo != null || _selectedLabels.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() {
                            _dateFrom = null;
                            _dateTo = null;
                            _selectedLabels = {};
                            _searchController.clear();
                          }),
                          child: Text('Clear',
                              style: TextStyle(
                                  color: primaryColor, fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _showEntriesFilter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: (_dateFrom != null || _dateTo != null || _selectedLabels.isNotEmpty)
                                ? primaryColor
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune,
                                  size: 15,
                                  color: (_dateFrom != null || _dateTo != null || _selectedLabels.isNotEmpty)
                                      ? Colors.white
                                      : Colors.grey.shade700),
                              const SizedBox(width: 4),
                              Text('Filter',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: (_dateFrom != null || _dateTo != null || _selectedLabels.isNotEmpty)
                                          ? Colors.white
                                          : Colors.grey.shade700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                    ],
                  ),
                ),
                ..._buildEntriesSlivers(),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
            Positioned(
              bottom: 25, left: 0, right: 0,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: BottomNavBar(
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    if (index == 0) { navigateTo(context, const HomePage()); return; }
                    if (index == 2) { navigateTo(context, const MyBusiness()); return; }
                    if (index == 3) { navigateTo(context, const TransactionsHistory()); return; }
                    if (index == 4) { navigateTo(context, const ProfilePage()); return; }
                    if (index == 5) setState(() => _selectedIndex = 5);
                  },
                ),
              ),
            ),
            Positioned(
              bottom: 110, right: 24,
              child: FloatingActionButton(
                onPressed: _showAddEntryChoiceSheet,
                backgroundColor: primaryColor,
                elevation: 4,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_Entry> _applyFilters(List<_Entry> all) {
    return all.where((e) {
      if (_selectedLabels.isNotEmpty) {
        final lbl = e.label.toLowerCase();
        if (!_selectedLabels.any((sel) => lbl.contains(sel))) return false;
      }
      if (e.date != null) {
        if (_dateFrom != null && e.date!.isBefore(_dateFrom!)) return false;
        if (_dateTo != null && e.date!.isAfter(_dateTo!)) return false;
      }
      return true;
    }).toList();
  }

  List<Widget> _buildEntriesSlivers() {
    final loading = _padiLoading || _txLoading;
    if (loading) {
      return [
        const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator(color: primaryColor)),
        ),
      ];
    }

    final allEntries = _getMergedEntries();

    if (allEntries.isEmpty) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.book_outlined, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No entries yet',
                      style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Text('Tap + to tag a transaction\nor add a manual entry',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final entries = _applyFilters(allEntries);
    final hasFilter =
        _dateFrom != null || _dateTo != null || _selectedLabels.isNotEmpty;

    if (entries.isEmpty && hasFilter) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.filter_list_off, size: 50, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('No entries match your filter',
                    style: GoogleFonts.inter(
                        fontSize: 15, color: Colors.grey.shade600)),
              ]),
            ),
          ),
        ),
      ];
    }

    // Compute filtered P&L
    final (filtIncome, filtExpense) = _computeTotals(entries);
    final filtNet = filtIncome - filtExpense;

    return [
      if (hasFilter)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                Text(
                    '${entries.length} result${entries.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12)),
                const Spacer(),
                Text('In: ',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12)),
                Text(_currencyFormat.format(filtIncome),
                    style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
                const SizedBox(width: 10),
                Text('Out: ',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12)),
                Text(_currencyFormat.format(filtExpense),
                    style: TextStyle(
                        color: Colors.red.shade400,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
                const SizedBox(width: 10),
                Text('Net: ',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12)),
                Text(_currencyFormat.format(filtNet),
                    style: TextStyle(
                        color: filtNet >= 0
                            ? Colors.green
                            : Colors.red.shade400,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ]),
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final entry = entries[i];
              final isIncome = entry.category == 'income';

              final tile = GestureDetector(
                onTap: () => _showEntryOptions(entry),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isIncome
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isIncome
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          color: isIncome ? Colors.green : Colors.red,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.label,
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            if (entry.isAutoTx)
                              Text('Auto-tagged',
                                  style: TextStyle(
                                      color: Colors.blue.shade300,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic))
                            else if (!entry.isManual &&
                                entry.txnTitle != null)
                              Text(entry.txnTitle!,
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12))
                            else if (entry.isManual)
                              Text('Manual entry',
                                  style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic)),
                            if (entry.qty != null)
                              Text('Qty: ${entry.qty}',
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12)),
                            if (entry.note.isNotEmpty)
                              Text(entry.note,
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12)),
                            if (entry.date != null)
                              Text(
                                  '${entry.date!.day}/${entry.date!.month}/${entry.date!.year}',
                                  style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 11)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${isIncome ? '+' : '-'}${_currencyFormat.format(entry.amount)}',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isIncome
                                    ? Colors.green
                                    : Colors.red),
                          ),
                          const SizedBox(height: 4),
                          Icon(Icons.more_horiz,
                              size: 16, color: Colors.grey.shade400),
                        ],
                      ),
                    ],
                  ),
                ),
              );

              // Only padiBook-backed entries support swipe-to-delete
              if (entry.padiDocId != null) {
                return Dismissible(
                  key: Key(entry.key),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child:
                        const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  confirmDismiss: (_) async {
                    _showDeleteConfirm(entry.padiDocId!);
                    return false;
                  },
                  child: tile,
                );
              }
              return KeyedSubtree(key: Key(entry.key), child: tile);
            },
          ),
        ),
    ];
  }
}



class _SummaryCard extends StatelessWidget {
  final double totalIncome;
  final double totalExpense;
  final NumberFormat currencyFormat;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  const _SummaryCard({
    required this.totalIncome,
    required this.totalExpense,
    required this.currencyFormat,
    this.dateFrom,
    this.dateTo,
  });

  String _periodLabel() {
    final fmt = DateFormat('d MMM yyyy');
    if (dateFrom == null && dateTo == null) return 'All time';
    if (dateFrom != null && dateTo != null) {
      return '${fmt.format(dateFrom!)} – ${fmt.format(dateTo!)}';
    }
    if (dateFrom != null) return 'From ${fmt.format(dateFrom!)}';
    return 'Up to ${fmt.format(dateTo!)}';
  }

  @override
  Widget build(BuildContext context) {
    final net = totalIncome - totalExpense;
    final netSign = net >= 0 ? '+' : '−';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF007AFF), Color(0xFF0055CC)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          // Period label
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 11, color: Colors.white.withValues(alpha: 0.6)),
              const SizedBox(width: 5),
              Text(
                _periodLabel(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _SummaryTile(
                label: 'Income',
                value: '+${currencyFormat.format(totalIncome)}',
                icon: Icons.arrow_downward,
                color: Colors.greenAccent,
              ),
            ),
            Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.3)),
            Expanded(
              child: _SummaryTile(
                label: 'Expense',
                value: '−${currencyFormat.format(totalExpense)}',
                icon: Icons.arrow_upward,
                color: Colors.redAccent.shade100,
              ),
            ),
          ]),
          const Divider(color: Colors.white24, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Net: ', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
              Text(
                '$netSign${currencyFormat.format(net.abs())}',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 16,
                    color: net >= 0 ? Colors.greenAccent : Colors.redAccent.shade100)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryTile({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
      const SizedBox(height: 4),
      Text(value,
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
          overflow: TextOverflow.ellipsis),
    ]);
  }
}

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

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ChoiceCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: primaryColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }
}

class _PosStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  const _PosStatTile({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _BreakdownSummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _BreakdownSummaryChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.bold, fontSize: 12, color: color)),
      ],
    );
  }
}
