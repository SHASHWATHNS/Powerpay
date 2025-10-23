import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'register_screen.dart';

// --- Color Constants ---
const Color brandPurple = Color(0xFF5A189A);
const Color brandPink = Color(0xFFDA70D6);
// --- End Color Constants ---

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _logoFadeIn;
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();

    // Logo animation controller
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // fast, smooth
    );

    _logoFadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeIn),
    );

    _logoScale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    // After logo animation → navigate immediately
    _logoController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RegisterScreen()),
        );
      }
    });

    _logoController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/powerpay_logo.png'), context);
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color screenBackground = Color(0xFFF0F0F0); // same as RegisterScreen

    return Scaffold(
      backgroundColor: screenBackground,
      body: Center(
        child: AnimatedBuilder(
          animation: _logoController,
          builder: (context, child) {
            return Opacity(
              opacity: _logoFadeIn.value,
              child: Transform.scale(
                scale: _logoScale.value,
                child: Image.asset(
                  'assets/images/powerpay_logo.png',
                  width: MediaQuery.of(context).size.width * 0.6,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
