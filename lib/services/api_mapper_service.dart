// lib/services/api_mapper_service.dart

class ApiMapper {
  // =======================================================================
  //                      *** Standard App Data ***
  // =======================================================================
  // These are the clean, user-facing lists for your dropdowns.
  static const List<String> supportedOperators = ['Airtel', 'VI', 'BSNL', 'JIO'];

  static const List<String> supportedCircles = [
    'Andhra Pradesh', 'Assam', 'Bihar', 'Chennai', 'Delhi', 'Gujarat', 'Haryana',
    'Himachal Pradesh', 'Jammu And Kashmir', 'Jharkhand', 'Karnataka', 'Kerala',
    'Kolkata', 'Madhya Pradesh', 'Maharashtra', 'Mumbai', 'North East', 'Orissa',
    'Punjab', 'Rajasthan', 'Tamil Nadu', 'Tripura', 'UP East', 'UP West', 'West Bengal',
  ];

  // =======================================================================
  //                 *** A1Topup API Mappings (for Recharge) ***
  // =======================================================================
  static String? getA1TopupOperatorCode(String appOperatorName) {
    // Merging Vodafone and Idea into 'VI'
    if (appOperatorName.toUpperCase() == 'VI') return 'V';

    const Map<String, String> operatorMap = {
      'AIRTEL': 'A',
      'BSNL': 'BT', // Using BSNL-TOPUP as the default for recharge
      'JIO': 'RC',
    };
    return operatorMap[appOperatorName.toUpperCase()];
  }

  static String? getA1TopupCircleCode(String appCircleName) {
    const Map<String, String> circleMap = {
      'ANDHRA PRADESH': '24', 'ASSAM': '17', 'BIHAR': '12', 'CHENNAI': '7', 'DELHI': '5',
      'GUJARAT': '14', 'HARYANA': '16', 'HIMACHAL PRADESH': '4', 'JAMMU AND KASHMIR': '9',
      'JHARKHAND': '12', // A1Topup uses the same code as Bihar
      'KARNATAKA': '13', 'KERALA': '25', 'KOLKATA': '6', 'MADHYA PRADESH': '21',
      'MAHARASHTRA': '22', 'MUMBAI': '3', 'NORTH EAST': '26', 'ORISSA': '23',
      'PUNJAB': '1', 'RAJASTHAN': '18', 'TAMIL NADU': '8', 'TRIPURA': '27',
      'UP EAST': '10', 'UP WEST': '11', 'WEST BENGAL': '2',
    };
    return circleMap[appCircleName.toUpperCase()];
  }

  // =======================================================================
  //                  *** Ezytm API Mappings (for Plans) ***
  // =======================================================================
  static String? getEzytmOperatorId(String appOperatorName) {
    // Merging Vodafone and Idea into 'VI'
    if (appOperatorName.toUpperCase() == 'VI') return '23'; // Using Vodafone's ID

    const Map<String, String> operatorMap = {
      'AIRTEL': '2',
      'BSNL': '5', // Using BSNL SPECIAL as the default for plans
      'JIO': '11',
    };
    return operatorMap[appOperatorName.toUpperCase()];
  }

  static String? getEzytmCircleId(String appCircleName) {
    const Map<String, String> circleMap = {
      'ANDHRA PRADESH': '49', 'ASSAM': '56', 'BIHAR': '52', 'CHENNAI': '40', 'DELHI': '10',
      'GUJARAT': '98', 'HARYANA': '96', 'HIMACHAL PRADESH': '03', 'JAMMU AND KASHMIR': '55',
      'JHARKHAND': '105', 'KARNATAKA': '06', 'KERALA': '95', 'KOLKATA': '31',
      'MADHYA PRADESH': '93', 'MAHARASHTRA': '90', 'MUMBAI': '92', 'NORTH EAST': '16',
      'ORISSA': '53', 'PUNJAB': '02', 'RAJASTHAN': '70', 'TAMIL NADU': '94',
      'TRIPURA': '100', 'UP EAST': '54', 'UP WEST': '97', 'WEST BENGAL': '51',
    };
    return circleMap[appCircleName.toUpperCase()];
  }
}