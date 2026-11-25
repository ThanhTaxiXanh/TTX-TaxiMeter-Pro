# CONTEXT_STATE — Nhật ký trạng thái sống

> AI: đọc file này sau `.github/copilot-instructions.md`. Cập nhật sau MỖI task.

## Trạng thái hiện tại
- **Phase hiện tại:** Phase 1 — HOÀN THÀNH (CI xanh: `flutter analyze` sạch, 59 test pass, build được 3 APK split-per-abi, artifact `ttx-taximeter-apks`).
  - 1a: lõi thuần Dart (`lib/core`, `lib/domain/models`), test T1–T12, G1–G8, E8, golden replay.
  - 1b: `android/` (Kotlin DSL, minSdk 24, targetSdk 34, compileSdk 35, coreLibraryDesugaring), `.gitignore`.
  - 1c: Drift schema 14 bảng (`lib/data/db/`), index, trigger sổ cái bất biến, `schemaVersion = 1`, test trong `test/data/app_database_test.dart`.
- **Next:** Phase 2 — Android Foreground Service (Kotlin + flutter_foreground_task), TripActiveController + `active_trip_snapshot` (3 s, định dạng `state_json`), DashboardScreen. Cần quyền location/foreground service/notification trong AndroidManifest.

## Bảng tiến độ 7 Phase
| Phase | Nội dung | Trạng thái |
|---|---|---|
| 0 | GitHub Brain & CI | Xong (commit) |
| 1 | Flutter, Drift, TariffConfigV2, Engine (12 test), GpsPolicy (8 test) | Xong (CI xanh) |
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
- **API:** `TaximeterEngine.compute(samples: List<GpsSample>, config: TariffConfigV2, contexts: SurchargeContexts, tripId: '')` nhận GPS thô; bên trong chạy GpsPolicy (cấu hình từ `config.gps`) rồi tính cước. Kết quả `FareResult` (`fareOpening/fareDistance/fareWaiting/fareSurcharge/fareTotal/fareHash`, `distanceM`, `waitingSec`, ...).
- **Quãng đường:** equirectangular số nguyên, 111 195 m/độ vĩ, cos(vĩ độ TB) từ bảng nguyên nội suy; tổng cộng dồn mm rồi `~/ 1000`. Dùng **toạ độ thô của điểm ACCEPTED**: toạ độ làm mượt (cửa sổ 3) chỉ để hiển thị vì làm hụt cuối chuyến khi mẫu thưa.
- **Tốc độ `speed_mmps` < 0 (= -1, không biết)** → suy ra từ khoảng cách/thời gian (cả ở GpsPolicy lẫn phát hiện chờ).
- **Thang trung gian làm tròn 1 lần:** `fareScale = 18000` (VND x 18000 = BCNN(1000, 3600)): quãng đường = đơn giá/km x m x 18; chờ = đơn giá/giờ x giây x 5. Làm tròn theo `rounding.unitVnd` + `mode` (ROUND_HALF_UP | FLOOR | CEIL) đúng 1 lần ở cuối.
- **`fareSurcharge`** = (sau phụ phí − trước phụ phí)/fareScale, KHÔNG gồm chênh lệch làm tròn. `fareTotal` mới có thẩm quyền.
- **Phụ phí:** theo `surchargePipeline.order` (id không có trong order xếp sau theo thứ tự khai báo), `allowStacking=false` → chỉ cái đầu; `maxStackCount` giới hạn số lớp. MULTIPLIER nhân từng thành phần trong `appliesTo` (opening/distance/waiting), mỗi bước `~/ 1000`; FIXED (`valueVnd`) cộng sau cùng. Điều kiện duy nhất hỗ trợ: `TIME_RANGE` (khung [from,to), from > to = qua nửa đêm, phần sau nửa đêm tính theo ngày bắt đầu khung, `daysOfWeek` ISO 1–7), cơ sở đánh giá duy nhất: `TRIP_START_TIME`. Múi giờ có bảng cố định: `Asia/Ho_Chi_Minh`, `Asia/Saigon` (UTC+7), `UTC`; múi giờ khác → FormatException.
- **Chờ (`waiting`):** trạng thái tại điểm i áp cho đoạn (i-1, i]; hysteresis vào < enter, ra > exit (km/h); đợt chờ < `minWaitSegmentSeconds` bị bỏ qua; grace trừ riêng TỪNG đợt; tính theo giây x `ratePerHourVnd`/3600. `countingPolicy = EXCLUSIVE_FROM_DISTANCE` được hiểu là: quãng đường của các đoạn thuộc đợt chờ không tính vào quãng đường (giá trị khác → FormatException).
- **Hiệu chuẩn:** BEFORE_OPENING_KM = `max(0, raw*f/1000 − included)`; AFTER_OPENING_KM = `max(0, raw − included)*f/1000`.
- **Config:** `TariffConfigV2.fromJson` đọc schema 2.0 đầy đủ, kiểm `validation` (tier tăng dần, bậc cuối `upToMeters` null, đơn giá > 0, exit > enter), giá trị lạ → FormatException. Số thực trong JSON (1.5 m/s, 2.0 lần) đổi MỘT lần sang số nguyên x1000 ngay trong fromJson. `contentSha256` = sha256(utf8(jsonEncode(config bỏ khoá `integrity`))) — phụ thuộc thứ tự khoá trong file; `integrity.sha256` khác null mà không khớp → FormatException.
- **`fareHash`** = sha256(utf8(contentSha256 + fareTotal + tripId)), nối chuỗi thập phân, hex thường; `tripId` mặc định rỗng.
- **GpsPolicy:** mặc định maxSpeed 120 km/h (theo config), accuracy 20 m → 35 m sau 10 s mất GPS → PAUSED sau 30 s; anchor = điểm ACCEPTED cuối, được "làm mới" mỗi lần loại điểm do trôi (để đứng yên lâu vẫn bị loại) và guard tắt khi neo cũ hơn `maxAnchorAgeSeconds`; smoothing trọng số 1e14/accuracy² (accuracy tối thiểu 1 m).
- **Package** đổi tên thành `ttx` (khớp import trong test của chủ dự án); analysis_options bỏ strict-casts vì test đọc fixture JSON dạng dynamic.
- Chưa chốt: định dạng `state_json` (làm ở Phase 2 cùng TripActiveController); giá trị mở rộng cho `countingPolicy`, `rounding.mode`, loại `condition` (chỉ hỗ trợ những gì fixture dùng).

