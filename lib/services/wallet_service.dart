// lib/services/wallet_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class WalletService {
  final _db = FirebaseFirestore.instance;

  // This backend URL is no longer needed since the method is removed
  // static const String _backendUrl = 'http://10.0.2.2:8080';

  Stream<double> streamWalletBalance() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream.value(0.0);
    }
    return _db.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return 0.0;
      }
      final data = snapshot.data()!;
      final balance = data['walletBalance'];
      if (balance is num) {
        return balance.toDouble();
      }
      return 0.0;
    });
  }

// The addMoney method has been removed
}