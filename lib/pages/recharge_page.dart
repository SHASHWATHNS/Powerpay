// lib/screens/recharge_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powerpay/providers/recharge_controller.dart';
import 'package:powerpay/services/api_mapper_service.dart';
import 'payment_webview_screen.dart'; // <<-- existing import

class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  late final TextEditingController _numberController;
  late final TextEditingController _amountController;

  // --- Category definitions (UNCHANGED) ---
  static const Map<String, List<String>> _operatorCategories = {
    'Jio': ['All', 'Unlimited', 'Talktime', 'JioPhone', 'JioBharat Phone', 'Data'],
    'Airtel': ['All', 'Unlimited', 'Talktime', 'Data', 'International'],
    'Vodafone Idea': ['All', 'Unlimited', 'Talktime', 'Data', 'Hero Unlimited'],
    'BSNL': ['All', 'Unlimited', 'Talktime', 'Data', 'Top'],
  };
  static const List<String> _defaultCategories = ['All', 'Unlimited', 'Talktime', 'Data'];
  late String _selectedCategory;
  static const String _fallbackPaymentShortlink = 'https://rzp.io/rzp/xd8KZaS';

  @override
  void initState() {
    super.initState();
    _numberController = TextEditingController();
    _amountController = TextEditingController();
    _selectedCategory = _defaultCategories.first;
    _numberController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    setState(() {
      // This forces a rebuild to check the `areInputsValid` boolean
    });
  }

  @override
  void dispose() {
    _numberController.removeListener(_onInputChanged); // <-- Clean up listener
    _numberController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  // --- WIDGET: Input Section (UNCHANGED) ---
  Widget _buildInputSection(RechargeState state, RechargeController controller) {
    final border12 = OutlineInputBorder(borderRadius: BorderRadius.circular(12));

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8), // Margin around the card
      elevation: 2.0, // Subtle shadow
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias, // Ensures content respects rounded corners
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Takes up only necessary space
          crossAxisAlignment: CrossAxisAlignment.start, // Align title
          children: [
            // --- Title for the card ---
            Text(
              'Enter Recharge Details',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor, // Use primary color
                  ),
            ),
            const SizedBox(height: 16), // Space after title

            // --- Existing Fields (Styling UNCHANGED) ---
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
              onChanged: (val) {
                controller.selectOperator(val);
                setState(() {});
              },
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
              onChanged: (val) {
                controller.selectCircle(val);
                setState(() {});
              },
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
            const SizedBox(height: 16), // Increased space
            ElevatedButton(
              onPressed: state.isLoading
                  ? null
                  : () async {
                      // --- Validation Logic (UNCHANGED) ---
                      final user = FirebaseAuth.instance.currentUser;
                      final amount = int.tryParse(_amountController.text) ?? 0;
                      final number = _numberController.text.trim();

                      if (user == null) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please login to continue')),
                        );
                        return;
                      }
                      if (amount <= 0) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid amount')),
                        );
                        return;
                      }
                      if (number.length != 10) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid 10-digit mobile number')),
                        );
                        return;
                      }

                      // --- PAYMENT NAVIGATION TEMPORARILY DISABLED ---
                      // final paymentUrl = '$_fallbackPaymentShortlink?amount=$amount&number=$number';
                      // final confirmed = await Navigator.of(context).push<bool>(
                      //   MaterialPageRoute(
                      //     builder: (_) => PaymentWebViewScreen(initialUrl: paymentUrl),
                      //   ),
                      // );
                      // if (confirmed == true) {
                      //   controller.performRecharge(number: number, amount: amount, uid: user.uid);
                      //   _amountController.clear();
                      //   _numberController.clear();
                      // } else {
                      //   if (!mounted) return;
                      //   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment not completed')));
                      // }
                      // --- END OF DISABLED SECTION ---

                      // --- NEW PLACEHOLDER ---
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payment logic will be added later.')),
                      );
                      // --- END NEW PLACEHOLDER ---
                    },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: state.isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Pay Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET: For the filter tabs (UNCHANGED) ---
  Widget _buildFilterChips(List<String> categories) {
    return SizedBox(
      height: 50, // Fixed height for the chip list
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == _selectedCategory;

          return ChoiceChip(
            label: Text(category),
            selected: isSelected,
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _selectedCategory = category;
                });
              }
            },
            selectedColor: Theme.of(context).primaryColor,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade400,
              ),
            ),
            elevation: isSelected ? 2 : 0,
          );
        },
      ),
    );
  }

  // --- WIDGET: Helper for building tags on cards (UNCHANGED) ---
  Widget _buildPlanTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rechargeControllerProvider);
    final controller = ref.read(rechargeControllerProvider.notifier);

    // --- Listeners (UNCHANGED) ---
    ref.listen<String?>(
      rechargeControllerProvider.select((s) => s.selectedOperator),
      (previous, next) {
        if (previous != next && next != null) {
          setState(() {
            _selectedCategory = "All"; // Always reset to All
          });
        }
      },
    );
    ref.listen<RechargeState>(rechargeControllerProvider, (previous, next) {
      if (next.statusMessage != null && next.statusMessage != previous?.statusMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.statusMessage!)),
        );
      }
    });
    // --- End Listeners ---

    // --- Derivations (UNCHANGED) ---
    final List<String> currentCategories =
        _operatorCategories[state.selectedOperator] ?? _defaultCategories;
    final bool areInputsValid = _numberController.text.length == 10 &&
        state.selectedOperator != null &&
        state.selectedCircle != null;
    final displayedPlans = state.plans.where((plan) {
      if (_selectedCategory == 'All') {
        return true; // Show all plans
      }
      final desc = (plan['desc'] as String? ?? '').toLowerCase();
      final category = _selectedCategory.toLowerCase();
      if (category == 'jiophone') return desc.contains('jio phone');
      if (category == 'jiobharat phone') return desc.contains('jiobharat') || desc.contains('jio bharat');
      if (category == 'hero unlimited') return desc.contains('hero');
      if (category == 'top') {
        return desc.contains('topup') || desc.contains('top up');
      }
      return desc.contains(category);
    }).toList();
    // --- End Derivations ---

    return Scaffold(
      appBar: AppBar(title: const Text('Mobile Recharge')),
      body: SafeArea(
        // --- Make the whole page scrollable (UNCHANGED) ---
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- 1. The Fixed Top Section ---
              _buildInputSection(state, controller),

              // --- 2. & 3. CONDITIONAL FILTERS AND PLANS (UNCHANGED) ---
              if (areInputsValid) ...[
                // --- 2. The Filter Chips ---
                _buildFilterChips(currentCategories),
                const Divider(height: 1),

                // --- 3. The Scrollable Bottom Section ---
                state.isLoading && state.plans.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : displayedPlans.isNotEmpty
                        ? ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: displayedPlans.length,
                            itemBuilder: (context, index) {
                              // ... (Plan card UI is UNCHANGED) ...
                              final plan = displayedPlans[index]; 
                              final String price = (plan['rs'] ?? '0').toString();
                              final String description = (plan['desc'] ?? 'No description available').toString();
                              final String validity = (plan['validity'] ?? '').toString();
                              final List<String> tags = [];
                              final descLower = description.toLowerCase();
                              if (descLower.contains('unlimited')) tags.add('UNLIMITED');
                              if (descLower.contains('data')) tags.add('DATA');
                              if (descLower.contains('sms')) tags.add('SMS');
                              
                              return Card(
                                elevation: 1.5,
                                shadowColor: Colors.grey.shade50,
                                margin: const EdgeInsets.only(bottom: 10),
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: InkWell(
                                  onTap: () {
                                    _amountController.text = price;
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 80,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              CircleAvatar(
                                                radius: 28,
                                                backgroundColor: Colors.grey.shade100,
                                                child: Text(
                                                  '₹ $price',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ),
                                              if (validity.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  validity,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                              ]
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 12.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                if (tags.isNotEmpty)
                                                  Wrap(
                                                    spacing: 6.0,
                                                    runSpacing: 4.0,
                                                    children: tags
                                                        .map((tag) => _buildPlanTag(tag))
                                                        .toList(),
                                                  ),
                                                if (tags.isNotEmpty) const SizedBox(height: 8),
                                                Text(
                                                  description,
                                                  style: const TextStyle(fontSize: 14.5, height: 1.4),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 48.0),
                              child: Text('No plans found for "$_selectedCategory"'),
                            ),
                          ),
              ] else ...[
                // --- Placeholder when inputs are not valid ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                  child: Text(
                    'Please enter a 10-digit number, select an operator, and choose a circle to view plans.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                  ),
                ),
              ],
              // --- END OF CONDITIONAL SECTION ---
            ],
          ),
        ),
      ),
    );
  }
}