// lib/pages/home_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:powerpay/pages/bank_page.dart';
import 'package:powerpay/pages/recharge_page.dart';
import 'package:powerpay/screens/user_management_page.dart';
import 'package:powerpay/screens/monthly_report_page.dart';
import 'package:powerpay/screens/commission_summary_page.dart';
import 'package:powerpay/screens/pay_for_recharge_page.dart';

import 'package:powerpay/providers/wallet_provider.dart';
import 'package:powerpay/providers/distributor_provider.dart';
import 'package:powerpay/providers/role_bootstrapper.dart'; // <-- if present in your project

/// --- Brand Colors ---
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
    // Ensure roles/claims are bootstrapped (if you implemented this provider)
    // If you don't have role_bootstrapper provider remove this line.
    ref.watch(bootstrapRoleProvider);

    // Watch the wallet balance stream provider
    final walletBalanceAsync = ref.watch(walletBalanceProvider);

    // Firebase user (for name/email)
    final firebaseUser = FirebaseAuth.instance.currentUser;

    // Distributor flags/data from your project providers (if present)
    final isDistributor = ref.watch(isDistributorProvider);
    final distributorData = ref.watch(distributorDataProvider);

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

            // Wallet Card
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
                        // Use .when to handle AsyncValue returned by provider
                        walletBalanceAsync.when(
                          data: (balance) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 600),
                            child: Text(
                              "₹${balance.toStringAsFixed(2)}",
                              key: ValueKey(balance),
                              style: GoogleFonts.poppins(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          loading: () => const SizedBox(
                            height: 28,
                            width: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          ),
                          error: (err, stack) {
                            // Show a readable error and log it
                            if (kDebugMode) {
                              debugPrint('[HomePage] walletBalance error: $err');
                            }
                            return Text(
                              "Error",
                              style: TextStyle(color: Colors.redAccent, fontSize: 18),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        if (firebaseUser?.email != null)
                          Text(
                            "Hello, ${distributorData?['name'] ?? firebaseUser!.email!}",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 14,
                            ),
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

            // Distributor Actions — show only if the flag is true
            const SizedBox(height: 8),
            if (isDistributor)
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
                    if (distributorData != null && distributorData['role'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(
                          "Role: ${distributorData['role']}",
                          style: GoogleFonts.poppins(fontSize: 12, color: textLight),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Horizontal Scrollable Small Circular Buttons
                    SizedBox(
                      height: 100,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          const SizedBox(width: 4),

                          // Pay for User
                          _buildSmallActionButton(
                            title: 'Pay for User',
                            icon: Icons.payment,
                            color: Colors.green,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PayForRechargePage(),
                                ),
                              );
                            },
                          ),

                          const SizedBox(width: 20),

                          // Users List
                          _buildSmallActionButton(
                            title: 'Users List',
                            icon: Icons.people,
                            color: brandBlue,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const UserManagementPage(),
                                ),
                              );
                            },
                          ),

                          const SizedBox(width: 20),

                          // Monthly Report
                          _buildSmallActionButton(
                            title: 'Monthly Report',
                            icon: Icons.bar_chart,
                            color: Colors.orange,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CommissionSummaryPage(),
                                ),
                              );
                            },
                          ),

                          const SizedBox(width: 20),

                          // Commission (Distributor sees it here as before)
                          _buildSmallActionButton(
                            title: 'Commission',
                            icon: Icons.attach_money,
                            color: brandPurple,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CommissionSummaryPage(),
                                ),
                              );
                            },
                          ),

                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
            // If not a distributor, show a compact Account Actions row so regular users can access Commission
              Padding(
                padding: const EdgeInsets.only(top: 32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Account Actions",
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          const SizedBox(width: 4),

                          // Commission (available to regular users here)
                          _buildSmallActionButton(
                            title: 'Commission',
                            icon: Icons.attach_money,
                            color: brandPurple,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CommissionSummaryPage(),
                                ),
                              );
                            },
                          ),

                          const SizedBox(width: 20),

                          // You can add more user-specific action buttons here if needed
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // Services Grid
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
                        child: Icon(
                          item["icon"] as IconData,
                          color: Colors.white,
                          size: 26,
                        ),
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

  // Helper method to build small circular action buttons like mobile button
  Widget _buildSmallActionButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [color, _darkenColor(color, 0.2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(2, 4),
                )
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
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
  }

  // Helper function to darken color for gradient
  Color _darkenColor(Color color, [double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);

    final hsl = HSLColor.fromColor(color);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));

    return hslDark.toColor();
  }
}
