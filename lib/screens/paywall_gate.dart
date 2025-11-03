// lib/screens/paywall_gate.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'payment_screen.dart';

class PaywallGate extends StatefulWidget {
  final Widget childWhenPaid; // your app home
  const PaywallGate({Key? key, required this.childWhenPaid}) : super(key: key);

  @override
  State<PaywallGate> createState() => _PaywallGateState();
}

class _PaywallGateState extends State<PaywallGate> {
  bool _loading = true;
  bool _isPaid = false;

  @override
  void initState() {
    super.initState();
    _checkPaid();
  }

  Future<void> _checkPaid() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isPaid = false;
        _loading = false;
      });
      return;
    }

    final doc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    final paid = data != null && (data['paid'] == true);
    setState(() {
      _isPaid = paid;
      _loading = false;
    });

    if (!paid) {
      // show payment prompt dialog
      await _showPayPrompt(user.uid);
      // after returning, re-check
      final doc2 =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final paid2 = (doc2.data() ?? {})['paid'] == true;
      setState(() {
        _isPaid = paid2;
      });
    }
  }

  Future<void> _showPayPrompt(String uid) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Payment required'),
        content: const Text('You must pay ₹699 to access the app. Press Pay to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Logout'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pay ₹699'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => PaymentScreen(
          paymentLink:
          'https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx?id=899',
          amount: 699.0,
        ),
      ));
    } else {
      // optional: sign out if user pressed logout
      if (result == false) {
        await FirebaseAuth.instance.signOut();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isPaid) {
      return widget.childWhenPaid;
    } else {
      return Scaffold(
        appBar: AppBar(title: const Text('Payment required')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => PaymentScreen(
                  paymentLink:
                  'https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx?id=899',
                  amount: 699.0,
                ),
              ));
              // after payment return, re-run check
              await _checkPaid();
            },
            child: const Text('Pay ₹699 to Continue'),
          ),
        ),
      );
    }
  }
}
