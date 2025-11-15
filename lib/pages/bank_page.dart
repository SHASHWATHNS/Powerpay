// lib/screens/bank_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../providers/wallet_provider.dart';

/// Backend wallet API
const String walletApiEndpoint =
    'https://projects.growtechnologies.in/powerpay/wallet_payment.php';

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
    _Plan(amount: 1000, id: 902, title: 'Plan 1 — ₹1000', subtitle: 'Top-up ₹1000'),
    _Plan(amount: 3000, id: 903, title: 'Plan 2 — ₹3000', subtitle: 'Top-up ₹3000'),
    _Plan(amount: 5000, id: 904, title: 'Plan 3 — ₹5000', subtitle: 'Top-up ₹5000'),
  ];

  int _selectedPlanIndex = 0;
  Timer? _debounceVerify;

  // Track if we should auto-verify on resume
  bool _shouldVerifyOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initial verification - but only show success for actual payments
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
      // Only verify if we explicitly started a payment
      if (_shouldVerifyOnResume) {
        _debounceVerify?.cancel();
        _debounceVerify = Timer(const Duration(milliseconds: 1000), () {
          _verifyPendingTopupsAndRefresh();
          _shouldVerifyOnResume = false; // Reset after verification
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
  Future<void> _verifyPendingTopupsAndRefresh({bool silent = false}) async {
    final loading = ref.read(bankPageLoadingProvider.notifier);
    loading.state = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final resp = await _callWalletApiVerify(uid: user.uid);
      debugPrint('[BankPage] Verify response: $resp');

      if (resp['success'] == true) {
        final newBalance = resp['newBalance']?.toString();
        final message = resp['message']?.toString();

        // Only show success message if we actually got money
        if (mounted && newBalance != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Payment successful! New balance: ₹$newBalance'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        } else if (mounted && !silent && message != null && message.contains('credited')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
            ),
          );
        }

        ref.invalidate(walletBalanceProvider);
      } else {
        final message = resp['message']?.toString() ?? 'No wallet updates.';
        // Don't show "No wallet updates" message - it's normal
        if (mounted && !silent && !message.contains('No wallet updates')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
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

  Future<Map<String, dynamic>> _callWalletApiVerify({required String uid}) async {
    final uri = Uri.parse(walletApiEndpoint);
    final payload = {'action': 'verify', 'uid': uid};

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      throw Exception('Wallet API returned ${resp.statusCode}');
    }
    return json.decode(resp.body);
  }

  /// Call record API to create pending payment
  Future<Map<String, dynamic>> _callWalletApiRecord({
    required String uid,
    required int amount,
    required String providerTxnId,
  }) async {
    final uri = Uri.parse(walletApiEndpoint);
    final payload = {
      'action': 'record',
      'uid': uid,
      'userId': uid,
      'amount': amount,
      'providerTxnId': providerTxnId,
      'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
    };

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw Exception('Record API returned ${resp.statusCode}');
    }
    return json.decode(resp.body);
  }

  /// Start payment: Record pending payment and enable verification on return
  Future<void> _startQPayPaymentForSelectedPlan() async {
    final loading = ref.read(bankPageLoadingProvider.notifier);
    loading.state = true;

    try {
      final plan = _plans[_selectedPlanIndex];
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final uid = user.uid;
      final providerTxnId = _uuid.v4();

      // Record pending payment in database
      final recordResult = await _callWalletApiRecord(
        uid: uid,
        amount: plan.amount,
        providerTxnId: providerTxnId,
      );

      if (recordResult['success'] != true) {
        throw Exception('Failed to record payment: ${recordResult['message']}');
      }

      // Build QPay payment URL
      var paymentLink = 'https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx?id=${plan.id}';

      final encodedProvider = Uri.encodeComponent(providerTxnId);
      final encodedUid = Uri.encodeComponent(uid);

      // Use your existing return URL
      final returnUrl = 'https://projects.growtechnologies.in/powerpay/wallet_payment.php?providerTxnId=$encodedProvider&uid=$encodedUid';
      final encodedReturn = Uri.encodeComponent(returnUrl);

      paymentLink = '$paymentLink'
          '&merchant_ref=$encodedProvider'
          '&custom_uid=$encodedUid'
          '&providerTxnId=$encodedProvider'
          '&amount=${plan.amount}'
          '&return_url=$encodedReturn';

      debugPrint('[BankPage] Starting payment: $providerTxnId');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opening payment page for ₹${plan.amount}...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // SET THIS FLAG - we want to verify when user returns
      _shouldVerifyOnResume = true;

      await _launchPaymentUrl(paymentLink);

    } catch (e) {
      debugPrint('[BankPage] Payment error: $e');
      // Clear the flag on error
      _shouldVerifyOnResume = false;
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