import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:padi_pay_business/utils.dart';

class PosAgentSettingsPage extends StatefulWidget {
  const PosAgentSettingsPage({super.key});

  @override
  State<PosAgentSettingsPage> createState() => _PosAgentSettingsPageState();
}

class _PosAgentSettingsPageState extends State<PosAgentSettingsPage> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  final _currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);

  bool _loading = true;
  final bool _saving = false;

  bool _posEnabled = false;
  List<Map<String, dynamic>> _tiers = [];

  // Cash at hand
  double _cashAtHand = 0;
  DateTime? _cashAtHandDate;

  DocumentReference get _posDoc =>
      FirebaseFirestore.instance.collection('posAgent').doc(_uid);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await _posDoc.get();
      if (snap.exists) {
        final d = snap.data() as Map<String, dynamic>;
        final rawTiers = d['chargeTiers'];
        setState(() {
          _posEnabled = d['enabled'] as bool? ?? false;
          _cashAtHand = (d['cashAtHand'] as num?)?.toDouble() ?? 0;
          final ts = d['cashAtHandUpdatedAt'];
          _cashAtHandDate = ts is Timestamp ? ts.toDate() : null;
          if (rawTiers is List) {
            _tiers = rawTiers
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        });
      } else {
        // Default tiers for a new POS agent
        setState(() {
          _tiers = [
            {'minAmount': 1000.0, 'maxAmount': 3000.0, 'charge': 100.0},
            {'minAmount': 3001.0, 'maxAmount': 7000.0, 'charge': 200.0},
            {'minAmount': 7001.0, 'maxAmount': 15000.0, 'charge': 300.0},
            {'minAmount': 15001.0, 'maxAmount': 30000.0, 'charge': 400.0},
            {'minAmount': 30001.0, 'maxAmount': 50000.0, 'charge': 500.0},
          ];
        });
      }
    } catch (e) {
      debugPrint('[POS] load error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    // kept for compatibility — all fields now save automatically
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveTiers() async {
    try {
      await _posDoc.set(
        {'chargeTiers': _tiers, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[POS] tiers save error: $e');
      if (mounted) showToast('Error saving tiers: $e', Colors.red);
    }
  }

  Future<void> _updateCashAtHand(double amount) async {
    try {
      final now = DateTime.now();
      final dateKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await Future.wait([
        _posDoc.set({
          'cashAtHand': amount,
          'cashAtHandUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
        _posDoc.collection('dailyLog').doc(dateKey).set({
          'cashAtHand': amount,
          'setAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      ]);
      setState(() {
        _cashAtHand = amount;
        _cashAtHandDate = now;
      });
      showToast('Cash at hand updated', Colors.green);
    } catch (e) {
      showToast('Error: $e', Colors.red);
    }
  }

  void _showEditTierSheet({Map<String, dynamic>? existing, int? index}) {
    final minCtrl = TextEditingController(
        text: existing != null ? (existing['minAmount'] as num).toStringAsFixed(0) : '');
    final maxCtrl = TextEditingController(
        text: existing != null ? (existing['maxAmount'] as num).toStringAsFixed(0) : '');
    final chargeCtrl = TextEditingController(
        text: existing != null ? (existing['charge'] as num).toStringAsFixed(0) : '');

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade200),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: primaryColor, width: 1.5),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 16),
              Text(
                existing != null ? 'Edit Charge Tier' : 'Add Charge Tier',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                'Set the amount range and charge for this tier',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.inter(fontSize: 15),
                    decoration: InputDecoration(
                      labelText: 'Min Amount (₦)',
                      hintText: '1000',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: border,
                      enabledBorder: border,
                      focusedBorder: focusedBorder,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.inter(fontSize: 15),
                    decoration: InputDecoration(
                      labelText: 'Max Amount (₦)',
                      hintText: '3000',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: border,
                      enabledBorder: border,
                      focusedBorder: focusedBorder,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: chargeCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.inter(fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Charge (₦)',
                  hintText: '100',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: border,
                  enabledBorder: border,
                  focusedBorder: focusedBorder,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  prefixText: '₦ ',
                  prefixStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w600, color: primaryColor),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                if (existing != null && index != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _tiers.removeAt(index));
                        Navigator.pop(ctx);
                        _saveTiers();
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Delete',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final min = double.tryParse(minCtrl.text.trim());
                      final max = double.tryParse(maxCtrl.text.trim());
                      final charge = double.tryParse(chargeCtrl.text.trim());
                      if (min == null || max == null || charge == null) {
                        showToast('Enter valid numbers', Colors.orange);
                        return;
                      }
                      if (min >= max) {
                        showToast('Min must be less than max', Colors.orange);
                        return;
                      }
                      final tier = {
                        'minAmount': min,
                        'maxAmount': max,
                        'charge': charge,
                      };
                      setState(() {
                        if (index != null) {
                          _tiers[index] = tier;
                        } else {
                          _tiers.add(tier);
                          _tiers.sort((a, b) =>
                              (a['minAmount'] as num)
                                  .compareTo(b['minAmount'] as num));
                        }
                      });
                      Navigator.pop(ctx);
                      _saveTiers();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Save',
                        style: GoogleFonts.inter(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
      );
  }

  void _showCashAtHandSheet() {
    String fmtCommas(String digits) {
      if (digits.isEmpty) return '';
      final n = int.tryParse(digits);
      if (n == null) return digits;
      return NumberFormat('#,##0').format(n);
    }

    final ctrl = TextEditingController(
        text: _cashAtHand > 0 ? fmtCommas(_cashAtHand.toInt().toString()) : '');
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade200),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: primaryColor, width: 1.5),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 16),
              Text('Cash at Hand',
                  style:
                      GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                'How much physical cash do you have right now?',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: GoogleFonts.inter(
                    fontSize: 22, fontWeight: FontWeight.w700),
                onChanged: (value) {
                  final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                  final formatted = fmtCommas(digits);
                  if (formatted != value) {
                    ctrl.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                          offset: formatted.length),
                    );
                  }
                },
                decoration: InputDecoration(
                  hintText: '100,000',
                  hintStyle: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 22,
                      fontWeight: FontWeight.w700),
                  prefixText: '₦ ',
                  prefixStyle: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: primaryColor),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: border,
                  enabledBorder: border,
                  focusedBorder: focusedBorder,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    final amount = double.tryParse(
                        ctrl.text.replaceAll(',', '').trim());
                    if (amount == null || amount < 0) {
                      showToast('Enter a valid amount', Colors.orange);
                      return;
                    }
                    Navigator.pop(ctx);
                    await _updateCashAtHand(amount);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Set Cash',
                      style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
      
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    final dateLabel = _cashAtHandDate != null
        ? 'Set ${DateFormat('d MMM, h:mm a').format(_cashAtHandDate!)}'
        : 'Not set today';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('POS Agent Mode',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black87)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Enable toggle ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _posEnabled
                  ? const Color(0xFF007AFF).withValues(alpha: 0.06)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _posEnabled
                    ? const Color(0xFF007AFF).withValues(alpha: 0.3)
                    : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _posEnabled
                        ? primaryColor.withValues(alpha: 0.15)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.point_of_sale,
                    color: _posEnabled ? primaryColor : Colors.grey,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('POS Agent Mode',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.black87)),
                      const SizedBox(height: 2),
                      Text(
                        'Auto-track cash disbursed and charges earned',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _posEnabled,
                  activeColor: primaryColor,
                  onChanged: (v) async {
                    setState(() => _posEnabled = v);
                    try {
                      await _posDoc.set(
                        {'enabled': v, 'updatedAt': FieldValue.serverTimestamp()},
                        SetOptions(merge: true),
                      );
                    } catch (e) {
                      debugPrint('[POS] toggle error: $e');
                      if (mounted) setState(() => _posEnabled = !v); // revert on error
                    }
                  },
                ),
              ],
            ),
          ),

          if (_posEnabled) ...[
            const SizedBox(height: 24),

            // ── Cash at Hand ───────────────────────────────────────────
            Text('Cash at Hand',
                style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showCashAtHandSheet,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        color: primaryColor, size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currencyFormat.format(_cashAtHand),
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.black87),
                          ),
                          const SizedBox(height: 2),
                          Text(dateLabel,
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Update',
                          style: TextStyle(
                              color: primaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Charge Tiers ───────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Charge Tiers',
                          style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text('Per transaction amount range',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 11)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _showEditTierSheet(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, color: Colors.white, size: 15),
                        const SizedBox(width: 4),
                        Text('Add Tier',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_tiers.isEmpty)
              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text('No tiers yet — tap Add Tier',
                    style: TextStyle(color: Colors.grey.shade400)),
              )
            else
              ..._tiers.asMap().entries.map((entry) {
                final i = entry.key;
                final tier = entry.value;
                final min = (tier['minAmount'] as num).toDouble();
                final max = (tier['maxAmount'] as num).toDouble();
                final charge = (tier['charge'] as num).toDouble();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () =>
                        _showEditTierSheet(existing: tier, index: i),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 6,
                              offset: const Offset(0, 1)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    color: primaryColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '₦${_fmt(min)} – ₦${_fmt(max)}',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                                Text('Range',
                                    style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('₦${_fmt(charge)}',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.green.shade700)),
                              Text('charge',
                                  style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 11)),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.edit_outlined,
                              size: 16, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                );
              }),

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Charges are matched to the transfer amount received. '
                      'Cash given out = transfer amount − charge.',
                      style: TextStyle(
                          color: Colors.amber.shade800, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: primaryColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Done',
                  style: GoogleFonts.inter(
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000) {
      return NumberFormat('#,##0', 'en').format(v);
    }
    return v.toStringAsFixed(0);
  }
}
