// lib/screens/recharge_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powerpay/providers/recharge_controller.dart';
import 'package:powerpay/services/api_mapper_service.dart';
import 'payment_webview_screen.dart'; // existing import

// New imports for wallet interaction and wallet page navigation
import '../services/wallet_service.dart' show walletServiceProvider;
import 'bank_page.dart';
import '../providers/wallet_provider.dart'; // to read walletBalanceProvider

class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  late final TextEditingController _numberController;
  late final TextEditingController _amountController;

  // local processing flag (used instead of controller.setLoading)
  bool _isProcessing = false;

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

  // Helper: robustly parse different wallet provider value shapes into a double
  double _parseWalletValueSafe(Object? walletProvValue) {
    try {
      // Case: Riverpod AsyncValue<T>
      if (walletProvValue is AsyncValue) {
        final val = walletProvValue.value;
        if (val is num) {
          return val.toDouble();
        } else if (val is String) {
          return double.tryParse(val) ?? 0.0;
        } else {
          return 0.0;
        }
      }

      // Case: numeric type directly
      if (walletProvValue is num) {
        return walletProvValue.toDouble();
      }

      // Case: String containing a number
      if (walletProvValue is String) {
        return double.tryParse(walletProvValue) ?? 0.0;
      }

      // Anything else (including null)
      return 0.0;
    } catch (e) {
      debugPrint('[RechargePage] _parseWalletValueSafe error: $e');
      return 0.0;
    }
  }

  // New: Check wallet and perform recharge if enough balance
  Future<void> _payUsingWallet({
    required String number,
    required int amount,
    required RechargeController controller,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to continue')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Read whatever the wallet provider exposes and parse it safely
      Object? walletProvValue;
      try {
        walletProvValue = ref.read(walletBalanceProvider);
      } catch (e) {
        debugPrint('[RechargePage] reading walletBalanceProvider threw: $e');
        walletProvValue = null;
      }

      final double balance = _parseWalletValueSafe(walletProvValue);

      debugPrint('[RechargePage] user=${user.uid} walletBalance=$balance required=$amount');

      if (balance >= amount) {
        // Enough balance → perform recharge. We don't assume performRecharge returns a value.
        await controller.performRecharge(number: number, amount: amount, uid: user.uid);

        // Clear inputs and refresh wallet provider (so UI shows updated balance)
        _amountController.clear();
        _numberController.clear();
        ref.invalidate(walletBalanceProvider);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recharge initiated / completed successfully')),
        );
      } else {
        // Insufficient
        final shortage = (amount - balance).ceil();
        if (!mounted) return;
        // Show dialog that navigates to wallet recharge (BankPage)
        await showDialog<void>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Insufficient Wallet Balance'),
              content: Text(
                'Your wallet has ₹${balance.toStringAsFixed(2)} but the recharge requires ₹$amount.\n'
                    'You need ₹$shortage more. Would you like to add money to your wallet now?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BankPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white, // ✅ makes text white
                  ),
                  child: const Text('Add Money'),
                ),
              ],
            );
          },
        );
      }
    } catch (e, st) {
      debugPrint('[RechargePage] _payUsingWallet error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment error: $e')),
      );
    } finally {
      setState(() => _isProcessing = false);
      // Ensure wallet balance refresh
      ref.invalidate(walletBalanceProvider);
    }
  }

  // --- WIDGET: Input Section (UNCHANGED except wiring pay to wallet) ---
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
              onPressed: (state.isLoading || _isProcessing)
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

                // New behavior: try to pay from wallet, otherwise prompt to recharge wallet
                await _payUsingWallet(number: number, amount: amount, controller: controller);
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: (state.isLoading || _isProcessing)
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

    return Scaffold(
      appBar: AppBar(title: const Text('Mobile Recharge')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInputSection(state, controller),
              if (areInputsValid) ...[
                _buildFilterChips(currentCategories),
                const Divider(height: 1),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                  child: Text(
                    'Please enter a 10-digit number, select an operator, and choose a circle to view plans.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
