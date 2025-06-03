import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powerpay/pages/home_page.dart';
import '../providers/navigation_provider.dart';  // Assuming navigationIndexProvider is here

final lastBackPressProvider = StateProvider<DateTime?>((ref) => null);

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  Future<bool> _onWillPop(BuildContext context, WidgetRef ref) async {
    final selectedIndex = ref.read(navigationIndexProvider);
    if (selectedIndex != 0) {
      // If not on Home, go back to Home on back press instead of exiting app
      ref.read(navigationIndexProvider.notifier).state = 0;
      return false; // Don't pop the route
    }

    final lastBackPress = ref.read(lastBackPressProvider);
    final now = DateTime.now();

    if (lastBackPress == null ||
        now.difference(lastBackPress) > const Duration(seconds: 2)) {
      // Update the last back press time
      ref.read(lastBackPressProvider.notifier).state = now;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );

      return false; // Don't exit yet
    }

    return true; // Exit app
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
          title: Image.asset(
            'assets/images/powerpay_logo.png',
            height: 65,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () {},
            ),
          ],
        )
            : null,
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(
                  color: Color(0xffead8f3),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      child:
                      Icon(Icons.person, size: 40, color: Colors.deepPurple),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Welcome!',
                      style: TextStyle(color: Colors.black, fontSize: 20),
                    ),
                  ],
                ),
              ),
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
