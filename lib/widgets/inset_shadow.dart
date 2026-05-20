import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class InsetShadow extends StatelessWidget {
  final BorderRadius borderRadius;

  const InsetShadow({super.key, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _InsetShadowPainter(borderRadius: borderRadius),
        size: Size.infinite,
      ),
    );
  }
}

class _InsetShadowPainter extends CustomPainter {
  final BorderRadius borderRadius;

  const _InsetShadowPainter({required this.borderRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final rrect = borderRadius.toRRect(bounds);

    canvas.save();
    canvas.clipRRect(rrect);

    final topPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(0, 10),
        const [Color(0x40FFFFFF), Color(0x00FFFFFF)],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 10), topPaint);

    final leftPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(10, 0),
        const [Color(0x40FFFFFF), Color(0x00FFFFFF)],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, 10, size.height), leftPaint);

    final cornerPaint = Paint()
      ..shader = ui.Gradient.radial(const Offset(0, 0), 30, const [
        Color(0x40FFFFFF),
        Color(0x00FFFFFF),
      ]);
    canvas.drawRect(Rect.fromLTWH(0, 0, 32, 32), cornerPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InsetShadowPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius;
  }
}
