import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'distributor_provider.dart';

/// Bootstraps the distributor flag at app start or refresh.
/// Logic:
/// 1) If users/{uid}.role == 'distributor' -> trust it, set flag true.
/// 2) Else read distributors_by_uid/{uid}.role -> if 'distributor' -> set flag true and PROMOTE users/{uid}.role to 'distributor'.
/// 3) Else set flag false. NEVER demote an existing distributor.
final bootstrapRoleProvider = FutureProvider<void>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final uid = user.uid;
  final usersRef = FirebaseFirestore.instance.collection('users').doc(uid);

  // Step 1: trust persisted role if distributor
  final userSnap = await usersRef.get();
  final currentRole = (userSnap.data()?['role'] as String?)?.toLowerCase().trim();

  if (currentRole == 'distributor' || currentRole == 'distributer') {
    ref.read(isDistributorProvider.notifier).state = true;
    return;
  }

  // Step 2: check index doc (always readable per Option A rules)
  final idxSnap = await FirebaseFirestore.instance
      .collection('distributors_by_uid')
      .doc(uid)
      .get();

  final idxRole = (idxSnap.data()?['role'] as String?)?.toLowerCase().trim();
  final isDistributorFromIndex =
      idxSnap.exists && (idxRole == 'distributor' || idxRole == 'distributer');

  if (isDistributorFromIndex) {
    // Promote in memory
    ref.read(isDistributorProvider.notifier).state = true;

    // Promote in users doc only if needed (NEVER demote elsewhere)
    if (!userSnap.exists ||
        ((userSnap.data()?['role'] as String?)?.toLowerCase().trim() !=
            'distributor')) {
      await usersRef.set(
        {
          'role': 'distributor',
        },
        SetOptions(merge: true),
      );
    }
    return;
  }

  // Step 3: not distributor
  ref.read(isDistributorProvider.notifier).state = false;
});
