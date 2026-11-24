# CONTEXT_STATE — Nhật ký trạng thái sống

> AI: đọc file này sau `.github/copilot-instructions.md`. Cập nhật sau MỖI task.

## Trạng thái hiện tại
- **Phase hiện tại:** Phase 1 — đang làm. **1a XONG** (CI xanh: `flutter analyze` sạch, 23 test pass): pubspec đầy đủ dependency, `lib/core/` (geo, TariffConfigV2, GpsPolicy, TaximeterEngine), test T1–T12, G1–G8, replay pipeline.
- **Next (1b):** thư mục `android/` (Kotlin DSL, minSdk 24, targetSdk 34, coreLibraryDesugaring) để build APK; **(1c):** Drift schema + migrations (Mục 4 master prompt) + test migration; **(1d):** golden GPX mẫu nếu có sẵn (chủ dự án cung cấp 5 file GPX, hoặc tạo tổng hợp).
- CI bỏ qua build APK khi chưa có `android/`.

## Bảng tiến độ 7 Phase
| Phase | Nội dung | Trạng thái |
|---|---|---|
| 0 | GitHub Brain & CI | Xong (commit) |
| 1 | Flutter, Drift, TariffConfigV2, Engine (12 test), GpsPolicy (8 test) | Đang làm: 1a xong (core + test), còn 1b android/, 1c Drift |
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

## Quyết định kỹ thuật Phase 1a (ĐÃ CHỐT — đổi phải cập nhật test/golden)
- Khoảng cách: equirectangular số nguyên, 111 195 m/độ vĩ (`mm = dE7 * 111195 ~/ 10000`), cos(vĩ độ trung bình) từ bảng nguyên x1e6 nội suy tuyến tính; tổng cộng dồn bằng mm rồi `~/ 1000` ra mét.
- Thang trung gian làm tròn 1 lần: `fareScale = 60000` (VND x 60000). Distance = rate/km x m x 60; waiting = rate/phút x giây x 1000.
- Phụ phí MULTIPLIER nhân tuần tự từng hệ số (`~/ 1000` mỗi bước, tránh tràn int64); FIXED cộng sau cùng.
- Hiệu chuẩn: BEFORE = `max(0, raw*f/1000 - included)`; AFTER = `max(0, raw - included)*f/1000`.
- Chờ: trạng thái tại điểm i áp dụng cho khoảng (i-1, i]; hysteresis vào < enter, ra > exit; grace và counting (giây / phút tròn xuống / phút làm tròn lên) tính theo TỪNG đợt chờ.
- `fareHash = sha256(utf8(configSha256 + fareTotalVnd + tripId))`, nối chuỗi thập phân, hex thường. `fareSurchargeVnd` = total − (opening + distance + waiting) (thành phần thông tin); `fareTotalVnd` mới có thẩm quyền.
- GpsPolicy: mặc định maxSpeed 200 km/h, accuracy 20 m → 35 m sau 10 s mất GPS → PAUSED sau 30 s; anchor = điểm ACCEPTED cuối; smoothing trọng số 1e14/accuracy² (accuracy tối thiểu 1 m).
- Chưa chốt: định dạng `state_json` (làm ở Phase 2 cùng TripActiveController).

## Việc còn chờ chủ dự án
- Điều cấm thứ 10 (đã có 9) và ý nghĩa test "E8".
- Tài nguyên `traffic_signs.geojson` đang rỗng/chưa đưa vào repo (dùng ở Phase 5).
- 5 file GPX mẫu cho golden replay (Phase 7), nếu có.

## Nhật ký
- 2026-11-24: Phase 1a — pubspec, lib/core (geo, tariff_config, gps_policy, taximeter_engine), 23 test; CI xanh; sửa audit CI chỉ khớp khóa dependency thật.
- 2026-11-24: Thay danh sách điều cấm bằng bản chính thức của chủ dự án.
- 2026-11-24: Phase 0 — tạo `.github/copilot-instructions.md`, 2 agent, 4 SKILL.md, `flutter-ci.yml`, `docs/CONTEXT_STATE.md`.
