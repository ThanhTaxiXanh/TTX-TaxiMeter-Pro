// Doc PMTiles v3 bang Dart thuan (khong mang). Chi doc header, thu muc, tile.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class PmTilesHeader {
  PmTilesHeader({
    required this.rootDirOffset,
    required this.rootDirLength,
    required this.metadataOffset,
    required this.metadataLength,
    required this.leafDirOffset,
    required this.leafDirLength,
    required this.tileDataOffset,
    required this.tileDataLength,
    required this.internalCompression,
    required this.tileCompression,
    required this.tileType,
    required this.minZoom,
    required this.maxZoom,
    required this.minLonE7,
    required this.minLatE7,
    required this.maxLonE7,
    required this.maxLatE7,
    required this.centerZoom,
    required this.centerLonE7,
    required this.centerLatE7,
  });

  factory PmTilesHeader.parse(Uint8List b) {
    if (b.length < 127 || utf8.decode(b.sublist(0, 7), allowMalformed: true) != 'PMTiles') {
      throw const FormatException('Khong phai file PMTiles');
    }
    if (b[7] != 3) throw FormatException('Chi ho tro PMTiles v3, file la v${b[7]}');
    final ByteData d = ByteData.sublistView(b);
    int u64(int o) => d.getUint64(o, Endian.little);
    int i32(int o) => d.getInt32(o, Endian.little);
    return PmTilesHeader(
      rootDirOffset: u64(8),
      rootDirLength: u64(16),
      metadataOffset: u64(24),
      metadataLength: u64(32),
      leafDirOffset: u64(40),
      leafDirLength: u64(48),
      tileDataOffset: u64(56),
      tileDataLength: u64(64),
      internalCompression: b[97],
      tileCompression: b[98],
      tileType: b[99],
      minZoom: b[100],
      maxZoom: b[101],
      minLonE7: i32(102),
      minLatE7: i32(106),
      maxLonE7: i32(110),
      maxLatE7: i32(114),
      centerZoom: b[118],
      centerLonE7: i32(119),
      centerLatE7: i32(123),
    );
  }

  final int rootDirOffset, rootDirLength;
  final int metadataOffset, metadataLength;
  final int leafDirOffset, leafDirLength;
  final int tileDataOffset, tileDataLength;

  /// 1 = khong nen, 2 = gzip (cac gia tri khac chua ho tro).
  final int internalCompression;
  final int tileCompression;

  /// 1 = MVT, 2 = PNG, 3 = JPEG, 4 = WEBP.
  final int tileType;
  final int minZoom, maxZoom;
  final int minLonE7, minLatE7, maxLonE7, maxLatE7;
  final int centerZoom, centerLonE7, centerLatE7;
}

class _Entry {
  _Entry(this.tileId, this.offset, this.length, this.runLength);
  final int tileId;
  final int offset;
  final int length;
  final int runLength;
}

/// Hilbert tile id theo dac ta PMTiles.
int zxyToTileId(int z, int x, int y) {
  if (z > 26) throw ArgumentError('zoom > 26');
  final int n = 1 << z;
  if (x < 0 || y < 0 || x >= n || y >= n) throw ArgumentError('x/y ngoai pham vi');
  int acc = 0;
  for (int i = 0; i < z; i++) {
    acc += (1 << i) * (1 << i);
  }
  int d = 0;
  int px = x, py = y;
  for (int s = n ~/ 2; s > 0; s ~/= 2) {
    final int rx = (px & s) > 0 ? 1 : 0;
    final int ry = (py & s) > 0 ? 1 : 0;
    d += s * s * ((3 * rx) ^ ry);
    if (ry == 0) {
      if (rx == 1) {
        px = n - 1 - px;
        py = n - 1 - py;
      }
      final int t = px;
      px = py;
      py = t;
    }
  }
  return acc + d;
}

class PmTilesReader {
  PmTilesReader._(this._file, this.header, this.metadata);

