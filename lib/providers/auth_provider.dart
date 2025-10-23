import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// This class will handle the actual Firebase calls
class AuthRepository {
  AuthRepository(this._auth, this._firestore);
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  // Stream to listen to auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // The login logic, moved from your screen
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Ensure the user document exists in Firestore
      if (userCredential.user != null) {
        await _ensureUserDocumentExists(userCredential.user!);
      }
    } catch (e) {
      // Let the UI handle showing the error
      rethrow;
    }
  }

  // Helper to create the user document if it doesn't exist
  Future<void> _ensureUserDocumentExists(User user) async {
    final userDocRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userDocRef.get();
    if (!userDoc.exists) {
      await userDocRef.set({
        'email': user.email,
        'walletBalance': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

// --- RIVERPOD PROVIDERS ---

// Provider for the FirebaseAuth instance
final firebaseAuthProvider =
Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

// Provider for the FirebaseFirestore instance
final firestoreProvider =
Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

// Provider for our AuthRepository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
      ref.watch(firebaseAuthProvider), ref.watch(firestoreProvider));
});

// StreamProvider to watch the auth state
// This is the main provider our app will listen to
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});