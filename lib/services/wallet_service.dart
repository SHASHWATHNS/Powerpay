import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

const _apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8080');

final walletServiceProvider = Provider<WalletService>((ref) {
  return WalletService(FirebaseAuth.instance);
});

class WalletService {
  final FirebaseAuth _auth;
  WalletService(this._auth);

  String? get _uid => _auth.currentUser?.uid;

  Future<Map<String, dynamic>> createQPayIndiaOrder(int amount) async {
    if (_uid == null) throw Exception('User not logged in.');
    final uri = Uri.parse('$_apiBase/qpay-india/create-order');

    final res = await http
        .post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'uid': _uid, 'amount': amount}),
    )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('Server ${res.statusCode}: ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final launchUrl = (body['launchUrl'] ?? '').toString().trim();
    if (launchUrl.isEmpty) {
      throw Exception('Backend did not return a valid payment URL.');
    }
    return body; // { orderId, launchUrl }
  }
}
