// lib/providers/auth_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:powerpay/models/app_user.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  AppUser? _current;
  AppUser? get currentUser => _current;
  bool get isLoggedIn => _current != null;

  late final StreamSubscription<User?> _sub;

  AuthProvider() {
    _sub = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  void _onAuthStateChanged(User? user) {
    if (user == null) {
      _current = null;
    } else {
      _current = AppUser(
        id: user.uid,
        name: user.displayName ?? (user.email ?? 'User'),
        email: user.email,
      );
    }
    notifyListeners();
  }

  // ---------------- Email / Password ----------------
  Future<void> registerWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<void> loginWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
