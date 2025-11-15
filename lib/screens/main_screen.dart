// lib/screens/main_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:powerpay/pages/commission_rates_page.dart';
import 'package:powerpay/pages/home_page.dart';
import 'package:powerpay/pages/support_page.dart';
import 'package:powerpay/pages/bank_page.dart'; // Renamed import to avoid conflict
import 'package:powerpay/pages/commission_page.dart';
import 'package:powerpay/providers/navigation_provider.dart';
import 'package:powerpay/screens/register_screen.dart';

import '../pages/transaction_history_page.dart.dart';
import '../pages/wallet_ledger_page.dart';
import 'user_management_page.dart';

// --- Color Constants from HomePage ---
const Color brandPurple = Color(0xFF5A189A);
const Color brandPink = Color(0xFFDA70D6);
const Color lightBackground = Color(0xFFFFFFFF);
const Color primaryText = Color(0xFF1E1E1E);
// --- End Color Constants ---

final lastBackPressProvider = StateProvider<DateTime?>((ref) => null);

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  Future<bool> _handleBackButton(BuildContext context, WidgetRef ref) async {
    final selectedIndex = ref.read(navigationIndexProvider);
    if (selectedIndex != 0) {
      ref.read(navigationIndexProvider.notifier).state = 0;
      return false;
    }
    final lastBackPress = ref.read(lastBackPressProvider);
    final now = DateTime.now();
    if (lastBackPress == null || now.difference(lastBackPress) > const Duration(seconds: 2)) {
      ref.read(lastBackPressProvider.notifier).state = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2)),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(navigationIndexProvider);
    final isHome = selectedIndex == 0;
    final user = FirebaseAuth.instance.currentUser;

    final List<Widget> pages = [
      const HomePage(),
      const SupportPage(),
      const BankPage(),
      const CommissionRatesPage(),
    ];

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _handleBackButton(context, ref);
        if (shouldPop && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: lightBackground,
        appBar: isHome
            ? AppBar(
          toolbarHeight: 80,
          backgroundColor: lightBackground,
          elevation: 0,
          centerTitle: true,
          title: Image.asset('assets/images/powerpay_logo.png', height: 65),
          actions: [
            //IconButton(
              //icon: const Icon(Icons.notifications, color: primaryText),
              //onPressed: () {},
            //),
            // Admin button

          ],
        )
            : null,
        drawer: Drawer(
          child: Column(
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [brandPurple, brandPink],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person, size: 40, color: brandPurple),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        user?.displayName ?? user?.email ?? 'Welcome!',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home, color: primaryText),
                title: const Text('Home', style: TextStyle(color: primaryText)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(navigationIndexProvider.notifier).state = 0;
                },
              ),
              ListTile(
                leading: const Icon(Icons.support_agent, color: primaryText),
                title: const Text('Support', style: TextStyle(color: primaryText)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(navigationIndexProvider.notifier).state = 1;
                },
              ),
              ListTile(
                leading: const Icon(Icons.money, color: primaryText),
                title: const Text('Payments', style: TextStyle(color: primaryText)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(navigationIndexProvider.notifier).state = 2;
                },
              ),
              ListTile(
                leading: const Icon(Icons.person, color: primaryText),
                title: const Text('Commissions', style: TextStyle(color: primaryText)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(navigationIndexProvider.notifier).state = 3;
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined, color: primaryText),
                title: const Text('Wallet Transactions', style: TextStyle(color: primaryText)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletLedgerPage()));
                },
              ),
              //ListTile(
                //leading: const Icon(Icons.history, color: primaryText),
                //title: const Text('History', style: TextStyle(color: primaryText)),
                //onTap: () {
                  //Navigator.pop(context);
                  //Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionHistoryPage()));
                //},
              //),

              const Spacer(),
              const Divider(height: 1),
              // ✅ MODIFIED LOGOUT TILE
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  // This command explicitly navigates to the LoginScreen and clears
                  // all previous screens from history, so the user can't go back.
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const RegisterScreen()),
                          (Route<dynamic> route) => false,
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        body: pages[selectedIndex],
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, -2))
            ],
          ),
          child: BottomNavigationBar(
            elevation: 0,
            selectedItemColor: brandPurple,
            unselectedItemColor: Colors.grey.shade500,
            backgroundColor: Colors.transparent,
            type: BottomNavigationBarType.fixed,
            currentIndex: selectedIndex,
            onTap: (i) =>
            ref.read(navigationIndexProvider.notifier).state = i,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
              BottomNavigationBarItem(icon: Icon(Icons.support_agent), label: "Support"),
              BottomNavigationBarItem(icon: Icon(Icons.money), label: "Payments"),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: "Commissions"),
            ],
          ),
        ),
      ),
    );
  }
}