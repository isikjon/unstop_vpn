import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
    this.logoWidth = 128,
  });

  final Widget trailing;
  final EdgeInsetsGeometry padding;
  final double logoWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/images/logoNew.svg',
              width: logoWidth,
              fit: BoxFit.contain,
            ),
            const Spacer(),
            trailing,
          ],
        ),
      ),
    );
  }
}
