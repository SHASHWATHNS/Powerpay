// lib/screens/user_management_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:powerpay/providers/distributor_provider.dart';
import 'package:powerpay/providers/role_bootstrapper.dart';

/// -------- Verhoeff algorithm implementation for Aadhaar validation --------
class _Verhoeff {
  static const List<List<int>> _d = [
    [0,1,2,3,4,5,6,7,8,9],
    [1,2,3,4,0,6,7,8,9,5],
    [2,3,4,0,1,7,8,9,5,6],
    [3,4,0,1,2,8,9,5,6,7],
    [4,0,1,2,3,9,5,6,7,8],
    [5,9,8,7,6,0,4,3,2,1],
    [6,5,9,8,7,1,0,4,3,2],
    [7,6,5,9,8,2,1,0,4,3],
    [8,7,6,5,9,3,2,1,0,4],
    [9,8,7,6,5,4,3,2,1,0],
  ];
  static const List<List<int>> _p = [
    [0,1,2,3,4,5,6,7,8,9],
    [1,5,7,6,2,8,3,0,9,4],
    [5,8,0,3,7,9,6,1,4,2],
    [8,9,1,6,0,4,3,5,2,7],
    [9,4,5,3,1,2,6,8,7,0],
    [4,2,8,6,5,7,3,9,0,1],
    [2,7,9,3,8,0,6,4,1,5],
    [7,0,4,6,9,1,3,2,5,8],
  ];
  static const List<int> _inv = [0,4,3,2,1,5,6,7,8,9];

  static bool validate(String num) {
    if (num.isEmpty) return false;
    int c = 0;
    final chars = num.split('').reversed.toList();
    for (var i = 0; i < chars.length; i++) {
      final intDigit = int.tryParse(chars[i]);
      if (intDigit == null) return false;
      c = _d[c][_p[(i % 8)][intDigit]];
    }
    return c == 0;
  }
}

class AppUserDetails {
  final String uid;
  final String name;
  final String email;
  final String phoneNumber;
  final String address;
  final String panNumber;
  final String aadharNumber;
  final String createdBy;
  final double commissionSlab; // percentage, e.g. 1.5

  AppUserDetails.fromFirestore(DocumentSnapshot doc)
      : uid = doc.id,
        name = (doc.data() as Map<String, dynamic>?)?['name'] ?? 'N/A',
        email = (doc.data() as Map<String, dynamic>?)?['email'] ?? 'N/A',
        phoneNumber = (doc.data() as Map<String, dynamic>?)?['phoneNumber'] ?? 'N/A',
        address = (doc.data() as Map<String, dynamic>?)?['address'] ?? 'N/A',
        panNumber = (doc.data() as Map<String, dynamic>?)?['panNumber'] ?? 'N/A',
        aadharNumber = (doc.data() as Map<String, dynamic>?)?['aadharNumber'] ?? 'N/A',
        createdBy = (doc.data() as Map<String, dynamic>?)?['createdBy'] ?? 'unknown',
        commissionSlab = (() {
          final raw = (doc.data() as Map<String, dynamic>?)?['commissionSlab'];
          if (raw == null) return 1.0;
          if (raw is num) return raw.toDouble();
          final parsed = double.tryParse(raw.toString());
          return parsed ?? 1.0;
        })();
}

/* ------------------------- Backend configuration ------------------------- */
const String _apiEndpoint =
    'https://projects.growtechnologies.in/powerpay/retailers_api.php';
const String _createAction = 'addRetailer';

Map<String, String> _optionalHeaders() {
  // return {'Authorization': 'Bearer YOUR_KEY'}; // if required
  return {};
}