  final RandomAccessFile _file;
  final PmTilesHeader header;
  final Map<String, dynamic> metadata;
  final Map<int, List<_Entry>> _dirCache = <int, List<_Entry>>{};

  static Future<PmTilesReader> open(String path) async {
    final RandomAccessFile f = await File(path).open();
    try {
      await f.setPosition(0);
      final Uint8List hb = Uint8List.fromList(await f.read(127));
      final PmTilesHeader h = PmTilesHeader.parse(hb);
      final Uint8List meta = await _readRange(f, h.metadataOffset, h.metadataLength);
      Map<String, dynamic> m = <String, dynamic>{};
      if (meta.isNotEmpty) {
        try {
          final Object? j = jsonDecode(utf8.decode(_decompress(meta, h.internalCompression)));
          if (j is Map<String, dynamic>) m = j;
        } catch (_) {}
      }
      return PmTilesReader._(f, h, m);
    } catch (_) {
      await f.close();
      rethrow;
    }
  }

  Future<void> close() => _file.close();

  static Future<Uint8List> _readRange(RandomAccessFile f, int off, int len) async {
    await f.setPosition(off);
    return Uint8List.fromList(await f.read(len));
  }

  static Uint8List _decompress(Uint8List b, int kind) {
    if (kind == 1) return b;
    if (kind == 2) return Uint8List.fromList(gzip.decode(b));
    throw FormatException('Kieu nen noi bo chua ho tro: $kind');
  }

  static int _varint(Uint8List b, List<int> pos) {
    int result = 0;
    int shift = 0;
    while (true) {
      final int v = b[pos[0]++];
      result |= (v & 0x7f) << shift;
      if (v < 0x80) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('varint qua dai');
    }
  }

  List<_Entry> _parseDir(Uint8List raw) {
    final List<int> pos = <int>[0];
    final int n = _varint(raw, pos);
    final List<int> ids = List<int>.filled(n, 0);
    int last = 0;
    for (int i = 0; i < n; i++) {
      last += _varint(raw, pos);
      ids[i] = last;
    }
    final List<int> runs = List<int>.generate(n, (_) => _varint(raw, pos));
    final List<int> lens = List<int>.generate(n, (_) => _varint(raw, pos));
    final List<_Entry> out = <_Entry>[];
    int prevOff = 0, prevLen = 0;
    for (int i = 0; i < n; i++) {
      final int v = _varint(raw, pos);
      final int off = (v == 0 && i > 0) ? prevOff + prevLen : v - 1;
      out.add(_Entry(ids[i], off, lens[i], runs[i]));
      prevOff = off;
      prevLen = lens[i];
    }
    return out;
  }

  Future<List<_Entry>> _dir(int off, int len) async {
    final List<_Entry>? c = _dirCache[off];
    if (c != null) return c;
    final Uint8List raw = _decompress(await _readRange(_file, off, len), header.internalCompression);
    final List<_Entry> d = _parseDir(raw);
    if (_dirCache.length > 256) _dirCache.clear();
    _dirCache[off] = d;
    return d;
  }

  /// Byte cua tile (con nguyen nen theo header.tileCompression) hoac null.
  Future<Uint8List?> getTile(int z, int x, int y) async {
    if (z < header.minZoom || z > header.maxZoom) return null;
    final int id = zxyToTileId(z, x, y);
    int off = header.rootDirOffset;
    int len = header.rootDirLength;
    for (int depth = 0; depth < 4; depth++) {
      final List<_Entry> dir = await _dir(off, len);
      int lo = 0, hi = dir.length - 1, found = -1;
      while (lo <= hi) {
        final int mid = (lo + hi) >> 1;
        if (dir[mid].tileId <= id) {
          found = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      if (found < 0) return null;
      final _Entry e = dir[found];
      if (e.runLength > 0) {
        if (id >= e.tileId + e.runLength) return null;
        return _readRange(_file, header.tileDataOffset + e.offset, e.length);
      }
      off = header.leafDirOffset + e.offset;
      len = e.length;
    }
    return null;
  }
}
