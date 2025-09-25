// lib/services/a1topup_proxy_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class A1TopupProxyService {
  static const String _backendUrl = 'http://10.0.2.2:8080';

  static Future<Map<String, dynamic>> recharge(
      String uid,
      String number,
      int amount,
      String operatorCode,
      String circleCode,
      String orderId,
      ) async {
    try {
      final uri = Uri.parse('$_backendUrl/recharge');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'number': number,
          'amount': amount,
          'operatorCode': operatorCode,
          'circleCode': circleCode,
          'orderId': orderId,
        }),
      );

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return {'status': 'failure', 'message': 'Invalid response format'};
      }

      return decoded;
    } catch (e) {
      return {'status': 'failure', 'message': 'Network error: $e'};
    }
  }
}