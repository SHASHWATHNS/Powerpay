// lib/screens/payment_flow.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'main_screen.dart'; // <-- update path if MainScreen is elsewhere

class PaymentFlow extends StatefulWidget {
  final String uid;
  final String paymentUrl;
  final bool isDistributor;

  const PaymentFlow({
    required this.uid,
    required this.paymentUrl,
    required this.isDistributor,
    super.key,
  });

  @override
  State<PaymentFlow> createState() => _PaymentFlowState();
}

class _PaymentFlowState extends State<PaymentFlow> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _alreadyHandledSuccess = false;
  bool _manualProcessing = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          setState(() => _isLoading = true);
        },
        onPageFinished: (url) {
          setState(() => _isLoading = false);
        },
        onNavigationRequest: (req) {
          final url = req.url.toLowerCase();

          // Heuristics for detecting payment success — customize if QPay gives a specific callback URL.
          final looksLikeSuccess = url.contains('success') ||
              url.contains('status=success') ||
              url.contains('paymentstatus=success') ||
              url.contains('payment_success') ||
              url.contains('txnstatus=success') ||
              (url.contains('txnid=') && url.contains('status'));

          if (looksLikeSuccess && !_alreadyHandledSuccess) {
            _alreadyHandledSuccess = true;
            _confirmPaymentAndEnterApp(auto: true);
            return NavigationDecision.prevent;
          }

          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  Future<void> _confirmPaymentAndEnterApp({required bool auto}) async {
    if (_manualProcessing) return;
    setState(() => _manualProcessing = true);
    try {
      // Update Firestore
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).update({
        'subscriptionPaid': true,
        'subscriptionPaidAt': FieldValue.serverTimestamp(),
      });

      // Show message and navigate into the app
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auto ? 'Payment confirmed automatically.' : 'Payment marked as completed.')),
      );

      // Replace stack with MainScreen
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to confirm payment: $e')));
    } finally {
      if (mounted) setState(() => _manualProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = widget.isDistributor ? '₹1099' : '₹599';
    return Scaffold(
      appBar: AppBar(
        title: Text('Pay $price to access app'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading) const Center(child: CircularProgressIndicator()),
            ],
          )),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _manualProcessing ? null : () => _confirmPaymentAndEnterApp(auto: false),
                child: _manualProcessing
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('I have completed payment'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
