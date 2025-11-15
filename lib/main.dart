// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:cloud_functions/cloud_functions.dart';

import 'screens/register_screen.dart';
import 'screens/main_screen.dart';

/// Toggle to true to use local Functions emulator (dev only).
const bool USE_FUNCTIONS_EMULATOR = false;
const String FUNCTIONS_EMULATOR_HOST = '10.0.2.2'; // Android emulator host
const int FUNCTIONS_EMULATOR_PORT = 5001;
const String FUNCTIONS_REGION = 'us-central1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureFirebaseInitialized();

  // FORCE sign-out on cold start so the app always asks for credentials on launch.
  // (This runs before runApp so no UI reads currentUser as logged-in.)
  try {
    final auth = FirebaseAuth.instance;
    final current = auth.currentUser;
    if (current != null) {
      await auth.signOut();
      debugPrint('[main] Signed out existing Firebase user on cold start to require login.');
    } else {
      debugPrint('[main] No existing Firebase user at cold start.');
    }
  } catch (e, st) {
    debugPrint('[main] Error while forcing signOut on cold start: $e\n$st');
    // continue anyway
  }

  if (kDebugMode && USE_FUNCTIONS_EMULATOR) {
    FirebaseFunctions.instanceFor(region: FUNCTIONS_REGION)
        .useFunctionsEmulator(FUNCTIONS_EMULATOR_HOST, FUNCTIONS_EMULATOR_PORT);
    debugPrint('[main] Cloud Functions client pointing to emulator at '
        '${FUNCTIONS_EMULATOR_HOST}:${FUNCTIONS_EMULATOR_PORT} (region $FUNCTIONS_REGION)');
  }

  debugPrint('Firebase initialized — launching app');
  runApp(const ProviderScope(child: MyApp()));
}

Future<void> _ensureFirebaseInitialized() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      debugPrint('[main] Firebase.initializeApp() completed');
    } else {
      debugPrint('[main] Firebase already initialized: ${Firebase.apps.map((a) => a.name).toList()}');
    }
  } catch (e, st) {
    debugPrint('[main] Firebase initialize error: $e\n$st');
    rethrow;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerPay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const Landing(),
    );
  }
}

class Landing extends StatefulWidget {
  const Landing({super.key});
  @override
  State<Landing> createState() => _LandingState();
}

/// _LandingState observes app lifecycle.
/// When the app goes to background and then resumes, it will sign the user out
/// so the user must enter credentials again when returning from recent apps.
class _LandingState extends State<Landing> with WidgetsBindingObserver {
  bool _checking = true;
  Widget _next = const RegisterScreen();

  // used to detect background->foreground transitions
  bool _wentToBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _decide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // mark background entry
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _wentToBackground = true;
    } else if (state == AppLifecycleState.resumed) {
      // on resume, if we were in background, force sign-out and show RegisterScreen
      if (_wentToBackground) {
        _wentToBackground = false;
        _forceSignOutOnResume();
      }
    }
    super.didChangeAppLifecycleState(state);
  }

  Future<void> _forceSignOutOnResume() async {
    try {
      final auth = FirebaseAuth.instance;
      final current = auth.currentUser;
      if (current != null) {
        // silent sign out
        await auth.signOut();
        debugPrint('[Landing] Signed out on resume from background to require login again.');
      }
    } catch (e, st) {
      debugPrint('[Landing] Error while forcing signOut on resume: $e\n$st');
      // ignore errors - do not block UI
    } finally {
      if (mounted) {
        setState(() {
          _next = const RegisterScreen();
          _checking = false;
        });
      }
    }
  }

  Future<void> _decide() async {
    try {
      if (Firebase.apps.isEmpty) {
        debugPrint('[Landing] Firebase.apps is empty — reinitializing...');
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }

      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;

      final user = auth.currentUser;
      debugPrint('[Landing] currentUser uid: ${user?.uid}');
      if (user == null) {
        setState(() {
          _next = const RegisterScreen();
          _checking = false;
        });
        return;
      }

      final docRef = firestore.collection('users').doc(user.uid);
      debugPrint('[Landing] reading users/${user.uid}');
      final doc = await docRef.get();
      final data = doc.data() ?? {};
      final rawPaid = data['subscriptionPaid'];
      bool subscriptionPaid = false;
      if (rawPaid is bool) subscriptionPaid = rawPaid;
      if (rawPaid is String) subscriptionPaid = rawPaid.toLowerCase() == 'true';

      debugPrint('[Landing] user=${user.uid} subscriptionPaid=$subscriptionPaid');

      if (subscriptionPaid) {
        setState(() {
          _next = const MainScreen();
          _checking = false;
        });
      } else {
        debugPrint('[Landing] unpaid user detected -> signing out and showing RegisterScreen');
        await auth.signOut();
        setState(() {
          _next = const RegisterScreen();
          _checking = false;
        });
      }
    } on FirebaseException catch (fe, st) {
      debugPrint('[Landing] FirebaseException: ${fe.code} - ${fe.message}\n$st');
      if (fe.message?.contains('deleted') == true || fe.code == 'app-deleted') {
        try {
          debugPrint('[Landing] Attempting to reinitialize Firebase due to app-deleted...');
          await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
          await _decide();
          return;
        } catch (e, st2) {
          debugPrint('[Landing] Reinitialize failed: $e\n$st2');
        }
      }
      setState(() {
        _next = const RegisterScreen();
        _checking = false;
      });
    } catch (e, st) {
      debugPrint('[Landing] error while deciding route: $e\n$st');
      setState(() {
        _next = const RegisterScreen();
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _next;
  }
}
