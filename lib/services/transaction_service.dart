import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction_model.dart';

final transactionServiceProvider = Provider((ref) {
  return TransactionService(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

class TransactionService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  TransactionService(this._auth, this._firestore);

  String? get _uid => _auth.currentUser?.uid;

  Stream<List<TransactionRecord>> streamMyTransactions() {
    if (_uid == null) return Stream.value([]);

    final query = _firestore
        .collection('users')
        .doc(_uid)
        .collection('wallet_ledger')
        .orderBy('createdAt', descending: true)
        .limit(50);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => TransactionRecord.fromFirestore(doc)).toList();
    });
  }

  // ✅ ADDED: Missing method to create a pending transaction record
  Future<String> createPending({
    required String number,
    required String operatorName,
    required int amount,
  }) async {
    if (_uid == null) throw Exception('User not logged in');

    final docRef = _firestore
        .collection('users')
        .doc(_uid)
        .collection('wallet_ledger')
        .doc(); // Firestore automatically generates the ID

    await docRef.set({
      'amount': -amount, // Debits are negative
      'type': 'DEBIT',
      'description': 'Mobile Recharge for $number',
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
      'operatorName': operatorName,
      'number': number,
    });
    return docRef.id;
  }

  // ✅ ADDED: Missing method to update the status of a transaction
  Future<void> markStatus({
    required String id,
    required String status,
    String? failureReason,
  }) async {
    if (_uid == null) throw Exception('User not logged in');

    final docRef = _firestore
        .collection('users')
        .doc(_uid)
        .collection('wallet_ledger')
        .doc(id);

    await docRef.update({
      'status': status,
      if (failureReason != null) 'failureReason': failureReason,
    });
  }
}