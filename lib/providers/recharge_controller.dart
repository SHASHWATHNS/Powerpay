import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powerpay/services/a1topup_proxy_service.dart';
import 'package:powerpay/services/api_mapper_service.dart';
import 'package:powerpay/services/plan_api_service.dart'; // Your Ezytm service
import 'package:powerpay/services/transaction_service.dart';

// State class to hold all UI data
class RechargeState {
  final bool isLoading;
  final String? selectedOperator;
  final String? selectedCircle;
  final List<dynamic> plans;
  final String? statusMessage;

  const RechargeState({
    this.isLoading = false, this.selectedOperator, this.selectedCircle,
    this.plans = const [], this.statusMessage,
  });

  RechargeState copyWith({ bool? isLoading, String? selectedOperator,
    String? selectedCircle, List<dynamic>? plans, String? statusMessage, bool clearStatus = false,
  }) {
    return RechargeState(
      isLoading: isLoading ?? this.isLoading,
      selectedOperator: selectedOperator ?? this.selectedOperator,
      selectedCircle: selectedCircle ?? this.selectedCircle,
      plans: plans ?? this.plans,
      statusMessage: clearStatus ? null : statusMessage ?? this.statusMessage,
    );
  }
}

// The Controller (StateNotifier)
class RechargeController extends StateNotifier<RechargeState> {
  RechargeController(this.ref) : super(const RechargeState());

  final Ref ref;
  final PlanApiService _planApiService = PlanApiService();

  void selectOperator(String? operator) {
    state = state.copyWith(selectedOperator: operator, plans: []);
    _fetchPlans();
  }

  void selectCircle(String? circle) {
    state = state.copyWith(selectedCircle: circle, plans: []);
    _fetchPlans();
  }

  Future<void> _fetchPlans() async {
    if (state.selectedOperator == null || state.selectedCircle == null) return;
    state = state.copyWith(isLoading: true);

    final operatorId = ApiMapper.getEzytmOperatorId(state.selectedOperator!);
    final circleId = ApiMapper.getEzytmCircleId(state.selectedCircle!);

    if (operatorId != null && circleId != null) {
      try {
        final plans = await _planApiService.getRechargePlans(operatorId, circleId);
        state = state.copyWith(plans: plans, isLoading: false);
      } catch (e) {
        state = state.copyWith(isLoading: false, statusMessage: "Failed to fetch plans.");
      }
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> performRecharge({ required String number, required int amount, required String uid }) async {
    state = state.copyWith(isLoading: true, clearStatus: true);

    if (state.selectedOperator == null || state.selectedCircle == null) {
      state = state.copyWith(isLoading: false, statusMessage: "Error: Operator or Circle not selected.");
      return;
    }

    final operatorCode = ApiMapper.getA1TopupOperatorCode(state.selectedOperator!);
    final circleCode = ApiMapper.getA1TopupCircleCode(state.selectedCircle!);

    if (operatorCode == null || circleCode == null) {
      state = state.copyWith(isLoading: false, statusMessage: "Error: This operator or circle is not supported for recharge.");
      return;
    }

    final txService = ref.read(transactionServiceProvider);
    String? transactionId;
    try {
      transactionId = await txService.createPending(number: number, operatorName: state.selectedOperator!, amount: amount);
      final response = await A1TopupProxyService.recharge(uid, number, amount, operatorCode, circleCode, transactionId!);
      final status = _inferStatus(response);
      final reason = _inferReason(response);
      await txService.markStatus(id: transactionId, status: status, failureReason: reason);
      state = state.copyWith(isLoading: false, statusMessage: "$status: ${reason ?? 'Completed'}");
    } catch (e) {
      if (transactionId != null) {
        await txService.markStatus(id: transactionId, status: 'failed', failureReason: e.toString());
      }
      state = state.copyWith(isLoading: false, statusMessage: "Error: ${e.toString()}");
    }
  }

  String _inferStatus(Map<String, dynamic> r) => (r['status'] ?? '').toString().toLowerCase() == 'success' ? 'success' : 'failed';
  String? _inferReason(Map<String, dynamic> r) => r['opid']?.toString() ?? r['txid']?.toString();
}

// The Provider for the UI
final rechargeControllerProvider = StateNotifierProvider<RechargeController, RechargeState>((ref) {
  return RechargeController(ref);
});