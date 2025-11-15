// lib/services/transaction_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction_model.dart';

/// Expose TransactionService via Riverpod so `ref.watch(transactionServiceProvider)` works.
final transactionServiceProvider = Provider<TransactionService>((ref) => TransactionService());

class TransactionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream merged transactions for the currently signed-in user.
  /// Emits an empty list if user not signed in.
  Stream<List<TransactionRecord>> streamMyTransactions() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    final uid = user.uid;
    final controller = StreamController<List<TransactionRecord>>();

    // caches
    var recharges = <TransactionRecord>[];
    var walletTxs = <TransactionRecord>[];
    var distPays = <TransactionRecord>[];

    void emitMerged() {
      final merged = <TransactionRecord>[];
      merged.addAll(recharges);
      merged.addAll(walletTxs);
      merged.addAll(distPays);
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!controller.isClosed) controller.add(merged);
    }

    // 1) recharges where uid == current uid
    final rechargeSub = _firestore
        .collection('recharges')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      recharges = snap.docs.map((d) => TransactionRecord.fromMap(d.id, d.data())).toList();
      emitMerged();
    }, onError: (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    });

    // 2) wallet_transactions: prefer participants array, fallback to fromUserId/toUserId
    final walletPrimary = _firestore
        .collection('wallet_transactions')
        .where('participants', arrayContains: uid)
        .orderBy('timestamp', descending: true)
        .limit(200);

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? walletPrimarySub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? walletFallbackFrom;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? walletFallbackTo;

    walletPrimarySub = walletPrimary.snapshots().listen((snap) {
      walletTxs = snap.docs.map((d) => TransactionRecord.fromMap(d.id, d.data())).toList();
      emitMerged();
    }, onError: (err, st) async {
      // fallback queries
      try {
        walletFallbackFrom = _firestore
            .collection('wallet_transactions')
            .where('fromUserId', isEqualTo: uid)
            .orderBy('timestamp', descending: true)
            .limit(200)
            .snapshots()
            .listen((snapA) {
          final listA = snapA.docs.map((d) => TransactionRecord.fromMap(d.id, d.data())).toList();
          // toUserId
          walletFallbackTo = _firestore
              .collection('wallet_transactions')
              .where('toUserId', isEqualTo: uid)
              .orderBy('timestamp', descending: true)
              .limit(200)
              .snapshots()
              .listen((snapB) {
            final listB = snapB.docs.map((d) => TransactionRecord.fromMap(d.id, d.data())).toList();
            walletTxs = [...listA, ...listB];
            emitMerged();
          }, onError: (e, st) {
            if (!controller.isClosed) controller.addError(e, st);
          });
        }, onError: (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        });
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    });

    // 3) distributor_payments: prefer participants then fallback
    final distPrimary = _firestore
        .collection('distributor_payments')
        .where('participants', arrayContains: uid)
        .orderBy('timestamp', descending: true)
        .limit(200);

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? distPrimarySub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? distFallbackA;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? distFallbackB;

    distPrimarySub = distPrimary.snapshots().listen((snap) {
      distPays = snap.docs.map((d) => TransactionRecord.fromMap(d.id, d.data())).toList();
      emitMerged();
    }, onError: (err, st) async {
      try {
        distFallbackA = _firestore
            .collection('distributor_payments')
            .where('distributorId', isEqualTo: uid)
            .orderBy('timestamp', descending: true)
            .limit(200)
            .snapshots()
            .listen((aSnap) {
          final aList = aSnap.docs.map((d) => TransactionRecord.fromMap(d.id, d.data())).toList();
          distFallbackB = _firestore
              .collection('distributor_payments')
              .where('userId', isEqualTo: uid)
              .orderBy('timestamp', descending: true)
              .limit(200)
              .snapshots()
              .listen((bSnap) {
            final bList = bSnap.docs.map((d) => TransactionRecord.fromMap(d.id, d.data())).toList();
            distPays = [...aList, ...bList];
            emitMerged();
          }, onError: (e, st) {
            if (!controller.isClosed) controller.addError(e, st);
          });
        }, onError: (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        });
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    });

    // cleanup
    controller.onCancel = () async {
      await rechargeSub.cancel();
      await walletPrimarySub?.cancel();
      await walletFallbackFrom?.cancel();
      await walletFallbackTo?.cancel();
      await distPrimarySub?.cancel();
      await distFallbackA?.cancel();
      await distFallbackB?.cancel();
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }
}
