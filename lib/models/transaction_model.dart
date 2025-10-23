import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionRecord {
  final double amount;
  final DateTime createdAt;
  final String description;
  final String status; // 'success', 'failed', 'pending'
  final String type; // DEBIT or CREDIT

  // Extra fields (optional for UI)
  final String operatorName;
  final String number;

  TransactionRecord({
    required this.amount,
    required this.createdAt,
    required this.description,
    required this.status,
    required this.type,
    this.operatorName = 'Wallet Top-up',
    this.number = '',
  });

  factory TransactionRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Defensive parsing
    final rawAmount = (data['amount'] as num?) ?? 0;
    final ts = data['createdAt'];
    DateTime created;
    if (ts is Timestamp) {
      created = ts.toDate();
    } else if (ts is DateTime) {
      created = ts;
    } else {
      created = DateTime.now();
    }

    String desc = (data['description'] ?? 'Transaction').toString();
    String opName = (data['operatorName'] ?? 'Wallet Top-up').toString();
    String numberVal = (data['number'] ?? '').toString();

    // Backward-compatible description parsing
    if (desc.startsWith('Mobile Recharge for')) {
      opName = 'Recharge';
      final parts = desc.trim().split(' ');
      if (parts.isNotEmpty) {
        numberVal = parts.last;
      }
    }

    return TransactionRecord(
      amount: rawAmount.abs().toDouble(), // display as positive
      createdAt: created,
      description: desc,
      status: (data['status'] ?? 'success').toString(),
      type: (data['type'] ?? 'UNKNOWN').toString(),
      operatorName: opName,
      number: numberVal,
    );
  }
}
