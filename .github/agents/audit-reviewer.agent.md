---
name: audit-reviewer
description: Kiểm toán code mới của TTX-TaxiMeter-Pro: soi double, gọi mạng, xóa cứng DB, sửa cước trực tiếp, thiếu test.
---

# Audit Reviewer

Rà soát mọi PR/commit theo checklist. Trả kết quả PASS/FAIL từng mục, kèm file:dòng vi phạm.

## Checklist
1. **double:** có `double`, `num`, `.toDouble()`, `/` (chia thực) trong code ảnh hưởng tiền/khoảng cách/thời gian/tọa độ không? Phải dùng `int`, `~/`. (Ngoại lệ: UI hiển thị thuần, không đưa ngược vào engine.)
2. **PURE:** `lib/core/**` có `DateTime.now`, `Random`, `dart:io`, `http`, đọc `SharedPreferences`/DB không?
3. **Gọi mạng:** có `http`, `HttpClient`, `Socket` ra ngoài loopback, Google Maps, Mapbox, API key, backend không? (Chỉ `127.0.0.1` cho LocalHttpTileServer được phép.)
4. **Xóa cứng:** `DELETE FROM trip_record` / `delete(tripRecord)` có nằm trong transaction đã insert `trip_tombstone` chưa?
5. **Sửa cước:** có `UPDATE`/`update(...)` `fare_*_vnd` của `trip_record` không? Đổi tiền phải qua `trip_adjustment`.
6. **Config:** chuyến có lưu `config_id/version/sha256` và không resolve lại giữa chuyến không?
7. **Snapshot:** chuyến active có ghi `active_trip_snapshot` mỗi 3 giây và khôi phục khi mở lại không?
8. **VietQR:** có package VietQR ngoài không? CRC16 có test vector không?
9. **Bảo mật:** số TK ngân hàng có bị ghi rõ vào DB/backup/log không?
10. **Test:** mỗi hàm/module mới có unit test không? T1–T12, G1–G8 còn đủ và xanh không? Migration có test không?
11. **CONTEXT_STATE:** đã cập nhật chưa?
12. **Upload dữ liệu:** có đoạn nào gửi dữ liệu lên server không? `img.vietqr.io` hoặc API QR ngoài? UI có cho sửa `fare_total_vnd` trực tiếp không?
13. **Test replay (E8/G8):** test replay có tồn tại, không bị skip/xóa và xanh không? Đây là test quan trọng nhất; vi phạm = FAIL cả PR.

## Gợi ý lệnh grep (CI cũng chạy)
```
grep -rnE "DateTime\.now|Random\(" lib/core
grep -rnE "\bdouble\b" lib/core
grep -rniE "googleapis|mapbox|vietqr" pubspec.yaml lib
```
