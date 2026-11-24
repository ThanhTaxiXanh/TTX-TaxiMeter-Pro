---
name: vietqr-offline
description: Tự build chuỗi VietQR EMVCo TLV + CRC16-CCITT (NAPAS) offline, không dùng package ngoài; kèm test vector đã tính.
---

# Skill: vietqr-offline

File: `lib/payment/vietqr_payload_builder.dart`, `lib/payment/qr_content_generator.dart`. CẤM package VietQR ngoài. CẤM gọi API. Hiển thị bằng `qr_flutter`; khi hiện QR bật sáng 100% (`screen_brightness`) và khôi phục khi đóng.

## Cấu trúc TLV (mỗi trường: Tag 2 chữ số + độ dài 2 chữ số thập phân + giá trị)
| Tag | Nội dung |
|---|---|
| 00 | `01` (phiên bản payload) |
| 01 | `12` (QR động, có số tiền) hoặc `11` (QR tĩnh) |
| 38 | Thông tin tài khoản NAPAS: con `00`=`A000000727` (GUID), con `01` = [con `00`=BIN, con `01`=số TK], con `02`=`QRIBFTTA` (chuyển nhanh đến tài khoản) |
| 53 | `704` (VND) |
| 54 | Số tiền (chuỗi số nguyên VND, không dấu phân cách) |
| 58 | `VN` |
| 62 | Tag con `08` = nội dung chuyển khoản: `TTX` + `YYMMDD` + `NNN` |
| 63 | CRC16 (4 hex hoa), tính trên toàn chuỗi gồm cả `6304` |

Độ dài tính theo số **byte UTF-8**; nội dung CK dùng ASCII không dấu.

## CRC16-CCITT-FALSE
Poly `0x1021`, init `0xFFFF`, không đảo bit, xorout `0x0000`. Xuất 4 ký tự hex HOA, đệm 0.

## Test vector (đã tính bằng script độc lập)
1. CRC chuẩn: `crc16("123456789") == "29B1"`.
2. Payload mẫu: BIN `970436`, STK `0123456789`, số tiền `50000`, nội dung `TTX261124001`:
```
00020101021238540010A00000072701240006970436011001234567890208QRIBFTTA53037045405500005802VN62160812TTX2611240016304E9AB
```
(CRC cuối: `E9AB`.) Khi Phase 3 có vector chính thức từ NAPAS/ngân hàng thật, thêm vào cùng file test.

## Edge cases
- Số tiền 0 hoặc âm → không sinh QR động.
- STK/BIN rỗng, BIN không đủ 6 chữ số → lỗi rõ ràng.
- Độ dài trường ≥ 100 → vẫn 2 chữ số (kiểm tra giới hạn 99).
- NNN tăng theo thứ tự chuyến trong ngày (001–999), YYMMDD theo giờ địa phương truyền từ ngoài vào (không `DateTime.now()` trong builder).
- Số TK lấy từ `flutter_secure_storage`; không log, không ghi vào backup.
