// lib/pages/payment_webview_screen.dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaymentWebViewScreen extends StatefulWidget {
  final String initialUrl;
  const PaymentWebViewScreen({Key? key, required this.initialUrl}) : super(key: key);

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (nav) {
            final url = nav.url.toLowerCase();
            // adjust these keywords if your payment landing page uses different text
            if (url.contains('success') || url.contains('thankyou') || url.contains('payment/success') || url.contains('callback')) {
              Navigator.of(context).pop(true); // treat as success
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (err) {
            debugPrint('Web error: ${err.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => _controller.reload())],
      ),
      body: Stack(children: [
        WebViewWidget(controller: _controller),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Manual confirmation fallback
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Confirm Payment'),
              content: const Text('If you have completed the payment on the web page, press Yes to confirm.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
                TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes')),
              ],
            ),
          );
          if (ok == true) Navigator.of(context).pop(true);
        },
        label: const Text('I have paid'),
        icon: const Icon(Icons.check),
      ),
    );
  }
}
