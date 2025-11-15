// lib/screens/recharge_page.dart
// Updated: plan tap scrolls to TOP; success dialog shows a green success card.

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:powerpay/providers/recharge_controller.dart';
import 'package:powerpay/services/api_mapper_service.dart';
import 'payment_webview_screen.dart'; // keep if used elsewhere
import 'bank_page.dart';

/// Small generic tuple helper used internally.
class Tuple3<T1, T2, T3> {
  final T1 item1;
  final T2 item2;
  final T3 item3;
  Tuple3(this.item1, this.item2, this.item3);
}

class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  late final TextEditingController _numberController;
  late final TextEditingController _amountController;
  bool _isProcessing = false;

  // Scroll controller for auto-scrolling (now scroll to TOP on plan tap)
  late final ScrollController _scrollController;

  // Backend endpoint provided by your backend dev
  static const String backendProcessRechargeUrl =
      'https://projects.growtechnologies.in/powerpay/process_recharge.php';

  // --- small fallback maps (common operator/circle -> provider codes)
  static const Map<String, String> _operatorToCode = {
    'Airtel': 'A',
    'Jio': 'RC',
    'Vi': 'V',
    'BSNL': 'BT',
    // Vodafone / Idea intentionally omitted
  };

  static const Map<String, String> _circleToCode = {
    'Chennai': '7',
    'TN': '8',
    'Tamil Nadu': '8',
    'Kolkata': '6',
    'West Bengal': '2',
    'Delhi': '5',
    'Mumbai': '3',
  };

  // --- Category definitions (unchanged) ---
  static const Map<String, List<String>> _operatorCategories = {
    'Jio': ['All', 'Unlimited', 'Talktime', 'JioPhone', 'JioBharat Phone', 'Data'],
    'Airtel': ['All', 'Unlimited', 'Talktime', 'Data', 'International'],
    'Vodafone Idea': ['All', 'Unlimited', 'Talktime', 'Data', 'Hero Unlimited'],
    'BSNL': ['All', 'Unlimited', 'Talktime', 'Data', 'Top'],
  };
  static const List<String> _defaultCategories = ['All', 'Unlimited', 'Talktime', 'Data'];
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _numberController = TextEditingController();
    _amountController = TextEditingController();
    _selectedCategory = _defaultCategories.first;
    _numberController.addListener(_onInputChanged);

    _scrollController = ScrollController();
  }

  void _onInputChanged() => setState(() {});

  @override
  void dispose() {
    _numberController.removeListener(_onInputChanged);
    _numberController.dispose();
    _amountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Smoothly scroll to the top (reverse of previous behavior).
  Future<void> _scrollToTop() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!_scrollController.hasClients) return;
        await _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
        );
      } catch (_) {
        // ignore animation errors
      }
    });
  }

  /// Try to discover a distributor document reference for the current uid.
  Future<DocumentReference?> _discoverDistributorDocForUid(String uid) async {
    final firestore = FirebaseFirestore.instance;
    try {
      final idxRef = firestore.collection('distributors_by_uid').doc(uid);
      final idxSnap = await idxRef.get();
      if (idxSnap.exists) {
        final idxData = idxSnap.data();
        if (idxData != null) {
          if (idxData.containsKey('distributor_doc_id')) {
            final id = idxData['distributor_doc_id']?.toString();
            if (id != null && id.isNotEmpty) {
              return firestore.collection('distributors').doc(id);
            }
          }
          if (idxData.containsKey('distributorId')) {
            final id = idxData['distributorId']?.toString();
            if (id != null && id.isNotEmpty) {
              return firestore.collection('distributors').doc(id);
            }
          }
          return idxRef;
        }
      }
    } catch (_) {}
    try {
      final q = await firestore.collection('distributors').where('firebase_uid', isEqualTo: uid).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    } catch (_) {}
    return null;
  }

  Future<Tuple3<DocumentReference, String, double>> _locateWalletDocAndBalance(
      Transaction tx, FirebaseFirestore firestore, String uid, DocumentReference? distributorDocIfFound) async {
    final candidates = <DocumentReference>[
      firestore.collection('wallets').doc(uid),
      firestore.collection('users').doc(uid),
      if (distributorDocIfFound != null) distributorDocIfFound,
      firestore.collection('distributors').doc(uid),
    ];

    final keys = ['balance', 'walletBalance', 'wallet_balance'];

    for (final docRef in candidates) {
      try {
        final snap = await tx.get(docRef);
        if (!snap.exists) continue;
        final rawData = snap.data();
        final Map<String, dynamic> data;
        if (rawData is Map<String, dynamic>) {
          data = rawData;
        } else {
          data = (rawData ?? {}) as Map<String, dynamic>;
        }
        for (final k in keys) {
          if (data.containsKey(k)) {
            final rawValue = data[k];
            double value;
            if (rawValue == null) {
              value = 0.0;
            } else if (rawValue is num) {
              value = rawValue.toDouble();
            } else {
              value = double.tryParse(rawValue.toString()) ?? 0.0;
            }
            return Tuple3<DocumentReference, String, double>(docRef, k, value);
          }
        }
      } catch (_) {
        continue;
      }
    }

    return Tuple3<DocumentReference, String, double>(
        FirebaseFirestore.instance.collection('wallets').doc(uid), 'balance', 0.0);
  }

  /// Performs the Firestore transaction for recharge.
  /// Returns a map: {'newBalance': double, 'rechargeId': String}
  Future<Map<String, dynamic>> _performRechargeFirestore({
    required String uid,
    required String number,
    required int amount,
    required String operator,
    required String circle,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final rechargesColl = firestore.collection('recharges');

    DocumentReference? distributorDocIfFound;
    try {
      distributorDocIfFound = await _discoverDistributorDocForUid(uid);
    } catch (_) {
      distributorDocIfFound = null;
    }

    final result = await firestore.runTransaction<Map<String, dynamic>>((tx) async {
      final locate = await _locateWalletDocAndBalance(tx, firestore, uid, distributorDocIfFound);
      final walletDoc = locate.item1;
      final balanceField = locate.item2;
      final currentBalance = locate.item3;

      if (currentBalance < amount) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'insufficient-balance',
          message: 'Not enough wallet balance. currentBalance:$currentBalance',
        );
      }

      final updatedBalance = currentBalance - amount;
      tx.update(walletDoc, {balanceField: updatedBalance});

      final newDocRef = rechargesColl.doc(); // create a new doc ref inside transaction
      final rechargeData = {
        'uid': uid,
        'mobile': number,
        'amount': amount,
        'operator': operator,
        'circle': circle,
        'status': 'initiated',
        'createdAt': FieldValue.serverTimestamp(),
      };
      tx.set(newDocRef, rechargeData);

      return {'newBalance': updatedBalance, 'rechargeId': newDocRef.id};
    });

    return result;
  }

  /// Calls your backend to process the recharge.
  /// Returns string: 'success'|'processing'|'failed'|'unknown'
  /// The backend should still update Firestore; we poll Firestore shortly after call to catch quick updates.
  Future<String> _callBackendProcessRecharge({
    required String rechargeId,
    required String uid,
    required String mobile,
    required int amount,
    required String operator,
    required String circle,
  }) async {
    final operatorCode = ApiMapper.operatorToCode(operator) ?? _operatorToCode[operator] ?? '';
    final circleCode = ApiMapper.circleToCode(circle) ?? _circleToCode[circle] ?? '';

    final payload = {
      'rechargeId': rechargeId,
      'uid': uid,
      'mobile': mobile,
      'amount': amount,
      'operator': operator,
      'circle': circle,
      'operatorcode': operatorCode,
      'circlecode': circleCode,
    };

    try {
      final resp = await http
          .post(Uri.parse(backendProcessRechargeUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload))
          .timeout(const Duration(seconds: 25));

      dynamic respBody;
      try {
        respBody = jsonDecode(resp.body);
      } catch (_) {
        respBody = {'raw': resp.body};
      }

      debugPrint('[process_recharge] backend response: ${respBody.toString()} (http ${resp.statusCode})');

      // 1) If backend explicitly returned status => honor it
      if (respBody is Map && respBody['status'] != null) {
        final s = respBody['status'].toString().toLowerCase();
        if (s.contains('success') || s.contains('completed')) return 'success';
        if (s.contains('processing') || s.contains('pending')) return 'processing';
        if (s.contains('fail') || s.contains('error')) return 'failed';
      }

      // 2) If HTTP status 200, treat as positive signal and inspect txn-like fields
      final int httpStatus = resp.statusCode;
      final bool httpOk = (httpStatus >= 200 && httpStatus < 300);

      // Look for txn keys or providerBody
      String? txn;
      if (respBody is Map) {
        for (final k in ['txnId', 'txnid', 'txid', 'transid', 'transactionId', 'orderid', 'order_id']) {
          if (respBody.containsKey(k)) {
            final v = respBody[k];
            if (v != null) txn = v.toString();
            break;
          }
        }
      }

      String providerRaw = '';
      if (respBody is Map && respBody['providerBody'] != null) {
        providerRaw = respBody['providerBody'].toString().toLowerCase();
      } else if (respBody is Map && respBody['providerResponse'] != null) {
        providerRaw = respBody['providerResponse'].toString().toLowerCase();
      } else if (respBody is Map && respBody['raw'] != null) {
        providerRaw = respBody['raw'].toString().toLowerCase();
      } else if (resp.body != null) {
        providerRaw = resp.body.toLowerCase();
      }

      final bool containsSuccess = providerRaw.contains('success') || providerRaw.contains('completed');
      final bool containsPending = providerRaw.contains('pending') || providerRaw.contains('in progress') || providerRaw.contains('already in pending') || providerRaw.contains('processing');
      final bool containsAuthOrIp = providerRaw.contains('authentication') || providerRaw.contains('invalid ip') || providerRaw.contains('invalid username') || providerRaw.contains('invalid password');

      // If HTTP OK and explicit txn present -> likely success
      if (httpOk && txn != null && txn.trim().isNotEmpty && txn.trim() != '0') return 'success';

      // If providerRaw contains success words and HTTP OK -> treat as success
      if (httpOk && containsSuccess) return 'success';

      // If provider indicates pending -> processing
      if (containsPending) return 'processing';

      // If auth / invalid ip -> failed (provider declined)
      if (containsAuthOrIp) return 'failed';

      // If HTTP OK and not obviously failing -> treat as processing (server probably accepted and will update firestore)
      if (httpOk) return 'processing';

      return 'unknown';
    } catch (e) {
      debugPrint('[process_recharge] error contacting backend: $e');
      return 'unknown';
    }
  }

  /// Poll Firestore recharges/{rechargeId} for up to [timeoutSeconds] to see status become 'success'|'completed'.
  /// Returns true if succeeded within timeout, false otherwise.
  Future<bool> _pollFirestoreForStatus(String rechargeId, {int timeoutSeconds = 12}) async {
    final docRef = FirebaseFirestore.instance.collection('recharges').doc(rechargeId);
    final end = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (DateTime.now().isBefore(end)) {
      try {
        final snap = await docRef.get();
        if (snap.exists) {
          final data = snap.data();
          final status = (data?['status'] ?? '').toString().toLowerCase();
          if (status == 'success' || status == 'completed') return true;
          // If provider already set failed -> stop waiting
          if (status == 'failed' || status == 'error' || status == 'provider_call_failed') return false;
        }
      } catch (_) {
        // ignore transient read errors
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  /// Shows a dialog that listens to recharges/{rechargeId} and displays live status updates.
  /// When success is detected, close the streaming dialog and show a short green success dialog.
  Future<void> _showRechargeStatusDialog(String rechargeId) async {
    if (!mounted) return;
    final docRef = FirebaseFirestore.instance.collection('recharges').doc(rechargeId);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Recharge status'),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: docRef.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Error reading status.'),
                      const SizedBox(height: 8),
                      Text(snapshot.error.toString(), style: const TextStyle(fontSize: 12)),
                    ],
                  );
                }

                if (!snapshot.hasData || snapshot.data == null) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(height: 16),
                      Center(child: CircularProgressIndicator()),
                      SizedBox(height: 12),
                      Text('Waiting for server...'),
                    ],
                  );
                }

                final data = snapshot.data!.data();
                final rawStatus = (data?['status'] ?? 'initiated').toString();
                final status = rawStatus.toLowerCase();
                final providerResp = data?['providerResponse'];
                final providerTxn = data?['providerTxnId'];

                // Processing states
                if (status == 'initiated' || status == 'processing' || status == 'pending') {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(height: 12),
                      Center(child: CircularProgressIndicator()),
                      SizedBox(height: 12),
                      Text('Processing... The server is sending the recharge to provider.'),
                    ],
                  );
                }

                // SUCCESS: close current dialog and show a dedicated green dialog/card
                if (status == 'success' || status == 'completed') {
                  // schedule closing the streaming dialog and show green success dialog
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    if (!mounted) return;
                    try {
                      // close the current streaming dialog
                      Navigator.of(ctx).pop();
                    } catch (_) {}
                    // show short green dialog
                    if (!mounted) return;
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (innerCtx) {
                        Future.delayed(const Duration(milliseconds: 1200), () {
                          if (!mounted) return;
                          try {
                            Navigator.of(innerCtx).pop();
                          } catch (_) {}
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully recharged')));
                        });

                        return Dialog(
                          backgroundColor: Colors.transparent,
                          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green.shade700,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: Colors.white, size: 44),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Successfully recharged',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                if (providerTxn != null) ...[
                                  const SizedBox(height: 10),
                                  Text('Provider txn: $providerTxn', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                ],
                                if (providerResp != null) ...[
                                  const SizedBox(height: 10),
                                  Text('Provider response:', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                                  const SizedBox(height: 6),
                                  Text(providerResp.toString(), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  });

                  // Return an empty sized box because we already scheduled UI changes
                  return const SizedBox.shrink();
                }

                // FAILURE states
                if (status == 'failed' || status == 'error' || status == 'provider_call_failed') {
                  final errorInfo = providerResp ?? data?['error'] ?? 'Unknown error';
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 8),
                      const Text('Recharge failed'),
                      const SizedBox(height: 8),
                      Text(errorInfo.toString(), style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      const Text('If money was deducted, backend should refund automatically or contact support.'),
                    ],
                  );
                }

                // Fallback
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Status: $rawStatus'),
                    if (providerResp != null) Text(providerResp.toString(), style: const TextStyle(fontSize: 12)),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _payUsingWallet({
    required String number,
    required int amount,
    required RechargeController controller,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login to continue')));
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final uid = user.uid;
      final txResult = await _performRechargeFirestore(
        uid: uid,
        number: number,
        amount: amount,
        operator: controller.state.selectedOperator ?? '',
        circle: controller.state.selectedCircle ?? '',
      );

      final double newBalance = (txResult['newBalance'] as num).toDouble();
      final String rechargeId = txResult['rechargeId'] as String;

      // Clear inputs and show initiated toast
      _amountController.clear();
      _numberController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recharge initiated successfully')));

      // Call backend and get heuristic inference
      final String inferred = await _callBackendProcessRecharge(
        rechargeId: rechargeId,
        uid: uid,
        mobile: number,
        amount: amount,
        operator: controller.state.selectedOperator ?? '',
        circle: controller.state.selectedCircle ?? '',
      );

      // Immediately poll Firestore for a short time to catch server-updated success
      final bool firestoreSawSuccess = await _pollFirestoreForStatus(rechargeId, timeoutSeconds: 12);

      if (inferred == 'success' || firestoreSawSuccess) {
        if (!mounted) return;
        // show immediate green dialog (use the same green short dialog for consistency)
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (innerCtx) {
            Future.delayed(const Duration(milliseconds: 1200), () {
              if (!mounted) return;
              try {
                Navigator.of(innerCtx).pop();
              } catch (_) {}
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully recharged')));
            });
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 40),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Successfully recharged',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      } else {
        // fallback to long-lived dialog that streams the document
        await _showRechargeStatusDialog(rechargeId);
      }
    } on FirebaseException catch (e) {
      debugPrint('[RechargePage] FirebaseException: code=${e.code} message=${e.message}');
      if (!mounted) return;

      if (e.code == 'permission-denied') {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Firestore Permission Denied'),
            content: const Text(
              'Your app does not have permission to access Firestore for this operation.\n\n'
                  'Common fixes:\n'
                  '• Ensure the user is signed in.\n'
                  '• Ensure your Firestore rules allow reading & updating the wallet document (wallets/{uid} or distributors/{id}).\n'
                  '• If you use distributors_by_uid index, ensure it exists for your user if you expect distributor access.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
            ],
          ),
        );
      } else if (e.code == 'insufficient-balance') {
        double currentBalance = 0.0;
        final msg = e.message ?? '';
        final match = RegExp(r'currentBalance:([0-9]+(?:\.[0-9]+)?)').firstMatch(msg);
        if (match != null) currentBalance = double.tryParse(match.group(1)!) ?? 0.0;
        final shortage = (amount - currentBalance).ceil();
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Insufficient Wallet Balance'),
            content: Text('You need ₹$shortage more in your wallet. Would you like to add money?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankPage()));
                },
                child: const Text('Add Money'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment error: ${e.message ?? e.code}')));
      }
    } catch (e, st) {
      debugPrint('[RechargePage] unknown error: $e\n$st');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Widget _buildInputSection(RechargeState state, RechargeController controller) {
    final border12 = OutlineInputBorder(borderRadius: BorderRadius.circular(12));

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter Recharge Details',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _numberController,
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                border: border12,
                prefixIcon: const Icon(Icons.phone_iphone),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: state.selectedOperator,
              // Filter out Vodafone / Idea from dropdown
              items: ApiMapper.supportedOperators
                  .where((op) =>
              !op.toLowerCase().contains('vodafone') && !op.toLowerCase().contains('idea'))
                  .map((op) => DropdownMenuItem(value: op, child: Text(op)))
                  .toList(),
              onChanged: (val) {
                controller.selectOperator(val);
                setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Select Operator',
                border: border12,
                prefixIcon: const Icon(Icons.network_cell),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: state.selectedCircle,
              items: ApiMapper.supportedCircles.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) {
                controller.selectCircle(val);
                setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Select Circle (State)',
                border: border12,
                prefixIcon: const Icon(Icons.public),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Amount',
                border: border12,
                prefixIcon: const Icon(Icons.currency_rupee),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_isProcessing || state.isLoading)
                  ? null
                  : () async {
                final user = FirebaseAuth.instance.currentUser;
                final amount = int.tryParse(_amountController.text) ?? 0;
                final number = _numberController.text.trim();

                if (user == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login to continue')));
                  return;
                }
                if (amount <= 0) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
                  return;
                }
                if (number.length != 10) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid 10-digit mobile number')));
                  return;
                }

                await _payUsingWallet(number: number, amount: amount, controller: controller);
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: (_isProcessing || state.isLoading)
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Pay Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(List<String> categories) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == _selectedCategory;

          return ChoiceChip(
            label: Text(category),
            selected: isSelected,
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _selectedCategory = category;
                });
              }
            },
            selectedColor: Theme.of(context).primaryColor,
            labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade400),
            ),
            elevation: isSelected ? 2 : 0,
          );
        },
      ),
    );
  }

  Widget _buildPlanTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rechargeControllerProvider);
    final controller = ref.read(rechargeControllerProvider.notifier);

    ref.listen<String?>(rechargeControllerProvider.select((s) => s.selectedOperator), (previous, next) {
      if (previous != next && next != null) {
        setState(() {
          _selectedCategory = "All";
        });
      }
    });
    ref.listen<RechargeState>(rechargeControllerProvider, (previous, next) {
      if (next.statusMessage != null && next.statusMessage != previous?.statusMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.statusMessage!)));
      }
    });

    final List<String> currentCategories = _operatorCategories[state.selectedOperator] ?? _defaultCategories;
    final bool areInputsValid = _numberController.text.length == 10 && state.selectedOperator != null && state.selectedCircle != null;
    final displayedPlans = state.plans.where((plan) {
      if (_selectedCategory == 'All') return true;
      final desc = (plan['desc'] as String? ?? '').toLowerCase();
      final category = _selectedCategory.toLowerCase();
      if (category == 'jiophone') return desc.contains('jio phone');
      if (category == 'jiobharat phone') return desc.contains('jiobharat') || desc.contains('jio bharat');
      if (category == 'hero unlimited') return desc.contains('hero');
      if (category == 'top') return desc.contains('topup') || desc.contains('top up');
      return desc.contains(category);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mobile Recharge')),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController, // attach scroll controller so _scrollToTop works
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInputSection(state, controller),
              if (areInputsValid) ...[
                _buildFilterChips(currentCategories),
                const Divider(height: 1),
                state.isLoading && state.plans.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 48.0), child: CircularProgressIndicator()))
                    : displayedPlans.isNotEmpty
                    ? ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: displayedPlans.length,
                  itemBuilder: (context, index) {
                    final plan = displayedPlans[index];
                    final String price = (plan['rs'] ?? '0').toString();
                    final String description = (plan['desc'] ?? 'No description available').toString();
                    final String validity = (plan['validity'] ?? '').toString();
                    final List<String> tags = [];
                    final descLower = description.toLowerCase();
                    if (descLower.contains('unlimited')) tags.add('UNLIMITED');
                    if (descLower.contains('data')) tags.add('DATA');
                    if (descLower.contains('sms')) tags.add('SMS');

                    return Card(
                      elevation: 1.5,
                      shadowColor: Colors.grey.shade50,
                      margin: const EdgeInsets.only(bottom: 10),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: InkWell(
                        onTap: () {
                          _amountController.text = price;
                          // After selecting plan, scroll to TOP (reverse)
                          _scrollToTop();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 80,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor: Colors.grey.shade100,
                                      child: Text(
                                        '₹ $price',
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
                                      ),
                                    ),
                                    if (validity.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(validity, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                    ]
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (tags.isNotEmpty)
                                        Wrap(spacing: 6.0, runSpacing: 4.0, children: tags.map((tag) => _buildPlanTag(tag)).toList()),
                                      if (tags.isNotEmpty) const SizedBox(height: 8),
                                      Text(description, style: const TextStyle(fontSize: 14.5, height: 1.4)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                )
                    : Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 48.0), child: Text('No plans found for "$_selectedCategory"'))),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                  child: Text(
                    'Please enter a 10-digit number, select an operator, and choose a circle to view plans.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
