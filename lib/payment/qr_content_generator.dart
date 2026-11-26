// Noi dung chuyen khoan: TTX + YYMMDD + NNN. THUAN: gio truyen tu ngoai vao.

/// YYMMDD theo gio dia phuong (offset phut so voi UTC), chi dung so nguyen.
String localYymmdd(int tsMs, {int offsetMinutes = 420}) {
  final int localMs = tsMs + offsetMinutes * 60000;
  // Ngay (so ngay tu 1970-01-01), floor cho gia tri am.
  int days = localMs ~/ 86400000;
  if (localMs % 86400000 < 0) days -= 1;
  // Civil-from-days (Howard Hinnant).
  final int z = days + 719468;
  final int era = (z >= 0 ? z : z - 146096) ~/ 146097;
  final int doe = z - era * 146097;
  final int yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
  int y = yoe + era * 400;
  final int doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
  final int mp = (5 * doy + 2) ~/ 153;
  final int d = doy - (153 * mp + 2) ~/ 5 + 1;
  final int m = mp < 10 ? mp + 3 : mp - 9;
  if (m <= 2) y += 1;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(y % 100)}${two(m)}${two(d)}';
}

/// [sequenceInDay] 1..999 (so thu tu chuyen trong ngay).
String transferContent({
  required int tripStartedAtMs,
  required int sequenceInDay,
  int offsetMinutes = 420,
}) {
  if (sequenceInDay < 1 || sequenceInDay > 999) {
    throw ArgumentError('So thu tu chuyen trong ngay phai 1..999');
  }
  return 'TTX${localYymmdd(tripStartedAtMs, offsetMinutes: offsetMinutes)}'
      '${sequenceInDay.toString().padLeft(3, '0')}';
}
