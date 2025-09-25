import 'package:dio/dio.dart';

class KwikAPIService {
  final Dio _dio = Dio();
  final String kwikApiKey = 'dacb12-a834b6-991a82-347d7e-e9b8b9';

  final operatorMap = {
    'Airtel': '1',
    'Reliance Jio Infocomm Ltd (RJIL)': '116',
    'Vi': '3',
    'BSNL': '11',
  };

  final circleMap = {
    'Tamil Nadu': 'TN',
    'Karnataka': 'KA',
    'Delhi': 'DL',
    'Mumbai': 'MB',
  };

  String? mapOperatorToId(String carrier) => operatorMap[carrier];

  String? mapCircleToCode(String location) => circleMap[location];

  Future<List<dynamic>> getRechargePlans(String opid, String stateCode) async {
    const url = 'https://www.kwikapi.com/api/v2/recharge_plans.php';

    try {
      final formData = FormData.fromMap({
        'api_key': kwikApiKey,
        'state_code': stateCode,
        'opid': opid,
      });

      final response = await _dio.post(url, data: formData);

      if (response.statusCode == 200 && response.data['status'] == true) {
        return response.data['data'] ?? [];
      }
    } catch (e) {
      print('KwikAPI error: $e');
    }

    return [];
  }
}
