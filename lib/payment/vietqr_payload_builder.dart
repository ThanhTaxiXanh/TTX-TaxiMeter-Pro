// VietQR (NAPAS 247, EMVCo TLV) tu viet. KHONG dung package ngoai, KHONG goi API.
// THUAN: khong doc dong ho, khong IO.
import 'dart:convert';

/// CRC16-CCITT-FALSE: poly 0x1021, init 0xFFFF, khong dao bit, xorout 0.
/// Tra ve 4 ky tu hex HOA.
String crc16Ccitt(String data) {
  int crc = 0xFFFF;
  for (final int b in utf8.encode(data)) {
    crc ^= b << 8;
    for (int i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

String _tlv(String tag, String value) {
  final int len = utf8.encode(value).length;
  if (len > 99) {
    throw ArgumentError('Truong $tag dai $len byte, toi da 99');
  }
  return '$tag${len.toString().padLeft(2, '0')}$value';
}

final RegExp _digits = RegExp(r'^[0-9]+$');
final RegExp _account = RegExp(r'^[0-9A-Za-z]+$');
final RegExp _content = RegExp(r'^[0-9A-Za-z ]+$');

class VietQrPayload {
  const VietQrPayload._();

  /// QR dong (co so tien) chuyen nhanh den tai khoan.
  /// [content]: noi dung chuyen khoan, ASCII khong dau, toi da 23 ky tu.
  static String build({
    required String bin,
    required String account,
    required int amountVnd,
    required String content,
  }) {
    if (amountVnd <= 0) {
      throw ArgumentError('So tien phai > 0 de sinh QR dong');
    }
    if (bin.length != 6 || !_digits.hasMatch(bin)) {
      throw ArgumentError('BIN ngan hang phai du 6 chu so');
    }
    if (account.isEmpty || account.length > 19 || !_account.hasMatch(account)) {
      throw ArgumentError('So tai khoan khong hop le');
    }
    if (content.isEmpty || content.length > 23 || !_content.hasMatch(content)) {
      throw ArgumentError('Noi dung chuyen khoan phai la ASCII khong dau, 1-23 ky tu');
    }

    final String beneficiary = _tlv('00', bin) + _tlv('01', account);
    final String merchant = _tlv('00', 'A000000727') +
        _tlv('01', beneficiary) +
        _tlv('02', 'QRIBFTTA');
    final String body = _tlv('00', '01') +
        _tlv('01', '12') +
        _tlv('38', merchant) +
        _tlv('53', '704') +
        _tlv('54', amountVnd.toString()) +
        _tlv('58', 'VN') +
        _tlv('62', _tlv('08', content));
    final String withCrcTag = '${body}6304';
    return '$withCrcTag${crc16Ccitt(withCrcTag)}';
  }
}
