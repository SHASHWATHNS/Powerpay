// // lib/pages/profile_page.dart
// import 'package:flutter/material.dart';
// import 'package:font_awesome_flutter/font_awesome_flutter.dart';
// import 'package:powerpay/pages/commission_page.dart'; // Import commission page
//
// final Color mixedColor = Color(0xFFd98fd9);
//
// class ProfilePage extends StatelessWidget {
//   const ProfilePage({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SafeArea(
//         child: SingleChildScrollView(
//           child: Column(
//             children: [
//               const SizedBox(height: 30),
//               const Center(
//                 child: Column(
//                   children: [
//                     CircleAvatar(
//                       radius: 50,
//                       backgroundImage: AssetImage('assets/images/powerpay_logo.png'),
//                     ),
//                     SizedBox(height: 15),
//                     Text(
//                       'Eon Morgn',
//                       style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
//                     ),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 20),
//
//               // This button now goes to the Commission Page
//               ListTile(
//                 leading: Icon(FontAwesomeIcons.scaleBalanced, color: mixedColor),
//                 trailing: Icon(Icons.chevron_right, color: mixedColor),
//                 title: const Text('  Commissions'),
//                 onTap: () {
//                   Navigator.of(context).push(
//                     MaterialPageRoute(builder: (_) =>  CommissionRatesPage()),
//                   );
//                 },
//               ),
//               const Divider(height: 1, indent: 16, endIndent: 16),
//
//               // Other list tiles
//               ListTile(
//                 leading: Icon(FontAwesomeIcons.rightFromBracket, color: mixedColor),
//                 trailing: Icon(Icons.chevron_right, color: mixedColor),
//                 title: const Text('  Logout'),
//                 onTap: () {},
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }