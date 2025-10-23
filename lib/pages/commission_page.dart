// lib/pages/commission_rates_page.dart
import 'package:flutter/material.dart';

// A simple class to hold the operator and rate data
class CommissionRate {
  final String operatorName;
  final double originalRate;
  final String? logoUrl;
  final IconData? fallbackIcon;

  CommissionRate(this.operatorName, this.originalRate, {this.logoUrl, this.fallbackIcon});

  // Calculates half of the original rate
  double get halvedRate => originalRate / 2;
}

class CommissionRatesPage extends StatelessWidget {
  const CommissionRatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Data extracted from the image you provided
    final List<CommissionRate> rates = [
      CommissionRate('Vodafone', 4.00, logoUrl: 'https://logo.clearbit.com/vodafone.in'),
      CommissionRate('Airtel', 2.00, logoUrl: 'https://logo.clearbit.com/airtel.in'),
      CommissionRate('Jio', 0.65, logoUrl: 'https://logo.clearbit.com/jio.com'),
      CommissionRate('BSNL', 5.20, logoUrl: 'https://logo.clearbit.com/bsnl.co.in'),
      CommissionRate('Idea', 4.00, logoUrl: 'https://logo.clearbit.com/ideacellular.com'),
      CommissionRate('Dish TV', 4.40, logoUrl: 'https://logo.clearbit.com/dishtv.in'),
      CommissionRate('Airtel Digital TV', 4.20, logoUrl: 'https://logo.clearbit.com/airtel.in'),
      CommissionRate('Sundirect DTH TV', 3.50, logoUrl: 'https://logo.clearbit.com/sundirect.in'),
      CommissionRate('Videocon DTH TV', 4.20, logoUrl: 'https://logo.clearbit.com/videocon.com'),
      CommissionRate('Tatasky DTH TV', 4.30, logoUrl: 'https://logo.clearbit.com/tataplay.com'),
      CommissionRate('Postpaid Bill', 0.00, fallbackIcon: Icons.receipt_long),
      CommissionRate('Google Play Gift Card', 2.00, logoUrl: 'https://logo.clearbit.com/google.com'),
      CommissionRate('Electricity Bill', 0.00, fallbackIcon: Icons.electric_bolt),
      CommissionRate('FASTag Recharge', 0.15, fallbackIcon: Icons.directions_car),
      CommissionRate('LIC Premium', 0.40, logoUrl: 'https://logo.clearbit.com/licindia.in'),
      CommissionRate('Gas Cylinder', 0.40, fallbackIcon: Icons.propane_tank),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Commission Rates'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: rates.length,
        itemBuilder: (context, index) {
          final item = rates[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.white,
                child: item.logoUrl != null
                    ? Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: Image.network(
                    item.logoUrl!,
                    errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.error_outline, color: Colors.red),
                  ),
                )
                    : Icon(item.fallbackIcon ?? Icons.business, color: Colors.grey.shade700),
              ),
              title: Text(
                item.operatorName,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              trailing: Text(
                // ✅ CHANGED: Now formats the number to two decimal places
                '${item.halvedRate.toStringAsFixed(2)}%',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          );
        },
      ),
    );
  }
}