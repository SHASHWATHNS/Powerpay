// lib/pages/commission_rates_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// CommissionRate holds distributor's commission and derives the user's commission (half fallback).
class CommissionRate {
  final String id; // machine id (useful if you fetch from backend)
  final String operatorName;
  final double distributorRate; // e.g. 2.00 means 2.00%
  final String? logoUrl;
  final IconData? fallbackIcon;

  CommissionRate({
    required this.id,
    required this.operatorName,
    required this.distributorRate,
    this.logoUrl,
    this.fallbackIcon,
  });

  /// old fallback behaviour: user commission is half of distributor if no user selected
  double exampleUserRate() => distributorRate / 2.0;
}

class CommissionRatesPage extends StatefulWidget {
  const CommissionRatesPage({super.key});

  @override
  State<CommissionRatesPage> createState() => _CommissionRatesPageState();
}

class _CommissionRatesPageState extends State<CommissionRatesPage> {
  // static distributor rates (same across networks as you requested)
  late final List<CommissionRate> _rates;

  // distributor's created users (retailers) loaded from Firestore (only for distributor accounts)
  List<Map<String, Object?>> _retailers = [];
  String? _selectedRetailerUid;
  bool _loadingRetailers = true;
  bool _loadingError = false;

  // account detection
  bool? _isRetailerAccount; // null while checking, true = retailer, false = distributor
  double? _currentUserSlab; // slab for logged-in retailer (if retailer)

  @override
  void initState() {
    super.initState();
    _buildStaticRates();
    _determineAccountAndLoad();
  }

  void _buildStaticRates() {
    _rates = <CommissionRate>[
      CommissionRate(id: 'jio', operatorName: 'Jio', distributorRate: 2.00, logoUrl: 'https://logo.clearbit.com/jio.com'),
      CommissionRate(id: 'airtel', operatorName: 'Airtel', distributorRate: 2.00, logoUrl: 'https://logo.clearbit.com/airtel.in'),
      CommissionRate(id: 'vi', operatorName: 'VI', distributorRate: 2.00, logoUrl: 'https://logo.clearbit.com/vi.com'),
      CommissionRate(id: 'bsnl', operatorName: 'BSNL', distributorRate: 0.65, logoUrl: 'https://logo.clearbit.com/bsnl.co.in'),
      CommissionRate(id: 'tatasky', operatorName: 'Tata Play (Tata Sky)', distributorRate: 4.30, logoUrl: 'https://logo.clearbit.com/tataplay.com'),
      CommissionRate(id: 'dishtv', operatorName: 'Dish TV', distributorRate: 4.40, logoUrl: 'https://logo.clearbit.com/dishtv.in'),
      CommissionRate(id: 'airtel_dth', operatorName: 'Airtel Digital TV', distributorRate: 4.20, logoUrl: 'https://logo.clearbit.com/airtel.in'),
      CommissionRate(id: 'sundirect', operatorName: 'Sun Direct', distributorRate: 3.50, logoUrl: 'https://logo.clearbit.com/sundirect.in'),
      CommissionRate(id: 'fastag', operatorName: 'FASTag Recharge', distributorRate: 0.30, fallbackIcon: Icons.directions_car),
      CommissionRate(id: 'electricity', operatorName: 'Electricity Bill', distributorRate: 0.20, fallbackIcon: Icons.electrical_services),
      CommissionRate(id: 'postpaid', operatorName: 'Postpaid Bill', distributorRate: 0.00, fallbackIcon: Icons.receipt_long),
    ];
  }

