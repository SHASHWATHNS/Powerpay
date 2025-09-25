import 'package:flutter/material.dart';
import 'package:powerpay/pages/recharge_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = [
      {"icon": Icons.phone_android, "label": "Mobile"},
      {"icon": Icons.electric_bolt, "label": "Electricity"},
      {"icon": Icons.tv, "label": "DTH"},
      {"icon": Icons.verified_user, "label": "Insurance"},
      {"icon": Icons.assignment_ind, "label": "NSDL PAN"},
      {"icon": Icons.local_gas_station, "label": "Gas Booking"},
      {"icon": Icons.flash_on, "label": "Electricity"},
      {"icon": Icons.local_gas_station_outlined, "label": "FasTag"},
      {"icon": Icons.wifi, "label": "Broadband"},
      {"icon": Icons.payments, "label": "Loan EMI Payment"},
      {"icon": Icons.more_horiz, "label": "More BBPS"},
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('DASHBOARD', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
      ),
      body: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
                child: Row(
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Welcome",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Glad to see you here!",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Start exploring our services.",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // The wallet balance display is removed
                    const SizedBox(width: 40),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text("Services", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            Expanded(
              child: GridView.builder(
                itemCount: services.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 22,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.80,
                ),
                itemBuilder: (context, index) {
                  final item = services[index];
                  return GestureDetector(
                    onTap: () {
                      if (item["label"] == "Mobile") {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RechargePage(),
                          ),
                        );
                      } else {
                        // Other item taps (optional)
                      }
                    },
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Icon(item["icon"] as IconData, color: Colors.indigo, size: 26),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          item["label"] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}