/* ------------------------- Page / Widgets ------------------------- */
class UserManagementPage extends ConsumerWidget {
  const UserManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(bootstrapRoleProvider);
    final isDistributor = ref.watch(isDistributorProvider);

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
        body: isDistributor
            ? const TabBarView(
          children: [
            _CreateUserForm(),
            _ViewUsersList(),
          ],
        )
            : const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "You don't have permission to view this page.\nDistributor access is required.",
              textAlign: TextAlign.center,
            ),
          ),
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

  // Commission slab options and selected value
  final List<double> _commissionOptions = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5];
  double _selectedCommission = 1.0; // default 1%

  bool _isLoading = false;

  // temp firebase app and auth used for creating & verifying the user in isolation
  FirebaseApp? _tempApp;
  FirebaseAuth? _tempAuth;
  FirebaseFirestore? _tempFirestore;
  bool _emailVerified = false;
  String? _createdUserUid;

  @override
  void initState() {
    super.initState();
    for (final c in [
      _name,
      _email,
      _password,
      _phone,
      _address,
      _pan,
      _aadhar,
    ]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

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

  String? _validateRequired(String? v) =>
      v == null || v.trim().isEmpty ? 'Required' : null;

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final email = v.trim();
    final emailReg = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailReg.hasMatch(email) ? null : 'Enter a valid email';
  }

  String? _validatePassword(String? v) =>
      (v == null || v.length < 6) ? 'Min 6 characters' : null;

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final p = v.trim();
    final phoneReg = RegExp(r'^[6-9]\d{9}$');
    if (!phoneReg.hasMatch(p)) return 'Enter a valid 10-digit phone (starts with 6-9)';
    return null;
  }

  String? _validatePAN(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final pan = v.trim().toUpperCase();
    final panReg = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
    if (!panReg.hasMatch(pan)) return 'Enter valid PAN (e.g. ABCDE1234F)';
    const allowedFourth = {'P','C','H','A','F','T','B','L','J','G'};
    final fourth = pan[3];
    if (!allowedFourth.contains(fourth)) return 'Invalid PAN: 4th character not a valid holder code';
    return null;
  }

  String? _validateAadhaar(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final clean = v.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^\d{12}$').hasMatch(clean)) return 'Aadhaar must be 12 digits';
    if (!_Verhoeff.validate(clean)) return 'Invalid Aadhaar (checksum failed)';
    return null;
  }

  bool get _isFormValid {
    return _validateRequired(_name.text) == null &&
        _validateEmail(_email.text) == null &&
        _validatePassword(_password.text) == null &&
        _validatePhone(_phone.text) == null &&
        _validateRequired(_address.text) == null &&
        _validatePAN(_pan.text) == null &&
        _validateAadhaar(_aadhar.text) == null;
  }

  Future<Map<String, dynamic>> _postToBackend(Map<String, String> body) async {
    final uri = Uri.parse(_apiEndpoint);
    final headers = _optionalHeaders();
    final resp = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 20));
    return {'status': resp.statusCode, 'body': resp.body};
  }

  Future<void> _createTempAppIfNeeded() async {
    if (_tempApp != null) return;
    // create a named temporary FirebaseApp with same options as default app
    final defaultApp = Firebase.app();
    final tempName = 'temp_user_creation_${DateTime.now().millisecondsSinceEpoch}';
    _tempApp = await Firebase.initializeApp(
      name: tempName,
      options: defaultApp.options,
    );
    _tempAuth = FirebaseAuth.instanceFor(app: _tempApp!);
    _tempFirestore = FirebaseFirestore.instanceFor(app: _tempApp!);
  }

  void _showAuthError(FirebaseAuthException e) {
    String msg = e.message ?? 'Authentication error';
    switch (e.code) {
      case 'too-many-requests':
        msg = 'Too many requests. Try again later, or use a test phone number in Firebase console during development.';
        break;
      case 'operation-not-allowed':
        msg = 'Phone sign-in is disabled for this Firebase project. (Phone OTP disabled)';
        break;
      default:
      // keep original message for other codes
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  Future<void> _sendEmailVerificationUsingTempAuth() async {
    final user = _tempAuth?.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No temporary user to send verification to.'), backgroundColor: Colors.orange));
      return;
    }
    try {
      await user.sendEmailVerification();
      await _tempFirestore?.collection('users').doc(user.uid).set({
        'emailVerificationSent': true,
        'backendPending': true,
      }, SetOptions(merge: true));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email verification sent.'), backgroundColor: Colors.blue));
    } on FirebaseAuthException catch (e) {
      _showAuthError(e);
    } catch (e) {
      debugPrint('sendEmailVerification error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send email verification: $e'), backgroundColor: Colors.red));
    }
  }

  Future<bool> _checkEmailVerifiedUsingTempAuth({int timeoutSeconds = 5}) async {
    final user = _tempAuth?.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
      final reloaded = _tempAuth!.currentUser;
      if (reloaded != null && reloaded.emailVerified) {
        setState(() { _emailVerified = true; });
        return true;
      } else {
        return false;
      }
    } catch (e) {
      debugPrint('email reload error: $e');
      return false;
    }
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isLoading = true; });

    final String? currentDistributorUid = FirebaseAuth.instance.currentUser?.uid;

    if (currentDistributorUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in as a distributor to create users.'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
      return;
    }

    final nameValue = _name.text.trim();
    final emailValue = _email.text.trim();
    final passwordValue = _password.text;
    final phoneValue = _phone.text.trim();
    final addressValue = _address.text.trim();
    final panValue = _pan.text.trim().toUpperCase();
    final aadharValue = _aadhar.text.trim().replaceAll(RegExp(r'\s+'), '');

    try {
      // 1) Create temporary FirebaseApp + Auth + Firestore (isolated)
      await _createTempAppIfNeeded();

      // 2) Create temp user with email+password in tempAuth
      final createdCred = await _tempAuth!.createUserWithEmailAndPassword(
        email: emailValue,
        password: passwordValue,
      );
      final newUser = createdCred.user!;
      _createdUserUid = newUser.uid;

      // 3) Save user doc in temp Firestore (including commission slab)
      await _tempFirestore!.collection('users').doc(newUser.uid).set({
        'name': nameValue,
        'email': emailValue,
        'phoneNumber': phoneValue,
        'address': addressValue,
        'panNumber': panValue,
        'aadharNumber': aadharValue,
        'createdAt': FieldValue.serverTimestamp(),
        'walletBalance': 0,
        'createdBy': currentDistributorUid,
        'backendPending': true,
        'emailVerificationSent': false,
        'commissionSlab': _selectedCommission, // NEW
      });

      // 4) Send email verification
      await _sendEmailVerificationUsingTempAuth();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Temporary user created: ${newUser.uid} - Please verify email to continue.'), backgroundColor: Colors.green));
    } on FirebaseAuthException catch (e) {
      final msg = e.code == 'email-already-in-use'
          ? 'This email is already in use.'
          : 'Error: ${e.message}';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      debugPrint('FirebaseAuthException: ${e.code} ${e.message}');
    } on FirebaseException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Firebase error: ${e.message}'), backgroundColor: Colors.red));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An unknown error occurred: $e'), backgroundColor: Colors.red));
      debugPrint('createUser unknown error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finalizeAndNotifyBackend() async {
    if (!_emailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email must be verified before finalizing.'), backgroundColor: Colors.orange));
      return;
    }
    if (_createdUserUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No temporary user found.'), backgroundColor: Colors.orange));
      return;
    }

    setState(() { _isLoading = true; });
    final currentDistributorUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

    final tempDoc = await _tempFirestore!.collection('users').doc(_createdUserUid!).get();
    final map = tempDoc.data() ?? {};
    final nameValue = map['name'] ?? _name.text.trim();
    final emailValue = map['email'] ?? _email.text.trim();
    final phoneValue = map['phoneNumber'] ?? _phone.text.trim();
    final addressValue = map['address'] ?? _address.text.trim();
    final panValue = map['panNumber'] ?? _pan.text.trim().toUpperCase();
    final aadharValue = map['aadharNumber'] ?? _aadhar.text.trim();
    final dynamic commissionValueRaw = map['commissionSlab'] ?? _selectedCommission;
    final commissionValue = (commissionValueRaw is num) ? commissionValueRaw.toDouble() : double.tryParse(commissionValueRaw.toString()) ?? _selectedCommission;

    final formBody = <String, String>{
      'action': _createAction,
      'uid': _createdUserUid!,
      'name': nameValue,
      'email': emailValue,
      'phoneNumber': phoneValue,
      'role': 'retailer',
      'status': '1',
      'address': addressValue,
      'panNumber': panValue,
      'aadharNumber': aadharValue,
      'walletBalance': '0',
      'createdBy': currentDistributorUid,
      'createdAt': DateTime.now().toIso8601String(),
      'commissionSlab': commissionValue.toString(), // NEW
    };

    const int maxRetries = 3;
    int attempt = 0;
    Map<String, dynamic>? lastResp;
    while (attempt < maxRetries) {
      attempt++;
      try {
        lastResp = await _postToBackend(formBody);
        final status = lastResp['status'] as int;
        final body = (lastResp['body'] ?? '').toString();
        debugPrint('[backend attempt $attempt] status=$status body=${body.length > 300 ? body.substring(0, 300) + '...' : body}');

        if (status == 200) {
          await _tempFirestore!.collection('users').doc(_createdUserUid!).set({
            'backendPending': false,
            'backendResponse': {
              'status': status,
              'body': body,
              'attempts': attempt,
              'at': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true));

          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User created and backend notified.'), backgroundColor: Colors.green));

          _formKey.currentState?.reset();
          _name.clear(); _email.clear(); _password.clear(); _phone.clear(); _address.clear(); _pan.clear(); _aadhar.clear();
          // reset commission to default
          setState(() { _selectedCommission = 1.0; });

          await _safeDeleteTempApp();
          break;
        } else {
          await _tempFirestore!.collection('users').doc(_createdUserUid!).set({
            'backendPending': true,
            'backendResponse': {
              'status': status,
              'body': body,
              'attempts': attempt,
              'at': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('Backend attempt $attempt exception: $e');
        lastResp = {'status': 0, 'body': 'exception: ${e.toString()}'};
        await _tempFirestore!.collection('users').doc(_createdUserUid!).set({
          'backendPending': true,
          'backendResponse': {
            'status': 0,
            'body': 'exception: ${e.toString()}',
            'attempts': attempt,
            'at': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      }

      if (attempt < maxRetries) {
        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }

    if (lastResp == null || (lastResp['status'] as int) != 200) {
      final status = lastResp != null ? lastResp['status'] : 'no-response';
      final body = lastResp != null ? (lastResp['body'] ?? '') : '';
      final short = body.toString().length > 160 ? body.toString().substring(0, 160) + '...' : body;
      final snack = SnackBar(
        content: Text('Backend notify failed (status $status): $short'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Details',
          textColor: Colors.white,
          onPressed: () async {
            final doc = await _tempFirestore!.collection('users').doc(_createdUserUid!).get();
            final resp = (doc.data() ?? {})['backendResponse'] ?? {'info': 'no backendResponse'};
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Backend response'),
                content: SingleChildScrollView(child: SelectableText(json.encode(resp))),
                actions: [ TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')) ],
              ),
            );
          },
        ),
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(snack);
    }

    if (mounted) setState(() { _isLoading = false; });
  }

  Future<void> _safeDeleteTempApp() async {
    try {
      if (_tempApp != null) {
        if (Firebase.apps.isNotEmpty && _tempApp!.name == Firebase.app().name) {
          debugPrint('Skipping delete of default Firebase app (${_tempApp!.name}).');
        } else {
          await _tempApp!.delete();
          debugPrint('Deleted temp FirebaseApp: ${_tempApp!.name}');
        }
      }
    } catch (e) {
      debugPrint('safeDeleteApp error: $e');
    } finally {
      _tempApp = null;
      _tempAuth = null;
      _tempFirestore = null;
      _createdUserUid = null;
      _emailVerified = false;
    }
  }

  InputDecoration _decor(String label, {Widget? suffix}) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.grey[100],
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    suffixIcon: suffix,
  );

  @override
  Widget build(BuildContext context) {
    final phoneLooksValid = _validatePhone(_phone.text) == null;
    final tempUserPresent = _tempAuth != null && _tempAuth!.currentUser != null;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextFormField(controller: _name, decoration: _decor('Full Name'), validator: _validateRequired),
          const SizedBox(height: 8),
          TextFormField(controller: _email, decoration: _decor('Email Address'), validator: _validateEmail, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 8),
          TextFormField(controller: _password, decoration: _decor('Password'), obscureText: true, validator: _validatePassword),
          const SizedBox(height: 8),
          TextFormField(controller: _phone, decoration: _decor('Phone Number'), keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)], validator: _validatePhone),
          const SizedBox(height: 8),
          TextFormField(controller: _address, decoration: _decor('Address'), validator: _validateRequired),
          const SizedBox(height: 8),
          TextFormField(controller: _pan, decoration: _decor('PAN Number'), textCapitalization: TextCapitalization.characters, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), LengthLimitingTextInputFormatter(10), UpperCaseTextFormatter()], validator: _validatePAN),
          const SizedBox(height: 8),
          TextFormField(controller: _aadhar, decoration: _decor('Aadhaar Number'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)], validator: _validateAadhaar),
          const SizedBox(height: 8),

          // Commission slab dropdown
          DropdownButtonFormField<double>(
            value: _selectedCommission,
            decoration: _decor('Commission Slab'),
            items: _commissionOptions.map((v) {
              return DropdownMenuItem<double>(
                value: v,
                child: Text('${v.toString()}%'),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedCommission = val);
            },
          ),

          const SizedBox(height: 16),

          // Create user button (creates temp user, sends email verification)
          ElevatedButton.icon(
            onPressed: (!_isFormValid || _isLoading) ? null : _createUser,
            icon: _isLoading ? const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)) : const Icon(Icons.add),
            label: Text(_isLoading ? 'Creating...' : 'Create User & Send Email'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // Phone status (format-only)
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Phone validity (format only)'),
            subtitle: Text(phoneLooksValid ? 'Looks valid (format)' : 'Invalid phone format'),
            trailing: null,
          ),

          const SizedBox(height: 12),

          // Email verification UI
          ListTile(
            leading: const Icon(Icons.email),
            title: const Text('Email verification'),
            subtitle: Text(_emailVerified ? 'Email verified' : (tempUserPresent ? 'Verification email sent' : 'Not sent')),
            trailing: ElevatedButton(
              onPressed: tempUserPresent ? _sendEmailVerificationUsingTempAuth : null,
              child: const Text('Send/Resend Email'),
            ),
          ),

          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: (tempUserPresent && !_emailVerified) ? () async {
              final ok = await _checkEmailVerifiedUsingTempAuth();
              if (ok) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email verified.'), backgroundColor: Colors.green));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email not verified yet.'), backgroundColor: Colors.orange));
              }
            } : null,
            child: const Text('Check email verified'),
          ),

          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: (!_emailVerified || _isLoading) ? null : _finalizeAndNotifyBackend,
            icon: _isLoading ? const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)) : const Icon(Icons.send),
            label: Text(_isLoading ? 'Finalizing...' : 'Finalize & Notify Backend'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// UpperCaseTextFormatter used for PAN input
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final upper = newValue.text.toUpperCase();
    final baseOffset = newValue.selection.baseOffset;
    final offset = upper.length < baseOffset ? upper.length : baseOffset;
    return TextEditingValue(text: upper, selection: TextSelection.collapsed(offset: offset));
  }
}

