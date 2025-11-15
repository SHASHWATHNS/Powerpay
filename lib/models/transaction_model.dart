// lib/models/transaction_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionRecord {
  final String id;
  final double amount;
  final String type; // 'CREDIT' or 'DEBIT' or other
  final String status; // e.g. 'success', 'failed', 'initiated'
  final String operatorName; // operator or source label
  final String number; // mobile number for recharge, or empty for others
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  TransactionRecord({
    required this.id,
    required this.amount,
    required this.type,
    required this.status,
    required this.operatorName,
    required this.number,
    required this.createdAt,
    required this.raw,
  });

  static DateTime _parseTimestamp(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory TransactionRecord.fromMap(String id, Map<String, dynamic> data) {
    final amount = (data['amount'] is num) ? (data['amount'] as num).toDouble()
        : double.tryParse((data['amount'] ?? '0').toString()) ?? 0.0;

    // Determine type heuristically: for recharges we treat as DEBIT, wallet inflows as CREDIT
    String type = (data['type'] ?? '').toString().toUpperCase();
    if (type.isEmpty) {
      // guess based on collection fields
      if (data.containsKey('uid') && data.containsKey('mobile')) {
        type = 'DEBIT';
      } else {
        type = (amount >= 0) ? 'CREDIT' : 'DEBIT';
      }
    }

    final status = (data['status'] ?? data['state'] ?? 'initiated').toString().toLowerCase();
    final operatorName = (data['operator'] ?? data['source'] ?? data['provider'] ?? '').toString();
    final number = (data['mobile'] ?? data['number'] ?? '').toString();

    final createdAt = _parseTimestamp(data['createdAt'] ?? data['timestamp'] ?? data['ts'] ?? data['server_time']);

    return TransactionRecord(
      id: id,
      amount: amount,
      type: type,
      status: status,
      operatorName: operatorName,
      number: number,
      createdAt: createdAt,
      raw: Map<String, dynamic>.from(data),
    );
  }
}
