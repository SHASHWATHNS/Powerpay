import 'package:flutter/material.dart';
import 'package:powerpay/screens/main_screen.dart';
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
            if (url.contains('success') || url.contains('thankyou') || url.contains('payment/success') || url.contains('callback')) {
              if (mounted) Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MainScreen()),
                (_) => false,
              );
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (err) => debugPrint('Web error: ${err.description}'),
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  void _goToHomePage() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goToHomePage,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh), 
            onPressed: () => _controller.reload()
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
      // FIXED: Removed Hero widgets and used regular FABs
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: null, // FIX: Disable hero animation for this button
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Confirm Payment'),
                  content: const Text('If you have completed the payment on the opened page, press "Yes" to confirm.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false), 
                      child: const Text('No')
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true), 
                      child: const Text('Yes')
                    ),
                  ],
                ),
              );
              if (ok == true && mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                  (_) => false,
                );
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('I have paid'),
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: null, // FIX: Disable hero animation for this button
            onPressed: _goToHomePage,
            icon: const Icon(Icons.home),
            label: const Text('Skip to Home'),
            backgroundColor: Colors.grey,
          ),
        ],
      ),
    );
  }
}