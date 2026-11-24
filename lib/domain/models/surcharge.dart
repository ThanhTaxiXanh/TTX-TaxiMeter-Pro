// Phu phi, dieu kien thoi gian va ngu canh danh gia. Chi so nguyen.
//
// Mui gio: chi ho tro bang co dinh (Viet Nam khong co gio mua he). Mui gio la
// lang -> ArgumentError ngay khi doc config (hong nhanh, khong doan).

enum SurchargeKind { multiplier, fixed }

const Map<String, int> _tzOffsetMinutes = <String, int>{
  'Asia/Ho_Chi_Minh': 420,
  'Asia/Saigon': 420,
  'UTC': 0,
};

int tzOffsetMinutes(String timezone) {
  final int? v = _tzOffsetMinutes[timezone];
  if (v == null) {
    throw FormatException('Mui gio khong ho tro: $timezone');
  }
  return v;
}

/// Ngu canh danh gia phu phi cua mot chuyen (truyen tu ngoai vao, khong doc
/// dong ho he thong).
class SurchargeContexts {
  const SurchargeContexts({
    required this.tripStartTimeMs,
    required this.timezone,
    required this.vehicleType,
    required this.geofenceMatches,
  });

  factory SurchargeContexts.fromJson(dynamic json) {
    final Map<String, dynamic> m = json as Map<String, dynamic>;
    final List<dynamic> geo =
        (m['geofenceMatches'] as List<dynamic>?) ?? const <dynamic>[];
    return SurchargeContexts(
      tripStartTimeMs: m['tripStartTimeMs'] as int,
      timezone: (m['timezone'] as String?) ?? 'Asia/Ho_Chi_Minh',
      vehicleType: (m['vehicleType'] as String?) ?? '',
      geofenceMatches: geo.map((dynamic e) => e as String).toList(),
    );
  }

  final int tripStartTimeMs;
  final String timezone;
  final String vehicleType;
  final List<String> geofenceMatches;
}

class TimeOfDayRange {
  const TimeOfDayRange(this.fromMinute, this.toMinute);

  final int fromMinute;
  final int toMinute;
}

int _parseHhmm(String s) {
  final List<String> p = s.split(':');
  if (p.length != 2) throw FormatException('Gio sai dinh dang HH:MM: $s');
  final int h = int.parse(p[0]);
  final int m = int.parse(p[1]);
  if (h < 0 || h > 24 || m < 0 || m > 59) {
    throw FormatException('Gio ngoai mien: $s');
  }
  return h * 60 + m;
}

int _floorDiv(int a, int b) => (a - (a % b)) ~/ b;

/// Dieu kien khung gio. Khoang [from, to); neu from > to thi vat qua nua dem
/// (vd 22:00-05:00). `daysOfWeek` theo ISO (1 = thu hai ... 7 = chu nhat);
/// phan sau nua dem tinh theo ngay bat dau khung gio.
class TimeRangeCondition {
  TimeRangeCondition({
    required this.timezone,
    required this.ranges,
    required this.daysOfWeek,
  }) : offsetMinutes = tzOffsetMinutes(timezone);

  factory TimeRangeCondition.fromJson(Map<String, dynamic> m) {
    final List<dynamic> rs = m['ranges'] as List<dynamic>;
    final List<TimeOfDayRange> ranges = <TimeOfDayRange>[];
    for (final dynamic r in rs) {
      final Map<String, dynamic> rm = r as Map<String, dynamic>;
      final int from = _parseHhmm(rm['from'] as String);
      final int to = _parseHhmm(rm['to'] as String);
      if (from == to) {
        throw FormatException('Khung gio rong/mo ho: ${rm['from']}-${rm['to']}');
      }
      ranges.add(TimeOfDayRange(from, to));
    }
    final List<dynamic>? days = m['daysOfWeek'] as List<dynamic>?;
    return TimeRangeCondition(
      timezone: m['timezone'] as String,
      ranges: ranges,
      daysOfWeek: days == null
          ? const <int>{1, 2, 3, 4, 5, 6, 7}
          : days.map((dynamic e) => e as int).toSet(),
    );
  }

  final String timezone;
  final int offsetMinutes;
  final List<TimeOfDayRange> ranges;
  final Set<int> daysOfWeek;

  bool matches(int tsMs) {
    final int localMs = tsMs + offsetMinutes * 60000;
    final int days = _floorDiv(localMs, 86400000);
    final int minute = (localMs - days * 86400000) ~/ 60000;
    // 1970-01-01 la thu nam (ISO 4).
    final int weekday = ((days + 3) % 7) + 1;
    final int prevWeekday = ((days + 2) % 7) + 1;
    for (final TimeOfDayRange r in ranges) {
      int? day;
      if (r.fromMinute < r.toMinute) {
        if (minute >= r.fromMinute && minute < r.toMinute) day = weekday;
      } else if (minute >= r.fromMinute) {
        day = weekday;
      } else if (minute < r.toMinute) {
        day = prevWeekday;
      }
      if (day != null && daysOfWeek.contains(day)) return true;
    }
    return false;
  }
}

class Surcharge {
  const Surcharge({
    required this.id,
    required this.kind,
    this.valuePermille = 1000,
    this.valueVnd = 0,
    this.appliesTo = const <String>{'opening', 'distance', 'waiting'},
    this.condition,
  });

  final String id;
  final SurchargeKind kind;

  /// MULTIPLIER: he so x 1000 (1200 = x1.2).
  final int valuePermille;

  /// FIXED: so tien VND cong them sau khi nhan.
  final int valueVnd;

  /// MULTIPLIER chi nhan vao cac thanh phan nay: opening | distance | waiting.
  final Set<String> appliesTo;

  /// null = luon ap dung. Co so danh gia luon la TRIP_START_TIME.
  final TimeRangeCondition? condition;

  bool matches(SurchargeContexts ctx) {
    final TimeRangeCondition? c = condition;
    if (c == null) return true;
    return c.matches(ctx.tripStartTimeMs);
  }
}

class SurchargePipeline {
  const SurchargePipeline({
    this.order = const <String>[],
    this.allowStacking = true,
    this.maxStackCount = 3,
  });

  final List<String> order;
  final bool allowStacking;
  final int maxStackCount;
}
