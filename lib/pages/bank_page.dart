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
  // Plans configuration
  final List<_Plan> _plans = const [
    _Plan(amount: 1000, id: 902, title: 'Plan 1 — ₹1000', subtitle: 'Top-up ₹1000'),
    _Plan(amount: 3000, id: 903, title: 'Plan 2 — ₹3000', subtitle: 'Top-up ₹3000'),
    _Plan(amount: 5000, id: 904, title: 'Plan 3 — ₹5000', subtitle: 'Top-up ₹5000'),
  ];

  // Selected plan index
  int _selectedPlanIndex = 0;

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

  Future<void> _startQPayPaymentForSelectedPlan() async {
    final loading = ref.read(bankPageLoadingProvider.notifier);
    loading.state = true;

    try {
      final plan = _plans[_selectedPlanIndex];
      debugPrint('[BankPage] Selected plan: ${plan.title} (₹${plan.amount})');

      // Build the QPay link for the chosen plan (IDs come from user)
      final paymentLink =
          'https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx?id=${plan.id}';

      // Optional: append amount (not required if link already encodes it)
      final launchUrlStr = paymentLink; // or '$paymentLink&amount=${plan.amount}';

      // Show a short message then launch
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening payment page for ₹${plan.amount}...')),
        );
      }

      await _launchPaymentUrl(launchUrlStr);

      // NOTE:
      // We rely on the app lifecycle (resumed) to refresh the wallet balance after payment.
      // Many payment providers redirect back to the app (deep link) or the user returns via browser.
      // When the app regains focus, didChangeAppLifecycleState will invalidate the wallet provider.
      debugPrint('[BankPage] Launched payment link for plan id=${plan.id}');
    } catch (e, st) {
      debugPrint('[BankPage] Error while starting payment: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        loading.state = false;
      }
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
            // Header / Info Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      'Choose a Top-up Plan',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select one of the plans below to add money to your wallet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Plans list
            ...List.generate(_plans.length, (index) {
              final plan = _plans[index];
              final selected = index == _selectedPlanIndex;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedPlanIndex = index);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Card(
                    elevation: selected ? 6 : 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: selected
                          ? BorderSide(color: Colors.purple.shade300, width: 1.5)
                          : BorderSide(color: Colors.transparent),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                      child: Row(
                        children: [
                          Radio<int>(
                            value: index,
                            groupValue: _selectedPlanIndex,
                            onChanged: (v) => setState(() => _selectedPlanIndex = v ?? 0),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  plan.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  plan.subtitle,
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isLoading
                                ? null
                                : () {
                              setState(() => _selectedPlanIndex = index);
                              _startQPayPaymentForSelectedPlan();
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                            ),
                            child: isLoading
                                ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                                : Text('Pay ₹${plan.amount}'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 12),

            // Main Pay button (duplicates convenience to pay selected plan)
            ElevatedButton.icon(
              onPressed: isLoading ? null : _startQPayPaymentForSelectedPlan,
              icon: isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
                  : const Icon(Icons.payment),
              label: Text(isLoading
                  ? 'Processing ₹${_plans[_selectedPlanIndex].amount}...'
                  : 'Pay ₹${_plans[_selectedPlanIndex].amount}'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: Colors.purple,
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

/// Simple plan model used in this screen
class _Plan {
  final int amount;
  final int id; // QPay payment link id
  final String title;
  final String subtitle;

  const _Plan({
    required this.amount,
    required this.id,
    required this.title,
    required this.subtitle,
  });
}
