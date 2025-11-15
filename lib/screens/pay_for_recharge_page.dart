// lib/screens/pay_for_recharge_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../providers/wallet_provider.dart';
import 'package:powerpay/providers/distributor_provider.dart';
import 'package:powerpay/providers/role_bootstrapper.dart';

// --- Brand Colors ---
const Color brandPurple = Color(0xFF5A189A);
const Color lightBg = Color(0xFFF7F7F9);
const Color textDark = Color(0xFF1E1E1E);
const Color textLight = Color(0xFF666666);

// ---------- YOUR BACKEND (already provided) ----------
const String BACKEND_WALLET_TX_API = 'https://projects.growtechnologies.in/powerpay/wallet_transfer.php';
// -----------------------------------------------------

class PayForRechargePage extends ConsumerStatefulWidget {
  const PayForRechargePage({super.key});

  @override
  ConsumerState<PayForRechargePage> createState() => _PayForRechargePageState();
}

class _PayForRechargePageState extends ConsumerState<PayForRechargePage> {
  String? _selectedUserId;
  String? _selectedUserName = 'Select a user';
  final _amountController = TextEditingController();
  bool _isLoading = false;
  double? _distributorBalance;
  String? _usersLoadError;

  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _loadDistributorBalance();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // STRICT parser: only accept exact numeric values from canonical keys.
  double _parseFirestoreBalance(dynamic raw) {
    try {
      if (raw == null) return 0.0;

      // If the doc.data() returned a Map, check exact keys.
      if (raw is Map) {
        // canonical wallet keys (only these are trusted)
        const List<String> keys = ['walletBalance', 'wallet_balance', 'walletBalancePaise'];

        for (final k in keys) {
          if (raw.containsKey(k)) {
            final v = raw[k];
            if (v == null) continue;
            // If paise field, convert to rupees when numeric
            if (k == 'walletBalancePaise') {
              final paise = _toDoubleStrict(v);
              if (paise != 0.0) return paise / 100.0;
              continue;
            }
            final parsed = _toDoubleStrict(v);
            if (parsed != 0.0) return parsed;
          }
        }

        // Nothing trusted found -> return 0.0
        return 0.0;
      }

      // If a direct number
      if (raw is num) return raw.toDouble();

      // If a strict numeric string
      if (raw is String) {
        final parsed = _toDoubleStrict(raw);
        return parsed;
      }

      return 0.0;
    } catch (e, st) {
      developer.log('_parseFirestoreBalance error: $e\n$st', name: 'pay_for_recharge');
      return 0.0;
    }
  }

