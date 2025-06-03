import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powerpay/providers/numlook_providers.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _controller = TextEditingController();
  String rawNumber = '';
  String? carrier;
  bool showIcon = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleFormat);
  }

  void _handleFormat() {
    final digits = _controller.text.replaceAll(RegExp(r'\D'), '');
    final trimmed = digits.length > 10 ? digits.substring(digits.length - 10) : digits;

    // Format number as XXXXX YYYYY
    String formatted = '';
    if (trimmed.length <= 5) {
      formatted = trimmed;
    } else {
      formatted = '${trimmed.substring(0, 5)} ${trimmed.substring(5)}';
    }

    setState(() {
      rawNumber = trimmed;
      showIcon = trimmed.length == 10;

      // 🧼 Hide carrier info if input is deleted or incomplete
      if (trimmed.length < 10) {
        carrier = null;
      }
    });

    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  Future<void> _lookupCarrier() async {
    FocusScope.of(context).unfocus();

    if (rawNumber.length != 10) return;

    setState(() => carrier = null); // Reset before search

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final result = await ref.read(numlookupProvider('+91$rawNumber').future);

    Navigator.of(context).pop();

    if (result != null) {
      setState(() {
        carrier = result;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Provider found!')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: const Text("Enter mobile number")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '+91',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      hintText: '00000 00000',
                      border: const OutlineInputBorder(),
                      counterText: '',
                      suffixIcon: showIcon
                          ? IconButton(
                        icon: const Icon(Icons.arrow_right_alt),
                        onPressed: _lookupCarrier,
                      )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Ensure this is a valid mobile number",
                style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.6)),
              ),
            ),
            const SizedBox(height: 20),
            if (carrier != null)
              Column(
                children: [
                  const Text(
                    "Provider found!",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Provider: $carrier',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
