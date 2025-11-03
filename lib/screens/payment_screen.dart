// lib/screens/payment_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/payment_service.dart';

class PaymentScreen extends StatefulWidget {
  /// The payment link to open (pass the QPay link here)
  final String paymentLink;

  /// Amount for bookkeeping (₹699)
  final double amount;

  const PaymentScreen({
    Key? key,
    required this.paymentLink,
    required this.amount,
  }) : super(key: key);

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final WebViewController _controller;
  final _paymentService = PaymentService();
  bool _loading = true;
  bool _handled = false;

  @override
  void initState() {
    super.initState();

    // NOTE: Do not call WebView.platform = ... here (avoids analyzer errors in some setups).
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();
            if (_detectSuccessFromUrlOrTitle(url)) {
              _onPaymentSuccess(url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) async {
            if (!mounted) return;
            setState(() => _loading = false);
            // fallback check: page title or body text
            try {
              final title = (await _controller.getTitle()) ?? '';
              if (_detectSuccessFromUrlOrTitle(title.toLowerCase())) {
                _onPaymentSuccess(url);
                return;
              }

              final contentRaw = await _controller.runJavaScriptReturningResult(
                  "document.body ? document.body.innerText : '';");
              if (contentRaw is String) {
                final content = contentRaw.toLowerCase();
                if (_detectSuccessFromUrlOrTitle(content)) {
                  _onPaymentSuccess(url);
                  return;
                }
              }
            } catch (_) {
              // ignore JS eval errors
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentLink));
  }

  bool _detectSuccessFromUrlOrTitle(String s) {
    final markers = [
      'success',
      'completed',
      'payment-success',
      'payment successful',
      'txn_success',
      'transaction successful',
      'thank you',
      'order success',
      'status=success',
    ];
    final lower = s.toLowerCase();
    for (final m in markers) {
      if (lower.contains(m)) return true;
    }
    return false;
  }

  Future<void> _onPaymentSuccess(String source) async {
    if (_handled) return;
    _handled = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment finished but no user is logged in.')),
      );
      Navigator.of(context).pop();
      return;
    }

    setState(() => _loading = true);

    try {
      await _paymentService.markUserAsPaid(
        uid: user.uid,
        amount: widget.amount,
        paymentId: source,
        rawResponse: {'source': source},
      );

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Payment successful'),
          content: const Text('Thank you. Your payment has been recorded and access is unlocked.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // close payment screen
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to record payment: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
