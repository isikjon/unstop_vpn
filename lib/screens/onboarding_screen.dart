import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../widgets/inset_shadow.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('onboarding_done') ?? false);
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF05080F),
      body: Stack(
        children: [
          // ── Background image (top ~68% of screen) ──────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.68,
            child: Image.asset(
              'assets/images/onboard_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),

          // ── Gradient fade between image and bottom card ─────────────────
          Positioned(
            top: size.height * 0.54,
            left: 0,
            right: 0,
            height: size.height * 0.18,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFF05080F)],
                ),
              ),
            ),
          ),

          // ── Bottom content card ─────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF05080F),
                borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
              ),
              padding: EdgeInsets.fromLTRB(
                24,
                32,
                24,
                MediaQuery.of(context).padding.bottom + 40,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                        'Интернет без\nограничений',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                          letterSpacing: -0.5,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 500.ms)
                      .slideY(
                        begin: 0.2,
                        end: 0,
                        delay: 200.ms,
                        duration: 500.ms,
                        curve: Curves.easeOut,
                      ),

                  const SizedBox(height: 16),

                  // Subtitle
                  Text(
                        'Добро пожаловать в UNSTOP VPN.\nНикаких ограничений — только свободный интернет.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF7A8FAE),
                          height: 1.6,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 350.ms, duration: 500.ms)
                      .slideY(
                        begin: 0.2,
                        end: 0,
                        delay: 350.ms,
                        duration: 500.ms,
                        curve: Curves.easeOut,
                      ),

                  const SizedBox(height: 36),

                  // Button
                  _OnboardButton(
                        onTap: () async {
                          await OnboardingScreen.markDone();
                          if (context.mounted) {
                            Navigator.pushReplacementNamed(context, '/home');
                          }
                        },
                      )
                      .animate()
                      .fadeIn(delay: 500.ms, duration: 500.ms)
                      .slideY(
                        begin: 0.3,
                        end: 0,
                        delay: 500.ms,
                        duration: 500.ms,
                        curve: Curves.easeOut,
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Button with inset highlight ──────────────────────────────────────────────
class _OnboardButton extends StatefulWidget {
  final VoidCallback onTap;
  const _OnboardButton({required this.onTap});

  @override
  State<_OnboardButton> createState() => _OnboardButtonState();
}

class _OnboardButtonState extends State<_OnboardButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          clipBehavior: Clip.antiAlias,
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF32B5FF), Color(0xFF169CF1), Color(0xFF0B88D8)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00A1FF).withValues(alpha: 0.45),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: InsetShadow(
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
              ),
              Center(
                child: Text(
                  'Открыть доступ в интернет',
                  style: AppTextStyles.button,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
