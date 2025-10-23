// lib/pages/wallet_ledger_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// Data model for a single ledger entry
class LedgerEntry {
  final double amount;
  final String type; // 'CREDIT' or 'DEBIT'
  final String description;
  final double balanceAfter;
  final DateTime createdAt;

  LedgerEntry({
    required this.amount,
    required this.type,
    required this.description,
    required this.balanceAfter,
    required this.createdAt,
  });

  factory LedgerEntry.fromFirestore(Map<String, dynamic> data) {
    return LedgerEntry(
      amount: (data['amount'] as num).toDouble(),
      type: data['type'] ?? 'UNKNOWN',
      description: data['description'] ?? 'No description',
      balanceAfter: (data['balanceAfter'] as num).toDouble(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }
}

// Provider to stream the list of wallet ledger entries
final walletLedgerProvider = StreamProvider<List<LedgerEntry>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('wallet_ledger')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => LedgerEntry.fromFirestore(doc.data())).toList());
});


class WalletLedgerPage extends ConsumerWidget {
  const WalletLedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerEntries = ref.watch(walletLedgerProvider);
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet Transactions'),
      ),
      body: ledgerEntries.when(
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(child: Text('No wallet transactions yet.'));
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final isCredit = entry.type == 'CREDIT';
              final color = isCredit ? Colors.green : Colors.red;
              final icon = isCredit ? Icons.arrow_downward : Icons.arrow_upward;
              final amountString = '${isCredit ? '+' : '-'} ${currencyFormat.format(entry.amount.abs())}';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.1),
                    child: Icon(icon, color: color),
                  ),
                  title: Text(entry.description, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(dateFormat.format(entry.createdAt)),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        amountString,
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Balance: ${currencyFormat.format(entry.balanceAfter)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => const Center(child: Text('Could not load transaction ledger.')),
      ),
    );
  }
}