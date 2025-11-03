// lib/screens/auth_gate.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'main_screen.dart'; // adjust import if MainScreen is in another path
import 'splash_screen.dart'; // adjust import if your splash/login widget differs
import 'payment_webview.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Ensure user doc exists with defaults.
  Future<void> _ensureUserDoc(User user) async {
    final ref = _firestore.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      print('[AuthGate] creating user doc for uid=${user.uid}');
      await ref.set({
        'email': user.email ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'user',
        'subscriptionPaid': false,
      });
    } else {
      final data = snap.data() ?? {};
      final updates = <String, dynamic>{};
      if (!data.containsKey('role')) updates['role'] = 'user';
      if (!data.containsKey('subscriptionPaid')) updates['subscriptionPaid'] = false;
      if (updates.isNotEmpty) {
        print('[AuthGate] adding missing fields: $updates');
        await ref.update(updates);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        final user = authSnap.data;
        if (user == null) {
          return const SplashScreen();
        }

        // Ensure doc exists; snapshots() below will reflect created doc.
        _ensureUserDoc(user);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _firestore.collection('users').doc(user.uid).snapshots(),
          builder: (context, userDocSnap) {
            if (userDocSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            final doc = userDocSnap.data;
            final data = doc?.data() ?? {};
            print('[AuthGate] user doc for uid=${user.uid}: $data');

            bool subscriptionPaid = false;
            final rawPaid = data['subscriptionPaid'];
            if (rawPaid is bool) subscriptionPaid = rawPaid;
            if (rawPaid is String) subscriptionPaid = rawPaid.toLowerCase() == 'true';

            final roleRaw = (data['role'] as String?) ?? 'user';
            final role = roleRaw.toLowerCase();
            final bool isDistributor = role == 'distributor' || role == 'distributer' || role.contains('distrib');

            if (subscriptionPaid) {
              print('[AuthGate] subscriptionPaid==true -> MainScreen');
              return const MainScreen();
            }

            // Not paid yet -> show PaymentPromptFlow which shows the popup then webview
            final paymentUrl = isDistributor
                ? 'https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx?id=896' // ₹1099
                : 'https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx?id=899'; // ₹599

            final price = isDistributor ? '₹1099' : '₹599';
            final roleLabel = isDistributor ? 'Distributor' : 'User';

            return PaymentPromptFlow(
              uid: user.uid,
              paymentUrl: paymentUrl,
              priceLabel: price,
              roleLabel: roleLabel,
            );
          },
        );
      },
    );
  }
}

/// Shows a popup once (on first build) prompting the user to pay.
/// If the user accepts, it shows the PaymentWebView. If they cancel, it signs them out.
class PaymentPromptFlow extends StatefulWidget {
  final String uid;
  final String paymentUrl;
  final String priceLabel;
  final String roleLabel;

  const PaymentPromptFlow({
    required this.uid,
    required this.paymentUrl,
    required this.priceLabel,
    required this.roleLabel,
    super.key,
  });

  @override
  State<PaymentPromptFlow> createState() => _PaymentPromptFlowState();
}

class _PaymentPromptFlowState extends State<PaymentPromptFlow> {
  bool _dialogShown = false;
  bool _showWebview = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Show the dialog once after the first frame.
    if (!_dialogShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPaymentDialogIfNeeded());
    }
  }

  Future<void> _showPaymentDialogIfNeeded() async {
    if (_dialogShown) return;
    _dialogShown = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // force explicit choice
      builder: (context) {
        return AlertDialog(
          title: Text('Pay ${widget.priceLabel} to access the app'),
          content: Text(
            'To continue as ${widget.roleLabel}, please pay ${widget.priceLabel}. Press OK to proceed to the secure payment page.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // Cancel
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true); // OK
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (result == true) {
      setState(() => _showWebview = true);
    } else {
      // User cancelled -> sign them out so they can't access the app
      print('[PaymentPromptFlow] user cancelled payment prompt -> signing out uid=${widget.uid}');
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showWebview) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Complete Payment'),
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            Expanded(child: PaymentWebView(initialUrl: widget.paymentUrl, uid: widget.uid)),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    // Manual confirmation fallback
                    try {
                      await FirebaseFirestore.instance.collection('users').doc(widget.uid).update({
                        'subscriptionPaid': true,
                        'subscriptionPaidAt': FieldValue.serverTimestamp(),
                      });
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to confirm payment: $e')));
                    }
                  },
                  child: const Text('I have completed payment'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // If dialog not shown yet, show a simple scaffold while waiting (dialog opens automatically)
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
