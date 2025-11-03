// lib/screens/payment_webview.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// PaymentWebView opens the payment URL and attempts to auto-detect success.
/// If the payment success-like URL is detected it sets subscriptionPaid=true for the given uid.
class PaymentWebView extends StatefulWidget {
  final String initialUrl;
  final String uid;

  const PaymentWebView({
    required this.initialUrl,
    required this.uid,
    super.key,
  });

  @override
  State<PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<PaymentWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _alreadyHandledSuccess = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            final url = request.url.toLowerCase();

            // Generic heuristics — you should replace these with the exact QPay success redirect if known.
            final bool looksLikeSuccess = url.contains('success') ||
                url.contains('status=success') ||
                url.contains('paymentstatus=success') ||
                url.contains('payment_success') ||
                url.contains('txnstatus=success') ||
                (url.contains('txnid=') && url.contains('status'));

            if (looksLikeSuccess && !_alreadyHandledSuccess) {
              _alreadyHandledSuccess = true;
              _markPaidAndNotify();
              // Prevent navigation to avoid double-processing the success page.
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _markPaidAndNotify() async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).update({
        'subscriptionPaid': true,
        'subscriptionPaidAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment detected and confirmed — returning to app...')),
      );

      // Optionally close the webview screen; AuthGate's stream will show MainScreen.
      // Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auto-confirm failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
