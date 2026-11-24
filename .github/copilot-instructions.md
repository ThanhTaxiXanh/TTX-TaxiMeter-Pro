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

## Điều cấm (BẮT BUỘC)
1. ❌ Không dùng Google Maps API, Mapbox, hay bất kỳ tile server trả phí.
2. ❌ Không gọi `img.vietqr.io` hay API ngoài khi sinh QR.
3. ❌ Không dùng `double` cho tiền/khoảng cách/thời gian.
4. ❌ Không cho sửa trực tiếp `fare_total_vnd` từ UI (đổi tiền qua `trip_adjustment`).
5. ❌ Không `DELETE FROM trip_record` khi chưa insert tombstone trong cùng transaction.
6. ❌ Không resolve lại config giữa chuyến đang chạy.
7. ❌ Không upload bất kỳ dữ liệu nào lên server.
8. ❌ Không dùng package vietqr có sẵn — tự implement.
9. ❌ Không bỏ qua test replay (E8/G8) — đây là test quan trọng nhất.

Quy tắc phụ rút ra từ prompt gốc (đề xuất, không thay thế danh sách trên): `lib/core` không dùng `DateTime.now()`/`Random()`/I/O; không lưu số tài khoản ngân hàng dạng rõ trong DB/backup; đổi schema phải có migration + test; không sang Phase mới khi CI chưa xanh.

## Tech stack
Android only (minSdk 24, targetSdk 34, Kotlin DSL, coreLibraryDesugaring). Dart SDK >=3.5.0 <4.0.0, Flutter >=3.24.0. State: `flutter_riverpod`. DB: Drift + sqlite3_flutter_libs. Map: `maplibre_gl` + PMTiles qua `LocalHttpTileServer` tự viết. Danh sách dependency đầy đủ nằm trong master prompt Mục 2 và phải được copy nguyên vào `pubspec.yaml` ở Phase 1.
