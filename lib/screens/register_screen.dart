// lib/screens/register_screen.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'main_screen.dart';
import 'payment_flow.dart';
import 'package:powerpay/providers/distributor_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  // Used to detect background -> foreground transitions
  bool _wentToBackground = false;

  // YOUR BACKEND ENDPOINT (must accept POST and verify payment server-side)
  static const String _backendPaymentApi =
      'https://projects.growtechnologies.in/powerpay/payment_api.php';

  @override
  void initState() {
    super.initState();
    // Observe lifecycle to force sign-in on resume
    WidgetsBinding.instance.addObserver(this);

    // Ensure any persisted auth is cleared when the login screen appears.
    // This makes sure the app always asks for credentials on open.
    // Run on next microtask so widget is mounted.
    Future.microtask(() => _forceSignOutSilently());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app goes to background, mark it.
    // When app resumes from background, force sign-out so user must login again.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _wentToBackground = true;
    } else if (state == AppLifecycleState.resumed) {
      if (_wentToBackground) {
        // Sign out on resume for extra security
        _wentToBackground = false;
        _forceSignOutSilently();
      }
    }
    super.didChangeAppLifecycleState(state);
  }

  Future<void> _forceSignOutSilently() async {
    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        await FirebaseAuth.instance.signOut();
        debugPrint('[auth] forced signOut on RegisterScreen init/resume');
      }
    } catch (e) {
      debugPrint('[auth] error forcing signOut: $e');
      // ignore - we don't want to block UI if signOut fails
    }
  }

  /// Calls backend which should VERIFY with QPay and update Firestore using Admin privileges.
  /// Expects JSON: { "status":"success", "paymentId":"...", "updated": true }
  /// debug: set true only for dev/staging to get 'debug' and 'log_tail' fields from server
  Future<Map<String, dynamic>> _callBackendPaymentApi({
    required String uid,
    required bool isDistributor,
    required String paymentId,
    bool debug = false,
  }) async {
    final body = {
      'uid': uid,
      'isDistributor': isDistributor ? '1' : '0',
      'paymentId': paymentId,
    };

    final uri = Uri.parse(_backendPaymentApi);
    final requestUri = debug ? uri.replace(queryParameters: {'debug': '1'}) : uri;

    final resp = await http.post(requestUri, body: body).timeout(const Duration(seconds: 20));

    Map<String, dynamic>? decoded;
    try {
      final d = json.decode(resp.body);
      if (d is Map<String, dynamic>) decoded = d;
    } catch (_) {
      decoded = null;
    }

    if (resp.statusCode != 200) {
      final serverMsg = decoded?['message'] ?? decoded?['error'] ?? resp.body;
      throw Exception('Backend ${resp.statusCode}: $serverMsg');
    }

    if (decoded == null) {
      return {'raw': resp.body};
    }
    return decoded;
  }

  Future<void> _showSnack(String text) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Try to ensure a users/{uid} doc exists.
  /// If a doc already exists we return it. If not, attempt to find by email (migration).
  /// If migration is impossible (permission denied / not found) create a minimal doc.
  Future<DocumentSnapshot<Map<String, dynamic>>> _ensureUserDoc(String uid, String email, bool isDistributorFS) async {
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);

    try {
      final snap = await userDocRef.get();
      if (snap.exists) return snap as DocumentSnapshot<Map<String, dynamic>>;

      // If not exists -> try to find an existing profile by email (best-effort).
      // Note: this read may be blocked by rules; we catch and handle it.
      try {
        final q = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();

        if (q.docs.isNotEmpty) {
          final existing = q.docs.first;
          final data = existing.data();
          // Attempt to create the user doc under the uid with the existing data (admin-owned fields removed).
          final toWrite = <String, dynamic>{
            'email': data['email'] ?? email,
            'walletBalance': data['walletBalance'] ?? 0,
            'createdAt': FieldValue.serverTimestamp(),
            'role': isDistributorFS ? 'distributor' : (data['role'] ?? (isDistributorFS ? 'distributor' : 'user')),
            'subscriptionPaid': data['subscriptionPaid'] ?? false,
          };
          await userDocRef.set(toWrite);
          debugPrint('[migrate] copied users/${existing.id} -> users/$uid');
          return await userDocRef.get() as DocumentSnapshot<Map<String, dynamic>>;
        }
      } on FirebaseException catch (e) {
        debugPrint('[migrate] could not query users by email: ${e.code} ${e.message}');
        // If permission-denied, we'll create a minimal doc below.
      }

      // No existing doc or couldn't read it -> create a minimal allowed doc (client create for own uid is permitted by rules)
      final minimal = {
        'email': email,
        'walletBalance': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'role': isDistributorFS ? 'distributor' : 'user',
        'subscriptionPaid': false,
      };
      await userDocRef.set(minimal);
      debugPrint('[ensureUserDoc] created minimal users/$uid');
      return await userDocRef.get() as DocumentSnapshot<Map<String, dynamic>>;
    } catch (e) {
      debugPrint('[ensureUserDoc] unexpected error: $e');
      rethrow;
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final email = _email.text.trim();
    final pass = _password.text;

    try {
      // 1) Sign in with Firebase Auth and wait
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );
      final user = cred.user;

      if (user == null) {
        await _showSnack('Sign-in failed.');
        setState(() => _loading = false);
        return;
      }

      final uid = user.uid;
      debugPrint('[register] signed in uid=$uid email=${user.email}');

      // 2) Detect distributor (safely)
      bool isDistributorFS = false;
      Map<String, dynamic>? distData;
      String? distDocId;

      try {
        final idxDoc = await FirebaseFirestore.instance.collection('distributors_by_uid').doc(uid).get();
        if (idxDoc.exists) {
          final roleValue = (idxDoc.data()?['role'] as String?)?.toLowerCase().trim();
          if (roleValue == 'distributor' || roleValue == 'distributer') {
            isDistributorFS = true;
          }
        }
      } on FirebaseException catch (e) {
        debugPrint('[register] distributors_by_uid read error: ${e.code} ${e.message}');
        // Not fatal — continue (we can still check distributors collection)
      }

      if (!isDistributorFS) {
        try {
          final q = await FirebaseFirestore.instance
              .collection('distributors')
              .where('firebase_uid', isEqualTo: uid)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            final data = q.docs.first.data();
            final roleValue = (data['role'] as String?)?.toLowerCase().trim();
            if (roleValue == 'distributor' || roleValue == 'distributer') {
              isDistributorFS = true;
              distData = data;
              distDocId = q.docs.first.id;
              // create an index for future fast checks (merge)
              await FirebaseFirestore.instance.collection('distributors_by_uid').doc(uid).set({
                'role': 'distributor',
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
          }
        } on FirebaseException catch (e) {
          debugPrint('[register] distributors query error: ${e.code} ${e.message}');
        }
      }

      // Update Riverpod flags
      ref.read(isDistributorProvider.notifier).state = isDistributorFS;
      ref.read(distributorDataProvider.notifier).state =
      distData != null ? {...distData, '_docId': distDocId} : null;

      // 3) Ensure user doc exists and is readable/creatable by client
      DocumentSnapshot<Map<String, dynamic>> userSnap;
      try {
        userSnap = await _ensureUserDoc(uid, user.email ?? email, isDistributorFS);
      } on FirebaseException catch (e) {
        // If we still can't read/create the user's own doc, abort and sign out
        debugPrint('[register] ensureUserDoc failed: ${e.code} ${e.message}');
        await FirebaseAuth.instance.signOut();
        await _showSnack('Firestore permission error for users/$uid: ${e.message ?? e.code}. Contact admin.');
        setState(() => _loading = false);
        return;
      }

      final udata = userSnap.data() ?? {};
      final roleRaw = (udata['role'] as String?) ?? (isDistributorFS ? 'distributor' : 'user');
      final role = roleRaw.toLowerCase();
      final bool isDistributor = role.contains('distrib');

      bool subscriptionPaid = false;
      final rawPaid = udata['subscriptionPaid'];
      if (rawPaid is bool) subscriptionPaid = rawPaid;
      if (rawPaid is String) subscriptionPaid = rawPaid.toLowerCase() == 'true';

      if (subscriptionPaid) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
              (_) => false,
        );
        return;
      }

      // 4) Payment flow (unchanged)
      final priceLabel = isDistributor ? '₹1099' : '₹599';
      final roleLabel = isDistributor ? 'Distributor' : 'User';
      final paymentUrl = isDistributor
          ? 'https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx?id=896'
          : 'https://pg.qpayindia.com/WWWS/Merchant/PaymentLinkoptions/PaymentURLLink.aspx?id=899';

      final dialogChoice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Pay $priceLabel to access the app'),
          content: Text('To continue as $roleLabel, please pay $priceLabel.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop('cancel'), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop('ok'), child: const Text('OK')),
          ],
        ),
      );

      if (dialogChoice != 'ok') {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        await _showSnack('Payment required to access the app. You have been signed out.');
        setState(() => _loading = false);
        return;
      }

      // Open PaymentFlow - expects Map {'success':true, 'paymentId': '...'} on success
      if (!mounted) return;
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentFlow(
            uid: uid,
            paymentUrl: paymentUrl,
            isDistributor: isDistributor,
          ),
        ),
      );

      bool paymentSuccess = false;
      String paymentId = '';

      if (result is bool) {
        paymentSuccess = result;
      } else if (result is Map) {
        final r = Map<String, dynamic>.from(result);
        final s = r['success'];
        if (s is bool) paymentSuccess = s;
        paymentId = (r['paymentId'] ?? '').toString();
      }

      if (!paymentSuccess || paymentId.isEmpty) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        await _showSnack('Payment not completed or paymentId missing. You have been signed out.');
        setState(() => _loading = false);
        return;
      }

      // Notify backend for server-side verification & Firestore update.
      try {
        final backendResp = await _callBackendPaymentApi(
          uid: uid,
          isDistributor: isDistributor,
          paymentId: paymentId,
          debug: false, // set true temporarily for dev/staging
        );

        final status = (backendResp['status'] as String?) ?? backendResp['status']?.toString();
        final updated = backendResp['updated'] == true || backendResp['updated']?.toString() == '1';

        if (status == 'success' && updated) {
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainScreen()),
                (_) => false,
          );
          return;
        } else {
          if (!mounted) return;
          final msg = backendResp['message'] ?? 'Payment verification did not complete. Please contact support.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));

          // If server returned debug information (dev only), show a dialog for copy/paste
          if (backendResp.containsKey('debug') || backendResp.containsKey('qpay') || backendResp.containsKey('log_tail')) {
            final debugParts = <String>[];
            if (backendResp['debug'] != null) debugParts.add('DEBUG: ${backendResp['debug']}');
            if (backendResp['qpay'] != null) {
              try {
                debugParts.add('QPAY: ${const JsonEncoder.withIndent('  ').convert(backendResp['qpay'])}');
              } catch (_) {
                debugParts.add('QPAY: ${backendResp['qpay'].toString()}');
              }
            }
            if (backendResp['log_tail'] != null) debugParts.add('LOG_TAIL:\n${backendResp['log_tail']}');

            if (debugParts.isNotEmpty) {
              await showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Server debug (dev only)'),
                  content: SingleChildScrollView(child: SelectableText(debugParts.join('\n\n'))),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
                  ],
                ),
              );
            }
          }

          setState(() => _loading = false);
          return;
        }
      } catch (e) {
        // e contains server message if server returned structured error
        if (!mounted) return;
        final errStr = e.toString();
        final retry = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Verification failed'),
            content: Text('Could not contact backend to verify payment:\n\n$errStr\n\nWould you like to retry verification now?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Retry')),
            ],
          ),
        );

        if (retry == true) {
          if (!mounted) return;
          setState(() => _loading = false);
          await _login();
          return;
        } else {
          await FirebaseAuth.instance.signOut();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verification cancelled. You have been signed out.')),
          );
          setState(() => _loading = false);
          return;
        }
      }
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'invalid-email' => 'Invalid email address.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' => 'No user found for that email.',
        'wrong-password' => 'Incorrect password.',
        'invalid-credential' => 'The supplied credential is incorrect or expired.',
        _ => e.message ?? 'Authentication error.',
      };
      if (!mounted) return;
      await _showSnack(msg);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      await _showSnack('Firestore error: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      await _showSnack('Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const SizedBox(height: 24),
                    Center(child: Image.asset('assets/images/powerpay_logo.png', height: 120)),
                    const SizedBox(height: 24),
                    Text(
                      'Login to Power Pay',
                      textAlign: TextAlign.center,
                      style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _decor('Email'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter email';
                        final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim());
                        if (!ok) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _login(),
                      decoration: _decor(
                        'Password',
                        suffix: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter password';
                        if (v.length < 6) return 'At least 6 characters';
                        return null;
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Retrieve Password'),
                              content: const SelectableText(
                                'To retrieve password contact Mr. Vinoth kumar - 84288 19336',
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
                              ],
                            ),
                          );
                        },
                        child: const Text('Forgot Password?'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Distributor detection uses distributors_by_uid/{uid} first; fallback to distributors.firebase_uid. We never downgrade from distributor to user.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}