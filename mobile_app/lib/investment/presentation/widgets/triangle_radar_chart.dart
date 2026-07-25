import 'package:flutter/material.dart';


class TriangleRadarChart extends StatelessWidget {
  final double returnScore;   // 0-100
  final double safetyScore;   // 0-100
  final double liquidityScore; // 0-100

  const TriangleRadarChart({
    super.key,
    required this.returnScore,
    required this.safetyScore,
    required this.liquidityScore,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: CustomPaint(
        painter: _TriangleRadarPainter(
          returnScore: returnScore.clamp(0, 100),
          safetyScore: safetyScore.clamp(0, 100),
          liquidityScore: liquidityScore.clamp(0, 100),
        ),
      ),
    );
  }
}

class _TriangleRadarPainter extends CustomPainter {
  final double returnScore;
  final double safetyScore;
  final double liquidityScore;

  _TriangleRadarPainter({
    required this.returnScore,
    required this.safetyScore,
    required this.liquidityScore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    // Three corners of the triangle
    // Top: Return (0, -1)
    // Bottom-Right: Safety (0.866, 0.5)
    // Bottom-Left: Liquidity (-0.866, 0.5)
    final top = Offset(center.dx, center.dy - radius);
    final bottomRight = Offset(center.dx + radius * 0.866, center.dy + radius * 0.5);
    final bottomLeft = Offset(center.dx - radius * 0.866, center.dy + radius * 0.5);

    // Paint for the outer triangle
    final outerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final trianglePath = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();

    canvas.drawPath(trianglePath, outerPaint);

    // Draw grid lines (inner triangles at 33%, 66%)
    for (double scale in [0.33, 0.66]) {
      final innerTop = Offset(
        center.dx,
        center.dy - radius * scale,
      );
      final innerRight = Offset(
        center.dx + radius * 0.866 * scale,
        center.dy + radius * 0.5 * scale,
      );
      final innerLeft = Offset(
        center.dx - radius * 0.866 * scale,
        center.dy + radius * 0.5 * scale,
      );
      
      final innerPath = Path()
        ..moveTo(innerTop.dx, innerTop.dy)
        ..lineTo(innerRight.dx, innerRight.dy)
        ..lineTo(innerLeft.dx, innerLeft.dy)
        ..close();
      
      canvas.drawPath(innerPath, outerPaint);
    }

    // Draw labels
    _drawLabel(canvas, "Return", top.dx - 30, top.dy - 25);
    _drawLabel(canvas, "Safety", bottomRight.dx + 10, bottomRight.dy + 5);
    _drawLabel(canvas, "Liquidity", bottomLeft.dx - 50, bottomLeft.dy + 5);

    // Calculate data points based on scores (0-100 mapped to 0-radius)
    double returnScale = returnScore / 100;
    double safetyScale = safetyScore / 100;
    double liquidityScale = liquidityScore / 100;

    final returnPoint = Offset(center.dx, center.dy - radius * returnScale);
    final safetyPoint = Offset(
      center.dx + radius * 0.866 * safetyScale,
      center.dy + radius * 0.5 * safetyScale,
    );
    final liquidityPoint = Offset(
      center.dx - radius * 0.866 * liquidityScale,
      center.dy + radius * 0.5 * liquidityScale,
    );

    // Draw filled area
    final dataPath = Path()
      ..moveTo(returnPoint.dx, returnPoint.dy)
      ..lineTo(safetyPoint.dx, safetyPoint.dy)
      ..lineTo(liquidityPoint.dx, liquidityPoint.dy)
      ..close();

    final fillPaint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    canvas.drawPath(dataPath, fillPaint);

    // Draw data points
    final dotPaint = Paint()..color = Colors.blueAccent;

    canvas.drawCircle(returnPoint, 6, dotPaint);
    canvas.drawCircle(safetyPoint, 6, dotPaint);
    canvas.drawCircle(liquidityPoint, 6, dotPaint);

    // Draw center dot
    canvas.drawCircle(center, 3, Paint()..color = Colors.white.withValues(alpha: 0.3));
  }

  void _drawLabel(Canvas canvas, String text, double x, double y) {
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 10,
        fontWeight: FontWeight.w500,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}