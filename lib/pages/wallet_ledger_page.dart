// lib/pages/wallet_ledger_page.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Unified ledger entry model for multiple Firestore collections.
class LedgerEntry {
  final String id;
  final double amount;
  final String type; // 'CREDIT' or 'DEBIT' or 'NEUTRAL'
  final String description;
  final double? balanceAfter; // may be null if not provided
  final DateTime createdAt;
  final String source; // e.g. 'wallet_transaction', 'recharge', 'distributor_payment'
  final String? txId;
  final String? clientTxnId;
  final String? status; // e.g. completed / initiated / failed

  LedgerEntry({
    required this.id,
    required this.amount,
    required this.type,
    required this.description,
    required this.balanceAfter,
    required this.createdAt,
    required this.source,
    this.txId,
    this.clientTxnId,
    this.status,
  });

  /// helper to parse Firestore timestamp-like fields safely
  static DateTime _parseTimestamp(dynamic t) {
    if (t == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    if (t is String) {
      try {
        return DateTime.parse(t);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Create LedgerEntry from wallet_transactions document
  factory LedgerEntry.fromWalletTx(String id, Map<String, dynamic> d) {
    final amount = (d['amount'] as num?)?.toDouble() ?? 0.0;
    final fromUserId = d['fromUserId']?.toString();
    final toUserId = d['toUserId']?.toString();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    // If current user is receiver -> CREDIT, if sender -> DEBIT
    final type = (currentUid != null && currentUid == toUserId)
        ? 'CREDIT'
        : ((currentUid != null && currentUid == fromUserId) ? 'DEBIT' : 'NEUTRAL');

    final createdAt = _parseTimestamp(d['timestamp'] ?? d['createdAt'] ?? d['ts']);
    final balanceAfter = (d['balanceAfter'] as num?)?.toDouble() ?? (d['walletBalanceAfter'] as num?)?.toDouble();
    final description = d['description'] ??
        (type == 'CREDIT' ? 'Received wallet transfer' : (type == 'DEBIT' ? 'Mobile Recharge' : 'Wallet transfer'));

    return LedgerEntry(
      id: id,
      amount: amount,
      type: type,
      description: description,
      balanceAfter: balanceAfter,
      createdAt: createdAt,
      source: 'wallet_transaction',
      txId: d['txId']?.toString(),
      clientTxnId: d['clientTxnId']?.toString(),
      status: d['status']?.toString() ?? d['statusText']?.toString(),
    );
  }

  /// Create LedgerEntry from recharges document
  factory LedgerEntry.fromRecharge(String id, Map<String, dynamic> d) {
    final amount = (d['amount'] as num?)?.toDouble() ?? 0.0;
    final uid = d['uid']?.toString();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final type = (currentUid != null && currentUid == uid) ? 'DEBIT' : 'NEUTRAL';
    // show mobile operator or basic desc
    final mobile = d['mobile']?.toString() ?? '';
    final operator = d['operator']?.toString() ?? '';
    final status = (d['status'] ?? 'initiated').toString();
    final createdAt = _parseTimestamp(d['createdAt'] ?? d['timestamp'] ?? d['ts']);
    final providerTxn = d['providerTxnId'] ?? d['provider_txn_id'];
    final description = 'Recharge $mobile ${operator.isNotEmpty ? "($operator)" : ""}';

    return LedgerEntry(
      id: id,
      amount: amount,
      type: type,
      description: description,
      balanceAfter: (d['balanceAfter'] as num?)?.toDouble(),
      createdAt: createdAt,
      source: 'recharge',
      txId: providerTxn?.toString() ?? d['txId']?.toString(),
      clientTxnId: d['clientTxnId']?.toString() ?? d['rechargeClientTxnId']?.toString(),
      status: status,
    );
  }

  /// Create LedgerEntry from distributor_payments document
  factory LedgerEntry.fromDistributorPayment(String id, Map<String, dynamic> d) {
    final amount = (d['amount'] as num?)?.toDouble() ?? 0.0;
    final distributorId = d['distributorId']?.toString() ?? d['from']?.toString();
    final userId = d['userId']?.toString() ?? d['to']?.toString();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    String type = 'NEUTRAL';
    if (currentUid != null) {
      if (currentUid == distributorId) type = 'DEBIT';
      if (currentUid == userId) type = 'CREDIT';
    }
    final createdAt = _parseTimestamp(d['timestamp'] ?? d['createdAt'] ?? d['ts']);
    final description = d['description']?.toString() ?? 'Distributor payment';

    return LedgerEntry(
      id: id,
      amount: amount,
      type: type,
      description: description,
      balanceAfter: (d['balanceAfter'] as num?)?.toDouble(),
      createdAt: createdAt,
      source: 'distributor_payment',
      txId: d['txId']?.toString(),
      clientTxnId: d['clientTxnId']?.toString(),
      status: d['status']?.toString(),
    );
  }
}

/// Provider that merges multiple Firestore streams into a single sorted list.
final walletLedgerProvider = StreamProvider<List<LedgerEntry>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);

  // Create a controller that emits combined lists
  final controller = StreamController<List<LedgerEntry>>();

  // Snapshot listeners
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? walletTxSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? rechargeSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? distributorPaySub;

  // Latest cached lists
  List<LedgerEntry> walletTxEntries = [];
  List<LedgerEntry> rechargeEntries = [];
  List<LedgerEntry> distributorPayEntries = [];

  void emitCombined() {
    final combined = <LedgerEntry>[];
    combined.addAll(walletTxEntries);
    combined.addAll(rechargeEntries);
    combined.addAll(distributorPayEntries);
    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!controller.isClosed) controller.add(combined);
  }

  try {
    // 1) wallet_transactions where fromUserId==uid OR toUserId==uid
    final walletTxQuery = FirebaseFirestore.instance
        .collection('wallet_transactions')
        .where('participants', arrayContains: uid) // prefer indexed field 'participants' if you maintain it
    // fallback: if participants doesn't exist, we'll get a larger set below in a second listener (but keep it simple)
        .orderBy('timestamp', descending: true)
        .limit(200);

    // Use a query that catches both sides by using 'participants' is recommended. If your schema doesn't have it,
    // Firestore does not support OR queries easily without SDK >= features; adjust backend to set participants array.
    walletTxSub = walletTxQuery.snapshots().listen((snap) {
      walletTxEntries = snap.docs.map((doc) {
        return LedgerEntry.fromWalletTx(doc.id, doc.data());
      }).toList();
      emitCombined();
    }, onError: (e) {
      // as fallback: query both sides separately
      try {
        FirebaseFirestore.instance
            .collection('wallet_transactions')
            .where('fromUserId', isEqualTo: uid)
            .snapshots()
            .listen((snap) {
          final fromList = snap.docs.map((d) => LedgerEntry.fromWalletTx(d.id, d.data())).toList();
          // combine with toUserId
          FirebaseFirestore.instance
              .collection('wallet_transactions')
              .where('toUserId', isEqualTo: uid)
              .snapshots()
              .listen((snap2) {
            final toList = snap2.docs.map((d) => LedgerEntry.fromWalletTx(d.id, d.data())).toList();
            walletTxEntries = [...fromList, ...toList];
            emitCombined();
          }, onError: (_) {});
        }, onError: (_) {});
      } catch (_) {}
    });

    // 2) recharges where uid == current uid (show attempts & final statuses)
    final rechargeQuery = FirebaseFirestore.instance
        .collection('recharges')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(200);

    rechargeSub = rechargeQuery.snapshots().listen((snap) {
      rechargeEntries = snap.docs.map((doc) => LedgerEntry.fromRecharge(doc.id, doc.data())).toList();
      emitCombined();
    }, onError: (e) {
      // ignore errors, still attempt to emit combined
      emitCombined();
    });

    // 3) distributor_payments where distributorId==uid OR userId==uid
    final distPayQuery = FirebaseFirestore.instance
        .collection('distributor_payments')
        .where('participants', arrayContains: uid) // recommended if you maintain participants array
        .orderBy('timestamp', descending: true)
        .limit(200);

    distributorPaySub = distPayQuery.snapshots().listen((snap) {
      distributorPayEntries = snap.docs.map((doc) => LedgerEntry.fromDistributorPayment(doc.id, doc.data())).toList();
      emitCombined();
    }, onError: (e) {
      // fallback separate queries
      try {
        FirebaseFirestore.instance
            .collection('distributor_payments')
            .where('distributorId', isEqualTo: uid)
            .snapshots()
            .listen((snapA) {
          final aList = snapA.docs.map((d) => LedgerEntry.fromDistributorPayment(d.id, d.data())).toList();
          FirebaseFirestore.instance
              .collection('distributor_payments')
              .where('userId', isEqualTo: uid)
              .snapshots()
              .listen((snapB) {
            final bList = snapB.docs.map((d) => LedgerEntry.fromDistributorPayment(d.id, d.data())).toList();
            distributorPayEntries = [...aList, ...bList];
            emitCombined();
          }, onError: (_) {});
        }, onError: (_) {});
      } catch (_) {}
    });
  } catch (_) {
    // If anything failed, push empty list
    controller.add([]);
  }

  // clean up when provider is disposed/cancelled
  controller.onCancel = () {
    walletTxSub?.cancel();
    rechargeSub?.cancel();
    distributorPaySub?.cancel();
    if (!controller.isClosed) controller.close();
  };

  return controller.stream;
});

