import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for clipboard
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:powerpay/pages/recharge_page.dart';
import 'package:powerpay/pages/bank_page.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Required to get user info
import 'package:powerpay/screens/user_management_page.dart'; // Required for navigation

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletBalance = ref.watch(walletBalanceProvider);
    // Get the current user from Firebase Auth to check their email
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

            // ✅ START: NEW SECTION FOR ADMIN ACTIONS
            // This entire block will only be visible if the logged-in user's
            // email matches the one specified in the 'if' condition.
            if (user?.email == 'grow@gmail.com')
              Padding(
                padding: const EdgeInsets.only(top: 32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Admin Actions",
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // You can add more admin buttons inside this Card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.manage_accounts, color: brandPurple),
                        title: const Text('User Management'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // Navigate to the user management page when tapped
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
            // ✅ END: NEW SECTION FOR ADMIN ACTIONS

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