import 'dart:io';
import 'dart:typed_data';

import 'map_style.dart';
import 'pmtiles_reader.dart';
import 'style_adapter.dart';

/// May chu HTTP chi lang nghe 127.0.0.1 de MapLibre doc PMTiles offline.
///   GET /style.json                 -> style MapLibre
///   GET /tiles/{z}/{x}/{y}.{mvt|png|jpg} -> tile (204 neu khong co)
///   GET /health
class LocalHttpTileServer {
  LocalHttpTileServer._(this._server, this._reader, this._baseStyles);

  final HttpServer _server;
  final PmTilesReader _reader;

  /// Style goc theo khoa '<kieu>-<day|night>' (kieu: standard | modern).
  final Map<String, String> _baseStyles;

  int get port => _server.port;
  String get styleUrl => styleUrlFor(light: false);

  /// Style sang/toi + kieu (cung may chu, doi bang tham so ?theme= va ?family=).
  String styleUrlFor({required bool light, String family = 'standard'}) =>
      'http://127.0.0.1:$port/style.json?theme=${light ? 'light' : 'dark'}&family=$family';

  static Future<LocalHttpTileServer> start(PmTilesReader reader,
      {Map<String, String> baseStyles = const <String, String>{}}) async {
    final HttpServer s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final LocalHttpTileServer self = LocalHttpTileServer._(s, reader, baseStyles);
    s.listen(self._handle);
    return self;
  }

  Future<void> stop() => _server.close(force: true);

  static String _contentType(int tileType) {
    switch (tileType) {
      case 1:
        return 'application/x-protobuf';
      case 2:
        return 'image/png';
      case 3:
        return 'image/jpeg';
      case 4:
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  String _style(bool light, String family) {
    final PmTilesHeader h = _reader.header;
    final String? base = _baseStyles['$family-${light ? 'day' : 'night'}'];
    if (base != null && h.tileType == 1) {
      final Object? vl = _reader.metadata['vector_layers'];
      final Set<String> ids = <String>{
        if (vl is List)
          for (final Object? e in vl)
            if (e is Map && e['id'] is String) e['id'] as String,
      };
      try {
        final String? out = adaptStyleForOffline(
            styleJson: base, port: port, minZoom: h.minZoom, maxZoom: h.maxZoom, availableLayers: ids);
        if (out != null) return out;
      } catch (_) {}
    }
    return buildMapStyleJson(port: port, header: h, metadata: _reader.metadata, light: light);
  }

  Future<void> _handle(HttpRequest req) async {
    final HttpResponse res = req.response;
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        res.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final List<String> seg = req.uri.pathSegments;
      if (seg.length == 1 && seg[0] == 'health') {
        res.write('ok');
      } else if (seg.length == 1 && seg[0] == 'style.json') {
        res.headers.contentType = ContentType.json;
        res.write(_style(req.uri.queryParameters['theme'] == 'light', req.uri.queryParameters['family'] ?? 'standard'));
      } else if (seg.length == 4 && seg[0] == 'tiles') {
        final int? z = int.tryParse(seg[1]);
        final int? x = int.tryParse(seg[2]);
        final int? y = int.tryParse(seg[3].split('.').first);
        if (z == null || x == null || y == null || z < 0 || z > 26) {
          res.statusCode = HttpStatus.badRequest;
        } else if (x < 0 || y < 0 || x >= (1 << z) || y >= (1 << z)) {
          res.statusCode = HttpStatus.badRequest;
        } else {
          final Uint8List? t = await _reader.getTile(z, x, y);
          if (t == null) {
            res.statusCode = HttpStatus.noContent;
          } else {
            res.headers.set(HttpHeaders.contentTypeHeader, _contentType(_reader.header.tileType));
            if (_reader.header.tileCompression == 2) {
              res.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
            }
            res.headers.set(HttpHeaders.cacheControlHeader, 'max-age=86400');
            res.contentLength = t.length;
            if (req.method == 'GET') res.add(t);
          }
        }
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      res.statusCode = HttpStatus.internalServerError;
    } finally {
      await res.close();
    }
  }
}
