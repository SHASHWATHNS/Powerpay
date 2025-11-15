// lib/screens/commission_summary_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

const Color brandPurple = Color(0xFF5A189A);
const Color brandBlue = Color(0xFF4F46E0);
const Color lightBg = Color(0xFFF7F7F9);
const Color textDark = Color(0xFF1E1E1E);
const Color textLight = Color(0xFF666666);

class CommissionSummaryPage extends StatefulWidget {
  const CommissionSummaryPage({super.key});

  @override
  State<CommissionSummaryPage> createState() => _CommissionSummaryPageState();
}

class _CommissionSummaryPageState extends State<CommissionSummaryPage> {
  String _selectedFilter = 'all'; // 'all', 'monthly', 'yearly'
  String? _errorMessage;
  bool _permissionDenied = false;
  bool _loading = true;

  late Future<Map<String, dynamic>> _commissionFuture;

  @override
  void initState() {
    super.initState();
    _commissionFuture = _fetchCommissionDataWithTimeout();
  }

  void _refresh() {
    setState(() {
      _errorMessage = null;
      _permissionDenied = false;
      _loading = true;
      _commissionFuture = _fetchCommissionDataWithTimeout();
    });
  }

  Future<Map<String, dynamic>> _fetchCommissionDataWithTimeout() {
    return _fetchCommissionData().timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        debugPrint('[commission] overall fetch timeout');
        setState(() => _loading = false);
        throw Exception('Request timed out (check network or Firestore).');
      },
    );
  }

  DateTime? _parseTimestamp(dynamic ts) {
    if (ts == null) return null;
    try {
      if (ts is Timestamp) return ts.toDate();
      if (ts is DateTime) return ts;
      if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
      if (ts is String) {
        final parsed = DateTime.tryParse(ts);
        if (parsed != null) return parsed;
        final asInt = int.tryParse(ts);
        if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      }
      if (ts is Map && ts['seconds'] != null) {
        final seconds = ts['seconds'];
        if (seconds is int) return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        if (seconds is String) return DateTime.fromMillisecondsSinceEpoch(int.parse(seconds) * 1000);
      }
    } catch (e) {
      debugPrint('[commission] timestamp parse error: $e');
    }
    return null;
  }

  /// Try constrained queries only (no single-doc get on global commission collections).
  /// Also probe recharge/recharge_logs and users/{uid}/commissions subcollection.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchCommissionDocsConstrained(
      String uid, {
        required bool isDistributor,
      }) async {
    final firestore = FirebaseFirestore.instance;
    FirebaseException? lastPermDenied;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> results = [];

    // Collections to try (ordered) - include recharge/recharge_logs because your data shows commissions there
    final candidates = [
      'commissions',
      'commission_logs',
      'commission_log',
      'commission_history',
      'commission_history_v2',
      'recharge_logs', // added
      'recharges',     // added
    ];

    for (final col in candidates) {
      debugPrint('[commission] trying constrained queries on collection: $col');

      // Build queries with many field-name fallbacks to match your actual doc shapes
      final List<Query<Map<String, dynamic>>> queries = [];
      if (isDistributor) {
        queries.add(firestore.collection(col).where('distributorId', isEqualTo: uid));
        queries.add(firestore.collection(col).where('distributor_id', isEqualTo: uid));
        queries.add(firestore.collection(col).where('retailerId', isEqualTo: uid));
        queries.add(firestore.collection(col).where('retailer_id', isEqualTo: uid));
        queries.add(firestore.collection(col).where('userId', isEqualTo: uid));
        queries.add(firestore.collection(col).where('uid', isEqualTo: uid));
        queries.add(firestore.collection(col).where('ownerId', isEqualTo: uid));
      } else {
        queries.add(firestore.collection(col).where('retailerId', isEqualTo: uid));
        queries.add(firestore.collection(col).where('retailer_id', isEqualTo: uid));
        queries.add(firestore.collection(col).where('userId', isEqualTo: uid));
        queries.add(firestore.collection(col).where('uid', isEqualTo: uid));
        queries.add(firestore.collection(col).where('ownerId', isEqualTo: uid));
      }

      for (final q in queries) {
        try {
          final snap = await q.get().timeout(const Duration(seconds: 6));
          debugPrint('[commission] $col query returned ${snap.docs.length} docs');
          if (snap.docs.isNotEmpty) results.addAll(snap.docs);
        } on FirebaseException catch (fe) {
          debugPrint('[commission] FirebaseException on $col query: ${fe.code} ${fe.message}');
          if (fe.code == 'permission-denied') {
            lastPermDenied = fe;
            // stop trying further queries for this collection (denied listing)
            break;
          } else {
            rethrow;
          }
        } on TimeoutException catch (te) {
          debugPrint('[commission] query timeout for $col: $te');
          continue;
        }
      }
      // continue with next collection
    }

    // Also probe common per-user subcollection: users/{uid}/commissions
    try {
      final subSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('commissions')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get()
          .timeout(const Duration(seconds: 6));
      debugPrint('[commission] users/$uid/commissions returned ${subSnap.docs.length} docs');
      if (subSnap.docs.isNotEmpty) results.addAll(subSnap.docs);
    } on FirebaseException catch (fe) {
      debugPrint('[commission] users/{uid}/commissions read failed: ${fe.code} ${fe.message}');
      if (fe.code == 'permission-denied') lastPermDenied = fe;
    } on TimeoutException {
      debugPrint('[commission] users/{uid}/commissions timed out');
    }

    // Deduplicate by full path (to avoid collisions across collections)
    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> dedup = {};
    for (final d in results) {
      dedup[d.reference.path] = d;
    }

    if (dedup.isNotEmpty) return dedup.values.toList();

    if (lastPermDenied != null) {
      // bubble up permission denied so UI shows correct message
      throw FirebaseException(
        plugin: 'cloud_firestore',
        message: 'Permission denied for commission collections',
        code: 'permission-denied',
      );
    }

    // no docs found
    return [];
  }

  Future<Map<String, dynamic>> _fetchCommissionData() async {
    debugPrint('[commission] fetching commission data (final)...');
    _permissionDenied = false;
    _errorMessage = null;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() => _loading = false);
      throw Exception('User not logged in');
    }
    final uid = currentUser.uid;
    final firestore = FirebaseFirestore.instance;

    try {
      // Determine role: prefer users/<uid>.role, else check distributors_by_uid index
      String role = 'retailer';
      try {
        final userSnap = await firestore.collection('users').doc(uid).get().timeout(const Duration(seconds: 4));
        if (userSnap.exists) {
          final ud = userSnap.data() ?? <String, dynamic>{};
          final rawRole = (ud['role'] as String?) ?? '';
          if (rawRole.isNotEmpty) role = rawRole.toLowerCase();
          debugPrint('[commission] role for $uid = $role (from users doc)');
        } else {
          final idxSnap = await firestore.collection('distributors_by_uid').doc(uid).get().timeout(const Duration(seconds: 4));
          if (idxSnap.exists) {
            role = 'distributor';
            debugPrint('[commission] role for $uid = distributor (from distributors_by_uid)');
          } else {
            role = 'retailer';
            debugPrint('[commission] role for $uid = retailer (default)');
          }
        }
      } on TimeoutException {
        debugPrint('[commission] role detection timed out; defaulting to retailer');
        role = 'retailer';
      } on FirebaseException catch (fe) {
        debugPrint('[commission] role detection FirebaseException: ${fe.code} ${fe.message}');
        if (fe.code == 'permission-denied') {
          // try index but swallow errors
          try {
            final idxSnap = await firestore.collection('distributors_by_uid').doc(uid).get().timeout(const Duration(seconds: 4));
            if (idxSnap.exists) role = 'distributor';
          } catch (_) {}
        } else {
          rethrow;
        }
      }

      final isDistributor = role == 'distributor';

      // Fetch constrained documents only (this matches your rules for retailers)
      final docs = await _fetchCommissionDocsConstrained(uid, isDistributor: isDistributor);

      // Process docs into your UI model
      final List<Map<String, dynamic>> commissionList = [];
      double totalUserCommission = 0.0;
      double totalDistributorCommission = 0.0;

      double _num(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v.replaceAll(',', '')) ?? 0.0;
        return 0.0;
      }

      for (final d in docs) {
        final data = d.data() ?? <String, dynamic>{};

        final retailerCommission = _num(data['retailerCommission'] ??
            data['userCommission'] ??
            data['retailer_commission'] ??
            data['retailer_share'] ??
            data['retailer_amt'] ??
            data['retailercommission'] // small fallback
        );

        final distributorCommission = _num(data['distributorCommission'] ??
            data['distributor_commission'] ??
            data['distributor_share'] ??
            data['dist_amt'] ??
            data['distributorcommission']
        );

        final commissionPool = _num(data['commissionPool'] ?? data['pool'] ?? data['commission_pool'] ?? data['commissionpool']);
        final rechargeAmount = _num(data['amount'] ??
            data['rechargeAmount'] ??
            data['recharge_amount'] ??
            data['rechargeAmt'] ??
            data['txnAmount'] ??
            (data['providerResponse'] is Map ? (data['providerResponse']['amount']) : null));

        final operator = (data['operator'] as String?) ??
            (data['operatorName'] as String?) ??
            (data['operator_name'] as String?) ??
            '';

        final retailerId = (data['retailerId'] as String?)
            ?? (data['retailer_id'] as String?)
            ?? (data['uid'] as String?)
            ?? (data['userId'] as String?)
            ?? (data['ownerId'] as String?)
            ?? '';

        final distributorId = (data['distributorId'] as String?)
            ?? (data['distributor_id'] as String?)
            ?? (data['beneficiaryId'] as String?)
            ?? (data['beneficiary_id'] as String?)
            ?? '';

        final createdAtRaw = data['createdAt'] ?? data['timestamp'] ?? data['created_at'] ?? data['commissionCreditedAt'] ?? data['creditedAt'] ?? data['processedAt'];
        final createdAt = _parseTimestamp(createdAtRaw);

        // skip zero commission documents
        if (retailerCommission == 0.0 && distributorCommission == 0.0 && commissionPool == 0.0) continue;

        if (isDistributor) {
          // distributor's own distributor-share entries (what distributor directly receives)
          if (distributorId == uid && distributorCommission > 0) {
            commissionList.add({
              'id': '${d.reference.path}_d',
              'amount': distributorCommission,
              'type': 'distributor',
              'description': 'Distributor share',
              'operator': operator,
              'rechargeAmount': rechargeAmount,
              'commissionPool': commissionPool,
              'retailerId': retailerId,
              'distributorId': distributorId,
              'timestamp': createdAt,
              'date': createdAt != null ? DateFormat('dd MMM yyyy').format(createdAt) : 'N/A',
              'time': createdAt != null ? DateFormat('HH:mm').format(createdAt) : '',
            });
            totalDistributorCommission += distributorCommission;
          }

          // distributor should also see retailer commissions for retailers that belong to them
          if (distributorId == uid && retailerCommission > 0) {
            commissionList.add({
              'id': '${d.reference.path}_r_of_${distributorId}',
              'amount': retailerCommission,
              'type': 'retailer',
              'description': 'Retailer share (from network)',
              'operator': operator,
              'rechargeAmount': rechargeAmount,
              'commissionPool': commissionPool,
              'retailerId': retailerId,
              'distributorId': distributorId,
              'timestamp': createdAt,
              'date': createdAt != null ? DateFormat('dd MMM yyyy').format(createdAt) : 'N/A',
              'time': createdAt != null ? DateFormat('HH:mm').format(createdAt) : '',
            });
            totalUserCommission += retailerCommission;
          }

          // also include cases where the retailerId is the distributor's uid (rare)
          if (retailerId == uid && retailerCommission > 0) {
            commissionList.add({
              'id': '${d.reference.path}_r',
              'amount': retailerCommission,
              'type': 'retailer',
              'description': 'Retailer share',
              'operator': operator,
              'rechargeAmount': rechargeAmount,
              'commissionPool': commissionPool,
              'retailerId': retailerId,
              'distributorId': distributorId,
              'timestamp': createdAt,
              'date': createdAt != null ? DateFormat('dd MMM yyyy').format(createdAt) : 'N/A',
              'time': createdAt != null ? DateFormat('HH:mm').format(createdAt) : '',
            });
            totalUserCommission += retailerCommission;
          }
        } else {
          // Retailer user sees their retailerCommission entries
          if (retailerId == uid && retailerCommission > 0) {
            commissionList.add({
              'id': d.reference.path,
              'amount': retailerCommission,
              'type': 'retailer',
              'description': 'Retailer share',
              'operator': operator,
              'rechargeAmount': rechargeAmount,
              'commissionPool': commissionPool,
              'retailerId': retailerId,
              'distributorId': distributorId,
              'timestamp': createdAt,
              'date': createdAt != null ? DateFormat('dd MMM yyyy').format(createdAt) : 'N/A',
              'time': createdAt != null ? DateFormat('HH:mm').format(createdAt) : '',
            });
            totalUserCommission += retailerCommission;
          }
        }
      }

      // Sort newest first
      commissionList.sort((a, b) {
        final ta = a['timestamp'] as DateTime?;
        final tb = b['timestamp'] as DateTime?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

      // Filter by timeframe
      final now = DateTime.now();
      final filtered = commissionList.where((c) {
        final dt = c['timestamp'] as DateTime?;
        if (dt == null) return _selectedFilter == 'all';
        if (_selectedFilter == 'monthly') return dt.year == now.year && dt.month == now.month;
        if (_selectedFilter == 'yearly') return dt.year == now.year;
        return true;
      }).toList();

      double filteredRetailer = 0.0;
      double filteredDistributor = 0.0;
      for (final c in filtered) {
        final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
        if ((c['type'] as String?) == 'distributor') filteredDistributor += amt;
        else filteredRetailer += amt;
      }

      setState(() => _loading = false);

      return {
        'totalCommission': filteredRetailer + filteredDistributor,
        'userCommission': filteredRetailer,
        'distributorCommission': filteredDistributor,
        'commissionList': filtered,
        'transactionCount': filtered.length,
      };
    } on FirebaseException catch (fe) {
      debugPrint('[commission] FirebaseException: ${fe.code} ${fe.message}');
      setState(() {
        _loading = false;
      });
      if (fe.code == 'permission-denied') {
        _permissionDenied = true;
        _errorMessage = 'Permission Denied — check Firestore rules for commission_logs/commissions and wallets/users.';
        return {
          'totalCommission': 0.0,
          'userCommission': 0.0,
          'distributorCommission': 0.0,
          'commissionList': <Map<String, dynamic>>[],
          'transactionCount': 0,
        };
      } else {
        _errorMessage = 'Failed to fetch commission data: ${fe.message ?? fe.code}';
        return {
          'totalCommission': 0.0,
          'userCommission': 0.0,
          'distributorCommission': 0.0,
          'commissionList': <Map<String, dynamic>>[],
          'transactionCount': 0,
        };
      }
    } catch (e, st) {
      debugPrint('[commission] Exception: $e\n$st');
      setState(() => _loading = false);
      _errorMessage = 'Unexpected error: $e';
      return {
        'totalCommission': 0.0,
        'userCommission': 0.0,
        'distributorCommission': 0.0,
        'commissionList': <Map<String, dynamic>>[],
        'transactionCount': 0,
      };
    }
  }

  void _onFilterSelected(String f) {
    setState(() {
      _selectedFilter = f;
      _commissionFuture = _fetchCommissionDataWithTimeout();
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: Text('Commission Summary', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: brandPurple,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: _onFilterSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Time')),
              const PopupMenuItem(value: 'monthly', child: Text('This Month')),
              const PopupMenuItem(value: 'yearly', child: Text('This Year')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: 'Refresh'),
        ],
      ),
      backgroundColor: lightBg,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _commissionFuture,
        builder: (context, snapshot) {
          if (_loading || snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 4)));
          }

          if (_permissionDenied) {
            return _buildPermissionDeniedWidget();
          }

          if (snapshot.hasError) {
            final err = snapshot.error.toString();
            debugPrint('[commission] FutureBuilder error: $err');
            return _buildErrorWidget(message: _errorMessage ?? err);
          }

          final data = snapshot.data ??
              {
                'totalCommission': 0.0,
                'userCommission': 0.0,
                'distributorCommission': 0.0,
                'commissionList': <Map<String, dynamic>>[],
                'transactionCount': 0,
              };

          final commissionList = data['commissionList'] as List<dynamic>? ?? [];

          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
              try {
                await _commissionFuture;
              } catch (_) {}
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Current Wallet Balance Card - read from wallets/<uid> primarily
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: (() async {
                      final firestore = FirebaseFirestore.instance;
                      final currentUid = FirebaseAuth.instance.currentUser?.uid;
                      if (currentUid == null) throw Exception('User not logged in');

                      // Try wallets doc first
                      try {
                        final w = await firestore.collection('wallets').doc(currentUid).get().timeout(const Duration(seconds: 5));
                        if (w.exists) return w;
                      } catch (we) {
                        debugPrint('[commission] wallets/$currentUid read failed: $we');
                      }

                      // Fallback to users/<uid>
                      try {
                        final u = await firestore.collection('users').doc(currentUid).get().timeout(const Duration(seconds: 5));
                        return u;
                      } catch (ue) {
                        debugPrint('[commission] users/$currentUid read failed: $ue');
                        rethrow;
                      }
                    })(),
                    builder: (context, userSnapshot) {
                      if (userSnapshot.connectionState == ConnectionState.waiting) {
                        return _buildCommissionCard(
                          title: 'Current Balance',
                          value: 'Loading...',
                          subtitle: 'Wallet Balance',
                          color: brandBlue,
                          icon: Icons.account_balance_wallet,
                        );
                      }

                      if (userSnapshot.hasError) {
                        debugPrint('[commission] wallet/users doc read error: ${userSnapshot.error}');
                        return _buildCommissionCard(
                          title: 'Current Balance',
                          value: '—',
                          subtitle: 'Unavailable',
                          color: brandBlue,
                          icon: Icons.account_balance_wallet,
                        );
                      }

                      final doc = userSnapshot.data;
                      final dataMap = doc?.data() as Map<String, dynamic>? ?? {};

                      final walletBalance = (dataMap['walletBalance'] as num?)?.toDouble() ??
                          (dataMap['balance'] as num?)?.toDouble() ??
                          (dataMap['commission'] as num?)?.toDouble() ??
                          0.0;

                      final lastCommission = (dataMap['lastCommissionAmount'] as num?)?.toDouble() ?? 0.0;
                      final lastCommissionAt = dataMap['lastCommissionAt'] as String?;
                      String lastCommissionText = 'No commissions yet';
                      if (lastCommission > 0 && lastCommissionAt != null) {
                        final date = DateTime.tryParse(lastCommissionAt);
                        if (date != null) {
                          lastCommissionText = 'Last: ₹${lastCommission.toStringAsFixed(2)} on ${DateFormat('dd MMM').format(date)}';
                        }
                      }

                      return _buildCommissionCard(
                        title: 'Current Balance',
                        value: '₹${walletBalance.toStringAsFixed(2)}',
                        subtitle: lastCommissionText,
                        color: brandBlue,
                        icon: Icons.account_balance_wallet,
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildCommissionCard(
                          title: 'Total Commission',
                          value: '₹${(data['totalCommission'] as double).toStringAsFixed(2)}',
                          subtitle: '${data['transactionCount']} transactions',
                          color: brandPurple,
                          icon: Icons.attach_money,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCommissionCard(
                          title: 'User Commission',
                          value: '₹${(data['userCommission'] as double).toStringAsFixed(2)}',
                          subtitle: 'From your recharges',
                          color: Colors.green,
                          icon: Icons.person,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.history, color: brandPurple),
                            const SizedBox(width: 8),
                            Text('Commission History', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: textDark)),
                            const Spacer(),
                            Text(_selectedFilter == 'monthly' ? 'This Month' : _selectedFilter == 'yearly' ? 'This Year' : 'All Time',
                                style: GoogleFonts.poppins(fontSize: 12, color: textLight)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (commissionList.isEmpty)
                          _buildEmptyState()
                        else
                          Column(children: commissionList.map((c) => _buildCommissionItem(c as Map<String, dynamic>)).toList()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionDeniedWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Permission Denied', style: GoogleFonts.poppins(fontSize: 20, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text('Check Firestore security rules for commission_logs/commissions and wallets/users collections.', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _refresh, style: ElevatedButton.styleFrom(backgroundColor: brandPurple), child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget({String? message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(message ?? 'Error Loading Commissions', style: GoogleFonts.poppins(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _refresh, style: ElevatedButton.styleFrom(backgroundColor: brandPurple), child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('No commission records found', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text('Your commission history will appear here after successful recharges', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          Text('Pull down to refresh', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildCommissionCard({required String title, required String value, required String subtitle, required Color color, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: textDark)),
          const SizedBox(height: 4),
          Text(title, style: GoogleFonts.poppins(fontSize: 12, color: textLight)),
          Text(subtitle, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500)),
        ])),
      ]),
    );
  }

  Widget _buildCommissionItem(Map<String, dynamic> commission) {
    final amount = (commission['amount'] as num?)?.toDouble() ?? 0.0;
    final date = commission['date'] as String? ?? 'N/A';
    final time = commission['time'] as String? ?? '';
    final operator = commission['operator'] as String? ?? '';
    final rechargeAmount = (commission['rechargeAmount'] as num?)?.toDouble() ?? 0.0;
    final commissionPool = (commission['commissionPool'] as num?)?.toDouble() ?? 0.0;
    final type = commission['type'] as String? ?? 'commission';
    final retailerId = commission['retailerId'] as String? ?? '';
    final distributorId = commission['distributorId'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: (type == 'distributor' ? Colors.orange : Colors.green).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: Icon(type == 'distributor' ? Icons.account_tree : Icons.currency_rupee, color: (type == 'distributor' ? Colors.orange : Colors.green), size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${rechargeAmount > 0 ? "₹${rechargeAmount.toStringAsFixed(2)}" : ""} ${operator.isNotEmpty ? operator : ''}', style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 14)),
          const SizedBox(height: 4),
          Row(children: [
            Text(date, style: GoogleFonts.poppins(fontSize: 12, color: textLight)),
            if (time.isNotEmpty) ...[const SizedBox(width: 8), Text(time, style: GoogleFonts.poppins(fontSize: 12, color: textLight))],
          ]),
          if (retailerId.isNotEmpty) Text('Retailer: $retailerId', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
          if (distributorId.isNotEmpty) Text('Distributor: $distributorId', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
          if (commissionPool > 0) Text('Pool: ₹${commissionPool.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('₹${amount.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: brandPurple, fontSize: 16)),
          Text(type == 'distributor' ? 'Distributor' : 'Retailer', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade600)),
        ]),
      ]),
    );
  }
}