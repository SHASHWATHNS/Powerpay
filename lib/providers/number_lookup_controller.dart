import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/number_details.dart';
import '../services/kwikapi_service.dart';
import 'numlook_providers.dart';

class NumberLookupState {
  final String raw;
  final String formatted;
  final bool canSearch;
  final NumberDetails? details;
  final List<dynamic> rechargePlans;

  NumberLookupState({
    required this.raw,
    required this.formatted,
    required this.canSearch,
    required this.details,
    required this.rechargePlans,
  });

  factory NumberLookupState.initial() => NumberLookupState(
    raw: '',
    formatted: '',
    canSearch: false,
    details: null,
    rechargePlans: [],
  );

  NumberLookupState copyWith({
    String? raw,
    String? formatted,
    bool? canSearch,
    NumberDetails? details,
    List<dynamic>? rechargePlans,
  }) {
    return NumberLookupState(
      raw: raw ?? this.raw,
      formatted: formatted ?? this.formatted,
      canSearch: canSearch ?? this.canSearch,
      details: details ?? this.details,
      rechargePlans: rechargePlans ?? this.rechargePlans,
    );
  }
}

class NumberLookupController extends StateNotifier<NumberLookupState> {
  NumberLookupController(this.ref) : super(NumberLookupState.initial());
  final Ref ref;

  void onNumberChanged(String input, TextEditingController controller) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    final trimmed = digits.length > 10 ? digits.substring(digits.length - 10) : digits;

    String formatted = trimmed.length <= 5
        ? trimmed
        : '${trimmed.substring(0, 5)} ${trimmed.substring(5)}';

    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );

    state = state.copyWith(
      raw: trimmed,
      formatted: formatted,
      canSearch: trimmed.length == 10,
      details: trimmed.length < 10 ? null : state.details,
    );
  }

  // ---------- Normalizers (key fix) ----------
  String _normalizeCarrier(String raw) {
    final s = (raw).toLowerCase().trim();

    if (s.isEmpty) return 'Unknown';

    // Map common variants -> your canonical operator keys
    if (s.contains('jio') || s.contains('reliance jio')) return 'Jio';
    if (s.contains('airtel') || s.contains('bharti')) return 'Airtel';
    if (s == 'vi' || s.contains('vodafone') || s.contains('idea')) return 'Vi';
    if (s.contains('bsnl') || s.contains('bharat sanchar')) return 'BSNL';

    // Title case fallback
    return s
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _normalizeCircle(String raw) {
    final s = (raw).toLowerCase().trim();

    if (s.isEmpty) return 'Unknown';

    // Reduce city/state text to circle names you support in KwikAPIService
    if (s.contains('karnataka') || s.contains('bengaluru') || s.contains('bangalore')) return 'Karnataka';
    if (s.contains('tamil nadu') || s.contains('chennai')) return 'Tamil Nadu';
    if (s.contains('mumbai')) return 'Mumbai';
    if (s.contains('maharashtra') && !s.contains('mumbai')) return 'Maharashtra';
    if (s.contains('delhi') || s.contains('new delhi')) return 'Delhi';
    if (s.contains('kolkata') || s.contains('west bengal')) return 'Kolkata';
    if (s.contains('kerala')) return 'Kerala';
    if (s.contains('andhra') || s.contains('ap')) return 'Andhra Pradesh';
    if (s.contains('telangana') || s.contains('hyderabad')) return 'Telangana';
    if (s.contains('gujarat') || s.contains('ahmedabad')) return 'Gujarat';
    if (s.contains('punjab') || s.contains('chandigarh')) return 'Punjab';
    if (s.contains('rajasthan') || s.contains('jaipur')) return 'Rajasthan';
    if (s.contains('mp') || s.contains('madhya pradesh') || s.contains('bhopal') || s.contains('indore')) return 'Madhya Pradesh';
    if (s.contains('up') || s.contains('uttar pradesh') || s.contains('lucknow') || s.contains('noida')) return 'Uttar Pradesh';

    // Title case fallback
    return raw
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Future<void> lookupNumber(BuildContext context) async {
    final number = state.raw;
    if (number.length != 10) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final details = await ref.read(numlookupProvider('+91$number').future);
      Navigator.of(context).pop();

      if (details != null) {
        // Normalize fields from Numlookup before mapping to Kwik
        final normalizedCarrier = _normalizeCarrier(details.carrier);
        final normalizedCircle = _normalizeCircle(details.location);

        // Always show detected details (even if plan mapping fails)
        state = state.copyWith(
          details: NumberDetails(
            carrier: normalizedCarrier,
            location: normalizedCircle,
          ),
          rechargePlans: const [],
        );

        final service = KwikAPIService();
        final opid = service.mapOperatorToId(normalizedCarrier);
        final circle = service.mapCircleToCode(normalizedCircle);

        if (opid != null && circle != null) {
          final plans = await service.getRechargePlans(opid, circle);
          state = state.copyWith(rechargePlans: plans);
        } else {
          showError(
            context,
            'Number validated. Couldn’t match Operator/Circle for plans (ported or uncommon label).',
          );
        }
      } else {
        showError(context, 'Failed to get number details.');
      }
    } catch (e) {
      Navigator.of(context).pop();
      showError(context, 'Something went wrong!');
    }
  }

  void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

final numberLookupControllerProvider =
StateNotifierProvider<NumberLookupController, NumberLookupState>(
        (ref) => NumberLookupController(ref));
