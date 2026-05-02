import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../widgets/logo_widget.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;

  void _maybeNavigate() {
    if (_navigated) return;
    _navigated = true;

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeNavigate());

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientBg),
        child: Stack(
          children: [
            ...List.generate(30, (i) {
              final x = (i * 137.5) % 1.0;
              final y = (i * 97.3) % 1.0;
              final size = (i % 3 + 1).toDouble();
              return Positioned(
                left: MediaQuery.of(context).size.width * x,
                top: MediaQuery.of(context).size.height * y,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.3 + (i % 5) * 0.1),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .fadeIn(delay: Duration(milliseconds: i * 80))
                    .then()
                    .fadeOut(duration: 1200.ms)
                    .then()
                    .fadeIn(duration: 1200.ms),
              );
            }),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const LogoWidget(size: 120)
                      .animate()
                      .scale(
                        begin: const Offset(0.5, 0.5),
                        end: const Offset(1, 1),
                        duration: 600.ms,
                        curve: Curves.easeOutBack,
                      )
                      .fadeIn(duration: 400.ms),
                  const SizedBox(height: 24),
                  ShaderMask(
                    shaderCallback: (bounds) =>
                        AppColors.gradientPrimary.createShader(bounds),
                    child: const Text(
                      'UNSTOP VPN',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 4,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 400.ms, duration: 500.ms)
                      .slideY(begin: 0.3, end: 0, delay: 400.ms, duration: 500.ms),
                  const SizedBox(height: 8),
                  Text(
                    'Fast. Secure. Unstoppable.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      letterSpacing: 1,
                    ),
                  ).animate().fadeIn(delay: 700.ms, duration: 500.ms),
                ],
              ),
            ),
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      backgroundColor: AppColors.border,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 3,
                    ),
                  ),
                ).animate().fadeIn(delay: 900.ms, duration: 400.ms),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
