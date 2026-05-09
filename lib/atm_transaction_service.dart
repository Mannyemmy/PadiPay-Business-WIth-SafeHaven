import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:padi_pay_business/utils.dart';

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

  bool get hasPending => _pendingCompleter != null && !_pendingCompleter!.isCompleted;

  void startTransaction({
    required String rrn,
    required double amount,
    required String chargedAmount,
    required String tag,
    String? safeHavenRrn,
  }) {
    // If there's already a pending transaction, clear it first (prevents "already processing")
    if (hasPending) {
      debugPrint('[TransactionService] WARNING: Starting new transaction while previous pending. Completing previous with error.');
      _pendingCompleter?.completeError(Exception('Previous transaction interrupted'));
      _clear();
    }
    _pendingCompleter = Completer<String>();
    _pendingRrn = rrn;
    _pendingAmount = amount;
    _pendingChargedAmount = chargedAmount;
    _pendingTag = tag;
    _pendingSafeHavenRrn = safeHavenRrn;
    debugPrint('[TransactionService] Transaction started: rrn=$rrn amount=$amount');
  }

  Future<String> get future {
    if (_pendingCompleter == null) {
      throw StateError('No transaction started. Call startTransaction first.');
    }
    return _pendingCompleter!.future;
  }

  void completeSuccess(String cardData) {
    if (!hasPending) {
      debugPrint('[TransactionService] completeSuccess called but no pending transaction');
      return;
    }
    debugPrint('[TransactionService] Completing success: rrn=$_pendingRrn');
    _saveTransactionAndSettle(cardData);
    _pendingCompleter!.complete(cardData);
    _clear();
  }

  void completeError(Object error) {
    if (!hasPending) {
      debugPrint('[TransactionService] completeError called but no pending transaction');
      return;
    }
    debugPrint('[TransactionService] Completing error: $_pendingRrn');
    _pendingCompleter!.completeError(error);
    _clear();
  }

  void _saveTransactionAndSettle(String cardData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final docRef = await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user?.uid,
        'type': 'atm_payment',
        'amount': _pendingAmount,
        'rrn': _pendingRrn,
        'reference': _pendingRrn,
        if (_pendingSafeHavenRrn != null && _pendingSafeHavenRrn!.isNotEmpty) 'safeHavenRrn': _pendingSafeHavenRrn,
        'terminalId': '2ISWH246',
        'status': 'success',
        'currency': 'NGN',
        'cardData': cardData,
        if (_pendingTag != null && _pendingTag!.isNotEmpty) 'tag': _pendingTag,
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('[TransactionService] Saved ATM transaction docId=${docRef.id}');

      if (user != null) {
        final label = _pendingTag != null && _pendingTag!.isNotEmpty ? _pendingTag! : 'Card Payment';
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

      // Settlement (you can implement here or keep calling from the screen)
      debugPrint('[TransactionService] Settlement not implemented here – will be handled by the screen');
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
  }
}