import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:powerpay/screens/main_screen.dart';
import 'register_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _textController;
  late final AnimationController _bgController;

  late final Animation<double> _textFadeInLogo;
  late final Animation<double> _textFadeInText;
  late final Animation<double> _textFadeOut;
  late final Animation<double> _bgFadeOut;

  @override
  void initState() {
    super.initState();

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _textFadeInLogo = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.2, curve: Curves.easeIn),
      ),
    );

    _textFadeInText = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.24, 0.44, curve: Curves.easeIn),
      ),
    );

    _textFadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.8, 1.0, curve: Curves.easeOut),
      ),
    );

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _bgFadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _bgController, curve: Curves.easeOut),
    );

    _textController.forward();

    _textController.addListener(() {
      final elapsed = _textController.lastElapsedDuration?.inMilliseconds ?? 0;
      if (elapsed >= 2400 &&
          !_bgController.isAnimating &&
          !_bgController.isCompleted) {
        _bgController.forward();
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RegisterScreen(),
          AnimatedBuilder(
            animation: Listenable.merge([_textController, _bgController]),
            builder: (context, child) {
              final bgOpacity = _bgFadeOut.value;

              return IgnorePointer(
                ignoring: bgOpacity == 0,
                child: Opacity(
                  opacity: bgOpacity,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xFFbbbbf0),
                          Colors.white,
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity:
                          _textFadeInLogo.value * _textFadeOut.value,
                          child: Image.asset(
                            'assets/images/powerpay_logo.png',
                            width: MediaQuery.of(context).size.width * 0.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Opacity(
                          opacity:
                          _textFadeInText.value * _textFadeOut.value,
                          child: Text(
                            'Power Play',
                            style: GoogleFonts.bebasNeue(
                              color: Colors.black,
                              fontSize: 40,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
