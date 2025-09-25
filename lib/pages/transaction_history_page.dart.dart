import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:powerpay/models/transaction_record.dart' hide TransactionRecord;

import '../services/transaction_service.dart';

class TransactionHistoryPage extends StatelessWidget {
  const TransactionHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = TransactionService();
    final df = DateFormat('dd MMM yyyy • hh:mm a');

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction History')),
      body: StreamBuilder<List<TransactionRecord>>(
        stream: service.streamMyTransactions(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <TransactionRecord>[];
          if (items.isEmpty) {
            return const Center(child: Text('No transactions yet'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final t = items[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text('₹'),
                  ),
                  title: Text('${t.operatorName} • ${t.number}'),
                  subtitle: Text(df.format(t.createdAt)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('₹${t.amount}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        t.status.toUpperCase(),
                        style: TextStyle(
                          color: t.status == 'success'
                              ? Colors.green
                              : (t.status == 'failed' ? Colors.red : Colors.grey),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
