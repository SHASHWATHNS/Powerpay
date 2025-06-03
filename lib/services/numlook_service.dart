import 'package:dio/dio.dart';

class NumlookupService {
  final Dio _dio = Dio();
  final String apiKey = 'num_live_Ix6NcnDY6SReXmzwjrmbfvMuWuiAs1P21P3NqgQG'; // Replace this

  Future<String?> getCarrierName(String phoneNumber) async {
    final url = 'https://api.numlookupapi.com/v1/validate/$phoneNumber?apikey=$apiKey';
    try {
      final response = await _dio.get(url);
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['valid'] == true) {
          return data['carrier'] ?? 'Unknown';
        }
        return 'Invalid number';
      }
    } catch (e) {
      print("Dio Error: $e");
    }
    return null;
  }
}
