import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final walletBalanceProvider = StreamProvider.autoDispose<double>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(0.0);

  return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().map((snap) {
    if (!snap.exists) return 0.0;
    return (snap.data()?['walletBalance'] as num? ?? 0).toDouble();
  });
});