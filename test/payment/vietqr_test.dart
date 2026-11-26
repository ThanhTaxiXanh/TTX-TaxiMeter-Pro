import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/payment/qr_content_generator.dart';
import 'package:ttx/payment/vietqr_payload_builder.dart';

void main() {
  test('CRC16-CCITT-FALSE vector chuan', () {
    expect(crc16Ccitt('123456789'), '29B1');
    expect(crc16Ccitt(''), 'FFFF');
  });

  test('payload mau khop tung ky tu', () {
    final String p = VietQrPayload.build(
      bin: '970436',
      account: '0123456789',
      amountVnd: 50000,
      content: 'TTX261124001',
    );
    expect(
      p,
      '00020101021238540010A00000072701240006970436011001234567890208QRIBFTTA'
      '53037045405500005802VN62160812TTX2611240016304E9AB',
    );
  });

  test('CRC cua payload tu nhat quan', () {
    final String p = VietQrPayload.build(
        bin: '970422', account: '9876543210', amountVnd: 123000, content: 'TTX261126007');
    final String body = p.substring(0, p.length - 4);
    expect(body.endsWith('6304'), isTrue);
    expect(p.substring(p.length - 4), crc16Ccitt(body));
  });

  test('tham so sai bi tu choi', () {
    expect(() => VietQrPayload.build(bin: '970436', account: '1', amountVnd: 0, content: 'A'),
        throwsArgumentError);
    expect(() => VietQrPayload.build(bin: '970436', account: '1', amountVnd: -5, content: 'A'),
        throwsArgumentError);
    expect(() => VietQrPayload.build(bin: '9704', account: '1', amountVnd: 1000, content: 'A'),
        throwsArgumentError);
    expect(() => VietQrPayload.build(bin: '970436', account: '', amountVnd: 1000, content: 'A'),
        throwsArgumentError);
    expect(() => VietQrPayload.build(bin: '970436', account: '12-34', amountVnd: 1000, content: 'A'),
        throwsArgumentError);
    expect(() => VietQrPayload.build(bin: '970436', account: '1', amountVnd: 1000, content: 'Có dấu'),
        throwsArgumentError);
  });

  test('YYMMDD theo gio Viet Nam, qua nua dem UTC', () {
    // 2026-11-24 10:00 VN
    expect(localYymmdd(1795489200000), '261124');
    // 2026-11-24 23:30 UTC = 2026-11-25 06:30 VN
    expect(localYymmdd(1795563000000), '261125');
    expect(localYymmdd(0, offsetMinutes: 0), '700101');
    // 2024-02-29 (nam nhuan) 12:00 UTC
    expect(localYymmdd(1709208000000, offsetMinutes: 0), '240229');
  });

  test('noi dung chuyen khoan TTX+YYMMDD+NNN', () {
    expect(transferContent(tripStartedAtMs: 1795489200000, sequenceInDay: 1), 'TTX261124001');
    expect(transferContent(tripStartedAtMs: 1795489200000, sequenceInDay: 999), 'TTX261124999');
    expect(() => transferContent(tripStartedAtMs: 0, sequenceInDay: 0), throwsArgumentError);
    expect(() => transferContent(tripStartedAtMs: 0, sequenceInDay: 1000), throwsArgumentError);
  });
}
