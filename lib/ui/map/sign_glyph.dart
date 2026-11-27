import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hinh bieu tuong bien bao ve bang code (khong can file anh): bien cam (P) nen trang vien do
/// co gach cheo, P.102 nen do thanh trang, P.130/P.131 nen xanh gach do; bien hieu lenh (R) nen xanh.
/// Mã biển hiện bên trong để nhận diện; ảnh thật có thể thay thế sau.
class SignGlyph extends StatelessWidget {
  const SignGlyph({super.key, required this.code, required this.group, this.size = 56});
  final String code;
  final String group;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GlyphPainter(code, group)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.code, this.group);
  final String code;
  final String group;

  static const Color red = Color(0xFFD32F2F);
  static const Color blue = Color(0xFF1565C0);

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final Offset c = Offset(r, r);
    final Paint fill = Paint()..style = PaintingStyle.fill;
    if (group == 'R') {
      fill.color = blue;
      canvas.drawCircle(c, r, fill);
      canvas.drawCircle(c, r - 1.5, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white);
      _text(canvas, size, code, Colors.white);
      return;
    }
    final String n = code.replaceFirst('P.', '');
    final bool blueDisc = n.startsWith('130') || n.startsWith('131');
    fill.color = n == '102' ? red : (blueDisc ? blue : Colors.white);
    canvas.drawCircle(c, r, Paint()..color = red);
    canvas.drawCircle(c, r * 0.8, fill);
    if (n == '102') {
      canvas.drawRect(Rect.fromCenter(center: c, width: r * 1.3, height: r * 0.3), Paint()..color = Colors.white);
      return;
    }
    final Paint line = Paint()
      ..color = red
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round;
    if (n.startsWith('130')) {
      final double d = r * 0.5;
      canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), line);
      canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), line);
      return;
    }
    if (n != '101') {
      final double d = r * math.sqrt1_2 * 0.8;
      canvas.drawLine(c + Offset(-d, d), c + Offset(d, -d), line);
    }
    _text(canvas, size, n, blueDisc ? Colors.white : Colors.black);
  }

  void _text(Canvas canvas, Size size, String t, Color color) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: color, fontSize: size.width * (t.length > 4 ? 0.2 : 0.26), fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.8);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.code != code || old.group != group;
}
