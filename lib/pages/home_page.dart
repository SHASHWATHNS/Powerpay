import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:powerpay/pages/payment_webview_screen.dart';
import 'package:powerpay/pages/recharge_page.dart';
import 'package:powerpay/pages/bank_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:powerpay/screens/user_management_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../providers/wallet_provider.dart';

// --- Brand Colors ---
const Color brandPurple = Color(0xFF5A189A);
const Color brandBlue = Color(0xFF4F46E0);
const Color brandPink = Color(0xFFE56EF2);
const Color lightBg = Color(0xFFF7F7F9);
const Color textDark = Color(0xFF1E1E1E);
const Color textLight = Color(0xFF666666);

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  // Function to show user selection and amount input for distributor
  void _showDistributorPaymentDialog(BuildContext context) {
    String? selectedUserId;
    String? selectedUserName = 'Select a user';
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 8,
            child: Container(
              padding: const EdgeInsets.all(24),
              width: MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      const Icon(Icons.payment, color: brandPurple, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Pay for User',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: textDark,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // User Selection
                  Text(
                    'Select User',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 8),

                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('email', isNotEqualTo: 'grow@gmail.com')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.red),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Error loading users',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        );
                      }

                      final users = snapshot.data?.docs ?? [];

                      if (users.isEmpty) {
                        return Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'No users available',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      }

                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedUserId,
                            isExpanded: true,
                            hint: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Choose a user',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                            items: users.map((userDoc) {
                              final userData = userDoc.data() as Map<String, dynamic>;
                              final email = userData['email'] ?? 'No Email';
                              final name = userData['name'] ?? email;

                              return DropdownMenuItem<String>(
                                value: userDoc.id,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        email,
                                        style: TextStyle(
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
                                selectedUserId = value;
                                if (value != null) {
                                  final selectedUser = users.firstWhere(
                                        (user) => user.id == value,
                                  );
                                  final userData = selectedUser.data() as Map<String, dynamic>;
                                  selectedUserName = userData['name'] ?? userData['email'];
                                }
                              });
                            },
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Amount Input
                  Text(
                    'Amount',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Enter amount in ₹',
                      prefixIcon: const Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: brandPurple),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            side: BorderSide(color: Colors.grey.shade400),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            if (selectedUserId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please select a user'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }

                            final amountText = amountController.text.trim();
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

                            Navigator.pop(context);

                            // Navigate to payment page
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PaymentWebViewScreen(
                                  initialUrl: 'https://rzp.io/rzp/xd8KZaS?amount=${amount.toInt()}',
                                ),
                              ),
                            );

                            // Log the payment
                            _logDistributorPayment(selectedUserId!, selectedUserName!, amount);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandPurple,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Proceed to Pay',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Log distributor payments in Firestore
  // Updated distributor payment logging with error handling
void _logDistributorPayment(String userId, String userName, double amount) {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    debugPrint('User not logged in, skipping payment log');
    return;
  }

  FirebaseFirestore.instance
      .collection('distributor_payments')
      .add({
        'userId': userId,
        'userName': userName,
        'amount': amount,
        'distributorId': currentUser.uid,
        'distributorEmail': currentUser.email,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'initiated',
      })
      .then((value) {
        debugPrint('Distributor payment logged: $userName - ₹$amount');
      })
      .catchError((error) {
        debugPrint('Error logging distributor payment: $error');
        // Don't show error to user, just log it
      });
}

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletBalance = ref.watch(walletBalanceProvider);
    final user = FirebaseAuth.instance.currentUser;

    final services = [
      {"icon": Icons.phone_android, "label": "Mobile"},
    ];

    return Scaffold(
      backgroundColor: lightBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),

            // 🔹 Wallet Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [brandPink, brandPurple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: brandPurple.withOpacity(0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Balance Section
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Active Total Balance",
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        walletBalance.when(
                          data: (balance) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 600),
                            child: Text(
                              "₹${balance?.toStringAsFixed(2) ?? '0.00'}",
                              key: ValueKey(balance),
                              style: GoogleFonts.poppins(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          loading: () => const CircularProgressIndicator(
                              strokeWidth: 3, color: Colors.white),
                          error: (err, stack) => const Text("Error",
                              style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  ),

                  // Add Funds button
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BankPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      elevation: 6,
                    ),
                    child: const Icon(
                      FontAwesomeIcons.plus,
                      color: brandPurple,
                      size: 18,
                    ),
                  )
                ],
              ),
            ),

            // ✅ DISTRIBUTOR ACTIONS SECTION
            if (user?.email == 'grow@gmail.com')
              Padding(
                padding: const EdgeInsets.only(top: 32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Distributor Actions",
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pay for User Card
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.payment, color: Colors.green),
                        ),
                        title: Text(
                          'Pay for User',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text('Select user and enter amount'),
                        trailing: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: brandPurple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.arrow_forward, size: 16, color: brandPurple),
                        ),
                        onTap: () {
                          _showDistributorPaymentDialog(context);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // User Management Card
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: brandPurple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.manage_accounts, color: brandPurple),
                        ),
                        title: Text(
                          'User Management',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: brandPurple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.arrow_forward, size: 16, color: brandPurple),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const UserManagementPage()),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // 🔹 Services Grid
            Text(
              "Quick Services",
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: textDark,
              ),
            ),
            const SizedBox(height: 20),

            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: services.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 20,
                crossAxisSpacing: 15,
                mainAxisExtent: 110,
              ),
              itemBuilder: (context, index) {
                final item = services[index];
                return GestureDetector(
                  onTap: () {
                    if (item["label"] == "Mobile") {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RechargePage()),
                      );
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [brandBlue, brandPink],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: brandPurple.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(2, 4),
                            )
                          ],
                        ),
                        child: Icon(item["icon"] as IconData,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item["label"] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: textLight,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}