import 'package:flutter/material.dart';

class ValetrixVPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw stylized V
    final path = Path();
    path.moveTo(size.width * 0.1, size.height * 0.1);
    path.lineTo(size.width * 0.5, size.height * 0.9);
    path.lineTo(size.width * 0.9, size.height * 0.1);
    canvas.drawPath(path, paint);

    // Circuit dots
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.1), 4, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.9), 4, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.1), 4, dotPaint);
    // Optionally add more circuit lines/dots for effect
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}