// lib/services/user_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final FirebaseFirestore _firestore;

  UserService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Call right after creating the FirebaseAuth user on the distributor side.
  Future<void> createInitialUserDoc({
    required String uid,
    required String email,
    String? distributorId,
  }) async {
    final userRef = _firestore.collection('users').doc(uid);
    final payload = <String, dynamic>{
      'paid': false,
      'distributorId': distributorId ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'email': email,
    };
    await userRef.set(payload, SetOptions(merge: true));
  }
}
