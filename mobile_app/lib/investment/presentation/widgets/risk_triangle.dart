import 'package:flutter/material.dart';

class RiskTriangle extends StatelessWidget {
  final double riskScore;
  const RiskTriangle({super.key, required this.riskScore});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200, height: 180,
      child: CustomPaint(painter: _TrianglePainter(riskScore)),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final double riskScore;
  _TrianglePainter(this.riskScore);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.grey.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 2;
    final top = Offset(size.width / 2, 0);
    final left = Offset(0, size.height);
    final right = Offset(size.width, size.height);

    canvas.drawPath(Path()..moveTo(top.dx, top.dy)..lineTo(left.dx, left.dy)..lineTo(right.dx, right.dy)..close(), paint);

    _text(canvas, "Return", top.dx - 20, top.dy - 20);
    _text(canvas, "Safety", left.dx - 20, left.dy + 5);
    _text(canvas, "Risk", right.dx, right.dy + 5);

    double riskFactor = (riskScore / 100).clamp(0.0, 1.0);
    double px = (1 - riskFactor) * left.dx + riskFactor * right.dx;
    double py = (1 - riskFactor) * left.dy + riskFactor * (top.dy + 40);

    canvas.drawCircle(Offset(px, py), 8, Paint()..color = riskScore > 50 ? Colors.redAccent : Colors.greenAccent);
  }

  void _text(Canvas c, String t, double x, double y) {
    TextPainter(text: TextSpan(text: t, style: const TextStyle(color: Colors.white, fontSize: 12)), textDirection: TextDirection.ltr)
      ..layout()..paint(c, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}