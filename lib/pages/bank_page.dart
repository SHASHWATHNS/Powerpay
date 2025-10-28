// lib/screens/bank_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart' show walletServiceProvider;

// Visible in logs to confirm which backend you're hitting
const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8080');

// Loading state for this page
final bankPageLoadingProvider = StateProvider.autoDispose<bool>((ref) => false);

class BankPage extends ConsumerStatefulWidget {
  const BankPage({super.key});

  @override
  ConsumerState<BankPage> createState() => _BankPageState();
}

class _BankPageState extends ConsumerState<BankPage> with WidgetsBindingObserver {
  // Fixed amount of ₹1099
  static const int fixedAmount = 1099;

  // Fallback payment shortlink (temporary flow)
  static const String _fallbackPaymentShortlink = 'https://rzp.io/rzp/xd8KZaS';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[BankPage] API_BASE => $apiBase');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Refresh wallet when the app returns from the payment page
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint('[BankPage] Resumed → refreshing wallet balance');
      ref.invalidate(walletBalanceProvider);
    }
  }

  Future<void> _launchPaymentUrl(String paymentUrl) async {
    final uri = Uri.parse(paymentUrl);

    // 1) Prefer external browser (best for payments)
    final canExternal = await canLaunchUrl(uri);
    debugPrint('[BankPage] canLaunch (external) = $canExternal');
    if (canExternal) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      debugPrint('[BankPage] launch external result = $ok');
      if (ok) return;
    }

    // 2) Fallback to in-app webview
    final okWebView = await launchUrl(uri, mode: LaunchMode.inAppWebView);
    debugPrint('[BankPage] launch in-app webview result = $okWebView');
    if (okWebView) return;

    // 3) Final fallback: let user copy URL
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Open Payment Page'),
        content: Text(
          "No browser found to open the payment page.\n\nCopy this URL and open it manually:\n\n$paymentUrl",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: paymentUrl));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment URL copied')),
              );
            },
            child: const Text('Copy URL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    throw Exception('Could not launch the payment URL.');
  }

  Future<void> _startQPayPayment() async {
    final loading = ref.read(bankPageLoadingProvider.notifier);
    loading.state = true;

    try {
      debugPrint('[BankPage] Creating QPay order for ₹$fixedAmount');
      final walletService = ref.read(walletServiceProvider);

      // Attempt to create order via backend QPay integration
      Map<String, dynamic>? orderData;
      try {
        orderData = await walletService.createQPayIndiaOrder(fixedAmount);
        debugPrint('[BankPage] createQPayIndiaOrder OK: $orderData');
      } catch (e) {
        debugPrint('[BankPage] createQPayIndiaOrder failed: $e');
        orderData = null;
      }

      // Try backend-provided launch URL first
      String launchUrlStr = '';
      if (orderData != null) {
        // backend may return different field names — prefer 'launchUrl' then 'paymentUrl' then 'url'
        launchUrlStr = (orderData['launchUrl'] ??
            orderData['paymentUrl'] ??
            orderData['url'] ??
            '')
            .toString()
            .trim();
      }

      if (launchUrlStr.isEmpty) {
        // No valid backend URL — use fallback shortlink
        debugPrint('[BankPage] Backend did not return valid payment URL — using fallback shortlink');
        // Append amount as query param
        launchUrlStr = '$_fallbackPaymentShortlink?amount=$fixedAmount';
      }

      await _launchPaymentUrl(launchUrlStr);

    } catch (e, st) {
      debugPrint('[BankPage] Error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) loading.state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(bankPageLoadingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Money to Wallet')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Amount Display Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Text(
                      'Fixed Amount',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹$fixedAmount',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Standard recharge amount',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            const Text(
              'Top-up Wallet using QPay',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 24),
            
            ElevatedButton.icon(
              onPressed: isLoading ? null : _startQPayPayment,
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.payment),
              label: Text(isLoading ? 'Processing ₹$fixedAmount...' : 'Pay ₹$fixedAmount'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
            
            const SizedBox(height: 20),
            
            const Center(
              child: Text(
                'Your balance will update automatically after you return to the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}