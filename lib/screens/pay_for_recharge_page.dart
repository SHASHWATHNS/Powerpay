import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/wallet_provider.dart';

// --- Brand Colors ---
const Color brandPurple = Color(0xFF5A189A);
const Color brandBlue = Color(0xFF4F46E0);
const Color brandPink = Color(0xFFE56EF2);
const Color lightBg = Color(0xFFF7F7F9);
const Color textDark = Color(0xFF1E1E1E);
const Color textLight = Color(0xFF666666);

class PayForRechargePage extends ConsumerStatefulWidget {
  const PayForRechargePage({super.key});

  @override
  ConsumerState<PayForRechargePage> createState() => _PayForRechargePageState();
}

class _PayForRechargePageState extends ConsumerState<PayForRechargePage> {
  String? _selectedUserId;
  String? _selectedUserName = 'Select a user';
  final _amountController = TextEditingController();
  bool _isLoading = false;
  double? _distributorBalance;

  @override
  void initState() {
    super.initState();
    _loadDistributorBalance();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _loadDistributorBalance() {
    final balanceAsync = ref.read(walletBalanceProvider);
    balanceAsync.when(
      data: (balance) {
        if (mounted) {
          setState(() {
            _distributorBalance = balance ?? 0.0;
          });
        }
      },
      loading: () {},
      error: (error, stack) {
        if (mounted) {
          setState(() {
            _distributorBalance = 0.0;
          });
        }
      },
    );
  }

  // Check if distributor has sufficient balance
  bool _hasSufficientBalance(double amount) {
    return _distributorBalance != null && _distributorBalance! >= amount;
  }

  // Transfer amount from distributor to user wallet
  Future<void> _transferToUserWallet() async {
    if (_selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a user'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an amount'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (amount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimum amount is ₹10'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check distributor balance
    if (!_hasSufficientBalance(amount)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Insufficient balance! Please recharge your wallet. Available: ₹${_distributorBalance?.toStringAsFixed(2) ?? "0.00"}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      // Start a batch write for atomic operations
      final batch = FirebaseFirestore.instance.batch();

      // 1. Deduct from distributor's wallet
      final distributorWalletRef = FirebaseFirestore.instance
          .collection('wallets')
          .doc(currentUser.uid);

      batch.update(distributorWalletRef, {
        'balance': FieldValue.increment(-amount),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. Add to user's wallet
      final userWalletRef = FirebaseFirestore.instance
          .collection('wallets')
          .doc(_selectedUserId!);

      batch.update(userWalletRef, {
        'balance': FieldValue.increment(amount),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 3. Log the transaction
      final transactionRef = FirebaseFirestore.instance
          .collection('wallet_transactions')
          .doc();

      batch.set(transactionRef, {
        'type': 'transfer',
        'fromUserId': currentUser.uid,
        'fromUserEmail': currentUser.email,
        'toUserId': _selectedUserId,
        'toUserName': _selectedUserName,
        'amount': amount,
        'description': 'Distributor recharge for user',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'completed',
      });

      // 4. Log distributor payment
      final distributorPaymentRef = FirebaseFirestore.instance
          .collection('distributor_payments')
          .doc();

      batch.set(distributorPaymentRef, {
        'userId': _selectedUserId,
        'userName': _selectedUserName,
        'amount': amount,
        'distributorId': currentUser.uid,
        'distributorEmail': currentUser.email,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'completed',
        'type': 'wallet_transfer',
      });

      // Commit the batch
      await batch.commit();

      // Refresh wallet balance
      ref.invalidate(walletBalanceProvider);
      _loadDistributorBalance();

      // Clear form after successful transfer
      _amountController.clear();
      setState(() {
        _selectedUserId = null;
        _selectedUserName = 'Select a user';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully transferred ₹${amount.toStringAsFixed(2)} to $_selectedUserName'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      debugPrint('Transfer error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Pay for User Recharge',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: brandPurple,
        elevation: 0,
      ),
      backgroundColor: lightBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: brandPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payment, color: brandPurple, size: 28),
                ),
                const SizedBox(width: 12),
                Text(
                  'Pay for User',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: textDark,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Text(
              'Transfer from your wallet to user wallet',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: textLight,
              ),
            ),

            // Distributor Balance Card
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: brandPurple.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: brandPurple.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet, color: brandPurple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Wallet Balance',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: textLight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${_distributorBalance?.toStringAsFixed(2) ?? "Loading..."}',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: brandPurple,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_distributorBalance != null && _distributorBalance! < 100)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Text(
                        'Low Balance',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // User Selection
            Text(
              'Select User *',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textDark,
              ),
            ),
            const SizedBox(height: 12),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('email', isNotEqualTo: 'grow@gmail.com')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Error loading users',
                        style: GoogleFonts.poppins(color: Colors.red),
                      ),
                    ),
                  );
                }

                final users = snapshot.data?.docs ?? [];

                if (users.isEmpty) {
                  return Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'No users available',
                        style: GoogleFonts.poppins(color: Colors.grey),
                      ),
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedUserId,
                      isExpanded: true,
                      hint: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Choose a user',
                          style: GoogleFonts.poppins(color: Colors.grey.shade600),
                        ),
                      ),
                      items: users.map((userDoc) {
                        final userData = userDoc.data() as Map<String, dynamic>;
                        final email = userData['email'] ?? 'No Email';
                        final name = userData['name'] ?? email;

                        return DropdownMenuItem<String>(
                          value: userDoc.id,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  email,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedUserId = value;
                          if (value != null) {
                            final selectedUser = users.firstWhere(
                                  (user) => user.id == value,
                            );
                            final userData = selectedUser.data() as Map<String, dynamic>;
                            _selectedUserName = userData['name'] ?? userData['email'];
                          }
                        });
                      },
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Amount Input
            Text(
              'Amount *',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textDark,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter amount in ₹',
                prefixIcon: const Icon(Icons.currency_rupee),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: brandPurple),
                ),
              ),
            ),

            const SizedBox(height: 8),
            Text(
              'Minimum amount: ₹10',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),

            // Balance Check
            if (_amountController.text.isNotEmpty)
              FutureBuilder(
                future: () async {
                  final amount = double.tryParse(_amountController.text) ?? 0;
                  return amount;
                }(),
                builder: (context, snapshot) {
                  final amount = snapshot.data ?? 0;
                  if (amount > 0) {
                    final hasBalance = _hasSufficientBalance(amount);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        hasBalance 
                            ? '✅ Sufficient balance available'
                            : '❌ Insufficient balance. Please recharge your wallet.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: hasBalance ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }
                  return const SizedBox();
                },
            ),

            const SizedBox(height: 40),

            // Transfer Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _transferToUserWallet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandPurple,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Transfer to User Wallet',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}