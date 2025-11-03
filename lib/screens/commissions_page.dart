// lib/screens/commissions_page.dart
import 'package:flutter/material.dart';

class NetworkCommission {
  final String networkId;
  final String networkName;
  final double distributorRate; // e.g. 2.00 for 2.00%
  NetworkCommission({
    required this.networkId,
    required this.networkName,
    required this.distributorRate,
  });

  double get userRate => (distributorRate / 2);
}

class CommissionsPage extends StatelessWidget {
  // replace this list with data fetched from your backend if you have one
  // Just example data. Only networks listed in allowedNetworks will be shown.
  final List<NetworkCommission> allNetworkData;

  CommissionsPage({Key? key, List<NetworkCommission>? networks})
      : allNetworkData = networks ??
      [
        NetworkCommission(networkId: 'airtel', networkName: 'Airtel', distributorRate: 2.0),
        NetworkCommission(networkId: 'jio', networkName: 'Jio', distributorRate: 2.0),
        NetworkCommission(networkId: 'vi', networkName: 'VI', distributorRate: 2.0),
        // remove any non-existing networks from here if present
      ],
        super(key: key);

  // Define the networks that actually exist (the ones you want to keep).
  // Replace with the exact IDs/names used in your project.
  final List<String> allowedNetworks = const [
    'airtel',
    'jio',
    'vi',
    'bsnl',
    'mtl', // add others you actually support
  ];

  @override
  Widget build(BuildContext context) {
    // Filter out non-existing networks
    final visible = allNetworkData
        .where((n) => allowedNetworks.contains(n.networkId))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Commissions')),
      body: ListView.builder(
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final n = visible[index];
          return ListTile(
            title: Text(n.networkName),
            subtitle: Row(
              children: [
                Text('Distributor: ${n.distributorRate.toStringAsFixed(2)}%'),
                const SizedBox(width: 16),
                Text('User: ${n.userRate.toStringAsFixed(2)}%'),
              ],
            ),
          );
        },
      ),
    );
  }
}
