// lib/screens/wallet_result_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../providers/wallet_provider.dart';

/// Endpoint on your server that handles verification and crediting.
const String qpayApiEndpoint = 'https://projects.growtechnologies.in/powerpay/qpay_wallet_api.php';

/// A page shown after QPay returns to the browser and opens the app via deep link.
/// The page shows details and (only if status == 'success') an "Add to Wallet" button.
class WalletResultPage extends ConsumerStatefulWidget {
  final String providerTxnId;
  final String? uid;
  final String? status;
  final double? amount;

  const WalletResultPage({
    Key? key,
    required this.providerTxnId,
    this.uid,
    this.status,
    this.amount,
  }) : super(key: key);

  @override
  ConsumerState<WalletResultPage> createState() => _WalletResultPageState();
}

class _WalletResultPageState extends ConsumerState<WalletResultPage> {
  bool _loading = false;
  bool _completed = false; // becomes true after successful credit
  String? _message;

  bool get _isSuccess => (widget.status ?? '').toLowerCase() == 'success';

  Future<void> _verifyAndAddToWallet() async {
    if (_loading || _completed) return;

    final user = FirebaseAuth.instance.currentUser;
    // Prefer UID from deep link if present; otherwise use logged-in user's uid.
    final uidToUse = widget.uid ?? user?.uid;
    if (uidToUse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user authenticated. Please sign in.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final payload = {
        'action': 'verify',
        'uid': uidToUse,
        'providerTxnId': widget.providerTxnId,
        if (widget.amount != null) 'amount': widget.amount.toString(),
      };

      final uri = Uri.parse(qpayApiEndpoint);
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));

      debugPrint('[WalletResultPage] status: ${resp.statusCode}');
      debugPrint('[WalletResultPage] body: ${resp.body}');

      if (resp.statusCode != 200) {
        throw Exception('Server returned ${resp.statusCode}: ${resp.body.isNotEmpty ? resp.body : '<empty body>'}');
      }

      if (resp.body.trim().isEmpty) {
        throw Exception('Server returned empty response body');
      }

      Map<String, dynamic> data;
      try {
        data = json.decode(resp.body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Invalid JSON from server: $e\nBody: ${resp.body}');
      }

      final success = data['success'] == true;

      if (success) {
        // Invalidate wallet provider so UI will refresh
        ref.invalidate(walletBalanceProvider);

        // Optional: read newBalance / message from server
        final newBalance = data['newBalance'] ?? data['final_balance'] ?? data['new_balance'];
        final credited = data['credited'] ?? data['amount'] ?? data['credited_amount'];

        String msg = 'Added to wallet';
        if (credited != null) {
          msg = 'Credited ₹${credited.toString()} to wallet';
        } else if (newBalance != null) {
          msg = 'Wallet updated — New balance: ₹${newBalance.toString()}';
        } else if (data['message'] != null) {
          msg = data['message'].toString();
        } else {
          msg = 'Payment verified and wallet updated';
        }

        setState(() {
          _completed = true;
          _message = msg;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.green),
        );

        return;
      }

      // not success
      final serverMsg = data['message']?.toString() ?? 'Verification failed';
      setState(() {
        _message = serverMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(serverMsg), backgroundColor: Colors.red),
      );
    } on TimeoutException catch (_) {
      setState(() {
        _message = 'Request timed out — please try again';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request timed out — please try again'), backgroundColor: Colors.red),
      );
    } catch (e) {
      setState(() {
        _message = 'Error: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _buildActionButton() {
    if (!_isSuccess) {
      return const SizedBox.shrink();
    }

    if (_completed) {
      return ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('Already Added'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
      );
    }

    return ElevatedButton(
      onPressed: _loading ? null : _verifyAndAddToWallet,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
      child: _loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Text('Add to Wallet'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amountText = widget.amount != null ? '₹${widget.amount!.toStringAsFixed(2)}' : '-';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Result'),
        actions: [
          IconButton(
            tooltip: 'Refresh verification',
            onPressed: _loading || _completed ? null : _verifyAndAddToWallet,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(
                    children: [
                      Icon(
                        _isSuccess ? Icons.check_circle_outline : Icons.hourglass_top,
                        color: _isSuccess ? Colors.green : Colors.orange,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isSuccess ? 'Payment Successful' : 'Payment Status: ${widget.status ?? 'unknown'}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Provider Txn ID: ${widget.providerTxnId}', style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('UID: ${widget.uid ?? "-"}', style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('Amount: $amountText', style: const TextStyle(fontSize: 13)),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      style: TextStyle(fontSize: 13, color: _completed ? Colors.green[800] : Colors.red[700]),
                    ),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 20),
            Center(child: _buildActionButton()),
            const SizedBox(height: 14),
            if (!_isSuccess) ...[
              const Text(
                'The Add to Wallet button appears only after a successful payment. If you think this is a mistake, contact support.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              )
            ] else ...[
              const Text(
                'Tap "Add to Wallet" to verify the transaction with the server and credit your wallet. This action is idempotent — if the transaction was already credited you will be informed.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              )
            ],
          ],
        ),
      ),
    );
  }
}
