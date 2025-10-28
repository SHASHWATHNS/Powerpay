import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// --- Brand Colors ---
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

  Future<Map<String, dynamic>> _fetchCommissionData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not logged in');

      debugPrint('Fetching commission data for user: ${currentUser.uid}');

      // Query commissions collection
      Query query = FirebaseFirestore.instance
          .collection('commissions')
          .where('distributorId', isEqualTo: currentUser.uid);

      // Apply time filter if needed
      if (_selectedFilter == 'monthly') {
        final now = DateTime.now();
        final startOfMonth = DateTime(now.year, now.month, 1);
        query = query.where('timestamp', isGreaterThanOrEqualTo: startOfMonth);
      } else if (_selectedFilter == 'yearly') {
        final now = DateTime.now();
        final startOfYear = DateTime(now.year, 1, 1);
        query = query.where('timestamp', isGreaterThanOrEqualTo: startOfYear);
      }

      final querySnapshot = await query.get();
      debugPrint('Found ${querySnapshot.docs.length} commission records');

      double totalCommission = 0;
      double pendingCommission = 0;
      double paidCommission = 0;
      final List<Map<String, dynamic>> commissionList = [];

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final amount = (data['amount'] as num?)?.toDouble() ?? 0;
        final status = data['status']?.toString() ?? 'pending';
        final timestamp = data['timestamp'] as Timestamp?;
        final description = data['description']?.toString() ?? 'Commission';

        totalCommission += amount;

        if (status == 'paid') {
          paidCommission += amount;
        } else {
          pendingCommission += amount;
        }

        commissionList.add({
          'id': doc.id,
          'amount': amount,
          'status': status,
          'description': description,
          'timestamp': timestamp,
          'date': timestamp != null ? DateFormat('dd MMM yyyy').format(timestamp.toDate()) : 'N/A',
        });
      }

      // Sort by timestamp (newest first)
      commissionList.sort((a, b) {
        final timeA = a['timestamp'] as Timestamp?;
        final timeB = b['timestamp'] as Timestamp?;
        if (timeA == null || timeB == null) return 0;
        return timeB.compareTo(timeA);
      });

      return {
        'totalCommission': totalCommission,
        'pendingCommission': pendingCommission,
        'paidCommission': paidCommission,
        'commissionList': commissionList,
        'transactionCount': querySnapshot.docs.length,
      };
    } catch (e, stack) {
      debugPrint('Error fetching commission data: $e');
      debugPrint('Stack trace: $stack');
      
      // Return empty data structure instead of throwing
      return {
        'totalCommission': 0.0,
        'pendingCommission': 0.0,
        'paidCommission': 0.0,
        'commissionList': <Map<String, dynamic>>[],
        'transactionCount': 0,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Commission Summary',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: brandPurple,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Time')),
              const PopupMenuItem(value: 'monthly', child: Text('This Month')),
              const PopupMenuItem(value: 'yearly', child: Text('This Year')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      backgroundColor: lightBg,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchCommissionData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            debugPrint('Commission FutureBuilder error: ${snapshot.error}');
            return _buildErrorWidget();
          }

          final data = snapshot.data ?? _getDefaultData();
          final commissionList = data['commissionList'] as List<dynamic>? ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Summary Cards
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
                        title: 'Paid',
                        value: '₹${(data['paidCommission'] as double).toStringAsFixed(2)}',
                        subtitle: 'Received',
                        color: Colors.green,
                        icon: Icons.check_circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildCommissionCard(
                  title: 'Pending',
                  value: '₹${(data['pendingCommission'] as double).toStringAsFixed(2)}',
                  subtitle: 'To be paid',
                  color: Colors.orange,
                  icon: Icons.pending,
                ),

                const SizedBox(height: 24),

                // Commission History
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.history, color: brandPurple),
                          const SizedBox(width: 8),
                          Text(
                            'Commission History',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (commissionList.isEmpty)
                        _buildEmptyState()
                      else
                        Column(
                          children: commissionList.map((commission) {
                            final commissionMap = commission as Map<String, dynamic>;
                            return _buildCommissionItem(commissionMap);
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Permission Denied',
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Please check your Firestore security rules to allow access to commission data.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: brandPurple,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'No commission records found',
            style: GoogleFonts.poppins(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your commission history will appear here',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getDefaultData() {
    return {
      'totalCommission': 0.0,
      'pendingCommission': 0.0,
      'paidCommission': 0.0,
      'commissionList': <Map<String, dynamic>>[],
      'transactionCount': 0,
    };
  }

  Widget _buildCommissionCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textDark,
                  ),
                ),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: textLight,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommissionItem(Map<String, dynamic> commission) {
    final amount = (commission['amount'] as num?)?.toDouble() ?? 0.0;
    final status = commission['status'] as String? ?? 'pending';
    final description = commission['description'] as String? ?? 'Commission';
    final date = commission['date'] as String? ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: lightBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: status == 'paid' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              status == 'paid' ? Icons.check_circle : Icons.pending,
              color: status == 'paid' ? Colors.green : Colors.orange,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                Text(
                  date,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: textLight,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              color: brandPurple,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}