## Golden replay & fixture
- **E8 (fixture):** 5 file `test/fixtures/trip_00*.json` (fixture 2–5 kế thừa config của trip_001 qua `configInheritFrom`); mỗi fixture kiểm kết quả mong đợi + replay hai lần khớp từng trường. Khoảng cách engine lệch ~0,1% so với con số "tròn" trong fixture (111 195 vs ~111 320 m/độ), nằm trong tolerance; `fare_total_vnd` khớp chính xác.
- **Chuyến thật:** 5 GPX → CSV (`tool/gpx_to_csv.py`, `test/golden/*.csv`), accuracy cố định 5 m (GPX không có), biểu giá của trip_001; so khớp byte-for-byte `*.expected.json`. Khoảng cách engine = 97,3–99,6% haversine độc lập (đã bỏ các đoạn chờ; không bị loại điểm nào trừ 1 điểm ở chuyến Trần Nguyên Hãn). Expected được ghi lại 2026-11-24 sau khi đổi engine (toạ độ thô, bỏ đoạn chờ, thang 18000).

## Quyết định kỹ thuật Phase 1b/1c
- **Android:** AGP 8.3.2, Gradle 8.6, Kotlin 1.9.24, JDK 17, `compileSdk 35` (plugin yêu cầu; `targetSdk 34`), applicationId/namespace `vn.ttx.taximeter`. Release tạm ký bằng khoá debug để cài trực tiếp từ CI (TODO Phase 7: khoá phát hành riêng, không commit keystore). Chưa có icon launcher (dùng mặc định).
- **Quyền INTERNET** có trong manifest CHỈ để `LocalHttpTileServer` nghe/kết nối loopback; `network_security_config` cho phép HTTP thuần chỉ tới `127.0.0.1`/`localhost`, mọi host khác chỉ HTTPS. Không có đoạn code nào gọi mạng ngoài.
- **`dependency_overrides: geolocator_android: 4.6.1`:** bản 4.6.2 hỏng build trên Flutter 3.24 (`Could not get unknown property 'flutter'`). Gỡ override khi nâng Flutter.
- **Drift:** bảng khai báo bằng Dart DSL, mã sinh (`*.g.dart`) KHÔNG commit (CI chạy build_runner). Index có `DESC` và trigger tạo bằng SQL thô trong `onCreate` (`lib/data/db/schema_extras.dart`). Trigger: cấm UPDATE trường cước/config của `trip_record`; cấm DELETE `trip_record` khi chưa có `trip_tombstone` cùng `trip_id` (insert tombstone trong CÙNG transaction); `trip_adjustment` và `trip_edit_log` chỉ thêm dòng (xóa adjustment chỉ khi đã có tombstone); `trip_tombstone` chỉ sửa được ghi chú/`reconciled*`/`restored_at`. CHECK: `id = 1` (snapshot, bank account), `status`/`method`/`state`/`deleted_reason`/`kind` theo tập giá trị trong spec.
- **Migration:** `appSchemaVersion = 1`; nhánh `onUpgrade` để trống đến khi có v2 (khi đó thêm nhánh `if (from < 2)` + test migration; nhớ tạo lại trigger/index nếu đổi). DB thật mở bằng `openAppDatabase()` (WAL, `ttx_taximeter.db` trong thư mục documents).
- CI: cài `libsqlite3-dev` để chạy test Drift trên runner; chỉ build APK khi có `android/`.

