// Gio dia phuong bang so nguyen (khong DateTime). Mac dinh UTC+7 (Viet Nam).
const int vnOffsetMinutes = 420;
const int _dayMs = 86400000;

class LocalDateTime {
  const LocalDateTime(this.year, this.month, this.day, this.hour, this.minute);
  final int year, month, day, hour, minute;
}

LocalDateTime localDateTime(int tsMs, {int offsetMinutes = vnOffsetMinutes}) {
  final int local = tsMs + offsetMinutes * 60000;
  int days = local ~/ _dayMs;
  int rem = local % _dayMs;
  if (rem < 0) {
    rem += _dayMs;
    days -= 1;
  }
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
  return LocalDateTime(y, m, d, rem ~/ 3600000, (rem % 3600000) ~/ 60000);
}

/// 00:00 gio dia phuong cua ngay chua [tsMs], tinh bang ms UTC.
int localDayStartMs(int tsMs, {int offsetMinutes = vnOffsetMinutes}) {
  final int local = tsMs + offsetMinutes * 60000;
  int d = local ~/ _dayMs;
  if (local % _dayMs < 0) d -= 1;
  return d * _dayMs - offsetMinutes * 60000;
}

/// 00:00 ngay 1 cua thang chua [tsMs].
int localMonthStartMs(int tsMs, {int offsetMinutes = vnOffsetMinutes}) {
  final LocalDateTime t = localDateTime(tsMs, offsetMinutes: offsetMinutes);
  return localDayStartMs(tsMs, offsetMinutes: offsetMinutes) - (t.day - 1) * _dayMs;
}

String two(int v) => v.toString().padLeft(2, '0');

/// "26/11/2026 08:40"
String formatLocalDateTime(int tsMs, {int offsetMinutes = vnOffsetMinutes}) {
  final LocalDateTime t = localDateTime(tsMs, offsetMinutes: offsetMinutes);
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}
