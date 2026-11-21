import 'dart:math' as math;

import 'package:flutter/material.dart';

class RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final Color track;
  RingPainter(this.progress, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final r = Rect.fromCircle(
      center: rect.center,
      radius: (size.width - stroke) / 2,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, base..color = track);
    if (progress > 0) {
      canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        base..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
