// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // <-- ProviderScope
import 'package:firebase_core/firebase_core.dart';
import 'package:powerpay/screens/splash_screen.dart';
import 'firebase_options.dart';

import 'screens/register_screen.dart'; // or your entry screen

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    const ProviderScope(        // <-- wrap the whole app
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(), // navigates to HomePage -> RechargePage
    );
  }
}
