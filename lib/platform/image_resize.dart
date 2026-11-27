import 'dart:typed_data';
import 'dart:ui' as ui;

/// Thu nho anh (giu ti le) de canh dai nhat <= [maxSide] px va ma hoa lai PNG; dung cho logo QR.
Future<Uint8List> shrinkToPng(Uint8List bytes, {int maxSide = 256}) async {
  final ui.Codec probe = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo pf = await probe.getNextFrame();
  final int w = pf.image.width, h = pf.image.height;
  pf.image.dispose();
  probe.dispose();
  final bool wide = w >= h;
  final ui.Codec c = await ui.instantiateImageCodec(
    bytes,
    targetWidth: wide ? (w > maxSide ? maxSide : w) : null,
    targetHeight: wide ? null : (h > maxSide ? maxSide : h),
  );
  final ui.FrameInfo f = await c.getNextFrame();
  final ByteData? d = await f.image.toByteData(format: ui.ImageByteFormat.png);
  f.image.dispose();
  c.dispose();
  if (d == null) throw const FormatException('Không đọc được ảnh');
  return d.buffer.asUint8List();
}
