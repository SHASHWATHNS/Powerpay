// lib/services/transaction_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TransactionService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) throw Exception('Not logged in');
    return u.uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(_uid).collection('transactions');

  // create a PENDING transaction and return its doc id
  Future<String> createPending({
    required String number,
    required String operatorName,
    required int amount,
  }) async {
    final doc = await _col.add({
      'number': number,
      'operator': operatorName,
      'amount': amount,
      'status': 'pending',
      'failureReason': null,
      'createdAt': FieldValue.serverTimestamp(), // auto timestamp
    });
    return doc.id;
  }

  Future<void> markStatus({
    required String id,
    required String status, // 'success' | 'failed' | 'pending'
    String? failureReason,
  }) {
    return _col.doc(id).update({
      'status': status,
      'failureReason': failureReason,
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String id) =>
      _col.doc(id).snapshots();

  // for history page
  Stream<List<TransactionRecord>> streamMyTransactions() => _col
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((q) => q.docs.map((d) => TransactionRecord.fromMap(d.id, d.data())).toList());
}

class TransactionRecord {
  final String id, number, operatorName, status;
  final int amount;
  final String? failureReason;
  final DateTime createdAt;

  TransactionRecord({
    required this.id,
    required this.number,
    required this.operatorName,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.failureReason,
  });

  factory TransactionRecord.fromMap(String id, Map<String, dynamic> m) {
    final ts = m['createdAt'];
    return TransactionRecord(
      id: id,
      number: (m['number'] ?? '') as String,
      operatorName: (m['operator'] ?? '') as String,
      amount: (m['amount'] ?? 0) as int,
      status: (m['status'] ?? 'pending') as String,
      failureReason: m['failureReason'] as String?,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
