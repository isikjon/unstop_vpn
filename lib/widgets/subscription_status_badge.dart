import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/subscription.dart';
import 'inset_shadow.dart';

class SubscriptionStatusBadge extends StatelessWidget {
  final Subscription subscription;
  final Duration trialLeft;

  const SubscriptionStatusBadge({
    super.key,
    required this.subscription,
    required this.trialLeft,
  });

  @override
  Widget build(BuildContext context) {
    if (subscription.isActive) {
      return _activeBadge();
    }
    return _trialBadge();
  }

  Widget _activeBadge() {
    final days = subscription.daysLeft;
    final text = days == null ? 'АКТИВНА' : '$days ДНЕЙ';
    final radius = BorderRadius.circular(16);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF11A9F4),
        borderRadius: radius,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: InsetShadow(borderRadius: radius)),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/icons/padpiska.svg',
                  width: 22,
                  height: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  text,
                  style: GoogleFonts.onest(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _trialBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1628),
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.manrope(
            color: const Color(0xFF628499),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          children: [
            const TextSpan(text: 'ПРОБНЫЙ ПЕРИОД: '),
            TextSpan(
              text: _formatDuration(trialLeft),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
