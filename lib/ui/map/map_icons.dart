import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const int _px = 96;

Future<Uint8List> _render(void Function(Canvas c, double s) paint) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas c = Canvas(rec);
  paint(c, _px.toDouble());
  final ui.Image img = await rec.endRecording().toImage(_px, _px);
  final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.png);
  return d!.buffer.asUint8List();
}

void _glyph(Canvas c, double s, IconData icon, Color color, double size) {
  final TextPainter tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset((s - tp.width) / 2, (s - tp.height) / 2));
}

void _text(Canvas c, double s, String t, Color color, double size) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: t, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w900)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset((s - tp.width) / 2, (s - tp.height) / 2));
}

void _disc(Canvas c, double s, Color fill, Color ring, double ringW) {
  final Offset o = Offset(s / 2, s / 2);
  c.drawCircle(o, s / 2 - 2, Paint()..color = fill);
  c.drawCircle(o, s / 2 - 2 - ringW / 2, Paint()
    ..color = ring
    ..style = PaintingStyle.stroke
    ..strokeWidth = ringW);
}

void _square(Canvas c, double s, Color fill, Color border) {
  final RRect r = RRect.fromRectAndRadius(Rect.fromLTWH(4, 4, s - 8, s - 8), const Radius.circular(14));
  c.drawRRect(r, Paint()..color = fill);
  c.drawRRect(r, Paint()
    ..color = border
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5);
}

/// Ve bieu tuong PNG (96x96) cho `name`; null neu ten khong biet.
Future<Uint8List?> renderMapIcon(String name) async {
  if (name.startsWith('sign_speed_')) {
    final int? v = int.tryParse(name.substring(11));
    if (v == null) return null;
    return _render((Canvas c, double s) {
      _disc(c, s, Colors.white, const Color(0xFFD32F2F), 11);
      _text(c, s, '$v', Colors.black, v >= 100 ? 30 : 40);
    });
  }
  switch (name) {
    case 'sign_speedCamera':
    case 'sign_streetCamera':
      final bool speed = name == 'sign_speedCamera';
      return _render((Canvas c, double s) {
        _disc(c, s, const Color(0xFF263238), speed ? const Color(0xFFFF5252) : Colors.white, 7);
        _glyph(c, s, speed ? Icons.speed : Icons.videocam, Colors.white, 48);
      });
    case 'sign_tollBooth':
      return _render((Canvas c, double s) {
        _square(c, s, const Color(0xFF1565C0), Colors.white);
        _text(c, s, 'BOT', Colors.white, 30);
      });
    case 'sign_tunnel':
      return _render((Canvas c, double s) {
        _square(c, s, const Color(0xFF1565C0), Colors.white);
        _glyph(c, s, Icons.tunnel, Colors.white, 52);
      });
    case 'sign_restArea':
      return _render((Canvas c, double s) {
        _square(c, s, const Color(0xFF1565C0), Colors.white);
        _glyph(c, s, Icons.local_parking, Colors.white, 52);
      });
    case 'sign_builtUpStart':
      return _render((Canvas c, double s) {
        _square(c, s, const Color(0xFF1565C0), Colors.white);
        _glyph(c, s, Icons.location_city, Colors.white, 52);
      });
    case 'sign_builtUpEnd':
      return _render((Canvas c, double s) {
        _square(c, s, const Color(0xFF1565C0), Colors.white);
        _glyph(c, s, Icons.landscape, Colors.white, 52);
      });
    case 'sign_noOvertaking':
      return _render((Canvas c, double s) {
        _disc(c, s, Colors.white, const Color(0xFFD32F2F), 11);
        _glyph(c, s, Icons.sync_alt, Colors.black, 44);
      });
    case 'sign_p133':
      // Het cam vuot: nen trang, vach cheo den (QCVN: bien het hieu luc).
      return _render((Canvas c, double s) {
        _disc(c, s, Colors.white, Colors.black, 6);
        _glyph(c, s, Icons.sync_alt, const Color(0xFF9E9E9E), 44);
        c.drawLine(Offset(s * 0.24, s * 0.76), Offset(s * 0.76, s * 0.24),
            Paint()..color = Colors.black..strokeWidth = 7..strokeCap = StrokeCap.round);
      });
    case 'poi_fuel':
      return _render((Canvas c, double s) {
        _square(c, s, const Color(0xFF1565C0), Colors.white);
        _glyph(c, s, Icons.local_gas_station, Colors.white, 54);
      });
    case 'poi_ev':
      return _render((Canvas c, double s) {
        _square(c, s, const Color(0xFF2E7D32), Colors.white);
        _glyph(c, s, Icons.ev_station, Colors.white, 54);
      });
  }
  return null;
}