  // Accepts only pure numeric strings (with optional decimal) or numeric types.
  double _toDoubleStrict(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.trim().replaceAll(',', ''); // allow comma thousands but strip them
      final numeric = RegExp(r'^[+-]?\d+(\.\d+)?$');
      if (numeric.hasMatch(s)) {
        return double.tryParse(s) ?? 0.0;
      }
      return 0.0; // reject any string with letters (PAN) or other chars
    }
    return 0.0;
  }

  // NEW: Load distributor balance STRICTLY from wallets/{uid} ONLY.
  Future<void> _loadDistributorBalance() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (mounted) setState(() => _distributorBalance = 0.0);
        developer.log('No current user -> distributorBalance set to 0', name: 'pay_for_recharge');
        return;
      }

      final db = FirebaseFirestore.instance;

      // ONLY wallets/{uid} as requested
      final walletDoc = await db.collection('wallets').doc(currentUser.uid).get();

      if (!walletDoc.exists) {
        // wallet doc missing -> show 0.0 (no fallback)
        if (mounted) setState(() => _distributorBalance = 0.0);
        developer.log('wallets/${currentUser.uid} DOES NOT exist -> balance 0', name: 'pay_for_recharge');
        return;
      }

      final data = walletDoc.data();
      final parsed = _parseFirestoreBalance(data);
      if (mounted) setState(() => _distributorBalance = parsed);
      developer.log('wallets/${currentUser.uid} balance parsed -> $parsed', name: 'pay_for_recharge');
    } catch (e, st) {
      developer.log('loadDistributorBalance error: $e\n$st', name: 'pay_for_recharge');
      if (mounted) setState(() => _distributorBalance = 0.0);
    }
  }

  bool _hasSufficientBalance(double amount) {
    return _distributorBalance != null && _distributorBalance! >= amount;
  }

  void _showSnack(String text, {bool isError = false, int durationSec = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: durationSec),
      ),
    );
  }

  /// Robust backend notifier (unchanged)
  Future<bool> _notifyBackendTransaction({
    required String txId,
    required String clientTxnId,
    required String distributorId,
    required String? distributorEmail,
    required String toUserId,
    required String? toUserName,
    required double amount,
    required DateTime timestamp,
  }) async {
    if (BACKEND_WALLET_TX_API.contains('YOUR_BACKEND')) {
      developer.log('Backend API not configured; skipping', name: 'pay_for_recharge');
      return false;
    }

    String? idToken;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) idToken = await user.getIdToken();
    } catch (e) {
      developer.log('Could not get idToken: $e', name: 'pay_for_recharge');
    }

    final headersWithAuth = <String, String>{
      'Accept': 'application/json',
      if (idToken != null) 'Authorization': 'Bearer $idToken',
    };

    final jsonBody = {
      'txId': txId,
      'clientTxnId': clientTxnId,
      'fromUid': distributorId,
      'fromEmail': distributorEmail,
      'distributorId': distributorId,
      'distributorEmail': distributorEmail,
      'toUserId': toUserId,
      'toUserName': toUserName,
      'amount': amount,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };

    final formVariants = <Map<String, String>>[
      {
        'txId': txId,
        'clientTxnId': clientTxnId,
        'fromUid': distributorId,
        'fromEmail': distributorEmail ?? '',
        'distributorId': distributorId,
        'distributorEmail': distributorEmail ?? '',
        'toUserId': toUserId,
        'toUserName': toUserName ?? '',
        'amount': amount.toString(),
        'timestamp': timestamp.toUtc().toIso8601String(),
      },
      {
        'tx_id': txId,
        'client_txn_id': clientTxnId,
        'from_uid': distributorId,
        'from_email': distributorEmail ?? '',
        'distributor_id': distributorId,
        'distributor_email': distributorEmail ?? '',
        'to_user_id': toUserId,
        'to_user_name': toUserName ?? '',
        'amount': amount.toString(),
        'timestamp': timestamp.toUtc().toIso8601String(),
      },
      {
        'from': distributorId,
        'to': toUserId,
        'amount': amount.toString(),
        'tx': txId,
        'client_txn_id': clientTxnId,
      },
    ];

    try {
      final resp = await http
          .post(Uri.parse(BACKEND_WALLET_TX_API),
          headers: {
            ...headersWithAuth,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(jsonBody))
          .timeout(const Duration(seconds: 20));

      developer.log('Backend JSON resp: ${resp.statusCode} ${resp.body}', name: 'pay_for_recharge');

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return true;
      } else {
        for (final form in formVariants) {
          try {
            final r = await http
                .post(Uri.parse(BACKEND_WALLET_TX_API),
                headers: {
                  ...headersWithAuth,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: form)
                .timeout(const Duration(seconds: 20));

            developer.log('Backend form resp: ${r.statusCode} ${r.body}', name: 'pay_for_recharge');

            if (r.statusCode >= 200 && r.statusCode < 300) {
              return true;
            }
          } catch (e, st2) {
            developer.log('Form variant POST error: $e\n$st2', name: 'pay_for_recharge');
          }
        }

        _showSnack('Transfer recorded locally but backend save failed (${resp.statusCode}).', isError: true, durationSec: 6);
        developer.log('Backend final failure response: ${resp.statusCode} ${resp.body}', name: 'pay_for_recharge');
        return false;
      }
    } catch (e, st) {
      developer.log('Backend JSON POST error: $e\n$st', name: 'pay_for_recharge');
      for (final form in formVariants) {
        try {
          final r = await http
              .post(Uri.parse(BACKEND_WALLET_TX_API),
              headers: {
                ...headersWithAuth,
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: form)
              .timeout(const Duration(seconds: 20));

          developer.log('Backend form resp (fallback): ${r.statusCode} ${r.body}', name: 'pay_for_recharge');

          if (r.statusCode >= 200 && r.statusCode < 300) {
            return true;
          }
        } catch (e2, st2) {
          developer.log('Form fallback error: $e2\n$st2', name: 'pay_for_recharge');
        }
      }

      _showSnack('Transfer recorded locally but backend save failed (network).', isError: true, durationSec: 6);
      return false;
    }
  }

  // Main transfer flow: unchanged but uses wallet writes already present in your code
  Future<void> _transferToUserWallet_client() async {
    if (_selectedUserId == null) {
      _showSnack('Please select a user', isError: true);
      return;
    }

    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      _showSnack('Please enter an amount', isError: true);
      return;
    }

    final amount = double.tryParse(amountText.replaceAll(RegExp(r'[^\d\.]'), '')) ?? 0.0;
    if (amount <= 0) {
      _showSnack('Please enter a valid amount', isError: true);
      return;
    }
    if (amount < 10) {
      _showSnack('Minimum amount is ₹10', isError: true);
      return;
    }

    // Refresh UI balance first (now strictly from wallets/{uid})
    await _loadDistributorBalance();
    if (!_hasSufficientBalance(amount)) {
      _showSnack(
        'Insufficient balance! Available: ₹${_distributorBalance?.toStringAsFixed(2) ?? "0.00"}',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    final txId = _uuid.v4();
    final clientTxnId = _uuid.v4();
    final now = DateTime.now().toUtc();

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('Not signed in');

      final distributorUid = currentUser.uid;
      final distributorEmail = currentUser.email;
      final db = FirebaseFirestore.instance;

      // Ensure distributor index exists
      final idxRef = db.collection('distributors_by_uid').doc(distributorUid);
      final idxSnap = await idxRef.get();
      if (!idxSnap.exists) {
        await idxRef.set({
          'firebase_uid': distributorUid,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByClient': true,
        });
      }

      // Read wallets-only balances as initial
      final distributorWalletRef = db.collection('wallets').doc(distributorUid);
      final distributorWalletSnap = await distributorWalletRef.get();
      double distributorInitialBalance = 0.0;
      bool distributorWalletExists = distributorWalletSnap.exists;

      if (distributorWalletExists) {
        distributorInitialBalance = _parseFirestoreBalance(distributorWalletSnap.data());
      } else {
        distributorInitialBalance = 0.0; // do NOT fallback to users/distributors
      }

      final userWalletRef = db.collection('wallets').doc(_selectedUserId);
      final userWalletSnap = await userWalletRef.get();
      double userInitialBalance = 0.0;
      bool userWalletExists = userWalletSnap.exists;

      if (userWalletExists) {
        userInitialBalance = _parseFirestoreBalance(userWalletSnap.data());
      } else {
        userInitialBalance = 0.0; // no fallback
      }

      final txLogRef = db.collection('wallet_transactions').doc(txId);
      final distributorPaymentRef = db.collection('distributor_payments').doc(txId);

      await db.runTransaction((tx) async {
        final dSnap = await tx.get(distributorWalletRef);
        final uSnap = await tx.get(userWalletRef);

        double distBal = 0.0;
        double usrBal = 0.0;

        if (dSnap.exists) {
          distBal = _parseFirestoreBalance(dSnap.data());
        } else {
          distBal = distributorInitialBalance;
          tx.set(distributorWalletRef, {
            'walletBalance': distBal,
            'ownerId': distributorUid,
            'role': 'distributor',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (uSnap.exists) {
          usrBal = _parseFirestoreBalance(uSnap.data());
        } else {
          usrBal = userInitialBalance;
          tx.set(userWalletRef, {
            'walletBalance': usrBal,
            'ownerId': _selectedUserId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (distBal < amount) {
          throw FirebaseException(
            plugin: 'firestore',
            code: 'failed-precondition',
            message: 'insufficient-funds: distributor has ₹$distBal (requested ₹$amount)',
          );
        }

        tx.update(distributorWalletRef, {
          'walletBalance': (distBal - amount),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        tx.update(userWalletRef, {
          'walletBalance': (usrBal + amount),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        tx.set(txLogRef, {
          'type': 'transfer',
          'fromUserId': distributorUid,
          'fromUserEmail': distributorEmail,
          'toUserId': _selectedUserId,
          'toUserName': _selectedUserName,
          'amount': amount,
          'description': 'Distributor recharge for user',
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'completed',
          'txId': txId,
          'clientTxnId': clientTxnId,
        });

        tx.set(distributorPaymentRef, {
          'userId': _selectedUserId,
          'userName': _selectedUserName,
          'amount': amount,
          'distributorId': distributorUid,
          'distributorEmail': distributorEmail,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'completed',
          'type': 'wallet_transfer',
          'txId': txId,
          'clientTxnId': clientTxnId,
        });
      });

      final backendOk = await _notifyBackendTransaction(
        txId: txId,
        clientTxnId: clientTxnId,
        distributorId: distributorUid,
        distributorEmail: distributorEmail,
        toUserId: _selectedUserId!,
        toUserName: _selectedUserName,
        amount: amount,
        timestamp: now,
      );

      if (!backendOk) developer.log('Backend save failed for tx $txId', name: 'pay_for_recharge');

      await _loadDistributorBalance();
      _amountController.clear();
      setState(() {
        _selectedUserId = null;
        _selectedUserName = 'Select a user';
      });

      _showSnack('Successfully transferred ₹${amount.toStringAsFixed(2)} to $_selectedUserName');
    } on FirebaseException catch (fe) {
      developer.log('Firestore transfer error: ${fe.code} ${fe.message}', name: 'pay_for_recharge');
      _showSnack('Transfer failed: [${fe.code}] ${fe.message}', isError: true, durationSec: 6);
    } catch (e, st) {
      developer.log('Unexpected transfer error: $e\n$st', name: 'pay_for_recharge');
      _showSnack('Transfer failed: $e', isError: true, durationSec: 6);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(bootstrapRoleProvider);
    final isDistributor = ref.watch(isDistributorProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Pay for User Recharge',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: brandPurple,
        elevation: 0,
      ),
      backgroundColor: lightBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: brandPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payment, color: brandPurple, size: 28),
                ),
                const SizedBox(width: 12),
                Text(
                  'Pay for User',
                  style: GoogleFonts.poppins(
                      fontSize: 24, fontWeight: FontWeight.w700, color: textDark),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Transfer from your wallet to user wallet',
                style: GoogleFonts.poppins(fontSize: 14, color: textLight)),
            const SizedBox(height: 24),

            // Balance card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: brandPurple.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: brandPurple.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet, color: brandPurple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Wallet Balance',
                            style: GoogleFonts.poppins(fontSize: 14, color: textLight)),
                        const SizedBox(height: 4),
                        Text(
                          '₹${_distributorBalance?.toStringAsFixed(2) ?? "Loading..."}',
                          style: GoogleFonts.poppins(
                              fontSize: 18, fontWeight: FontWeight.w700, color: brandPurple),
                        ),
                      ],
                    ),
                  ),
                  if (_distributorBalance != null && _distributorBalance! < 100)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Text('Low Balance',
                          style: GoogleFonts.poppins(fontSize: 10, color: Colors.orange)),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            if (!isDistributor) ...[
              Text('Select User *',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w600, color: textDark)),
              const SizedBox(height: 12),
              Container(
                height: 60,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "You don't have permission to list users.\nDistributor access is required.",
                  style: GoogleFonts.poppins(color: Colors.red),
                ),
              ),
              const SizedBox(height: 24),
            ] else ...[
              Text('Select User *',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w600, color: textDark)),
              const SizedBox(height: 12),

              Builder(builder: (context) {
                final distributorUid = FirebaseAuth.instance.currentUser?.uid;

                if (distributorUid == null) {
                  return Container(
                    height: 60,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text("Not signed in.", style: GoogleFonts.poppins(color: Colors.red)),
                  );
                }

                Stream<QuerySnapshot> usersStream = FirebaseFirestore.instance
                    .collection('users')
                    .where('createdBy', isEqualTo: distributorUid)
                    .snapshots();

                return StreamBuilder<QuerySnapshot>(
                  stream: usersStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      final err = snapshot.error;
                      _usersLoadError = err?.toString();
                      return Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'Error loading users: ${_usersLoadError ?? ''}',
                            style: GoogleFonts.poppins(color: Colors.red),
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    final users = docs.where((userDoc) {
                      final data = userDoc.data() as Map<String, dynamic>? ?? {};
                      final email = (data['email'] ?? '').toString().toLowerCase();
                      return email != 'grow@gmail.com';
                    }).toList();

                    if (users.isEmpty) {
                      return Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text('No users available', style: GoogleFonts.poppins(color: Colors.grey)),
                        ),
                      );
                    }

                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedUserId,
                          isExpanded: true,
                          hint: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('Choose a user', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
                          ),
                          items: users.map((userDoc) {
                            final userData = userDoc.data() as Map<String, dynamic>;
                            final email = userData['email'] ?? 'No Email';
                            final name = userData['name'] ?? email;
                            return DropdownMenuItem<String>(
                              value: userDoc.id,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                                    Text(email, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedUserId = value;
                              if (value != null) {
                                final selectedUser = (snapshot.data?.docs ?? []).firstWhere((u) => u.id == value);
                                final userData = selectedUser.data() as Map<String, dynamic>;
                                _selectedUserName = userData['name'] ?? userData['email'];
                              }
                            });
                          },
                        ),
                      ),
                    );
                  },
                );
              }),
              const SizedBox(height: 24),
            ],

            // Amount input
            Text('Amount *', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: textDark)),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter amount in ₹',
                prefixIcon: const Icon(Icons.currency_rupee),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: brandPurple)),
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 8),
            if (_amountController.text.isNotEmpty)
              Builder(builder: (context) {
                final amt = double.tryParse(_amountController.text) ?? 0;
                if (amt > 0) {
                  final hasBalance = _hasSufficientBalance(amt);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      hasBalance ? '✅ Sufficient balance available' : '❌ Insufficient balance. Please recharge your wallet.',
                      style: GoogleFonts.poppins(fontSize: 12, color: hasBalance ? Colors.green : Colors.red, fontWeight: FontWeight.w500),
                    ),
                  );
                }
                return const SizedBox();
              }),

            const SizedBox(height: 40),

            // Transfer button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading || !ref.watch(isDistributorProvider) ? null : _transferToUserWallet_client,
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandPurple,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Transfer to User Wallet', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
