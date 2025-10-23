import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_models.dart'; // Using the unified models file

// --- Placeholder for KwikAPIService ---
class KwikAPIService {
  String? mapOperatorToId(String? carrier) => '1';
  String? mapCircleToCode(String? location) => '1';
  Future<List<dynamic>> getRechargePlans(String opid, String circle) async => [];
}
final kwikApiServiceProvider = Provider((ref) => KwikAPIService());

// --- Placeholder for A1TopupProxyService ---
class A1TopupProxyService {
  Future<Map<String, dynamic>> recharge(
      String uid, String number, int amount, String opCode, String circleCode, String orderId
      ) async {
    return {'status': 'success', 'message': 'Recharge successful!'};
  }
}
final a1TopupProxyServiceProvider = Provider((ref) => A1TopupProxyService());

// --- Basic Models and Controller for Number Lookup ---
@immutable
class NumberLookupState {
  final bool canSearch;
  final NumberDetails? details;
  const NumberLookupState({this.canSearch = false, this.details});
}

final numberLookupControllerProvider =
StateNotifierProvider.autoDispose<NumberLookupController, NumberLookupState>((ref) {
  return NumberLookupController();
});

class NumberLookupController extends StateNotifier<NumberLookupState> {
  NumberLookupController() : super(const NumberLookupState());

  void onNumberChanged(String value, TextEditingController controller) {
    state = NumberLookupState(canSearch: value.length >= 10, details: state.details);
  }

  Future<void> lookupNumber(BuildContext context) async {
    state = NumberLookupState(
      canSearch: true,
      details: NumberDetails(carrier: 'Airtel', location: 'Delhi'),
    );
  }
}