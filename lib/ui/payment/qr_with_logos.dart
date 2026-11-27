import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Ma QR co logo o giua (dung muc sua loi cao) va logo o duoi ma.
class QrWithLogos extends StatelessWidget {
  const QrWithLogos({super.key, required this.data, this.size = 240, this.centerLogo, this.bottomLogo});

  final String data;
  final double size;
  final Uint8List? centerLogo;
  final Uint8List? bottomLogo;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          QrImageView(
            key: const Key('qr'),
            data: data,
            size: size,
            backgroundColor: Colors.white,
            // Co logo giua thi dung muc H de van quet duoc.
            errorCorrectionLevel: centerLogo == null ? QrErrorCorrectLevel.M : QrErrorCorrectLevel.H,
            embeddedImage: centerLogo == null ? null : MemoryImage(centerLogo!),
            embeddedImageStyle: EmbeddedImageStyle(size: Size(size * 0.2, size * 0.2)),
          ),
          if (bottomLogo != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Image.memory(bottomLogo!, key: const Key('qr_bottom_logo'), height: size * 0.28, fit: BoxFit.contain),
            ),
        ],
      ),
    );
  }
}
