// lib/providers/distributor_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Global flag the UI (HomePage) can read to show distributor features
final isDistributorProvider = StateProvider<bool>((ref) => false);

/// Optional: Keep the distributor document data (id, email, name, role, etc.)
final distributorDataProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

/// Check distributors/{uid} and set flags. Returns data or null.
final distributorByUidOnceProvider =
FutureProvider.family<Map<String, dynamic>?, String>((ref, uid) async {
  if (uid.isEmpty) return null;
  final doc = await FirebaseFirestore.instance.collection('distributors').doc(uid).get();
  if (doc.exists) {
    final data = doc.data()!;
    ref.read(isDistributorProvider.notifier).state = true;
    ref.read(distributorDataProvider.notifier).state = {...data, '_docId': doc.id};
    return data;
  } else {
    ref.read(isDistributorProvider.notifier).state = false;
    ref.read(distributorDataProvider.notifier).state = null;
    return null;
  }
});
