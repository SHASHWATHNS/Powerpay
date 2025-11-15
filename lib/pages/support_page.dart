import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// --- Brand Colors ---
const Color brandPurple = Color(0xFF5A189A);
const Color brandPink = Color(0xFFE56EF2);
const Color lightBg = Color(0xFFF7F7F9);
const Color textDark = Color(0xFF1E1E1E);
const Color textLight = Color(0xFF666666);

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  // --- Utility: launch Email ---
  Future<void> _launchEmail(BuildContext context, String email) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': 'Support Request - PowerPay',
        'body': 'Hi Team,\n\nI need help with...',
      },
    );

    if (!await launchUrl(emailUri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email app')),
      );
    }
  }

  // --- Utility: launch Phone ---
  Future<void> _launchPhone(BuildContext context, String phone) async {
    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: phone,
    );

    if (!await launchUrl(phoneUri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open dialer')),
      );
    }
  }

  // --- Utility: launch WhatsApp chat ---
  Future<void> _launchWhatsApp(BuildContext context, String phoneWithCountryCode) async {
    // phoneWithCountryCode should be like '919360559979' (no +, no spaces)
    final String message = Uri.encodeComponent("Hello, I need help with...");
    final Uri waUri = Uri.parse("https://wa.me/$phoneWithCountryCode?text=$message");

    if (!await launchUrl(waUri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define contact points
    const String supportEmail = "powerpay.112025@gmail.com";
    const String refundsEmail = "powerpay.112025@gmail.com";
    const String displayHelplineNumber = "+91 9560559979";
    const String helplineNumber = "84288 19336";

    // WhatsApp number (with country code, no + or spaces) - using the number you provided
    const String whatsappNumberForUrl = "919360559979"; // +91 9360559979

    return Scaffold(
      backgroundColor: lightBg,
      appBar: AppBar(
        title: Text(
          'Contact Support',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: textDark,
          ),
        ),
        backgroundColor: lightBg,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Get the help you need.",
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: brandPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Use the appropriate contact method below based on your query.",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: textLight,
              ),
            ),
            const SizedBox(height: 30),

            // --- 1. Complaints and General Requests (Email) ---
            _buildInfoSection(
              context: context,
              icon: FontAwesomeIcons.solidEnvelope,
              title: "Complaints & General Requests",
              detail: supportEmail,
              detailColor: brandPurple,
              action: () => _launchEmail(context, supportEmail),
            ),

            const SizedBox(height: 20),

            // --- 2. Refund Inquiries ---
            _buildInfoSection(
              context: context,
              icon: FontAwesomeIcons.handHoldingDollar,
              title: "Refund Status Contact",
              detail: refundsEmail,
              detailColor: brandPink,
              action: () => _launchEmail(context, refundsEmail),
            ),

            const SizedBox(height: 20),

            // --- 3. Immediate Contact (Phone) ---
            _buildInfoSection(
              context: context,
              icon: FontAwesomeIcons.phoneVolume,
              title: "Customer Helpline (Call)",
              detail: displayHelplineNumber,
              detailColor: const Color(0xFF00B09B),
              action: () => _launchPhone(context, helplineNumber),
            ),

            const SizedBox(height: 20),

            // --- 4. WhatsApp Chat ---
            _buildInfoSection(
              context: context,
              icon: FontAwesomeIcons.whatsapp,
              title: "Chat with us on WhatsApp",
              detail: "+91 9360559979",
              detailColor: const Color(0xFF25D366), // WhatsApp green
              action: () => _launchWhatsApp(context, whatsappNumberForUrl),
            ),

            const SizedBox(height: 40),
            Center(
              child: Text(
                "Our support team is available 9AM - 6PM IST.",
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: textLight,
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // Helper Widget for Reusable Contact Detail Layout
  Widget _buildInfoSection({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String detail,
    required Color detailColor,
    required VoidCallback action,
  }) {
    return GestureDetector(
      onTap: action,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: detailColor.withOpacity(0.1),
              ),
              child: Icon(
                icon,
                color: detailColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 20),

            // Text Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: detailColor,
                    ),
                  ),
                ],
              ),
            ),

            // Action Icon
            Icon(
              (icon == FontAwesomeIcons.phoneVolume) ? Icons.call : Icons.arrow_forward_ios,
              size: 20,
              color: textLight,
            ),
          ],
        ),
      ),
    );
  }
}
