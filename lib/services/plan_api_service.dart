import 'package:dio/dio.dart';


class PlanApiService {
  final Dio _dio = Dio();

  final String _apiMemberId = '6590';
  final String _apiPassword = 'Naren@123';

  Future<List<dynamic>> getRechargePlans(String operatorId, String circleId) async {
    const url = 'https://planapi.in/api/Mobile/NewMobilePlans';

    try {
      final response = await _dio.get(
        url,
        queryParameters: {
          'apimember_id': _apiMemberId,
          'api_password': _apiPassword,
          'operatorcode': operatorId,
          'cricle': circleId,
        },
      );

      // --- THIS IS THE FIX ---
      // The new logic iterates through all categories and combines them.
      if (response.statusCode == 200 && response.data['RDATA'] is Map) {
        final rdataMap = response.data['RDATA'] as Map<String, dynamic>;
        final List<dynamic> allPlans = []; // Create an empty list to hold everything.

        // Iterate through all the values in the RDATA map (e.g., the lists for "Plan Vouchers", "Data", etc.)
        for (final value in rdataMap.values) {
          // Check if the current value is a list of plans.
          if (value is List) {
            // If it is, add all of its items to our master list.
            allPlans.addAll(value);
          }
        }

        return allPlans; // Return the final, combined list.
      }

      print('PlanAPI Error: Could not find a valid RDATA object. Body: ${response.data}');
      return [];

    } on DioException catch (e) {
      print('PlanAPI DioError: $e');
      throw Exception('Failed to fetch plans. Please check API credentials and URL.');
    } catch (e) {
      print('PlanAPI Unexpected Error: $e');
      return [];
    }
  }
}