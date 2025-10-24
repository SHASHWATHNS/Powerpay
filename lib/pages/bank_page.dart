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
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

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
    _amountController.dispose();
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
    if (!_formKey.currentState!.validate()) return;

    final loading = ref.read(bankPageLoadingProvider.notifier);
    loading.state = true;

    try {
      final amountText = _amountController.text.trim();
      final amount = int.parse(amountText);

      debugPrint('[BankPage] Creating QPay order for ₹$amount');
      final walletService = ref.read(walletServiceProvider);

      // Attempt to create order via backend QPay integration
      Map<String, dynamic>? orderData;
      try {
        orderData = await walletService.createQPayIndiaOrder(amount);
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
        // Append amount as query param (optional)
        launchUrlStr = '$_fallbackPaymentShortlink?amount=$amount';
      }

      await _launchPaymentUrl(launchUrlStr);

      // If we got here, launching succeeded; clear input
      _amountController.clear();
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
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Top-up Wallet using QPay',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Amount (in ₹)',
                  hintText: 'Minimum ₹10',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.currency_rupee),
                ),
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Please enter an amount';
                  final n = int.tryParse(v);
                  if (n == null || n < 10) {
                    return 'Amount must be a whole number, minimum ₹10';
                  }
                  return null;
                },
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
                label: Text(isLoading ? 'Preparing Payment...' : 'Add Money Now'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
      ),
    );
  }
}
