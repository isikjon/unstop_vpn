import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class LogoWidget extends StatelessWidget {
  final double size;
  const LogoWidget({super.key, this.size = 60});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.25),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1F3C), Color(0xFF0A1525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: size * 0.4,
            spreadRadius: size * 0.05,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // U letter
          ShaderMask(
            shaderCallback: (bounds) =>
                AppColors.gradientPrimary.createShader(bounds),
            child: Text(
              'U',
              style: TextStyle(
                fontSize: size * 0.52,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1,
              ),
            ),
          ),
          // Rocket
          Positioned(
            right: size * 0.12,
            bottom: size * 0.12,
            child: Transform.rotate(
              angle: -0.6,
              child: Icon(
                Icons.rocket_launch_rounded,
                size: size * 0.28,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