class WalletLedgerPage extends ConsumerWidget {
  const WalletLedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(walletLedgerProvider);
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet Transactions')),
      body: ledgerAsync.when(
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(child: Text('No wallet transactions yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final e = entries[index];
              final isCredit = e.type == 'CREDIT';
              final isDebit = e.type == 'DEBIT';
              final color = isCredit ? Colors.green : (isDebit ? Colors.red : Colors.grey.shade700);
              final icon = e.source == 'recharge'
                  ? Icons.smartphone
                  : (e.source == 'wallet_transaction' ? Icons.swap_horiz : Icons.account_balance_wallet);
              final sign = isCredit ? '+' : (isDebit ? '-' : '');
              final amountString = '$sign ${currencyFormat.format(e.amount.abs())}';

              // extra small status label
              Widget statusChip() {
                final s = e.status?.toLowerCase() ?? '';
                if (s.contains('fail') || s.contains('error') || s.contains('provider_call_failed')) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), border: Border.all(color: Colors.red.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
                    child: Text(e.status ?? 'FAILED', style: const TextStyle(fontSize: 11, color: Colors.red)),
                  );
                } else if (s.contains('init') || s.contains('process')) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.06), border: Border.all(color: Colors.orange.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
                    child: Text(e.status ?? 'PENDING', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                  );
                } else if (s.contains('success') || s.contains('completed')) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.06), border: Border.all(color: Colors.green.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
                    child: Text(e.status ?? 'SUCCESS', style: const TextStyle(fontSize: 11, color: Colors.green)),
                  );
                } else {
                  return const SizedBox.shrink();
                }
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.12),
                    child: Icon(icon, color: color),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(e.description, style: const TextStyle(fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      statusChip(),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateFormat.format(e.createdAt)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        if (e.txId != null) Text('tx: ${e.txId}', style: const TextStyle(fontSize: 11)),
                        if (e.clientTxnId != null) Text('client: ${e.clientTxnId}', style: const TextStyle(fontSize: 11)),
                        Text('source: ${e.source}', style: const TextStyle(fontSize: 11)),
                      ]),
                    ],
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(amountString, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(
                        e.balanceAfter != null ? 'Balance: ${currencyFormat.format(e.balanceAfter)}' : 'Balance: —',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  onTap: () {
                    // show detailed dialog
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(e.description),
                        content: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Amount: ${currencyFormat.format(e.amount)}'),
                              const SizedBox(height: 6),
                              Text('Type: ${e.type}'),
                              const SizedBox(height: 6),
                              Text('Source: ${e.source}'),
                              const SizedBox(height: 6),
                              Text('Status: ${e.status ?? "—"}'),
                              const SizedBox(height: 6),
                              Text('Created: ${dateFormat.format(e.createdAt)}'),
                              const SizedBox(height: 6),
                              if (e.txId != null) Text('txId: ${e.txId}'),
                              if (e.clientTxnId != null) Text('clientTxnId: ${e.clientTxnId}'),
                              if (e.balanceAfter != null) ...[
                                const SizedBox(height: 6),
                                Text('Balance after: ${currencyFormat.format(e.balanceAfter!)}'),
                              ],
                            ],
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
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Could not load transaction ledger: $err')),
      ),
    );
  }
}
