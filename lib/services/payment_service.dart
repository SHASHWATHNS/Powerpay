// lib/services/payment_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentService {
  final FirebaseFirestore _firestore;

  PaymentService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Mark the user as paid and save metadata
  Future<void> markUserAsPaid({
    required String uid,
    required double amount,
    String? paymentId,
    Map<String, dynamic>? rawResponse,
  }) async {
    final userRef = _firestore.collection('users').doc(uid);

    final payload = <String, dynamic>{
      'paid': true,
      'paidAt': FieldValue.serverTimestamp(),
      'paidAmount': amount,
      'paymentId': paymentId ?? '',
      'paymentRaw': rawResponse ?? {},
    };

    await userRef.set(payload, SetOptions(merge: true));
  }

  /// Optional helper
  Future<bool> isUserPaid(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data();
    return data != null && (data['paid'] == true);
  }
}
