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

  /// The operator list was copied exactly from the screenshot you provided.
  /// Distributor percentages match the screenshot. User rate is shown as half.
  List<CommissionRate> _buildRates() {
    return <CommissionRate>[
      CommissionRate(
        id: 'vodafone',
        operatorName: 'Vodafone',
        distributorRate: 4.00,
        logoUrl: 'https://logo.clearbit.com/vodafone.in',
      ),
      CommissionRate(
        id: 'reliance_jio',
        operatorName: 'RELIANCE - JIO',
        distributorRate: 0.85,
        logoUrl: 'https://logo.clearbit.com/jio.com',
      ),
      CommissionRate(
        id: 'airtel',
        operatorName: 'Airtel',
        distributorRate: 2.50,
        logoUrl: 'https://logo.clearbit.com/airtel.in',
      ),
      CommissionRate(
        id: 'bsnl_stv',
        operatorName: 'BSNL - STV',
        distributorRate: 5.00,
        logoUrl: 'https://logo.clearbit.com/bsnl.co.in',
      ),
      CommissionRate(
        id: 'bsnl_topup',
        operatorName: 'BSNL - TOPUP',
        distributorRate: 5.00,
        logoUrl: 'https://logo.clearbit.com/bsnl.co.in',
      ),
      CommissionRate(
        id: 'idea',
        operatorName: 'Idea',
        distributorRate: 4.00,
        logoUrl: 'https://logo.clearbit.com/vi.com', // VI is the merged brand
      ),
      CommissionRate(
        id: 'dish_tv',
        operatorName: 'DISH TV',
        distributorRate: 4.40,
        logoUrl: 'https://logo.clearbit.com/dishtv.in',
      ),
      CommissionRate(
        id: 'airtel_digital_dth',
        operatorName: 'Airtel Digital DTH TV',
        distributorRate: 4.20,
        logoUrl: 'https://logo.clearbit.com/airtel.in',
      ),
      CommissionRate(
        id: 'sundirect_dth',
        operatorName: 'SUNDIRECT DTH TV',
        distributorRate: 3.50,
        logoUrl: 'https://logo.clearbit.com/sundirect.in',
      ),
      CommissionRate(
        id: 'videocon_dth',
        operatorName: 'VIDEOCON DTH TV',
        distributorRate: 4.20,
        logoUrl: 'https://logo.clearbit.com/videocon.com',
      ),
      CommissionRate(
        id: 'tatasky_dth',
        operatorName: 'TATASKY DTH TV',
        distributorRate: 3.70,
        logoUrl: 'https://logo.clearbit.com/tataplay.com',
      ),
      CommissionRate(
        id: 'ajmer_vidyut_rajasthan',
        operatorName: 'Ajmer Vidyut Vitran Nigam - RAJASTHAN',
        distributorRate: 0.00,
        logoUrl: null,
      ),
      CommissionRate(
        id: 'apdcl_assam',
        operatorName: 'APDCL (Non-RAPDR) - ASSAM',
        distributorRate: 0.00,
        logoUrl: null,
      ),
      CommissionRate(
        id: 'google_play',
        operatorName: 'Google Play',
        distributorRate: 2.00,
        logoUrl: 'https://logo.clearbit.com/play.google.com',
      ),
      CommissionRate(
        id: 'federal_bank_fastag',
        operatorName: 'Federal Bank - Fastag',
        distributorRate: 0.15,
        fallbackIcon: Icons.credit_card,
      ),
      CommissionRate(
        id: 'hdfc_bank_fastag',
        operatorName: 'Hdfc Bank - Fastag',
        distributorRate: 0.15,
        fallbackIcon: Icons.credit_card,
      ),
      CommissionRate(
        id: 'icici_fastag',
        operatorName: 'Icici Bank Fastag',
        distributorRate: 0.15,
        fallbackIcon: Icons.credit_card,
      ),
      CommissionRate(
        id: 'idbi_fastag',
        operatorName: 'Idbi Bank Fastag',
        distributorRate: 0.15,
        fallbackIcon: Icons.credit_card,
      ),
      CommissionRate(
        id: 'idfc_first_fastag',
        operatorName: 'Idfc First Bank - Fastag',
        distributorRate: 0.15,
        fallbackIcon: Icons.credit_card,
      ),
      // If there are more rows in the screenshot not visible in the crop,
      // tell me and I'll add them exactly as shown.
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rates = _buildRates();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Rates'),
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
                    // Show user rate exactly half of distributor rate
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
