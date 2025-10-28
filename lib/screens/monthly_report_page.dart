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

class MonthlyReportPage extends StatefulWidget {
  const MonthlyReportPage({super.key});

  @override
  State<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());
  bool _isLoading = false;

  List<String> get _monthOptions {
    final now = DateTime.now();
    final months = <String>[];
    for (int i = 0; i < 12; i++) {
      final date = DateTime(now.year, now.month - i);
      months.add(DateFormat('yyyy-MM').format(date));
    }
    return months;
  }

  Future<Map<String, dynamic>> _fetchMonthlyData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not logged in');

      // Parse selected month
      final selectedDate = DateFormat('yyyy-MM').parse(_selectedMonth);
      final startDate = DateTime(selectedDate.year, selectedDate.month, 1);
      final endDate = DateTime(selectedDate.year, selectedDate.month + 1, 0, 23, 59, 59);

      debugPrint('Fetching data for: $_selectedMonth');
      debugPrint('Date range: $startDate to $endDate');

      // 1. Get distributor payments for the month
      final paymentsQuery = await FirebaseFirestore.instance
          .collection('distributor_payments')
          .where('distributorId', isEqualTo: currentUser.uid)
          .where('timestamp', isGreaterThanOrEqualTo: startDate)
          .where('timestamp', isLessThanOrEqualTo: endDate)
          .get();

      debugPrint('Found ${paymentsQuery.docs.length} payments');

      double totalPayments = 0;
      int successfulPayments = 0;
      int failedPayments = 0;

      for (final doc in paymentsQuery.docs) {
        final data = doc.data();
        final amount = (data['amount'] as num?)?.toDouble() ?? 0;
        final status = data['status']?.toString() ?? 'initiated';
        
        totalPayments += amount;
        if (status == 'completed') {
          successfulPayments++;
        } else if (status == 'failed') {
          failedPayments++;
        }
      }

      // 2. Get commission data (if exists)
      double totalCommission = 0;
      try {
        final commissionQuery = await FirebaseFirestore.instance
            .collection('commissions')
            .where('distributorId', isEqualTo: currentUser.uid)
            .where('month', isEqualTo: _selectedMonth)
            .get();

        for (final doc in commissionQuery.docs) {
          final data = doc.data();
          totalCommission += (data['amount'] as num?)?.toDouble() ?? 0;
        }
      } catch (e) {
        debugPrint('Error fetching commission: $e');
      }

      // 3. Get user registrations for the month
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('createdAt', isGreaterThanOrEqualTo: startDate)
          .where('createdAt', isLessThanOrEqualTo: endDate)
          .get();

      final newUsers = usersQuery.docs.length;

      return {
        'totalPayments': totalPayments,
        'successfulPayments': successfulPayments,
        'failedPayments': failedPayments,
        'totalCommission': totalCommission,
        'newUsers': newUsers,
        'averageTransaction': successfulPayments > 0 ? totalPayments / successfulPayments : 0,
      };
    } catch (e) {
      debugPrint('Error in _fetchMonthlyData: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Monthly Report',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: brandPurple,
        elevation: 0,
      ),
      backgroundColor: lightBg,
      body: Column(
        children: [
          // Month Selector
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: brandPurple),
                const SizedBox(width: 12),
                Text(
                  'Select Month:',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: textDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedMonth,
                        isExpanded: true,
                        items: _monthOptions.map((month) {
                          final date = DateFormat('yyyy-MM').parse(month);
                          final displayName = DateFormat('MMMM yyyy').format(date);
                          return DropdownMenuItem<String>(
                            value: month,
                            child: Text(displayName),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedMonth = value;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _fetchMonthlyData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  debugPrint('FutureBuilder error: ${snapshot.error}');
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
                          'Error loading report data',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please check your internet connection',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final data = snapshot.data!;
                final date = DateFormat('yyyy-MM').parse(_selectedMonth);
                final displayMonth = DateFormat('MMMM yyyy').format(date);

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Header
                      Text(
                        'Report for $displayMonth',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Summary Cards
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        children: [
                          _buildSummaryCard(
                            title: 'Total Payments',
                            value: '₹${data['totalPayments'].toStringAsFixed(2)}',
                            icon: Icons.payments,
                            color: Colors.green,
                          ),
                          _buildSummaryCard(
                            title: 'Successful Payments',
                            value: data['successfulPayments'].toString(),
                            icon: Icons.check_circle,
                            color: Colors.blue,
                          ),
                          _buildSummaryCard(
                            title: 'Failed Payments',
                            value: data['failedPayments'].toString(),
                            icon: Icons.cancel,
                            color: Colors.red,
                          ),
                          _buildSummaryCard(
                            title: 'Total Commission',
                            value: '₹${data['totalCommission'].toStringAsFixed(2)}',
                            icon: Icons.attach_money,
                            color: Colors.orange,
                          ),
                          _buildSummaryCard(
                            title: 'New Users',
                            value: data['newUsers'].toString(),
                            icon: Icons.person_add,
                            color: brandPurple,
                          ),
                          _buildSummaryCard(
                            title: 'Avg Transaction',
                            value: '₹${data['averageTransaction'].toStringAsFixed(2)}',
                            icon: Icons.trending_up,
                            color: Colors.teal,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Additional Stats
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
                            Text(
                              'Performance Summary',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: textDark,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildStatRow('Success Rate', 
                                '${data['successfulPayments'] + data['failedPayments'] > 0 ? (data['successfulPayments'] / (data['successfulPayments'] + data['failedPayments']) * 100).toStringAsFixed(1) : '0'}%'),
                            _buildStatRow('Total Transactions', 
                                (data['successfulPayments'] + data['failedPayments']).toString()),
                            _buildStatRow('Commission Rate', 
                                '${data['totalPayments'] > 0 ? (data['totalCommission'] / data['totalPayments'] * 100).toStringAsFixed(1) : '0'}%'),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: textLight,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: textDark,
            ),
          ),
        ],
      ),
    );
  }
}