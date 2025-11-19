// lib/screens/payment_success_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../providers/wallet_provider.dart';

/// A simple payment success page that shows a green tick and a key/button
/// "Add money to wallet". Pressing the button calls the wallet API verify
/// action for the given providerTxnId and, on success, invalidates the wallet provider.
///
/// Required constructor params:
/// - uid: current user uid
/// - providerTxnId: provider transaction id created before opening QPay
/// - amount: the top-up amount (for UI/info)
/// - walletApiEndpoint: same endpoint as used by BankPage
class PaymentSuccessPage extends ConsumerStatefulWidget {
  final String uid;
  final String providerTxnId;
  final int amount;
  final String walletApiEndpoint;

  const PaymentSuccessPage({
    super.key,
    required this.uid,
    required this.providerTxnId,
    required this.amount,
    required this.walletApiEndpoint,
  });

  @override
  ConsumerState<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends ConsumerState<PaymentSuccessPage> {
  bool _inProgress = false;
  bool _done = false;

  Future<Map<String, dynamic>> _callWalletApiVerify() async {
    final uri = Uri.parse(widget.walletApiEndpoint);
    final payload = {
      'action': 'verify',
      'uid': widget.uid,
      'providerTxnId': widget.providerTxnId,
      'status': 'success',
    };

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      throw Exception('Wallet API returned ${resp.statusCode}');
    }

    return json.decode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _handleAddMoney() async {
    if (_inProgress || _done) return;

    setState(() {
      _inProgress = true;
    });

    try {
      final resp = await _callWalletApiVerify();
      debugPrint('[PaymentSuccessPage] verify resp: $resp');

      if (!mounted) return;

      if (resp['success'] == true) {
        // If server returned a final balance or credited amount, show it
        final finalBalance = resp['final_balance'] ?? resp['newBalance'];
        if (finalBalance != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Payment credited. New balance: ₹$finalBalance'), backgroundColor: Colors.green),
          );
        } else if (resp['message'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp['message'].toString()), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Payment processed'), backgroundColor: Colors.green),
          );
        }

        // Mark done and invalidate wallet provider so UI refreshes
        setState(() {
          _done = true;
          _inProgress = false;
        });

        // Invalidate wallet balance provider (so UI updates)
        ref.invalidate(walletBalanceProvider);

        // Close this page after a short delay so user sees the message
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) Navigator.of(context).pop(true);
        });

        return;
      }

      // Not successful: show server message
      final msg = resp['message']?.toString() ?? 'Verify failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.orange),
      );
    } catch (e) {
      debugPrint('[PaymentSuccessPage] verify error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _inProgress = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final amountDisplay = widget.amount.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Completed'),
        automaticallyImplyLeading: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Big green tick
            Container(
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(24),
              child: Icon(Icons.check_circle, size: 110, color: Colors.green[700]),
            ),
            const SizedBox(height: 24),
            Text(
              'Payment initiated',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '₹$amountDisplay will be credited to your wallet after confirmation.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            Text(
              'Transaction ID:',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),
            Text(
              widget.providerTxnId,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 28),

            // Primary key: Add money to wallet
            // SizedBox(
            //   width: double.infinity,
            //   child: ElevatedButton.icon(
            //     icon: _inProgress
            //         ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            //         : const Icon(Icons.vpn_key),
            //     label: Padding(
            //       padding: const EdgeInsets.symmetric(vertical: 14.0),
            //       child: Text(_done ? 'Added to wallet' : 'Add money to wallet (₹$amountDisplay)'),
            //     ),
            //     onPressed: (_inProgress || _done) ? null : _handleAddMoney,
            //     style: ElevatedButton.styleFrom(
            //       backgroundColor: Colors.green[700],
            //       foregroundColor: Colors.white,
            //       textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            //     ),
            //   ),
            // ),

            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Done'),
            ),

            const Spacer(),

            // Small hint
            Text(
              'If the wallet doesn\'t update automatically, press "Refresh & Verify" on the Add Money screen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
