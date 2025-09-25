import 'dart:convert';
import 'package:http/http.dart' as http;

class A1TopupApi {
  // Mapping operator names to A1 API codes
  static const Map<String, String> operatorCodeMap = {
    'Airtel': 'A',
    'VI': 'V',
    'BSNL': 'BT',
    'JIO': 'RC',
  };

  // Method to perform a direct recharge
  static Future<Map<String, dynamic>> rechargeDirect({
    required String baseUrl,
    required String username,
    required String password,
    required String number,
    required String amount,
    required String operatorName, // Operator name (e.g., Airtel, VI, etc.)
    required String circleCode,   // Circle code (e.g., "8" for Tamil Nadu)
  }) async {
    // Ensure the operator is valid and mapped
    final operatorCode = operatorCodeMap[operatorName];
    if (operatorCode == null) {
      return {'status': 'failure', 'message': 'Unknown operator: $operatorName'};
    }

    // Construct the API endpoint with query parameters
    final uri = Uri.parse(baseUrl).replace(queryParameters: {
      'username': username,
      'pwd': password,
      'circlecode': circleCode,
      'operatorcode': operatorCode,
      'number': number,
      'amount': amount,
      'orderid': DateTime.now().millisecondsSinceEpoch.toString(), // Unique order ID
      'format': 'json',
    });

    // Send GET request to the A1 API endpoint
    try {
      final response = await http.get(uri);

      // If the response is not successful, return the error
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          'status': 'failure',
          'message': 'HTTP Error ${response.statusCode}',
          'raw': response.body,
        };
      }

      // Parse the response JSON
      final parsedResponse = jsonDecode(response.body);

      // Check if the parsed response is a Map and return it
      return parsedResponse is Map<String, dynamic>
          ? parsedResponse
          : {'status': 'unknown', 'raw': response.body};
    } catch (e) {
      // Handle any errors that occur during the HTTP request
      return {'status': 'failure', 'message': 'Request failed: $e'};
    }
  }
}