// ---------------------------- View Users List ----------------------------
class _ViewUsersList extends StatefulWidget {
  const _ViewUsersList();

  @override
  State<_ViewUsersList> createState() => _ViewUsersListState();
}

class _ViewUsersListState extends State<_ViewUsersList> {
  List<AppUserDetails> docsToUsers(QuerySnapshot snap) => snap.docs.map((d) => AppUserDetails.fromFirestore(d)).toList();

  Future<List<AppUserDetails>> _fetchOnce(String distributorUid) async {
    final Query q = FirebaseFirestore.instance.collection('users').where('createdBy', isEqualTo: distributorUid).orderBy('createdAt', descending: true).limit(200);
    final snap = await q.get();
    return docsToUsers(snap);
  }

  Future<void> _ensureDefaultApp() async {
    if (Firebase.apps.isEmpty) {
      debugPrint('[ViewUsers] No Firebase apps found — calling Firebase.initializeApp()');
      await Firebase.initializeApp();
    } else {
      debugPrint('[ViewUsers] Firebase apps present: ${Firebase.apps.map((a) => a.name).join(', ')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final distributorUid = FirebaseAuth.instance.currentUser?.uid;
    if (distributorUid == null) return const Center(child: Text('Not signed in.'));

    return FutureBuilder<void>(
      future: _ensureDefaultApp(),
      builder: (context, fb) {
        if (fb.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (fb.hasError) return Center(child: Text('Error preparing Firebase: ${fb.error}'));

        final Query usersQuery = FirebaseFirestore.instance.collection('users').where('createdBy', isEqualTo: distributorUid).orderBy('createdAt', descending: true).limit(200);

        final Stream<QuerySnapshot> streamWithTimeout = usersQuery.snapshots().timeout(const Duration(seconds: 10), onTimeout: (sink) {
          debugPrint('Firestore stream timeout after 10s — closing sink.');
          sink.close();
        });

        return StreamBuilder<QuerySnapshot>(
          stream: streamWithTimeout,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return FutureBuilder<List<AppUserDetails>>(
                future: _fetchOnce(distributorUid),
                builder: (context, fb2) {
                  if (fb2.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (fb2.hasError) return Center(child: Text('Error reading users: ${fb2.error}\n\nCheck Firestore rules and network/auth state.'));
                  final users = fb2.data ?? [];
                  if (users.isEmpty) return const Center(child: Text('No users found.'));
                  return _buildListView(users);
                },
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return FutureBuilder<List<AppUserDetails>>(
                future: _fetchOnce(distributorUid),
                builder: (context, fb2) {
                  if (fb2.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (fb2.hasError) return Center(child: Text('Error fetching users: ${fb2.error}'));
                  final users = fb2.data ?? [];
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  tooltip: 'Edit user',
                  onPressed: () => _openEditDialog(user),
                ),
                // Optionally add other actions here
              ],
            ),
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
                        SelectableText('Commission slab: ${user.commissionSlab.toString()}%'),
                        SelectableText('Created by (distributor UID): ${user.createdBy}'),
                        const SizedBox(height: 16),
                        const Text('Password is not displayed for security reasons.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                      ],
                    ),
                  ),
                  actions: [ TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')) ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openEditDialog(AppUserDetails user) async {
    final _editFormKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: user.name);
    final phoneCtrl = TextEditingController(text: user.phoneNumber);
    final addressCtrl = TextEditingController(text: user.address);
    final panCtrl = TextEditingController(text: user.panNumber);
    final aadharCtrl = TextEditingController(text: user.aadharNumber);
    double _selectedCommission = user.commissionSlab;
    bool _isSaving = false;

    String? validateRequired(String? v) => v == null || v.trim().isEmpty ? 'Required' : null;
    String? validatePhone(String? v) {
      if (v == null || v.trim().isEmpty) return 'Required';
      final p = v.trim();
      final phoneReg = RegExp(r'^[6-9]\d{9}$');
      if (!phoneReg.hasMatch(p)) return 'Enter a valid 10-digit phone (starts with 6-9)';
      return null;
    }
    String? validatePAN(String? v) {
      if (v == null || v.trim().isEmpty) return 'Required';
      final pan = v.trim().toUpperCase();
      final panReg = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
      if (!panReg.hasMatch(pan)) return 'Enter valid PAN (e.g. ABCDE1234F)';
      const allowedFourth = {'P','C','H','A','F','T','B','L','J','G'};
      final fourth = pan[3];
      if (!allowedFourth.contains(fourth)) return 'Invalid PAN: 4th character not a valid holder code';
      return null;
    }
    String? validateAadhaar(String? v) {
      if (v == null || v.trim().isEmpty) return 'Required';
      final clean = v.replaceAll(RegExp(r'\s+'), '');
      if (!RegExp(r'^\d{12}$').hasMatch(clean)) return 'Aadhaar must be 12 digits';
      if (!_Verhoeff.validate(clean)) return 'Invalid Aadhaar (checksum failed)';
      return null;
    }

    final commissionOptions = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5];

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setStateInner) {
          return AlertDialog(
            title: const Text('Edit Retailer'),
            content: SingleChildScrollView(
              child: Form(
                key: _editFormKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Email is read-only
                    TextFormField(
                      initialValue: user.email,
                      decoration: const InputDecoration(labelText: 'Email (read-only)'),
                      enabled: false,
                    ),
                    const SizedBox(height: 8),

                    TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name'), validator: validateRequired),
                    const SizedBox(height: 8),

                    TextFormField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number'), keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)], validator: validatePhone),
                    const SizedBox(height: 8),

                    TextFormField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Address'), validator: validateRequired),
                    const SizedBox(height: 8),

                    TextFormField(controller: panCtrl, decoration: const InputDecoration(labelText: 'PAN Number'), textCapitalization: TextCapitalization.characters, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), LengthLimitingTextInputFormatter(10), UpperCaseTextFormatter()], validator: validatePAN),
                    const SizedBox(height: 8),

                    TextFormField(controller: aadharCtrl, decoration: const InputDecoration(labelText: 'Aadhaar Number'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)], validator: validateAadhaar),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<double>(
                      value: _selectedCommission,
                      decoration: const InputDecoration(labelText: 'Commission slab for user (%)'),
                      items: commissionOptions.map((v) => DropdownMenuItem<double>(value: v, child: Text('${v.toString()}%'))).toList(),
                      onChanged: (v) {
                        if (v != null) setStateInner(() => _selectedCommission = v);
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text('Email cannot be modified from here. To change email use backend or admin console.'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isSaving ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _isSaving ? null : () async {
                  if (!_editFormKey.currentState!.validate()) return;
                  setStateInner(() => _isSaving = true);
                  try {
                    // Update Firestore user doc
                    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                      'name': nameCtrl.text.trim(),
                      'phoneNumber': phoneCtrl.text.trim(),
                      'address': addressCtrl.text.trim(),
                      'panNumber': panCtrl.text.trim().toUpperCase(),
                      'aadharNumber': aadharCtrl.text.trim(),
                      'commissionSlab': _selectedCommission,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User updated successfully'), backgroundColor: Colors.green));
                  } catch (e) {
                    debugPrint('Error updating user: $e');
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red));
                    setStateInner(() => _isSaving = false);
                  }
                },
                child: _isSaving ? const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)) : const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }
}

/// ----------------- Commission credit helper -----------------
/// Use this after a confirmed/successful recharge settlement.
/// IMPORTANT: Preferably execute this logic from a trusted server (Cloud Function / backend)
/// to avoid tampering. Client-side shown here for convenience.
Future<double> creditCommissionForRecharge({
  required String retailerUid,
  required double rechargeAmount,
}) async {
  if (rechargeAmount <= 0) return 0.0;
  final userRef = FirebaseFirestore.instance.collection('users').doc(retailerUid);

  return FirebaseFirestore.instance.runTransaction<double>((tx) async {
    final snap = await tx.get(userRef);
    if (!snap.exists) throw Exception('Retailer user not found');

    final data = snap.data() ?? {};
    // read commission slab, default to 1.0 if missing
    final dynamic rawSlab = data['commissionSlab'] ?? 1.0;
    final slab = (rawSlab is num) ? rawSlab.toDouble() : double.tryParse(rawSlab.toString()) ?? 1.0;

    // Calculate commission (rounded to 2 decimal places)
    double commission = (slab / 100.0) * rechargeAmount;
    commission = (commission * 100).roundToDouble() / 100.0;

    // Update walletBalance safely (assuming walletBalance stored as number)
    final currentWallet = (data['walletBalance'] is num) ? (data['walletBalance'] as num).toDouble() : 0.0;
    final newWallet = (currentWallet + commission);

    // For audit, prefer a separate ledger collection in production. Here we append to an array for simplicity.
    tx.update(userRef, {
      'walletBalance': newWallet,
      'walletLedger': FieldValue.arrayUnion([{
        'type': 'commission',
        'amount': commission,
        'from': 'recharge_system',
        'on': FieldValue.serverTimestamp(),
        'rechargeAmount': rechargeAmount,
        'commissionSlab': slab,
      }]),
    });

    return commission;
  });
}
