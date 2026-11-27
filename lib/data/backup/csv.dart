/// Escape mot o CSV (RFC 4180): bao dau nhay khi co dau phay, nhay kep, xuong dong.
String csvCell(Object? v) {
  final String s = v == null ? '' : v.toString();
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Ghep bang CSV, co BOM UTF-8 de Excel doc dung tieng Viet.
String buildCsv(List<String> header, List<List<Object?>> rows) {
  final StringBuffer b = StringBuffer('﻿');
  b.writeln(header.map(csvCell).join(','));
  for (final List<Object?> r in rows) {
    b.writeln(r.map(csvCell).join(','));
  }
  return b.toString();
}
