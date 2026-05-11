import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TransactionService {
  static final TransactionService _instance = TransactionService._internal();
  factory TransactionService() => _instance;
  TransactionService._internal();

  Completer<String>? _pendingCompleter;
  String? _pendingRrn;
  double? _pendingAmount;
  String? _pendingChargedAmount;
  String? _pendingTag;
  String? _pendingSafeHavenRrn;

  // Tracks the last transaction's RRN and whether it ended in success,
  // so late callbacks arriving after a timeout can be detected and handled.
  String? _lastRrn;
  bool _lastWasSuccess = false;

  /// True while a transaction is in-flight (completer exists and not done).
  bool get hasPending =>
      _pendingCompleter != null && !_pendingCompleter!.isCompleted;

  /// True once the completer has been resolved (success OR error) or is null.
  /// Use this to detect a late callback after the UI timeout fired.
  bool get isCompleted =>
      _pendingCompleter == null || _pendingCompleter!.isCompleted;

  /// The RRN of the most recently started transaction (survives _clear()).
  String? get lastRrn => _lastRrn;

  /// Whether the most recently completed transaction was a success.
  bool get lastWasSuccess => _lastWasSuccess;

  void startTransaction({
    required String rrn,
    required double amount,
    required String chargedAmount,
    required String tag,
    String? safeHavenRrn,
  }) {
    if (hasPending) {
      debugPrint(
        '[TransactionService] WARNING: new tx started while previous pending — interrupting previous.',
      );
      _pendingCompleter?.completeError(
        Exception('Previous transaction interrupted'),
      );
      _clear();
    }
    _pendingCompleter = Completer<String>();
    _pendingRrn = rrn;
    _pendingAmount = amount;
    _pendingChargedAmount = chargedAmount;
    _pendingTag = tag;
    _pendingSafeHavenRrn = safeHavenRrn;

    // Remember for late-callback detection
    _lastRrn = rrn;
    _lastWasSuccess = false;

    debugPrint(
      '[TransactionService] Transaction started: rrn=$rrn amount=$amount',
    );
  }

  Future<String> get future {
    if (_pendingCompleter == null) {
      throw StateError('No transaction started. Call startTransaction first.');
    }
    return _pendingCompleter!.future;
  }

  void completeSuccess(String cardData) {
    if (!hasPending) {
      debugPrint(
        '[TransactionService] completeSuccess called but no pending transaction',
      );
      return;
    }
    debugPrint('[TransactionService] Completing success: rrn=$_pendingRrn');
    _lastWasSuccess = true;
    _saveTransactionAndSettle(cardData);
    _pendingCompleter!.complete(cardData);
    _clear();
  }

  void completeError(Object error) {
    if (!hasPending) {
      debugPrint(
        '[TransactionService] completeError called but no pending transaction',
      );
      return;
    }
    debugPrint('[TransactionService] Completing error: rrn=$_pendingRrn');
    _lastWasSuccess = false;
    _pendingCompleter!.completeError(error);
    _clear();
  }

  /// Call this when a SUCCESS callback arrives AFTER the UI timeout already
  /// fired (i.e. [isCompleted] is true but [lastWasSuccess] is false).
  /// Saves the transaction to Firestore and padiBook, then marks the last
  /// transaction as success so duplicate calls are ignored.
  ///
  /// Returns true if the save was performed, false if it was skipped
  /// (e.g. already recorded as success, or the RRN doesn't match).
  Future<bool> handleLateSuccess({
    required String cardData,
    required String rrn,
    required double amount,
    required String tag,
  }) async {
    // Guard: only handle if this matches the last known RRN and wasn't
    // already recorded as success.
    if (_lastWasSuccess) {
      debugPrint(
        '[TransactionService] handleLateSuccess ignored — already recorded success',
      );
      return false;
    }
    if (_lastRrn != rrn) {
      debugPrint(
        '[TransactionService] handleLateSuccess ignored — RRN mismatch '
        '(expected $_lastRrn, got $rrn)',
      );
      return false;
    }

    debugPrint(
      '[TransactionService] ⚠️ Late success for rrn=$rrn — saving now',
    );

    // Mark immediately to prevent a second call from double-saving.
    _lastWasSuccess = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user?.uid,
        'type': 'atm_payment',
        'amount': amount,
        'rrn': rrn,
        'reference': rrn,
        'terminalId': '2ISWH246',
        'status': 'success',
        'currency': 'NGN',
        'cardData': cardData,
        if (tag.isNotEmpty) 'tag': tag,
        'note': 'late_callback_after_ui_timeout',
        'timestamp': FieldValue.serverTimestamp(),
      });

      debugPrint('[TransactionService] ✅ Late tx saved to Firestore');

      if (user != null) {
        final label = tag.isNotEmpty ? tag : 'Card Payment';
        await FirebaseFirestore.instance
            .collection('padiBook')
            .doc(user.uid)
            .collection('entries')
            .add({
              'label': label,
              'category': 'income',
              'amount': amount,
              'note': '',
              'date': Timestamp.now(),
              'isManual': false,
              'transactionId': rrn,
              'transactionTitle': 'NFC Card Payment',
            });
        debugPrint('[TransactionService] ✅ Late tx saved to padiBook');
      }

      return true;
    } catch (e) {
      debugPrint('[TransactionService] handleLateSuccess save failed: $e');
      // Reset so a retry can attempt saving again
      _lastWasSuccess = false;
      return false;
    }
  }

  void _saveTransactionAndSettle(String cardData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final docRef = await FirebaseFirestore.instance
          .collection('transactions')
          .add({
            'userId': user?.uid,
            'type': 'atm_payment',
            'amount': _pendingAmount,
            'rrn': _pendingRrn,
            'reference': _pendingRrn,
            if (_pendingSafeHavenRrn != null &&
                _pendingSafeHavenRrn!.isNotEmpty)
              'safeHavenRrn': _pendingSafeHavenRrn,
            'terminalId': '2ISWH246',
            'status': 'success',
            'currency': 'NGN',
            'cardData': cardData,
            if (_pendingTag != null && _pendingTag!.isNotEmpty)
              'tag': _pendingTag,
            'timestamp': FieldValue.serverTimestamp(),
          });
      debugPrint(
        '[TransactionService] Saved ATM transaction docId=${docRef.id}',
      );

      if (user != null) {
        final label =
            _pendingTag != null && _pendingTag!.isNotEmpty
                ? _pendingTag!
                : 'Card Payment';
        await FirebaseFirestore.instance
            .collection('padiBook')
            .doc(user.uid)
            .collection('entries')
            .add({
              'label': label,
              'category': 'income',
              'amount': _pendingAmount,
              'note': '',
              'date': Timestamp.now(),
              'isManual': false,
              'transactionId': _pendingRrn,
              'transactionTitle': 'NFC Card Payment',
            });
      }

      debugPrint(
        '[TransactionService] Settlement will be handled by the screen',
      );
    } catch (e) {
      debugPrint('[TransactionService] Failed to save: $e');
    }
  }

  void _clear() {
    _pendingCompleter = null;
    _pendingRrn = null;
    _pendingAmount = null;
    _pendingChargedAmount = null;
    _pendingTag = null;
    _pendingSafeHavenRrn = null;
    // _lastRrn and _lastWasSuccess are intentionally NOT cleared here —
    // they must survive _clear() so late callbacks can still be detected.
  }
}