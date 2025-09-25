import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionRecord {
  final String id;
  final String number;
  final String operatorName;
  final int amount;
  final String status; // 'pending' | 'success' | 'failed'
  final DateTime createdAt;
  final String? failureReason;

  TransactionRecord({
    required this.id,
    required this.number,
    required this.operatorName,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.failureReason,
  });
}