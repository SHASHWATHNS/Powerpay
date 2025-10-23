// lib/pages/add_money_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'payment_webview_screen.dart'; // file should be in the same folder (lib/pages/)

class AddMoneyPage extends StatefulWidget {
  const AddMoneyPage({Key? key}) : super(key: key);

  @override
  State<AddMoneyPage> createState() => _AddMoneyPageState();
}

class _AddMoneyPageState extends State<AddMoneyPage> {
  final TextEditingController amountController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  void _onAddMoneyPressed() {
    final text = amountController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an amount')));
      return;
    }
    final amount = double.tryParse(text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount')));
      return;
    }

    _openPaymentWebView(amount);
  }

  Future<void> _openPaymentWebView(double amount) async {
    setState(() => _loading = true);

    // Shortlink you provided. We append amount as query param (optional — page may ignore it).
    final url = 'https://rzp.io/rzp/xd8KZaS?amount=${amount.toInt()}';

    try {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => PaymentWebViewScreen(initialUrl: url),
        ),
      );

      setState(() => _loading = false);

      if (result == true) {
        // Payment acknowledged (either auto-detected or user-confirmed)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment acknowledged — wallet will be updated.')),
        );

        // OPTIONAL: call your backend to credit the wallet (mock or real)
        // await _notifyBackendForCredit(amount);

      } else {
        // canceled / not completed
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment not completed')),
        );
      }
    } catch (e, st) {
      setState(() => _loading = false);
      debugPrint('Error opening payment webview: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An error occurred while opening the payment page')),
      );
    }
  }

  // Optional: notify your backend to credit the wallet after confirmation
  // Replace URL and payload with your actual endpoint & logic
  Future<void> _notifyBackendForCredit(double amount) async {
    try {
      final url = Uri.parse('http://192.168.1.42:3000/creditWallet'); // example
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': 'OSGEapiacc', 'amount': amount}),
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        // handle success
        debugPrint('Backend credited wallet: ${resp.body}');
      } else {
        debugPrint('Backend credit error: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      debugPrint('Notify backend error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Money to Wallet")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Amount (in ₹)',
                border: OutlineInputBorder(),
                prefixText: '₹ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.payment),
                label: Text(_loading ? 'Preparing Payment...' : 'Add Money Now'),
                onPressed: _loading ? null : _onAddMoneyPressed,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your balance will update automatically after you return to the app.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
