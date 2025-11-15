// lib/screens/payment_flow.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  String _capturedPaymentId = '';

  @override
  void initState() {
    super.initState();

    // NOTE:
    // We intentionally DON'T set WebView.platform = AndroidWebView() or WebKitWebView()
    // here because those classes live in separate packages (webview_flutter_android / webview_flutter_wkwebview)
    // and referencing them directly causes "undefined" errors if the platform packages are not added.
    //
    // The WebViewController + WebViewWidget approach works with the main webview_flutter package.
    // If you DO want to use the platform-specific controllers (for advanced features), add the
    // platform packages to pubspec.yaml and reintroduce the platform assignment.

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onNavigationRequest: (NavigationRequest nav) {
            final url = nav.url;
            final low = url.toLowerCase();

            // Heuristics for success and cancel. Tune these to the exact QPay redirect URLs/params.
            final looksLikeSuccess = low.contains('status=success') ||
                low.contains('/success') ||
                low.contains('paymentstatus=success') ||
                low.contains('payment_success') ||
                low.contains('txnstatus=success') ||
                (low.contains('txnid=') && low.contains('status'));

            final looksLikeCancel = low.contains('status=cancel') ||
                low.contains('/cancel') ||
                low.contains('payment_cancel');

            if (looksLikeCancel && !_alreadyHandledSuccess) {
              _alreadyHandledSuccess = true;
              if (mounted) Navigator.of(context).pop(false);
              return NavigationDecision.prevent;
            }

            if (looksLikeSuccess && !_alreadyHandledSuccess) {
              _alreadyHandledSuccess = true;

              // Try to parse paymentId from common query param names.
              try {
                final uri = Uri.parse(url);
                final qp = uri.queryParameters;
                final paymentId = qp['paymentId'] ??
                    qp['transactionId'] ??
                    qp['txnid'] ??
                    qp['txnId'] ??
                    qp['id'] ??
                    '';

                _capturedPaymentId = paymentId;
              } catch (_) {
                _capturedPaymentId = '';
              }

              if (mounted) {
                Navigator.of(context).pop({
                  'success': true,
                  'paymentId': _capturedPaymentId,
                  'rawRedirect': url,
                });
              }
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  @override
  Widget build(BuildContext context) {
    final price = widget.isDistributor ? '₹1099' : '₹599';
    return Scaffold(
      appBar: AppBar(
        title: Text('Pay $price to access app'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            // Indicate cancellation
            Navigator.of(context).pop(false);
          },
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
