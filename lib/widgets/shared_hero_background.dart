import 'package:flutter/material.dart';

class SharedHeroBackground extends StatelessWidget {
  static const assetPath = 'assets/images/onboard_bg.png';

  final double heightFactor;

  const SharedHeroBackground({super.key, this.heightFactor = 0.68});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: screenHeight * heightFactor,
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      ),
    );
  }
}
