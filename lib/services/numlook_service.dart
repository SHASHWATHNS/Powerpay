import 'package:dio/dio.dart';
import '../models/number_details.dart';

class NumlookupService {
  final Dio _dio = Dio();

  Future<NumberDetails?> lookup(String phone) async {
    const baseUrl = 'https://api.numlookupapi.com/v1/validate/';
    // Keep your existing live key here; shown as placeholder for safety
    const apiKey = 'num_live_OzebtNe4vmXUzQBAIHVfJgFPoaNuzJAy1tmMIAFw';

    try {
      // You are already passing phone as +91XXXXXXXXXX from the controller
      final response = await _dio.get('$baseUrl$phone?apikey=$apiKey');

      if (response.statusCode == 200 && response.data['valid'] == true) {
        // Some payloads may use alternative location fields depending on country
        final carrier = (response.data['carrier'] ?? '').toString();
        final location = (response.data['location'] ??
            response.data['region'] ??
            response.data['state'] ??
            '')
            .toString();

        return NumberDetails(
          carrier: carrier,
          location: location,
        );
      }
    } catch (e) {
      // Keep lightweight logging; avoid crashing caller
      // ignore: avoid_print
      print('Numlookup error: $e');
    }

    return null;
  }
}
