import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Logo Study Timer dessiné en code (identique à assets/images/logo.svg).
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _LogoPainter()),
  );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 512;
    Offset o(double x, double y) => Offset(x * k, y * k);
    final white = Paint()..color = Colors.white;

    // Fond arrondi en dégradé
    final bg = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(112 * k),
    );
    canvas.drawRRect(
      bg,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
        ).createShader(Offset.zero & size),
    );

    // Bouton du chronomètre
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(226 * k, 62 * k, 60 * k, 30 * k),
        Radius.circular(10 * k),
      ),
      white,
    );
    canvas.drawRect(Rect.fromLTWH(246 * k, 86 * k, 20 * k, 30 * k), white);

    // Cadran
    final c = o(256, 288);
    canvas.drawCircle(
      c,
      158 * k,
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );
    final ring = Rect.fromCircle(center: c, radius: 132 * k);
    canvas.drawCircle(
      c,
      132 * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20 * k
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.drawArc(
      ring,
      -math.pi / 2,
      math.pi * 2 * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20 * k
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF34D399), Color(0xFF22D3EE)],
        ).createShader(ring),
    );

    // Livre ouvert
    final left = Path()
      ..moveTo(256 * k, 262 * k)
      ..cubicTo(232 * k, 244 * k, 200 * k, 242 * k, 176 * k, 250 * k)
      ..lineTo(176 * k, 332 * k)
      ..cubicTo(200 * k, 324 * k, 232 * k, 326 * k, 256 * k, 344 * k)
      ..close();
    final right = Path()
      ..moveTo(256 * k, 262 * k)
      ..cubicTo(280 * k, 244 * k, 312 * k, 242 * k, 336 * k, 250 * k)
      ..lineTo(336 * k, 332 * k)
      ..cubicTo(312 * k, 324 * k, 280 * k, 326 * k, 256 * k, 344 * k)
      ..close();
    canvas.drawPath(left, white);
    canvas.drawPath(
      right,
      Paint()..color = Colors.white.withValues(alpha: 0.82),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
