# CONTEXT_STATE — Nhật ký trạng thái sống

> AI: đọc file này sau `.github/copilot-instructions.md`. Cập nhật sau MỖI task.

## Trạng thái hiện tại
- **Phase hiện tại:** Phase 0 — HOÀN THÀNH hạ tầng CI & Skills (đã commit, chờ xác nhận chạy CI lần đầu).
- **Next:** Phase 1 — Khởi tạo Flutter & Core Engine (Flutter project, Drift schema + migrations, TariffConfigV2, TaximeterEngine T1–T12, GpsPolicy G1–G8).
- Chưa có file `.dart` nào; workflow CI tự bỏ qua build khi chưa có `pubspec.yaml`.

## Bảng tiến độ 7 Phase
| Phase | Nội dung | Trạng thái |
|---|---|---|
| 0 | GitHub Brain & CI | Xong (commit) |
| 1 | Flutter, Drift, TariffConfigV2, Engine (12 test), GpsPolicy (8 test) | Chưa bắt đầu |
| 2 | Foreground Service, TripActiveController, snapshot 3s, DashboardScreen | Chưa bắt đầu |
| 3 | VietQR, BankRepository, QrPaymentDialog, luồng thanh toán | Chưa bắt đầu |
| 4 | TripList/Detail, Tombstone, Trash, Revenue, Reconciliation | Chưa bắt đầu |
| 5 | MapScreen, LocalHttpTileServer, Traffic, biển QCVN, ReportReview | Chưa bắt đầu |
| 6 | Settings (12 nhóm), Backup/Restore/Purge, Vùng nguy hiểm | Chưa bắt đầu |
| 7 | Golden replay 5 GPX, tối ưu pin, APK release | Chưa bắt đầu |

Cổng chuyển Phase: Phase N phải pass 100% `flutter analyze` + `flutter test` trên GitHub Actions và CONTEXT_STATE đã cập nhật.

## Quyết định kiến trúc đã chốt
- Android only (minSdk 24, targetSdk 34, Kotlin DSL, coreLibraryDesugaring). Không iOS.
- Dart cho UI/Core/DB/QR/Tile server; Kotlin chỉ cho Foreground Service location + MethodChannel.
- State: flutter_riverpod. DB: Drift (SQLite), schema theo master prompt Mục 4.
- Integer-only cho tiền/khoảng cách/thời gian/tọa độ E7; Engine và GpsPolicy PURE.
- Config biểu giá bất biến theo chuyến (id, version, sha256).
- Sổ cái bất biến: trip_adjustment, trip_tombstone (cùng transaction), thùng rác 30 ngày.
- Snapshot chuyến active mỗi 3 giây.
- VietQR tự build, offline; map PMTiles qua LocalHttpTileServer loopback.
- Backup ZIP có SHA256, không export số TK; restore verify + auto-backup + rollback.
- Flutter 3.24.x, Java 17 Temurin trên CI; APK split-per-abi, artifact `ttx-taximeter-apks`.

## Điểm cần chốt ở Phase 1 (ghi lại tại đây khi quyết)
- Công thức khoảng cách số nguyên (haversine nguyên vs equirectangular).
- Thang trung gian làm tròn 1 lần (đề xuất S = 60 000, xem skill taximeter-engine).
- Định dạng chính xác `fareHash` và `state_json`.
- "Mục 11 — 10 điều cấm" không có trong master prompt gốc; 10 điều trong copilot-instructions.md được tổng hợp, chủ dự án có thể chỉnh.
- Tài nguyên `traffic_signs.geojson` đang nằm trong Project TTX TaxiMeter Pro (chưa đưa vào repo).

## Nhật ký
- 2026-11-24: Phase 0 — tạo `.github/copilot-instructions.md`, 2 agent, 4 SKILL.md, `flutter-ci.yml`, `docs/CONTEXT_STATE.md`.
