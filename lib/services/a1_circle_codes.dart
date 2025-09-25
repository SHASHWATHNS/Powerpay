// lib/services/a1_circle_codes.dart

/// Maps provider "circle" names to codes from their table/screenshot.
/// Add/adjust names to match what your lookup returns (case-insensitive).
class A1CircleCodes {
  static const Map<String, String> _map = {
    // --- add all you need (keys are lowercase) ---
    'tamil nadu': '8',
    'chennai': '7',
    'mumbai': '3',
    'delhi': '5',
    'kolkata': '6',
    'maharashtra': '4',
    'gujarat': '12',
    'uttar pradesh east': '10',
    'uttar pradesh west': '11',
    'rajasthan': '18',
    'punjab': '1',
    'west bengal': '2',
    'north east': '26',
    'himachal pradesh': '21',
    'karnataka': '9',
    'kerala': '14',
    'madhya pradesh': '16',
    'bihar': '17',
    'assam': '24',
    'haryana': '20',
    'jammu and kashmir': '25',
    'jharkhand': '22',
    'chhattisgarh': '27',
    'andhra pradesh': '13',
    // Fallbacks/aliases
    'orissa': '23',
    'odisha': '23',
    // Your addition
    'dharmapuri': '8',
  };

  static String? codeFor(String? circleName) {
    if (circleName == null) return null;
    final key = circleName.trim().toLowerCase();
    return _map[key];
  }
}