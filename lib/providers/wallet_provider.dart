// lib/providers/wallet_provider.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

final walletBalanceProvider = StreamProvider.autoDispose<double>((ref) {
  final controller = StreamController<double>();
  final firestore = FirebaseFirestore.instance;

  // ONLY these exact keys are considered.
  const List<String> canonicalKeys = [
    'walletBalance',       // preferred: number
    'wallet_balance',      // alternate
    'walletBalancePaise',  // integer paise -> converted to rupees
  ];

  // Strict pattern: only numeric strings allowed (optional sign, digits, optional decimal)
  final RegExp numericString = RegExp(r'^[+-]?\d+(\.\d+)?$');

  double _toDoubleStrict(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final s = value.trim().replaceAll(',', ''); // allow comma thousands but strip them
      if (numericString.hasMatch(s)) {
        return double.tryParse(s) ?? 0.0;
      }
      return 0.0;
    }
    return 0.0;
  }

  double _extractFromWallets(Map<String, dynamic>? data, {String? debugPrefix}) {
    if (data == null) return 0.0;
    try {
      for (final key in canonicalKeys) {
        if (!data.containsKey(key)) continue;
        final raw = data[key];

        if (key == 'walletBalancePaise') {
          final paise = _toDoubleStrict(raw);
          if (paise == 0.0) {
            if (kDebugMode) debugPrint('[walletProvider] wallets:$debugPrefix key="$key" parsed to 0 -> ignoring');
            continue;
          }
          final rupees = paise / 100.0;
          if (kDebugMode) debugPrint('[walletProvider] wallets:$debugPrefix accepted key="$key" -> $rupees (from paise)');
          return rupees;
        }

        final parsed = _toDoubleStrict(raw);
        if (parsed == 0.0) {
          if (kDebugMode) debugPrint('[walletProvider] wallets:$debugPrefix key="$key" parsed to 0 -> ignoring');
          continue;
        }
        if (kDebugMode) debugPrint('[walletProvider] wallets:$debugPrefix accepted key="$key" -> $parsed');
        return parsed;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[walletProvider::_extractFromWallets] $e');
    }
    return 0.0;
  }

  Future<void> start() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      controller.add(0.0);
      await controller.close();
      return;
    }
    final uid = user.uid;

    double walletsVal = 0.0;
    double lastEmitted = -1.0;

    void recomputeAndEmit() {
      final effective = walletsVal;
      if (effective != lastEmitted) {
        lastEmitted = effective;
        if (kDebugMode) debugPrint('[walletProvider] emit balance=$effective (source: wallets/$uid)');
        controller.add(effective);
      }
    }

    // ONLY read from wallets/{uid}
    final walletsSub = firestore.collection('wallets').doc(uid).snapshots().listen(
          (snap) {
        try {
          final data = snap.data() as Map<String, dynamic>?;
          walletsVal = _extractFromWallets(data, debugPrefix: uid);
        } catch (e) {
          if (kDebugMode) debugPrint('[walletProvider] wallets snapshot error: $e');
          walletsVal = 0.0;
        }
        recomputeAndEmit();
      },
      onError: (err) {
        if (kDebugMode) debugPrint('[walletProvider] wallets stream error: $err');
        walletsVal = 0.0;
        recomputeAndEmit();
      },
      cancelOnError: false,
    );

    ref.onDispose(() async {
      await walletsSub.cancel();
      await controller.close();
    });
  }

  start();
  return controller.stream;
});