## Quyết định của chủ dự án (2026-11-25)
- **Giữ nguyên spec Mục 4** cho `bank_account` (`trip_payment`, `trip_tombstone`): số tài khoản nằm trong `database.db` và vì vậy trong file backup, để restore xong không phải nhập lại gì. Lưu ý kỹ thuật cho Phase 3/6: `driver_bank_account.account_number_encrypted` mã hoá bằng khoá của thiết bị (flutter_secure_storage) nên restore sang máy khác sẽ không giải mã được; khi làm BankRepository/Backup cần chọn cách để số TK hiện tại vẫn restore được (vd lưu thêm bản đọc được trong backup, hoặc không mã hoá cột này).

## Việc còn chờ chủ dự án
- Tài nguyên `traffic_signs.geojson` đang rỗng/chưa đưa vào repo (dùng ở Phase 5).
- Ý nghĩa test "E8" đã hiểu = replay fixture (`replay_golden_test.dart`); nếu khác, báo lại.

## Nhật ký
- 2026-11-25: Phase 1b (android/, APK build trên CI) và 1c (Drift schema + trigger sổ cái + test) xong; CI xanh, 59 test → Phase 1 hoàn thành, sẵn sàng Phase 2.
- 2026-11-24: Engine theo schema config 2.0 + 5 fixture E8 của chủ dự án; đổi package thành `ttx`; ghi lại expected 5 chuyến thật; CI xanh.
- 2026-11-24: Thêm 5 GPX golden replay + expected; viết lại test G1–G8 theo đặc tả chủ dự án; chủ dự án rút gọn còn 9 điều cấm (commit c949a12).
- 2026-11-24: Phase 1a — pubspec, lib/core (geo, tariff_config, gps_policy, taximeter_engine), 23 test; CI xanh; sửa audit CI chỉ khớp khóa dependency thật.
- 2026-11-24: Thay danh sách điều cấm bằng bản chính thức của chủ dự án.
- 2026-11-24: Phase 0 — tạo `.github/copilot-instructions.md`, 2 agent, 4 SKILL.md, `flutter-ci.yml`, `docs/CONTEXT_STATE.md`.
