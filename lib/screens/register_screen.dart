// lib/screens/register_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'main_screen.dart';
import 'payment_flow.dart'; // make sure this file exists (PaymentFlow widget)

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      final user = userCredential.user;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign-in failed.')));
        setState(() => _loading = false);
        return;
      }

      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

      // Ensure user doc exists and has required fields
      final userDoc = await userDocRef.get();
      if (!userDoc.exists) {
        await userDocRef.set({
          'email': user.email ?? '',
          'walletBalance': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'role': 'user', // default role; change via admin if needed
          'subscriptionPaid': false,
        });
      } else {
        // add missing fields defensively
        final data = userDoc.data() ?? {};
        final updates = <String, dynamic>{};
        if (!data.containsKey('role')) updates['role'] = 'user';
        if (!data.containsKey('subscriptionPaid')) updates['subscriptionPaid'] = false;
        if (updates.isNotEmpty) await userDocRef.update(updates);
      }

      // Reload doc to get current values
      final fresh = await userDocRef.get();
      final Map<String, dynamic> data = fresh.data() ?? {};

      // Determine role
      final roleRaw = (data['role'] as String?) ?? 'user';
      final role = roleRaw.toLowerCase();
      final bool isDistributor = role == 'distributor' || role == 'distributer' || role.contains('distrib');

      // Determine subscriptionPaid (defensive for bool/string)
      bool subscriptionPaid = false;
      final rawPaid = data['subscriptionPaid'];
      if (rawPaid is bool) subscriptionPaid = rawPaid;
      if (rawPaid is String) subscriptionPaid = rawPaid.toLowerCase() == 'true';

      if (subscriptionPaid) {
        // Already paid -> go to main app
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
              (_) => false,
        );
        return;
      }

      // Not paid -> show payment prompt (non-dismissible)
      final priceLabel = isDistributor ? '₹1099' : '₹599';
      final roleLabel = isDistributor ? 'Distributor' : 'User';
      final paymentUrl = isDistributor
          ? 'https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx?id=896'
          : 'https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx?id=899';

      final shouldPay = await showDialog<bool>(
        context: context,
        barrierDismissible: false, // force explicit choice
        builder: (context) {
          return AlertDialog(
            title: Text('Pay $priceLabel to access the app'),
            content: Text('To continue as $roleLabel, please pay $priceLabel. Press OK to proceed to the secure payment page.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      if (shouldPay != true) {
        // User cancelled -> sign out and remain on login
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment required to access the app. You have been signed out.')));
        setState(() => _loading = false);
        return;
      }

      // User agreed to pay -> push PaymentFlow which will handle auto-confirm/manual confirm and then navigate to MainScreen.
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PaymentFlow(uid: user.uid, paymentUrl: paymentUrl, isDistributor: isDistributor),
      ));

      // PaymentFlow should navigate into MainScreen on success. If it returns, ensure we are on MainScreen or show message.
      // (No further action here.)
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'invalid-email' => 'Invalid email address.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' => 'No user found for that email.',
        'wrong-password' => 'Incorrect password.',
        _ => e.message ?? 'Authentication error.'
      };
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign-in failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _decor(String label, {Widget? suffix}) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.grey[100],
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    suffixIcon: suffix,
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const SizedBox(height: 24),
                    Center(
                      child: Image.asset('assets/images/powerpay_logo.png', height: 120),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Login to Power Pay',
                      textAlign: TextAlign.center,
                      style: t.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _decor('Email'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter email';
                        final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim());
                        if (!ok) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _login(),
                      decoration: _decor(
                        'Password',
                        suffix: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter password';
                        if (v.length < 6) return 'At least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Use the email/password you created in Firebase Authentication.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
