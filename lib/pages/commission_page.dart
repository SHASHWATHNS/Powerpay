// lib/services/api_mapper_service.dart

class ApiMapper {
  static const List<String> supportedOperators = ['Airtel', 'VI', 'BSNL', 'JIO'];

  static const List<String> supportedCircles = [
    'Andhra Pradesh', 'Assam', 'Bihar', 'Chennai', 'Delhi', 'Gujarat', 'Haryana',
    'Himachal Pradesh', 'Jammu And Kashmir', 'Jharkhand', 'Karnataka', 'Kerala',
    'Kolkata', 'Madhya Pradesh', 'Maharashtra', 'Mumbai', 'North East', 'Orissa',
    'Punjab', 'Rajasthan', 'Tamil Nadu', 'Tripura', 'UP East', 'UP West', 'West Bengal',
  ];

  // Legacy mapping functions used by Flutter UI
  // These names are intentionally short (operatorToCode / circleToCode)
  // so they match earlier references in your app.
  static String? operatorToCode(String? appOperatorName) {
    if (appOperatorName == null) return null;
    final n = appOperatorName.trim().toUpperCase();
    if (n == 'VI' || n == 'VODAFONE IDEA' || n == 'VODAFONE' || n == 'IDEA') return 'V';
    if (n == 'AIRTEL') return 'A';
    if (n.contains('BSNL')) return 'BT';
    if (n.contains('JIO')) return 'RC';
    // fallback - return null to indicate unknown
    return null;
  }

  static String? circleToCode(String? appCircleName) {
    if (appCircleName == null) return null;
    final n = appCircleName.trim().toUpperCase();
    const Map<String, String> mp = {
      'ANDHRA PRADESH':'24','ASSAM':'17','BIHAR':'12','CHENNAI':'7','DELHI':'5',
      'GUJARAT':'14','HARYANA':'16','HIMACHAL PRADESH':'4','JAMMU AND KASHMIR':'9',
      'JHARKHAND':'12','KARNATAKA':'13','KERALA':'25','KOLKATA':'6','MADHYA PRADESH':'21',
      'MAHARASHTRA':'22','MUMBAI':'3','NORTH EAST':'26','ORISSA':'23','PUNJAB':'1',
      'RAJASTHAN':'18','TAMIL NADU':'8','TRIPURA':'27','UP EAST':'10','UP WEST':'11','WEST BENGAL':'2'
    };
    if (mp.containsKey(n)) return mp[n];
    // tolerate short forms
    const alt = {'TN':'8','WB':'2','MP':'21','MH':'22','KA':'13','KL':'25'};
    if (alt.containsKey(n)) return alt[n];
    return null;
  }

  // Ezytm mapping kept (if you use it elsewhere)
  static String? getEzytmOperatorId(String? appOperatorName) {
    if (appOperatorName == null) return null;
    final n = appOperatorName.trim().toUpperCase();
    if (n == 'VI') return '23';
    const m = {'AIRTEL':'2','BSNL':'5','JIO':'11'};
    return m[n];
  }
  static String? getEzytmCircleId(String? appCircleName) {
    if (appCircleName == null) return null;
    final n = appCircleName.trim().toUpperCase();
    const m = {
      'ANDHRA PRADESH':'49','ASSAM':'56','BIHAR':'52','CHENNAI':'40','DELHI':'10','GUJARAT':'98','HARYANA':'96','HIMACHAL PRADESH':'03','JAMMU AND KASHMIR':'55','JHARKHAND':'105','KARNATAKA':'06','KERALA':'95','KOLKATA':'31','MADHYA PRADESH':'93','MAHARASHTRA':'90','MUMBAI':'92','NORTH EAST':'16','ORISSA':'53','PUNJAB':'02','RAJASTHAN':'70','TAMIL NADU':'94','TRIPURA':'100','UP EAST':'54','UP WEST':'97','WEST BENGAL':'51'
    };
    return m[n];
  }
}
