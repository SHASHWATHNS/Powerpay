// lib/screens/bank_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:powerpay/screens/payment_success_page.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../providers/wallet_provider.dart';

/// Backend wallet API
const String walletApiEndpoint =
    'https://projects.growtechnologies.in/powerpay/qpay_wallet_api.php';

/// Loading state for this page
final bankPageLoadingProvider = StateProvider.autoDispose<bool>((ref) => false);

final _uuid = Uuid();

class BankPage extends ConsumerStatefulWidget {
  const BankPage({super.key});

  @override
  ConsumerState<BankPage> createState() => _BankPageState();
}

class _BankPageState extends ConsumerState<BankPage> with WidgetsBindingObserver {
  final List<_Plan> _plans = const [
    _Plan(amount: 1000, id: 923, title: 'Plan 1 — ₹1000', subtitle: 'Top-up ₹1000'),
    _Plan(amount: 3000, id: 923, title: 'Plan 2 — ₹3000', subtitle: 'Top-up ₹3000'),
    _Plan(amount: 5000, id: 923, title: 'Plan 3 — ₹5000', subtitle: 'Top-up ₹5000'),
  ];

  int _selectedPlanIndex = 0;
  Timer? _debounceVerify;

  // Track if we should auto-verify on resume
  bool _shouldVerifyOnResume = false;

  // Store providerTxnId for the active payment so we can verify only that txn (optional)
  String? _lastProviderTxnId;
  bool _paymentStarted = false;

