import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/ui/common/format.dart';

void main() {
  test('formatVnd', () {
    expect(formatVnd(0), '0 ₫');
    expect(formatVnd(999), '999 ₫');
    expect(formatVnd(1000), '1.000 ₫');
    expect(formatVnd(1234567), '1.234.567 ₫');
  });
  test('formatKm cat bot', () {
    expect(formatKm(0), '0,00 km');
    expect(formatKm(1239), '1,23 km');
    expect(formatKm(12005), '12,00 km');
  });
  test('formatDuration', () {
    expect(formatDuration(5), '00:05');
    expect(formatDuration(125), '02:05');
    expect(formatDuration(3725), '1:02:05');
  });
  test('formatSpeedKmh', () {
    expect(formatSpeedKmh(10000), '36,0 km/h');
    expect(formatSpeedKmh(-1), '--');
  });
}
