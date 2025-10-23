import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Data model for a user's full details
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

// Widget for the 'Create User' Tab
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

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      FirebaseApp tempApp = await Firebase.initializeApp(
        name: 'temp_creation_app_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);

      final userCredential = await tempAuth.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      final newUserUid = userCredential.user?.uid;

      if (newUserUid != null) {
        await FirebaseFirestore.instance.collection('users').doc(newUserUid).set({
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
              backgroundColor: Colors.green),
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
      await tempApp.delete();
    } on FirebaseAuthException catch (e) {
      final msg = e.code == 'email-already-in-use'
          ? 'This email is already in use.'
          : 'Error: ${e.message}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unknown error occurred: $e'), backgroundColor: Colors.red));
    } finally {
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
          TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name'), validator: (v) => v!.isEmpty ? 'Required' : null),
          TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Email Address'), validator: (v) => v!.isEmpty ? 'Required' : null),
          TextFormField(controller: _password, decoration: const InputDecoration(labelText: 'Password'), obscureText: true, validator: (v) => v!.length < 6 ? 'Min 6 characters' : null),
          TextFormField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone Number'), keyboardType: TextInputType.phone, validator: (v) => v!.isEmpty ? 'Required' : null),
          TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address'), validator: (v) => v!.isEmpty ? 'Required' : null),
          TextFormField(controller: _pan, decoration: const InputDecoration(labelText: 'PAN Number'), validator: (v) => v!.isEmpty ? 'Required' : null),
          TextFormField(controller: _aadhar, decoration: const InputDecoration(labelText: 'Aadhar Number'), validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _createUser,
            icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add),
            label: Text(_isLoading ? 'Creating...' : 'Create User'),
          ),
        ],
      ),
    );
  }
}

// Widget for the 'View Users' Tab
class _ViewUsersList extends StatelessWidget {
  const _ViewUsersList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No users found.'));
        }

        final users = snapshot.data!.docs.map((doc) => AppUserDetails.fromFirestore(doc)).toList();

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                title: Text(user.name),
                subtitle: Text(user.email),
                // ✅ CHANGED: This onTap handler now shows the full details.
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
      },
    );
  }
}