import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/number_lookup_controller.dart';
import '../services/a1_circle_codes.dart';
import '../services/a1topup_proxy_service.dart';
import '../services/kwikapi_service.dart';
import '../services/transaction_service.dart';

class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});
  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  final TextEditingController numberController = TextEditingController();
  final TextEditingController amountController = TextEditingController();

  String? _selectedOperator;
  List<dynamic> _plans = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    numberController.addListener(() {
      if (numberController.text.length < 10) {
        setState(() => _plans = []);
      }
    });
  }

  String? _normalizeCarrierToOperator(String? carrierRaw) {
    final c = (carrierRaw ?? '').toLowerCase();
    if (c.contains('airtel')) return 'Airtel';
    if (c.contains('vi') || c.contains('vodafone') || c.contains('idea')) return 'VI';
    if (c.contains('bsnl')) return 'BSNL';
    if (c.contains('jio') || c.contains('reliance')) return 'JIO';
    return null;
  }

  Future<void> _fetchPlans() async {
    final state = ref.read(numberLookupControllerProvider);
    if (state.details == null) return;

    final service = KwikAPIService();
    final opid = service.mapOperatorToId(state.details!.carrier);
    final circle = service.mapCircleToCode(state.details!.location);

    if (opid != null && circle != null) {
      final plans = await service.getRechargePlans(opid, circle);
      setState(() => _plans = plans);
    } else {
      setState(() => _plans = []);
    }
  }

  void _setOperator(String? op) => setState(() => _selectedOperator = op);

  final border12 = OutlineInputBorder(borderRadius: BorderRadius.circular(12));

  String _sanitizeMsisdn(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) return digits.substring(digits.length - 10);
    return digits;
  }

  String _inferStatus(Map<String, dynamic> r) {
    final s = (r['api_status'] ?? r['status'] ?? '').toString().toLowerCase();
    if (s.contains('success')) return 'success';
    if (s.contains('pend')) return 'pending';
    if (s.contains('fail') || s.contains('error')) return 'failed';
    return 'failed';
  }

  String? _inferReason(Map<String, dynamic> r) {
    final keys = ['message', 'opid', 'reason', 'error', 'desc', 'detail'];
    for (final k in keys) {
      final v = r[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString();
      }
    }
    return null;
  }

  Future<void> _showStatusSheet(BuildContext context, String status, {String? reason}) async {
    Color _badgeColor(String s) {
      switch (s) {
        case 'success':
          return Colors.green;
        case 'failed':
          return Colors.red;
        default:
          return Colors.orange; // pending
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.circle, color: _badgeColor(status), size: 12),
                const SizedBox(width: 8),
                Text(
                  status.toUpperCase(),
                  style: TextStyle(color: _badgeColor(status), fontWeight: FontWeight.w800, letterSpacing: .6),
                ),
              ]),

              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(reason, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  String _normalizeOpForApi(String op) {
    final o = op.toLowerCase();
    if (o.contains('vi') || o.contains('vodafone') || o.contains('idea')) return 'V';
    if (o.contains('airtel')) return 'A';
    if (o.contains('jio')) return 'RC';
    if (o.contains('bsnl')) return 'BT';
    return op;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(numberLookupControllerProvider);
    final notifier = ref.read(numberLookupControllerProvider.notifier);

    if (state.details != null) {
      final fromLookup = _normalizeCarrierToOperator(state.details!.carrier);
      if (fromLookup != null && _selectedOperator != fromLookup) {
        _setOperator(fromLookup);
        _fetchPlans();
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Recharge Page')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: numberController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
              ],
              onChanged: (v) => notifier.onNumberChanged(v, numberController),
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                hintText: 'Enter 10-digit number',
                border: border12,
                prefixIcon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text('+91', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                suffixIcon: state.canSearch
                    ? IconButton(
                  tooltip: 'Lookup',
                  icon: const Icon(Icons.search),
                  onPressed: () async {
                    await notifier.lookupNumber(context);
                    _fetchPlans();
                  },
                )
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _selectedOperator,
              items: const [
                DropdownMenuItem(value: 'Airtel', child: Text('Airtel')),
                DropdownMenuItem(value: 'VI', child: Text('Vi')),
                DropdownMenuItem(value: 'BSNL', child: Text('BSNL')),
                DropdownMenuItem(value: 'JIO', child: Text('Jio')),
              ],
              onChanged: (val) {
                _setOperator(val);
                _fetchPlans();
              },
              decoration: InputDecoration(
                labelText: 'Operator',
                border: border12,
                prefixIcon: const Icon(Icons.network_cell),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Enter Amount',
                border: border12,
                prefixIcon: const Icon(Icons.currency_rupee),
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : () async {
                  setState(() => _isLoading = true);

                  ScaffoldMessenger.of(context).hideCurrentSnackBar();

                  final sanitizedNumber = _sanitizeMsisdn(numberController.text);
                  final amount = int.tryParse(amountController.text.trim()) ?? 0;
                  final operatorName = _selectedOperator ?? 'Unknown';
                  final opForApi = _normalizeOpForApi(operatorName);

                  if (sanitizedNumber.length != 10 ||
                      amount <= 0 ||
                      !(opForApi == 'A' || opForApi == 'V' || opForApi == 'BT' || opForApi == 'RC')) {
                    final reason = sanitizedNumber.length != 10
                        ? 'Invalid number'
                        : amount <= 0
                        ? 'Invalid amount'
                        : 'Unknown operator';
                    if (!mounted) { setState(() => _isLoading = false); return; }
                    await _showStatusSheet(context, 'failed', reason: reason);
                    setState(() => _isLoading = false);
                    return;
                  }

                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    if (!mounted) { setState(() => _isLoading = false); return; }
                    await _showStatusSheet(context, 'failed', reason: 'You must be logged in.');
                    setState(() => _isLoading = false);
                    return;
                  }

                  final txService = TransactionService();
                  String? transactionId;

                  try {
                    transactionId = await txService.createPending(
                      number: sanitizedNumber,
                      operatorName: operatorName,
                      amount: amount,
                    );
                  } catch (e) {
                    print('Error creating pending transaction: $e');
                    if (!mounted) { setState(() => _isLoading = false); return; }
                    await _showStatusSheet(context, 'failed', reason: 'Failed to create transaction record.');
                    setState(() => _isLoading = false);
                    return;
                  }


                  try {
                    final circleName = ref.read(numberLookupControllerProvider).details?.location;
                    final circleCode = A1CircleCodes.codeFor(circleName) ?? '8';

                    final response = await A1TopupProxyService.recharge(
                      user.uid,
                      sanitizedNumber,
                      amount,
                      opForApi,
                      circleCode,
                      transactionId!,
                    );

                    final status = _inferStatus(response);
                    final reason = _inferReason(response);

                    await txService.markStatus(
                      id: transactionId!,
                      status: status,
                      failureReason: reason,
                    );

                    if (!mounted) { setState(() => _isLoading = false); return; }
                    await _showStatusSheet(context, status, reason: reason);

                  } catch (e) {
                    print('Error from backend proxy call: $e');
                    await txService.markStatus(
                      id: transactionId!,
                      status: 'failed',
                      failureReason: 'Backend communication error: $e',
                    );

                    if (!mounted) { setState(() => _isLoading = false); return; }
                    await _showStatusSheet(context, 'failed', reason: 'An unexpected error occurred.');
                  } finally {
                    setState(() => _isLoading = false);
                  }
                },
                child: _isLoading
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('Pay Now', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}