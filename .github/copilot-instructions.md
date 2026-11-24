# TTX-TaxiMeter-Pro — Hiến pháp dự án

> Mọi AI (Copilot, Claude, ChatGPT...) PHẢI đọc file này đầu tiên ở mọi phiên.

## Quy tắc vận hành
1. **Luôn đọc `docs/CONTEXT_STATE.md` và `SKILL.md` liên quan trước khi sửa code.**
2. **Luôn cập nhật `docs/CONTEXT_STATE.md` sau khi hoàn thành task.**
3. Chủ dự án làm việc 100% trên điện thoại qua GitHub. Build, test, APK chạy trên GitHub Actions (`.github/workflows/flutter-ci.yml`).
4. Không sang Phase N+1 nếu Phase N chưa pass 100% `flutter analyze` + `flutter test` trên GitHub Actions và chưa cập nhật CONTEXT_STATE.
5. Dùng agent: `.github/agents/core-engineer.agent.md` (viết code), `.github/agents/audit-reviewer.agent.md` (rà soát).
6. Skill theo module: `.github/skills/<tên>/SKILL.md` (taximeter-engine, gps-and-offline-map, vietqr-offline, ledger-and-backup).

## Sản phẩm
Ứng dụng đồng hồ tính tiền taxi Android cho 1 tài xế. Không backend, không dịch vụ trả phí. Flutter/Dart + Kotlin (chỉ Foreground Service + MethodChannel). UI Tiếng Việt, Material 3, Dark Mode mặc định.

## 4 mục tiêu bất biến
1. Tính cước tất định, replay khớp byte-for-byte từ raw GPS.
2. Offline 100% (tính cước, PMTiles, cảnh báo giao thông, VietQR).
3. Chi phí bằng 0 (không Google Maps API, Mapbox, tile server trả phí).
4. Sổ cái bất biến (điều chỉnh qua `trip_adjustment`, xóa vĩnh viễn qua `trip_tombstone`).

## 8 nguyên tắc thiết kế bất biến
1. **Integer-only cho tiền & vật lý.** Không `double` cho trường ảnh hưởng cước. Đơn vị: m, giây, ms, VND, permille (hệ số x 1000), tọa độ `lat_e7`/`lng_e7` (int x 10^7).
2. **Engine PURE.** `TaximeterEngine.compute()` và `GpsPolicy.evaluate()` không đọc `DateTime.now()`, không `Random()`, không I/O.
3. **Config bất biến.** Mỗi chuyến lưu `config_id`, `config_version`, `config_sha256`; không resolve lại biểu giá giữa chuyến.
4. **Không sửa cước trực tiếp.** Đổi tiền → tạo `trip_adjustment`. Cấm `UPDATE trip_record SET fare_total_vnd = ...`.
5. **Không xóa cứng chuyến.** Xóa mềm (`archived=1`, thùng rác 30 ngày) → xóa vĩnh viễn phải insert `trip_tombstone` trong CÙNG 1 SQLite transaction trước `DELETE FROM trip_record`.
6. **Crash-safe snapshot.** Chuyến active ghi `active_trip_snapshot` mỗi 3 giây.
7. **VietQR offline 100%.** Tự sinh EMVCo TLV + CRC16, không gọi API ngoài, không dùng package vietqr.
8. **Hiển thị tốc độ chuẩn Việt Nam.** Biển giới hạn tốc độ viền đỏ nền trắng chữ đen (QCVN), tốc độ mặc định theo loại đường, chạm biển trên map để override nhanh.

## 10 điều cấm
(Master prompt nhắc "Mục 11" nhưng không có nội dung; 10 điều dưới đây được tổng hợp từ các ràng buộc trong prompt. Chủ dự án có thể chỉnh.)
1. CẤM `double`/`num` thập phân cho tiền, khoảng cách, thời gian, tọa độ tính cước.
2. CẤM `DateTime.now()`, `Random()`, I/O, đọc biến toàn cục trong `TaximeterEngine`/`GpsPolicy`.
3. CẤM `UPDATE` trực tiếp `fare_*_vnd` của `trip_record`.
4. CẤM `DELETE FROM trip_record` khi chưa insert `trip_tombstone` cùng transaction.
5. CẤM resolve lại biểu giá giữa chuyến hoặc sửa `tariff_config` đã ACTIVE (tạo version mới).
6. CẤM gọi mạng cho tính cước, QR, cảnh báo giao thông; CẤM Google Maps API, Mapbox, backend, dịch vụ trả phí.
7. CẤM dùng package VietQR ngoài; phải tự build TLV + CRC16.
8. CẤM lưu số tài khoản ngân hàng dạng rõ trong DB/backup (mã hóa bằng `flutter_secure_storage`, không export trong backup).
9. CẤM xóa/sửa dòng `trip_tombstone` ngoài cột đối soát (`reconciled*`, `restored_at`); CẤM đổi schema mà không có migration + test.
10. CẤM đánh dấu task xong khi thiếu unit test hoặc CI chưa xanh; CẤM sang Phase mới khi cổng kiểm soát chưa đạt.

## Tech stack
Android only (minSdk 24, targetSdk 34, Kotlin DSL, coreLibraryDesugaring). Dart SDK >=3.5.0 <4.0.0, Flutter >=3.24.0. State: `flutter_riverpod`. DB: Drift + sqlite3_flutter_libs. Map: `maplibre_gl` + PMTiles qua `LocalHttpTileServer` tự viết. Danh sách dependency đầy đủ nằm trong master prompt Mục 2 và phải được copy nguyên vào `pubspec.yaml` ở Phase 1.
