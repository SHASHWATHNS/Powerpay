// lib/pages/transaction_history_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/transaction_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionHistoryPage extends ConsumerWidget {
  const TransactionHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(transactionServiceProvider as ProviderListenable);
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
            final err = snapshot.error;
            if (err is FirebaseException && err.code == 'permission-denied') {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    'Permission denied: your account does not have access to read transactions.\n\n'
                        'Possible fixes:\n'
                        '• Ensure you are signed in.\n'
                        '• Ensure your Firestore rules are published (use the console) and documents include uid/participants fields.\n'
                        '• Ensure distributors_by_uid exists for distributor accounts if you expect distributor access.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No transactions yet.'));
          }

          final items = snapshot.data!;

          double successfulTotal = 0;
          double failedTotal = 0;
          for (final t in items) {
            if (t.type == 'DEBIT') {
              if (t.status == 'success') successfulTotal += t.amount;
              else if (t.status == 'failed') failedTotal += t.amount;
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
                        title: Text(isCredit ? 'Wallet Top-up' : '${t.operatorName.isNotEmpty ? t.operatorName : "Recharge"} • ${t.number.isNotEmpty ? t.number : ""}'),
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
                            if (!isCredit)
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
                        onTap: () {
                          // Show details dialog
                          showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(isCredit ? 'Wallet Top-up' : 'Transaction details'),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Amount: ${numberFormat.format(t.amount)}'),
                                      const SizedBox(height: 8),
                                      Text('Type: ${t.type}'),
                                      const SizedBox(height: 8),
                                      Text('Status: ${t.status}'),
                                      const SizedBox(height: 8),
                                      if (t.operatorName.isNotEmpty) Text('Operator: ${t.operatorName}'),
                                      if (t.number.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text('Number: ${t.number}'),
                                      ],
                                      const SizedBox(height: 8),
                                      Text('Created: ${dateFormat.format(t.createdAt)}'),
                                      const SizedBox(height: 8),
                                      Text('Raw data (preview):'),
                                      const SizedBox(height: 8),
                                      Text(t.raw.toString(), style: const TextStyle(fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
                              ],
                            ),
                          );
                        },
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
