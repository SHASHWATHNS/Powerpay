import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powerpay/providers/recharge_controller.dart';
import 'package:powerpay/services/api_mapper_service.dart';

class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  late final TextEditingController _numberController;
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _numberController = TextEditingController();
    _amountController = TextEditingController();
  }

  @override
  void dispose() {
    _numberController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  // Helper widget for the top, non-scrolling part
  Widget _buildInputSection(RechargeState state, RechargeController controller) {
    final border12 = OutlineInputBorder(borderRadius: BorderRadius.circular(12));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Takes up only necessary space
        children: [
          TextField(
            controller: _numberController,
            decoration: InputDecoration(
              labelText: 'Mobile Number',
              border: border12,
              prefixIcon: const Icon(Icons.phone_iphone),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: state.selectedOperator,
            items: ApiMapper.supportedOperators
                .map((op) => DropdownMenuItem(value: op, child: Text(op)))
                .toList(),
            onChanged: (val) => controller.selectOperator(val),
            decoration: InputDecoration(
              labelText: 'Select Operator',
              border: border12,
              prefixIcon: const Icon(Icons.network_cell),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: state.selectedCircle,
            items: ApiMapper.supportedCircles
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (val) => controller.selectCircle(val),
            decoration: InputDecoration(
              labelText: 'Select Circle (State)',
              border: border12,
              prefixIcon: const Icon(Icons.public),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            decoration: InputDecoration(
              labelText: 'Amount',
              border: border12,
              prefixIcon: const Icon(Icons.currency_rupee),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: state.isLoading
                ? null
                : () {
              final user = FirebaseAuth.instance.currentUser;
              final amount = int.tryParse(_amountController.text) ?? 0;
              if (user != null && amount > 0) {
                controller.performRecharge(
                  number: _numberController.text,
                  amount: amount,
                  uid: user.uid,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 50), // Ensure button has good height
            ),
            child: state.isLoading
                ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
                : const Text('Pay Now', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rechargeControllerProvider);
    final controller = ref.read(rechargeControllerProvider.notifier);

    ref.listen<RechargeState>(rechargeControllerProvider, (previous, next) {
      if (next.statusMessage != null && next.statusMessage != previous?.statusMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.statusMessage!)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Mobile Recharge')),
      body: SafeArea(
        // Use a Column to separate the fixed and scrollable parts
        child: Column(
          children: [
            // --- 1. The Fixed Top Section ---
            _buildInputSection(state, controller),

            // --- 2. The Scrollable Bottom Section ---
            Expanded(
              child: state.isLoading && state.plans.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : state.plans.isNotEmpty
                  ? ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: state.plans.length,
                itemBuilder: (context, index) {
                  final plan = state.plans[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text('₹ ${plan['rs']}'),
                      subtitle: Text(plan['desc'] ?? 'No description available'),
                      onTap: () {
                        _amountController.text = (plan['rs'] ?? '').toString();
                      },
                    ),
                  );
                },
              )
                  : const Center(
                child: Text('Select operator and circle to see plans.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}