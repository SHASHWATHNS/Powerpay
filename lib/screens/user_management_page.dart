// lib/screens/user_management_page.dart
// Ready-to-paste file for the User Management screen.
// IMPORTANT: Ensure Firebase.initializeApp() is called in your app's main() before using this widget.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Data model for a user's full details
class AppUserDetails {
  final String uid;
  final String name;
  final String email;
  final String phoneNumber;
  final String address;
  final String panNumber;
  final String aadharNumber;

  AppUserDetails.fromFirestore(DocumentSnapshot doc)
      : uid = doc.id,
        name = (doc.data() as Map<String, dynamic>?)?['name'] ?? 'N/A',
        email = (doc.data() as Map<String, dynamic>?)?['email'] ?? 'N/A',
        phoneNumber = (doc.data() as Map<String, dynamic>?)?['phoneNumber'] ?? 'N/A',
        address = (doc.data() as Map<String, dynamic>?)?['address'] ?? 'N/A',
        panNumber = (doc.data() as Map<String, dynamic>?)?['panNumber'] ?? 'N/A',
        aadharNumber = (doc.data() as Map<String, dynamic>?)?['aadharNumber'] ?? 'N/A';
}

class UserManagementPage extends StatelessWidget {
  const UserManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('User Management'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Create User', icon: Icon(Icons.person_add)),
              Tab(text: 'View Users', icon: Icon(Icons.people)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CreateUserForm(),
            _ViewUsersList(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------- Create User Form ----------------------------
class _CreateUserForm extends StatefulWidget {
  const _CreateUserForm();

  @override
  State<_CreateUserForm> createState() => _CreateUserFormState();
}

class _CreateUserFormState extends State<_CreateUserForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _pan = TextEditingController();
  final _aadhar = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _address.dispose();
    _pan.dispose();
    _aadhar.dispose();
    super.dispose();
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    FirebaseApp? tempApp;
    try {
      // Create a temporary FirebaseApp that uses the same Firebase options
      // This keeps the currently signed-in admin intact while we create a new user.
      tempApp = await Firebase.initializeApp(
        name: 'temp_creation_app_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);

      // Create the new auth user (on the temp app)
      final userCredential = await tempAuth.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      final newUserUid = userCredential.user?.uid;

      if (newUserUid != null) {
        // IMPORTANT: use Firestore tied to the same temp app so the security rules see the correct auth
        final tempFirestore = FirebaseFirestore.instanceFor(app: tempApp);

        await tempFirestore.collection('users').doc(newUserUid).set({
          'name': _name.text.trim(),
          'email': _email.text.trim(),
          'phoneNumber': _phone.text.trim(),
          'address': _address.text.trim(),
          'panNumber': _pan.text.trim(),
          'aadharNumber': _aadhar.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'walletBalance': 0,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User created successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        _formKey.currentState?.reset();
        _name.clear();
        _email.clear();
        _password.clear();
        _phone.clear();
        _address.clear();
        _pan.clear();
        _aadhar.clear();
      }
    } on FirebaseAuthException catch (e) {
      final msg = e.code == 'email-already-in-use'
          ? 'This email is already in use.'
          : 'Error: ${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } on FirebaseException catch (e) {
      // More specific Firestore / SDK errors surfaced here
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Firebase error: ${e.message}'), backgroundColor: Colors.red),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An unknown error occurred: $e'), backgroundColor: Colors.red),
      );
    } finally {
      // Clean up the temporary app (and its auth instance)
      if (tempApp != null) {
        try {
          await tempApp.delete();
          debugPrint('Temporary FirebaseApp deleted.');
        } catch (e) {
          debugPrint('Error deleting tempApp: $e');
        }
      }

      // Rebind Firestore & Auth to the default app to fix "FirebaseApp was deleted" state
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
          debugPrint('Initialized default Firebase app in finally block.');
        }
        // Force instances tied to the default app so SDK doesn't reference a deleted app.
        FirebaseAuth.instanceFor(app: Firebase.app());
        FirebaseFirestore.instanceFor(app: Firebase.app());
        debugPrint('Rebound Firestore/Auth to default app.');
      } catch (e) {
        debugPrint('Error rebinding Firestore/Auth: $e');
      }

      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full Name'),
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email Address'),
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            keyboardType: TextInputType.emailAddress,
          ),
          TextFormField(
            controller: _password,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            validator: (v) => v == null || v.length < 6 ? 'Min 6 characters' : null,
          ),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone Number'),
            keyboardType: TextInputType.phone,
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address'),
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          TextFormField(
            controller: _pan,
            decoration: const InputDecoration(labelText: 'PAN Number'),
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          TextFormField(
            controller: _aadhar,
            decoration: const InputDecoration(labelText: 'Aadhar Number'),
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _createUser,
            icon: _isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.add),
            label: Text(_isLoading ? 'Creating...' : 'Create User'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------- View Users List ----------------------------
// Reworked to be resilient if the stream stalls; prints extra debug info.
class _ViewUsersList extends StatefulWidget {
  const _ViewUsersList();

  @override
  State<_ViewUsersList> createState() => _ViewUsersListState();
}

class _ViewUsersListState extends State<_ViewUsersList> {
  // Query used for both stream and one-time fetch fallback
  final Query usersQuery = FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).limit(200);

  // Helper to convert docs
  List<AppUserDetails> docsToUsers(QuerySnapshot snap) => snap.docs.map((d) => AppUserDetails.fromFirestore(d)).toList();

  Future<List<AppUserDetails>> _fetchOnce() async {
    try {
      final snap = await usersQuery.get();
      return docsToUsers(snap);
    } catch (e) {
      debugPrint('One-time fetch error: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Add a timeout to the snapshot stream so the UI doesn't stay in `waiting` forever.
    final Stream<QuerySnapshot> streamWithTimeout = usersQuery.snapshots().timeout(
      const Duration(seconds: 10),
      onTimeout: (EventSink<QuerySnapshot> sink) {
        // Instead of trying to add another stream, close the sink so StreamBuilder will get a done event.
        debugPrint('Firestore stream timeout after 10s — closing sink to avoid indefinite waiting.');
        sink.close();
      },
    );

    return StreamBuilder<QuerySnapshot>(
      stream: streamWithTimeout,
      builder: (context, snapshot) {
        debugPrint('StreamBuilder state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}');

        if (snapshot.hasError) {
          final err = snapshot.error;
          debugPrint('Firestore stream error: $err');

          return FutureBuilder<List<AppUserDetails>>(
            future: _fetchOnce(),
            builder: (context, fb) {
              if (fb.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (fb.hasError) {
                return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Error reading users: ${fb.error}\n\nCheck Firestore rules and network/auth state.'),
                    ));
              }
              final users = fb.data ?? [];
              if (users.isEmpty) return const Center(child: Text('No users found.'));
              return _buildListView(users);
            },
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // If the stream closed (onTimeout closed the sink) there will be no data -> fallback to one-time fetch
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return FutureBuilder<List<AppUserDetails>>(
            future: _fetchOnce(),
            builder: (context, fb) {
              if (fb.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (fb.hasError) return Center(child: Text('Error fetching users: ${fb.error}'));
              final users = fb.data ?? [];
              if (users.isEmpty) return const Center(child: Text('No users found.'));
              return _buildListView(users);
            },
          );
        }

        final users = docsToUsers(snapshot.data!);

        if (users.isEmpty) return const Center(child: Text('No users found.'));

        return _buildListView(users);
      },
    );
  }

  Widget _buildListView(List<AppUserDetails> users) {
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            title: Text(user.name),
            subtitle: Text(user.email),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(user.name),
                  content: SingleChildScrollView(
                    child: ListBody(
                      children: <Widget>[
                        SelectableText('Name: ${user.name}'),
                        SelectableText('Email: ${user.email}'),
                        SelectableText('Phone: ${user.phoneNumber}'),
                        SelectableText('Address: ${user.address}'),
                        SelectableText('PAN: ${user.panNumber}'),
                        SelectableText('Aadhar: ${user.aadharNumber}'),
                        const SizedBox(height: 16),
                        const Text(
                          'Password is not displayed for security reasons.',
                          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
