import 'package:cloud_firestore/cloud_firestore.dart';

// Unified model for all transaction ledger entries
class TransactionRecord {
  final double amount;
  final DateTime createdAt;
  final String description;
  final String status; // 'success', 'failed', 'pending'
  final String type; // DEBIT or CREDIT
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
    final rawAmount = (data['amount'] as num?) ?? 0;

    return TransactionRecord(
      amount: rawAmount.abs().toDouble(), // Always display as a positive number
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      description: (data['description'] ?? 'Transaction').toString(),
      status: (data['status'] ?? 'success').toString(),
      type: (data['type'] ?? 'UNKNOWN').toString(),
      operatorName: (data['operatorName'] ?? (rawAmount > 0 ? 'Wallet Top-up' : 'Recharge')).toString(),
      number: (data['number'] ?? '').toString(),
    );
  }
}

// Model for number lookup details
class NumberDetails {
  final String carrier;
  final String location;

  NumberDetails({required this.carrier, required this.location});
}