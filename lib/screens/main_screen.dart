// lib/pages/main_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:powerpay/pages/home_page.dart';
import 'package:powerpay/screens/register_screen.dart';
import '../pages/transaction_history_page.dart.dart';
import '../providers/navigation_provider.dart';

final lastBackPressProvider = StateProvider<DateTime?>((ref) => null);

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  Future<bool> _onWillPop(BuildContext context, WidgetRef ref) async {
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
    final bool isHome = selectedIndex == 0;

    return WillPopScope(
      onWillPop: () => _onWillPop(context, ref),
      child: Scaffold(
        appBar: isHome
            ? AppBar(
          toolbarHeight: 80,
          backgroundColor: const Color(0xffead8f3),
          elevation: 0,
          centerTitle: true,
          title: Image.asset('assets/images/powerpay_logo.png', height: 65),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () {},
            ),
          ],
        )
            : null,

        // Drawer + Logout
        drawer: Drawer(
          child: Column(
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Color(0xffead8f3)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, size: 40, color: Colors.deepPurple),
                    ),
                    SizedBox(height: 10),
                    Text('Welcome!', style: TextStyle(color: Colors.black, fontSize: 20)),
                  ],
                ),
              ),

              // Menu items
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Home'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(navigationIndexProvider.notifier).state = 0;
                },
              ),
              ListTile(
                leading: const Icon(Icons.call),
                title: const Text('Support'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(navigationIndexProvider.notifier).state = 1;
                },
              ),
              ListTile(
                leading: const Icon(Icons.money),
                title: const Text('Payments'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(navigationIndexProvider.notifier).state = 2;
                },
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(navigationIndexProvider.notifier).state = 3;
                },
              ),
              ListTile(
                leading: const Icon(Icons.money_off_rounded),
                title: const Text('History'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TransactionHistoryPage()),
                  );
                },
              ),

              const Spacer(),
              const Divider(height: 1),

              // ---- Logout button at bottom ----
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(context); // close drawer first
                  await FirebaseAuth.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                        (_) => false,
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        body: Column(
          children: [
            if (isHome) const Expanded(child: HomePage()),
          ],
        ),
      ),
    );
  }
}