  Future<void> _determineAccountAndLoad() async {
    setState(() {
      _isRetailerAccount = null; // checking
      _currentUserSlab = null;
      _loadingRetailers = true;
      _loadingError = false;
      _retailers = [];
      _selectedRetailerUid = null;
    });

    final current = FirebaseAuth.instance.currentUser;
    if (current == null) {
      // Not signed in
      setState(() {
        _isRetailerAccount = false; // treat as distributor but show message later
        _loadingRetailers = false;
      });
      return;
    }

    try {
      // Read current user's document
      final doc = await FirebaseFirestore.instance.collection('users').doc(current.uid).get();
      final data = doc.data() as Map<String, dynamic>?;

      // Parse commission slab if present
      double slab = 0.0;
      if (data != null) {
        final raw = data['commissionSlab'];
        if (raw is num) slab = raw.toDouble();
        else if (raw is String) slab = double.tryParse(raw) ?? 0.0;
      }

      // Detect retailer: role == 'retailer' OR createdBy present (non-empty)
      final isRetailer = (() {
        if (data == null) return false;
        final role = data['role'];
        if (role is String && role.toLowerCase() == 'retailer') return true;
        final createdBy = data['createdBy'];
        if (createdBy != null && (createdBy is String) && createdBy.trim().isNotEmpty) return true;
        return false;
      })();

      if (isRetailer) {
        // logged-in account is a retailer: set slab and selected uid to current user
        setState(() {
          _isRetailerAccount = true;
          _currentUserSlab = slab;
          _selectedRetailerUid = current.uid;
          _loadingRetailers = false;
        });
      } else {
        // Distributor account: load retailers list for preview
        setState(() {
          _isRetailerAccount = false;
          _loadingRetailers = true;
        });
        await _loadRetailersForDistributor();
      }
    } catch (e, st) {
      debugPrint('[CommissionRates] account detect/load error: $e\n$st');
      // fallback treat as distributor but fail gently
      setState(() {
        _isRetailerAccount = false;
        _loadingRetailers = false;
        _loadingError = true;
      });
    }
  }

  Future<void> _loadRetailersForDistributor() async {
    setState(() {
      _loadingRetailers = true;
      _loadingError = false;
      _retailers = [];
      _selectedRetailerUid = null;
    });

    final current = FirebaseAuth.instance.currentUser;
    if (current == null) {
      setState(() {
        _loadingRetailers = false;
        _loadingError = true;
      });
      return;
    }

    try {
      final qSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('createdBy', isEqualTo: current.uid)
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();

      final list = qSnap.docs.map((d) {
        final Map<String, Object?> m = Map<String, Object?>.from(d.data() as Map<String, dynamic>? ?? {});
        // normalize commission slab
        double slab = 0.0;
        final raw = m['commissionSlab'];
        if (raw is num) slab = raw.toDouble();
        else if (raw is String) slab = double.tryParse(raw) ?? 0.0;
        return <String, Object?>{
          'uid': d.id,
          'name': (m['name'] ?? '') as Object?,
          'email': (m['email'] ?? '') as Object?,
          'commissionSlab': slab,
        };
      }).toList();

      setState(() {
        _retailers = list;
        _loadingRetailers = false;
        _loadingError = false;
      });
    } catch (e, st) {
      debugPrint('[CommissionRates] failed to load retailers: $e\n$st');
      setState(() {
        _loadingRetailers = false;
        _loadingError = true;
      });
    }
  }

  /// Get the selected retailer's slab (if any). For retailer account the slab comes from _currentUserSlab.
  double? get _selectedRetailerSlab {
    if (_isRetailerAccount == true) {
      return _currentUserSlab;
    }
    if (_selectedRetailerUid == null) return null;
    final found = _retailers.where((r) => (r['uid'] as String?) == _selectedRetailerUid);
    if (found.isEmpty) return null;
    final slab = found.first['commissionSlab'];
    if (slab is num) return slab.toDouble();
    if (slab is String) return double.tryParse(slab);
    return null;
  }

