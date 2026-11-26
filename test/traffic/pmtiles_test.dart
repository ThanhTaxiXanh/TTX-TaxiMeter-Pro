import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/data/map/local_tile_server.dart';
import 'package:ttx/data/map/map_style.dart';
import 'package:ttx/data/map/pmtiles_reader.dart';

// ---- Bo ghi PMTiles v3 toi thieu (chi cho test) ----
List<int> varint(int v) {
  final List<int> o = <int>[];
  while (v >= 0x80) {
    o.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  o.add(v);
  return o;
}

class E {
  E(this.id, this.offset, this.length, this.run);
  final int id, offset, length, run;
}

Uint8List dirBytes(List<E> es, {bool gz = false}) {
  final List<int> o = <int>[...varint(es.length)];
  int last = 0;
  for (final E e in es) {
    o.addAll(varint(e.id - last));
    last = e.id;
  }
  for (final E e in es) {
    o.addAll(varint(e.run));
  }
  for (final E e in es) {
    o.addAll(varint(e.length));
  }
  for (int i = 0; i < es.length; i++) {
    o.addAll(varint(i > 0 && es[i].offset == es[i - 1].offset + es[i - 1].length ? 0 : es[i].offset + 1));
  }
  return Uint8List.fromList(gz ? gzip.encode(o) : o);
}

Uint8List buildPm({
  required List<E> root,
  required Uint8List tileData,
  Uint8List? leaf,
  required Map<String, dynamic> meta,
  bool gz = false,
  int tileCompression = 1,
  int minZ = 0,
  int maxZ = 5,
}) {
  final Uint8List rootB = dirBytes(root, gz: gz);
  final Uint8List metaB = Uint8List.fromList(
      gz ? gzip.encode(utf8.encode(jsonEncode(meta))) : utf8.encode(jsonEncode(meta)));
  final Uint8List leafB = leaf ?? Uint8List(0);
  const int hdr = 127;
  final int rootOff = hdr;
  final int metaOff = rootOff + rootB.length;
  final int leafOff = metaOff + metaB.length;
  final int dataOff = leafOff + leafB.length;
  final ByteData h = ByteData(hdr);
  final List<int> magic = utf8.encode('PMTiles');
  for (int i = 0; i < 7; i++) {
    h.setUint8(i, magic[i]);
  }
  h.setUint8(7, 3);
  h.setUint64(8, rootOff, Endian.little);
  h.setUint64(16, rootB.length, Endian.little);
  h.setUint64(24, metaOff, Endian.little);
  h.setUint64(32, metaB.length, Endian.little);
  h.setUint64(40, leafOff, Endian.little);
  h.setUint64(48, leafB.length, Endian.little);
  h.setUint64(56, dataOff, Endian.little);
  h.setUint64(64, tileData.length, Endian.little);
  h.setUint8(96, 1);
  h.setUint8(97, gz ? 2 : 1);
  h.setUint8(98, tileCompression);
  h.setUint8(99, 1);
  h.setUint8(100, minZ);
  h.setUint8(101, maxZ);
  h.setInt32(102, 1020000000, Endian.little);
  h.setInt32(106, 80000000, Endian.little);
  h.setInt32(110, 1090000000, Endian.little);
  h.setInt32(114, 233000000, Endian.little);
  h.setUint8(118, 10);
  h.setInt32(119, 1060000000, Endian.little);
  h.setInt32(123, 210000000, Endian.little);
  return Uint8List.fromList(<int>[
    ...h.buffer.asUint8List(), ...rootB, ...metaB, ...leafB, ...tileData,
  ]);
}

void main() {
  test('tile id Hilbert khop dac ta', () {
    expect(zxyToTileId(0, 0, 0), 0);
    expect(<int>[
      zxyToTileId(1, 0, 0), zxyToTileId(1, 0, 1), zxyToTileId(1, 1, 1), zxyToTileId(1, 1, 0),
    ], <int>[1, 2, 3, 4]);
    expect(zxyToTileId(2, 0, 0), 5);
    expect(zxyToTileId(2, 3, 0), 20);
    expect(() => zxyToTileId(1, 2, 0), throwsArgumentError);
  });

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pmt'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<PmTilesReader> openBytes(Uint8List b) async {
    final File f = File('${tmp.path}/t.pmtiles')..writeAsBytesSync(b);
    return PmTilesReader.open(f.path);
  }

  test('doc header, metadata, tile trong thu muc goc (khong nen va gzip)', () async {
    for (final bool gz in <bool>[false, true]) {
      final Uint8List data = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7]);
      // id0 (0/0/0): 3 byte; id1..id2 chay chung 4 byte (run=2): z1 (0,0),(0,1)
      final Uint8List pm = buildPm(
        root: <E>[E(0, 0, 3, 1), E(1, 3, 4, 2)],
        tileData: data,
        meta: <String, dynamic>{'vector_layers': <Map<String, String>>[<String, String>{'id': 'roads'}]},
        gz: gz,
      );
      final PmTilesReader r = await openBytes(pm);
      expect(r.header.minZoom, 0);
      expect(r.header.maxZoom, 5);
      expect(r.header.centerLatE7, 210000000);
      expect(r.metadata['vector_layers'], isNotEmpty);
      expect(await r.getTile(0, 0, 0), <int>[1, 2, 3]);
      expect(await r.getTile(1, 0, 0), <int>[4, 5, 6, 7]);
      expect(await r.getTile(1, 0, 1), <int>[4, 5, 6, 7]); // cung run
      expect(await r.getTile(1, 1, 1), isNull);
      expect(await r.getTile(9, 0, 0), isNull); // ngoai zoom
      await r.close();
    }
  });

  test('thu muc la (leaf)', () async {
    final Uint8List leaf = dirBytes(<E>[E(1, 0, 2, 1), E(3, 2, 3, 1)]);
    final Uint8List data = Uint8List.fromList(<int>[9, 9, 8, 8, 8]);
    final Uint8List pm = buildPm(
      root: <E>[E(0, 0, 0, 0)].map((E e) => E(1, 0, leaf.length, 0)).toList(),
      tileData: data,
      leaf: leaf,
      meta: <String, dynamic>{},
    );
    final PmTilesReader r = await openBytes(pm);
    expect(await r.getTile(1, 0, 0), <int>[9, 9]);
    expect(await r.getTile(1, 1, 1), <int>[8, 8, 8]);
    expect(await r.getTile(1, 0, 1), isNull); // id 2 khong co
    await r.close();
  });

  test('file khong phai PMTiles / sai phien ban bi tu choi', () async {
    expect(() => openBytes(Uint8List(200)), throwsFormatException);
    final Uint8List bad = Uint8List(200)..setAll(0, utf8.encode('PMTiles'));
    bad[7] = 2;
    expect(() => openBytes(bad), throwsFormatException);
  });

  test('may chu tile cuc bo: style, tile, 204, gzip header', () async {
    final Uint8List data = Uint8List.fromList(<int>[1, 2, 3]);
    final PmTilesReader r = await openBytes(buildPm(
      root: <E>[E(0, 0, 3, 1)],
      tileData: data,
      tileCompression: 2,
      meta: <String, dynamic>{
        'vector_layers': <Map<String, String>>[
          <String, String>{'id': 'water'},
          <String, String>{'id': 'roads'},
          <String, String>{'id': 'places'},
        ],
      },
    ));
    final LocalHttpTileServer s = await LocalHttpTileServer.start(r);
    final HttpClient c = HttpClient()..autoUncompress = false;
    try {
      Future<HttpClientResponse> get(String p) async =>
          (await c.getUrl(Uri.parse('http://127.0.0.1:${s.port}$p'))).close();

      final HttpClientResponse t = await get('/tiles/0/0/0.mvt');
      expect(t.statusCode, 200);
      expect(t.headers.value('content-encoding'), 'gzip');
      expect(t.headers.contentType?.mimeType, 'application/x-protobuf');
      expect(await t.fold<List<int>>(<int>[], (List<int> a, List<int> b) => a..addAll(b)), <int>[1, 2, 3]);

      expect((await get('/tiles/1/1/1.mvt')..drain<void>()).statusCode, 204);
      expect((await get('/tiles/1/9/9.mvt')..drain<void>()).statusCode, 400);
      expect((await get('/nope')..drain<void>()).statusCode, 404);

      final HttpClientResponse st = await get('/style.json');
      final Map<String, dynamic> style =
          jsonDecode(await st.transform(utf8.decoder).join()) as Map<String, dynamic>;
      expect(style['version'], 8);
      final String tiles = ((style['sources'] as Map<String, dynamic>)['v'] as Map<String, dynamic>)['tiles'][0] as String;
      expect(tiles.startsWith('http://127.0.0.1:${s.port}/tiles/'), isTrue);
      final List<dynamic> layers = style['layers'] as List<dynamic>;
      final Set<String> ids = layers.map((dynamic l) => (l as Map<String, dynamic>)['id'] as String).toSet();
      expect(ids, containsAll(<String>['background', 'water-fill', 'roads-line']));
      expect(ids.any((String i) => i.startsWith('places')), isFalse);
    } finally {
      c.close(force: true);
      await s.stop();
      await r.close();
    }
  });

  test('style raster khi tile la PNG', () {
    final PmTilesHeader h = PmTilesHeader.parse(buildPm(
      root: <E>[E(0, 0, 1, 1)],
      tileData: Uint8List(1),
      meta: <String, dynamic>{},
    ).sublist(0, 127)..[99] = 2);
    final Map<String, dynamic> st =
        jsonDecode(buildMapStyleJson(port: 1, header: h, metadata: <String, dynamic>{})) as Map<String, dynamic>;
    expect(((st['sources'] as Map<String, dynamic>)['v'] as Map<String, dynamic>)['type'], 'raster');
  });
}
