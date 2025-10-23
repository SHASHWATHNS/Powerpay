import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart'; // Import the model
import '../services/transaction_service.dart'; // Import the service

// --- CHANGED: Use ConsumerWidget for Riverpod integration ---
class TransactionHistoryPage extends ConsumerWidget {
  const TransactionHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // --- CHANGED: Get the service from the provider ---
    final service = ref.watch(transactionServiceProvider);
    final numberFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final dateFormat = DateFormat('dd MMM yyyy • hh:mm a');

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction History')),
      body: StreamBuilder<List<TransactionRecord>>(
        stream: service.streamMyTransactions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No transactions yet.'));
          }

          final items = snapshot.data!;

          double successfulTotal = 0;
          double failedTotal = 0;
          for (final t in items) {
            // Only consider debits (recharges) for this summary
            if (t.type == 'DEBIT') {
              if (t.status == 'success') {
                successfulTotal += t.amount;
              } else if (t.status == 'failed') {
                failedTotal += t.amount;
              }
            }
          }

          final summaryHeader = Card(
            margin: const EdgeInsets.all(12.0),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _SummaryColumn(
                    label: '✅ SUCCESSFUL',
                    amount: successfulTotal,
                    color: Colors.green.shade700,
                    format: numberFormat,
                  ),
                  _SummaryColumn(
                    label: '❌ FAILED',
                    amount: failedTotal,
                    color: Colors.red.shade700,
                    format: numberFormat,
                  ),
                ],
              ),
            ),
          );

          return Column(
            children: [
              summaryHeader,
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final t = items[i];
                    final isCredit = t.type == 'CREDIT';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCredit ? Colors.green.shade100 : Colors.indigo.shade100,
                          child: Icon(
                            isCredit ? Icons.add : Icons.receipt_long,
                            size: 20,
                            color: isCredit ? Colors.green.shade800 : Colors.indigo.shade800,
                          ),
                        ),
                        title: Text(isCredit ? 'Wallet Top-up' : '${t.operatorName} • ${t.number}'),
                        subtitle: Text(dateFormat.format(t.createdAt)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${isCredit ? '+' : '-'} ${numberFormat.format(t.amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: isCredit ? Colors.green.shade800 : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (!isCredit) // Only show status for debits
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Helper widget for the summary card (No changes needed here)
class _SummaryColumn extends StatelessWidget {
  const _SummaryColumn({
    required this.label,
    required this.amount,
    required this.color,
    required this.format,
  });

  final String label;
  final double amount;
  final Color color;
  final NumberFormat format;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          format.format(amount),
          style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}