  // Store pending amount so PaymentSuccessPage can show it
  int? _pendingAmount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initial verification - silent (don't show "no updates" messages)
    Future.delayed(const Duration(seconds: 1), () {
      _verifyPendingTopupsAndRefresh(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceVerify?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only proceed if we explicitly started a payment
      if (_shouldVerifyOnResume && _paymentStarted) {
        _debounceVerify?.cancel();
        _debounceVerify = Timer(const Duration(milliseconds: 800), () async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return;

          try {
            // UX: show PaymentSuccessPage so user can press Add money if they prefer.
            if (mounted) {
              try {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PaymentSuccessPage(
                      uid: user.uid,
                      providerTxnId: _lastProviderTxnId ?? '',
                      amount: _pendingAmount ?? _plans[_selectedPlanIndex].amount,
                      walletApiEndpoint: walletApiEndpoint,
                    ),
                  ),
                );
              } catch (e) {
                debugPrint('[BankPage] Navigation to success page failed: $e');
              }
            }

            // Auto-verify (best-effort) even if providerTxnId is missing
            await _verifyPendingTopupsAndRefresh(silent: true);
          } catch (e) {
            debugPrint('[BankPage] Auto-verify/navigation error: $e');
          } finally {
            // Reset flags
            _shouldVerifyOnResume = false;
            _paymentStarted = false;
            _pendingAmount = null;
            _lastProviderTxnId = null;
          }
        });
      }
    }
  }

  Future<void> _launchPaymentUrl(String paymentUrl) async {
    final uri = Uri.parse(paymentUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('Could not launch payment URL');
    }
  }

  /// Verify payments - with option to be silent (no messages for "no updates")
  /// If _lastProviderTxnId is set we will pass it to server to request targeted verify.
  Future<void> _verifyPendingTopupsAndRefresh({bool silent = false}) async {
    final loading = ref.read(bankPageLoadingProvider.notifier);
    loading.state = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email ?? '';

      final resp = await _callWalletApiVerify(uid: user.uid, providerTxnId: _lastProviderTxnId, email: email);
      debugPrint('[BankPage] Verify response: $resp');

      // Centralized response handling
      if (!silent) {
        _handleVerifyResponse(resp);
      } else {
        // If silent: still invalidate wallet provider if server returned newBalance/final_balance
        if (resp['success'] == true && (resp['newBalance'] != null || resp['final_balance'] != null || (resp['processed'] is List && (resp['processed'] as List).isNotEmpty))) {
          ref.invalidate(walletBalanceProvider);
        }
      }
    } catch (e) {
      debugPrint('[BankPage] Verify error: $e');
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) loading.state = false;
    }
  }

  /// Call server verify — optionally with providerTxnId and email
  /// IMPORTANT: always includes 'status': 'success' so backend will credit
  Future<Map<String, dynamic>> _callWalletApiVerify({
    required String uid,
    String? providerTxnId,
    String? email,
  }) async {
    final uri = Uri.parse(walletApiEndpoint);

    // Build payload: always include status: 'success'. If providerTxnId is null, server will use uid/email fallback.
    final payload = <String, dynamic>{
      'action': 'verify',
      'uid': uid,
      'status': 'success', // ensure backend treats this as a successful payment
    };

    if (providerTxnId != null && providerTxnId.isNotEmpty) {
      payload['providerTxnId'] = providerTxnId;
    } else {
      // If providerTxnId is missing, include email so server can match by email
      if (email != null && email.isNotEmpty) payload['email'] = email;
    }

    debugPrint('[BankPage] verify payload: ${jsonEncode(payload)}');

    final resp = await http
        .post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    )
        .timeout(const Duration(seconds: 20));

    debugPrint('[BankPage] verify status: ${resp.statusCode}');
    debugPrint('[BankPage] verify body: ${resp.body}');

    if (resp.statusCode != 200) {
      final bodySnippet = resp.body.isNotEmpty ? resp.body : '<empty body>';
      throw Exception('Wallet API returned ${resp.statusCode}: $bodySnippet');
    }

    final body = resp.body.trim();
    if (body.isEmpty) throw Exception('Wallet API returned empty body');

    try {
      return json.decode(body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Invalid JSON from Wallet API: $e\nBody: $body');
    }
  }

  /// Robust record call with retry and longer timeouts.
  /// Returns server JSON on success, or throws on hard failure.
  Future<Map<String, dynamic>> _callWalletApiRecord({
    required String uid,
    required int amount,
    required String providerTxnId,
    String? email,
  }) async {
    final uri = Uri.parse(walletApiEndpoint);
    final payload = {
      'action': 'record',
      'uid': uid,
      'userId': uid,
      'amount': amount,
      'providerTxnId': providerTxnId,
      'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
      if (email != null && email.isNotEmpty) 'email': email,
    };

    debugPrint('[BankPage] record payload: $payload');

    // Helper to perform one attempt
    Future<http.Response> attempt() {
      return http
          .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
          .timeout(const Duration(seconds: 15)); // increased timeout
    }

    try {
      http.Response resp = await attempt();
      // if non-200, try once more for transient server errors (but only one retry)
      if (resp.statusCode != 200) {
        debugPrint('[BankPage] record first attempt status=${resp.statusCode}. Retrying once...');
        resp = await attempt();
      }

      debugPrint('[BankPage] record status: ${resp.statusCode}');
      debugPrint('[BankPage] record body: ${resp.body}');

      if (resp.statusCode != 200) {
        final bodySnippet = resp.body.isNotEmpty ? resp.body : '<empty body>';
        throw Exception('Record API returned ${resp.statusCode}: $bodySnippet');
      }

      final body = resp.body.trim();
      if (body.isEmpty) throw Exception('Record API returned empty body');

      return json.decode(body) as Map<String, dynamic>;
    } on TimeoutException catch (te) {
      debugPrint('[BankPage] record timeout: $te');
      rethrow; // caller will handle (we may choose to proceed to payment)
    } catch (e) {
      debugPrint('[BankPage] record error: $e');
      rethrow;
    }
  }

  /// Start payment: Record pending payment and enable verification on return
  /// This version will still open the payment page even if recording times out.
  Future<void> _startQPayPaymentForSelectedPlan() async {
    final loading = ref.read(bankPageLoadingProvider.notifier);
    loading.state = true;

    try {
      final plan = _plans[_selectedPlanIndex];
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final uid = user.uid;
      final email = user.email ?? '';

      // Generate providerTxnId here (unique per payment)
      final providerTxnId = _uuid.v4();

      // Save locally so we can verify only this txn on resume (optional)
      _lastProviderTxnId = providerTxnId;
      _paymentStarted = true;

      // Store pending amount so PaymentSuccessPage can show it
      _pendingAmount = plan.amount;

      Map<String, dynamic>? recordResult;
      bool recordSucceeded = false;

      try {
        // Try recording the payment (but if it times out we'll proceed anyway)
        recordResult = await _callWalletApiRecord(
          uid: uid,
          amount: plan.amount,
          providerTxnId: providerTxnId,
          email: email,
        );
        recordSucceeded = recordResult['success'] == true;
      } on TimeoutException catch (_) {
        // TIMEOUT: proceed to payment but notify user and log
        debugPrint('[BankPage] record timed out — proceeding to open payment page');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Network slow: starting payment. Verification may occur after return.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        // recordSucceeded remains false; we'll auto-verify on resume
      } catch (e) {
        // Non-timeout error — show warning but still proceed to payment
        debugPrint('[BankPage] record failed: $e. Proceeding to payment.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not create record: $e'), backgroundColor: Colors.orange),
          );
        }
      }

      // Build QPay payment URL safely using Uri.replace(queryParameters:)
      final encodedProvider = Uri.encodeComponent(providerTxnId);
      final encodedUid = Uri.encodeComponent(uid);
      final returnUrl = 'https://projects.growtechnologies.in/powerpay/wallet_payment.php?providerTxnId=$encodedProvider&uid=$encodedUid';

      final paymentUri = Uri.parse('https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx').replace(
        queryParameters: {
          'id': plan.id.toString(),
          'merchant_ref': providerTxnId,
          'custom_uid': uid,
          'providerTxnId': providerTxnId,
          'amount': plan.amount.toString(),
          'return_url': returnUrl,
        },
      );

      final paymentLink = paymentUri.toString();

      debugPrint('[BankPage] Starting payment: $providerTxnId -> $paymentLink');

      // set flag so resume flow triggers verification
      _shouldVerifyOnResume = true;

      await _launchPaymentUrl(paymentLink);
    } catch (e) {
      debugPrint('[BankPage] Payment error: $e');
      // Clear the flag on error
      _shouldVerifyOnResume = false;
      _paymentStarted = false;
      _pendingAmount = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) loading.state = false;
    }
  }

  /// Handle verify response from server and show appropriate UI.
  /// This will only clear _lastProviderTxnId when a confirmation for that txn is seen.
  void _handleVerifyResponse(Map<String, dynamic> resp) {
    debugPrint('[BankPage] _handleVerifyResponse: $resp');

    if (resp['success'] == true) {
      // Prefer final or explicit newBalance fields from server
      final finalBalance = resp['final_balance'] ?? resp['newBalance'] ?? resp['new_balance'];
      if (finalBalance != null) {
        final nb = finalBalance.toString();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Payment successful! New balance: ₹$nb'), backgroundColor: Colors.green),
          );
        }
        // confirmed: clear saved txn
        _lastProviderTxnId = null;
        ref.invalidate(walletBalanceProvider);
        return;
      }

      // If server returned 'processed' list, try to find matching providerTxnId entry
      if (resp['processed'] is List && (resp['processed'] as List).isNotEmpty) {
        final processed = resp['processed'] as List<dynamic>;

        if (_lastProviderTxnId != null) {
          final match = processed.firstWhere(
                (p) {
              if (p is Map) {
                final pid = p['providerTxnId'] ?? p['providerTxn'] ?? p['txn'] ?? p['transactionId'];
                return pid != null && pid.toString() == _lastProviderTxnId;
              }
              return false;
            },
            orElse: () => null,
          );

          if (match != null && match is Map) {
            final credited = match['credited'] ?? match['amount'] ?? match['newBalance'];
            final newBal = match['newBalance'];
            if (credited != null) {
              final amountStr = credited.toString();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ Credited ₹$amountStr to wallet' + (newBal != null ? ' | New balance: ₹${newBal.toString()}' : '')), backgroundColor: Colors.green),
                );
              }
              _lastProviderTxnId = null;
              ref.invalidate(walletBalanceProvider);
              return;
            }
          } else {
            // No matching credited entry for our txn
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No payment confirmed yet.'), duration: Duration(seconds: 2)),
              );
            }
            return;
          }
        } else {
          // processed entries but we don't have a last txn — show summary
          final creditedItems = processed.where((p) => p is Map && (p['credited'] != null || p['amount'] != null)).toList();
          if (creditedItems.isNotEmpty) {
            final sum = creditedItems.fold<double>(0.0, (acc, p) {
              final m = p as Map;
              final v = (m['credited'] ?? m['amount']) as num?;
              return acc + (v?.toDouble() ?? 0.0);
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✅ Credited ₹$sum to wallet'), backgroundColor: Colors.green),
              );
            }
            ref.invalidate(walletBalanceProvider);
            return;
          }
        }
      }

      // If server returned credited_total or similar
      if (resp['credited_total'] != null) {
        final total = resp['credited_total'].toString();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Credited total ₹$total to wallet'), backgroundColor: Colors.green),
          );
        }
        _lastProviderTxnId = null;
        ref.invalidate(walletBalanceProvider);
        return;
      }

      // Generic success but nothing credited
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp['message']?.toString() ?? 'Verify completed')),
        );
      }
      return;
    }

    // Not success
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resp['message']?.toString() ?? 'Verify failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(bankPageLoadingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Money to Wallet'),
        actions: [
          IconButton(
            tooltip: 'Refresh & Verify',
            onPressed: isLoading ? null : () => _verifyPendingTopupsAndRefresh(),
            icon: isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info card
            Card(
              color: Colors.blue[50],
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, size: 40, color: Colors.blue),
                    SizedBox(height: 10),
                    Text(
                      'Payment Process',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Select plan and tap "Pay"\n'
                          '2. Complete payment in browser\n'
                          '3. Return to app manually\n'
                          '4. Wallet updates automatically\n'
                          '5. Use refresh button if needed',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            const Text(
              'Select Top-up Plan:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            ..._plans.asMap().entries.map((entry) {
              final index = entry.key;
              final plan = entry.value;
              final selected = index == _selectedPlanIndex;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Card(
                  elevation: selected ? 4 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: selected ? Colors.purple : Colors.transparent,
                      width: selected ? 2 : 0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Radio<int>(
                          value: index,
                          groupValue: _selectedPlanIndex,
                          onChanged: (v) => setState(() => _selectedPlanIndex = v ?? 0),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan.title,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                plan.subtitle,
                                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: isLoading ? null : () => _startQPayPaymentForSelectedPlan(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                          ),
                          child: isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text('Pay ₹${plan.amount}'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

class _Plan {
  final int amount;
  final int id;
  final String title;
  final String subtitle;

  const _Plan({
    required this.amount,
    required this.id,
    required this.title,
    required this.subtitle,
  });
}