  /// Compute final displayed user commission percentage.
  /// If retailer slab exists: userCommissionPercent = distributorRate * (slab / 100)
  /// Else fallback: distributorRate / 2  (example mode)
  double _computeDisplayedUserPercent(double distributorRate, double? retailerSlab) {
    if (retailerSlab != null) {
      return distributorRate * (retailerSlab / 100.0);
    } else {
      return distributorRate / 2.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // show loading while determining account type
    if (_isRetailerAccount == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your Commission Rates')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isRetailer = _isRetailerAccount == true;
    final selectedSlab = _selectedRetailerSlab;

    return Scaffold(
      appBar: AppBar(title: const Text('Your Commission Rates')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _determineAccountAndLoad();
          },
          child: ListView(
            padding: const EdgeInsets.all(12.0),
            children: [
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header depends on account type
                      Text(isRetailer ? 'Your slab (retailer)' : 'Retailer preview', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),

                      // If distributor show dropdown; if retailer show a read-only slab box
                      if (!isRetailer)
                        Row(
                          children: [
                            Expanded(
                              child: _loadingRetailers
                                  ? const SizedBox(height: 42, child: Center(child: CircularProgressIndicator()))
                                  : (_loadingError
                                  ? Row(
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.orange),
                                  const SizedBox(width: 8),
                                  const Expanded(child: Text('Failed to load your retailers. Pull to refresh.')),
                                ],
                              )
                                  : DropdownButtonFormField<String?>(
                                value: _selectedRetailerUid,
                                isExpanded: true, // important to prevent clipping
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('No retailer selected — show example rate')),
                                  ..._retailers.map((r) {
                                    final name = (r['name'] as Object?)?.toString() ?? '—';
                                    final slab = (r['commissionSlab'] as Object?)?.toString() ?? '-';
                                    final label = name.length > 40 ? '${name.substring(0, 36)}...' : name;
                                    return DropdownMenuItem<String?>(
                                      value: r['uid'] as String?,
                                      child: Text('$label   ($slab%)', overflow: TextOverflow.ellipsis, maxLines: 1),
                                    );
                                  }).toList(),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedRetailerUid = val;
                                  });
                                },
                                decoration: const InputDecoration(labelText: 'Preview for retailer'),
                              )),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _retailers.isEmpty ? null : () => setState(() => _selectedRetailerUid = null),
                              child: const Text('Clear'),
                            )
                          ],
                        )
                      else
                      // retailer: show slab read-only and an Edit hint (actual edit kept in user management)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Your slab (%)', style: TextStyle(color: Colors.grey.shade800)),
                                  Text(
                                    selectedSlab != null ? selectedSlab.toStringAsFixed(2) : '0.00',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('To change your slab, contact your distributor or use the retailer management page.'),
                          ],
                        ),

                      const SizedBox(height: 8),

                      // descriptive note, allow wrapping and avoid overflow
                      Text(
                        selectedSlab != null
                            ? (isRetailer
                            ? 'Your slab: ${selectedSlab.toStringAsFixed(2)}%. Your computed commission per operator is distributorRate * (slab/100).'
                            : 'Selected retailer slab: ${selectedSlab.toStringAsFixed(2)}%')
                            : 'If no retailer selected, user rate shown below uses distributor/2 as example.',
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                        softWrap: true,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              // List of operator cards
              ..._rates.map((item) {
                final double userRateToShow = _computeDisplayedUserPercent(item.distributorRate, selectedSlab);

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 22,
                      child: item.logoUrl != null
                          ? Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Image.network(
                          item.logoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            item.fallbackIcon ?? Icons.signal_cellular_alt,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      )
                          : Icon(
                        item.fallbackIcon ?? Icons.signal_cellular_alt,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    title: Text(item.operatorName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Distributor: ${item.distributorRate.toStringAsFixed(2)}%'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('User rate', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 4),
                        // format with two decimals (0.08 will show as 0.08)
                        Text('${userRateToShow.toStringAsFixed(2)}%', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
              }).toList(),

              const SizedBox(height: 16),
              const Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('• Distributor commission shown above is fixed in-app per operator.'),
              const Text('• User commission is calculated as (distributorRate * (userSlab/100)).'),
              const Text('• If no retailer is selected the UI shows an example user rate (distributor / 2).'),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
