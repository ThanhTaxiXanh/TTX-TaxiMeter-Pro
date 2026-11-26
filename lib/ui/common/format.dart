// Dinh dang hien thi bang so nguyen (khong dung double cho tien/khoang cach).

/// 1234567 -> "1.234.567 ₫"
String formatVnd(int vnd) {
  final bool neg = vnd < 0;
  final String digits = (neg ? -vnd : vnd).toString();
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
    b.write(digits[i]);
  }
  return '${neg ? '-' : ''}$b ₫';
}

/// 1234 m -> "1,23 km" (cat bot, khong lam tron len).
String formatKm(int meters) {
  final int km = meters ~/ 1000;
  final int cs = (meters % 1000) ~/ 10;
  return '$km,${cs.toString().padLeft(2, '0')} km';
}

/// 3725 s -> "1:02:05"; duoi 1 gio -> "02:05".
String formatDuration(int seconds) {
  final int s = seconds < 0 ? 0 : seconds;
  final int h = s ~/ 3600;
  final String m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final String ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$ss' : '$m:$ss';
}

/// mm/s -> "36,0 km/h" (mm/s * 3,6 / 1000 = mm/s * 36 / 10000).
String formatSpeedKmh(int mmps) {
  if (mmps < 0) return '--';
  final int tenths = mmps * 36 ~/ 1000;
  return '${tenths ~/ 10},${tenths % 10} km/h';
}

/// 350 -> "350 m"; 1250 -> "1,2 km".
String formatDistance(int meters) {
  if (meters < 1000) return '$meters m';
  return '${meters ~/ 1000},${(meters % 1000) ~/ 100} km';
}
