// lib/pages/commission_rates_page.dart
import 'package:flutter/material.dart';

/// CommissionRate holds distributor's commission and derives the user's commission (half).
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

  /// User commission must be exactly half of distributor commission numerically.
  double get userRate => distributorRate / 2.0;
}

class CommissionRatesPage extends StatelessWidget {
  const CommissionRatesPage({super.key});

  List<CommissionRate> _buildRates() {
    return <CommissionRate>[
      // Telecom
      CommissionRate(
        id: 'jio',
        operatorName: 'Jio',
        distributorRate: 2.00,
        logoUrl: 'https://logo.clearbit.com/jio.com',
      ),
      CommissionRate(
        id: 'airtel',
        operatorName: 'Airtel',
        distributorRate: 2.00,
        logoUrl: 'https://logo.clearbit.com/airtel.in',
      ),
      CommissionRate(
        id: 'vi',
        operatorName: 'VI', // Vodafone Idea (brand merged)
        distributorRate: 2.00,
        logoUrl: 'https://logo.clearbit.com/vi.com',
      ),
      CommissionRate(
        id: 'bsnl',
        operatorName: 'BSNL',
        distributorRate: 0.65,
        logoUrl: 'https://logo.clearbit.com/bsnl.co.in',
      ),

      // DTH / TV
      CommissionRate(
        id: 'tatasky',
        operatorName: 'Tata Play (Tata Sky)',
        distributorRate: 4.30,
        logoUrl: 'https://logo.clearbit.com/tataplay.com',
      ),
      CommissionRate(
        id: 'dishtv',
        operatorName: 'Dish TV',
        distributorRate: 4.40,
        logoUrl: 'https://logo.clearbit.com/dishtv.in',
      ),
      CommissionRate(
        id: 'airtel_dth',
        operatorName: 'Airtel Digital TV',
        distributorRate: 4.20,
        logoUrl: 'https://logo.clearbit.com/airtel.in',
      ),
      CommissionRate(
        id: 'sundirect',
        operatorName: 'Sun Direct',
        distributorRate: 3.50,
        logoUrl: 'https://logo.clearbit.com/sundirect.in',
      ),

      // Utility / Others (keep only those that are commonly used)
      CommissionRate(
        id: 'fastag',
        operatorName: 'FASTag Recharge',
        distributorRate: 0.30,
        fallbackIcon: Icons.directions_car,
      ),
      CommissionRate(
        id: 'electricity',
        operatorName: 'Electricity Bill',
        distributorRate: 0.20,
        fallbackIcon: Icons.electrical_services,
      ),
      CommissionRate(
        id: 'postpaid',
        operatorName: 'Postpaid Bill',
        distributorRate: 0.00,
        fallbackIcon: Icons.receipt_long,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rates = _buildRates();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Commission Rates'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12.0),
        itemCount: rates.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = rates[index];

          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
              title: Text(
                item.operatorName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Distributor: ${item.distributorRate.toStringAsFixed(2)}%'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'User rate',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.userRate.toStringAsFixed(2)}%',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
