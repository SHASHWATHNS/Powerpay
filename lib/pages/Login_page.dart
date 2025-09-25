// import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:google_sign_in/google_sign_in.dart';
//
// class LoginPage extends StatelessWidget {
//   const LoginPage({super.key});
//
//   Future<UserCredential> signInWithGoogle() async {
//     final GoogleSignInAccount? gUser = await GoogleSignIn().signIn();
//     if (gUser == null) throw Exception("Login cancelled");
//
//     final GoogleSignInAuthentication gAuth = await gUser.authentication;
//
//     final credential = GoogleAuthProvider.credential(
//       accessToken: gAuth.accessToken,
//       idToken: gAuth.idToken,
//     );
//
//     return await FirebaseAuth.instance.signInWithCredential(credential);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Login")),
//       body: Center(
//         child: ElevatedButton.icon(
//           icon: const Icon(Icons.login),
//           label: const Text("Sign in with Google"),
//           onPressed: () async {
//             try {
//               await signInWithGoogle();
//             } catch (e) {
//               ScaffoldMessenger.of(context).showSnackBar(
//                 SnackBar(content: Text("Login failed: $e")),
//               );
//             }
//           },
//         ),
//       ),
//     );
//   }
// }
