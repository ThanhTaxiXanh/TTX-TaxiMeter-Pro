import 'package:flutter/material.dart';

/// Bien gioi han toc do toi da theo QCVN 41 (P.127): tron, vien do, nen trang,
/// chu so den.
class SpeedLimitSign extends StatelessWidget {
  const SpeedLimitSign({super.key, required this.kmh, this.size = 72});
  final int kmh;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('speed_limit_sign'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD32F2F), width: size * 0.11),
      ),
      child: Text(
        '$kmh',
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: size * (kmh >= 100 ? 0.3 : 0.4),
        ),
      ),
    );
  }
}
