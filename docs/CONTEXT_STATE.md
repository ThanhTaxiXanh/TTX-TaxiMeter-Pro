# CONTEXT_STATE — Nhật ký trạng thái sống

> AI: đọc file này sau `.github/copilot-instructions.md`. Cập nhật sau MỖI task.

## Trạng thái hiện tại
- **Phase hiện tại:** Phase 5 — MỘT PHẦN (5a/5b/5c xong, CI xanh). Còn: 5d.
  - Dữ liệu chủ dự án cung cấp (2026-11-26): `signs_2026-10-13b.geojson` (70.971 biển, nguồn MapCar, `verification_status=unverified`) và `poi-vn-2026-11-16.geojson` (5.311 trạm xăng/sạc, ODbL © OpenStreetMap). `tool/convert_traffic_data.py` chuyển thành `assets/data/signs.bin` (13 byte/biển, ~0,9 MB) và `assets/data/poi.json`; POI nguồn lưu ở `data_src/`. Biển nguồn gốc 17 MB KHÔNG đưa vào repo (giữ file trên máy chủ dự án).
  - Loại biển (type_index): 0 hết khu đông dân cư, 1 bắt đầu khu đông dân cư, 2 tốc độ tối đa (value km/h), 3 cấm vượt, 4 p133 (chưa rõ ý nghĩa, hiển thị trung tính "Hết cấm vượt"), 5 điểm dừng nghỉ, 6 camera bắn tốc độ, 7 camera giám sát, 8 trạm thu phí, 9 hầm. `direction_raw` = hướng xe áp dụng (độ).
  - `lib/domain/traffic/`: `SignIndex` (lưới ~1,1 km, truy vấn bán kính), hướng đi/phương vị bằng số nguyên, `currentSpeedLimit`, `signsAhead`, `HeadingTracker`, GeoJSON hiển thị. Chỉ hiển thị, KHÔNG ảnh hưởng cước.
  - `lib/data/map/`: `PmTilesReader` (PMTiles v3, Dart thuần, thư mục gốc + lá, gzip), `LocalHttpTileServer` (127.0.0.1, `/style.json`, `/tiles/z/x/y.mvt`, 204 khi không có tile), `buildMapStyleJson` (tô màu theo tên lớp vector trong metadata, nền tối, CHƯA có nhãn chữ vì cần font glyph offline), `MapSourceService` (chọn file .pmtiles bằng file_picker, chuyển vào thư mục riêng của app; file `vietnam.pmtiles` 147 MB của chủ dự án KHÔNG nằm trong repo/APK).
  - UI: `MapScreen` (MapLibre, vị trí người dùng, chấm biển bảng trong 1,5 km + trạm xăng/sạc trong 3 km, biển giới hạn tốc độ kiểu QCVN P.127 + cảnh báo camera), nút bản đồ trên Dashboard; Dashboard hiện biển tốc độ/cảnh báo camera khi đang chạy và tô đỏ tốc độ khi vượt giới hạn.
  - CHƯA kiểm chứng trên điện thoại thật: MapLibre đọc style/tile từ máy chủ cục bộ; hình dạng schema của vietnam.pmtiles chưa biết (style dựa vào tên lớp).
  - Còn lại 5d: `TrafficRepository` (bảng `traffic_override`: sửa/thêm giới hạn tốc độ, biển, camera thủ công), `TrafficListScreen`, `TrafficEditScreen`, `ReportReviewScreen` (bảng `traffic_report`).
- **Next:** Phase 5d rồi Phase 6 (Settings 12 nhóm, Backup/Restore/Purge, Vùng nguy hiểm — gõ XOA).

### (Lịch sử) Phase 4 / 3 / 2
Phase 4 — Chuyến đi, thùng rác, bia mộ, doanh thu, đối soát — HOÀN THÀNH (CI xanh).
  - Dữ liệu: `lib/data/trip/trip_repository.dart` (danh sách/chi tiết, sửa ghi chú + cờ chạy thử có `trip_edit_log`, `addAdjustment` — KHÔNG bao giờ sửa `fare_total_vnd`, `moveToTrash`/`restoreFromTrash` bằng `archived`), `tombstone_repository.dart` (`deletePermanently`: chèn `trip_tombstone` → xoá phụ thuộc (adjustment, payment, raw GPS, raw_trace_meta) → `DELETE trip_record` trong 1 transaction; `setReconciled`; `restore` tạo lại chuyến `is_reconstructed=1` từ bia mộ, giữ nguyên cước), `trip_models.dart` (`RevenueSummary` thuần), `lib/domain/time/local_time.dart` (giờ VN bằng số nguyên).
  - UI: `TripListScreen` (vuốt trái → thùng rác, chừa 20px mép trái; menu: Doanh thu / Thùng rác / Chuyến đã xóa / Đối soát), `TripDetailScreen` (+ sửa ghi chú, điều chỉnh tiền, vào thùng rác), `TrashScreen` (khôi phục / xóa vĩnh viễn kèm lý do), `TombstoneScreen`, `ReconciliationScreen`, `RevenueScreen` (hôm nay / 7 ngày / tháng; bỏ qua thùng rác & chạy thử). Nút lịch sử chuyến trên Dashboard.
  - Chưa làm (để Phase 6): tự dọn thùng rác sau 30 ngày (PurgeService), xuất CSV trước khi dọn.
  - Doanh thu = cước gốc + điều chỉnh; chưa có biểu đồ (fl_chart) — thêm sau nếu cần.
- **Next:** Phase 5 — MapScreen (MapLibre + PMTiles offline qua LocalHttpTileServer), TrafficRepository, biển báo QCVN, ReportReviewScreen. CẦN chủ dự án cung cấp: file `.pmtiles` khu vực hoạt động và `traffic_signs.geojson` (hiện rỗng).

### (Lịch sử) Phase 3 / 2
Phase 3 — VietQR & thanh toán — HOÀN THÀNH (CI xanh). Phase 2 đã xong và chạy được trên điện thoại thật.
  - `lib/payment/vietqr_payload_builder.dart` (TLV + CRC16-CCITT-FALSE tự viết, khớp vector `E9AB`), `qr_content_generator.dart` (TTX+YYMMDD+NNN, giờ VN bằng số nguyên).
  - `lib/data/bank/`: danh mục ngân hàng nhúng sẵn (`bank_seed.dart`, 41 mục; BIN cần đối chiếu NAPAS trước khi dùng thật), `BankRepository` (seed, tài khoản nhận tiền). Theo quyết định chủ dự án: số TK lưu ĐỌC ĐƯỢC trong `driver_bank_account.account_number_encrypted` (tên cột giữ nguyên) để restore không phải nhập lại.
  - `lib/data/payment/payment_repository.dart`: ghi `trip_payment` (CASH→PAID; QR→UNPAID→PAID khi tài xế bấm "Đã nhận tiền"), số thứ tự chuyến trong ngày.
  - UI: `PaymentDialog` (hiện sau khi kết thúc chuyến: Tiền mặt / Chuyển khoản QR / Để sau; QR bật sáng tối đa rồi khôi phục), `BankSettingsScreen` (nút ngân hàng trên Dashboard).
  - Sửa lỗi Phase 2: thêm icon launcher + icon thông báo (thiếu icon làm Android giết app khi bật dịch vụ GPS); xin quyền vị trí + thông báo ngay khi mở app.
- **Next:** Phase 4 — TripList/Detail, Tombstone repo (xoá = chèn tombstone cùng transaction), Trash, Revenue, Reconciliation.

### (Lịch sử) Phase 2
Phase 2 — HOÀN THÀNH (CI xanh: analyze sạch, test pass, build APK).
  - Lõi: `lib/domain/trip/active_trip_session.dart` (thuần; cước luôn = `TaximeterEngine.compute` trên toàn bộ mẫu GPS thô; hiển thị trong chuyến dùng `rounding.displayMode`=floor, chốt dùng mode của config).
  - Lưu: `lib/data/trip/trip_store.dart` (`DriftTripStore`, SQL thô): mẫu GPS ghi dần vào `raw_gps_points` (decision='RAW'), `active_trip_snapshot.state_json` = {v, contexts, sampleCount}; khôi phục = đọc lại đúng (config_id, version) và kiểm sha256 (KHÔNG resolve lại config); `finishTrip` ghi `trip_record` + `raw_trace_meta` + xoá snapshot trong 1 transaction.
  - Biểu giá mặc định MẪU (`lib/domain/tariff/default_tariff.dart`: mở cửa 12.000/0,8 km, 15.000→12.000 đ/km, chờ 90.000 đ/giờ, làm tròn 1.000) tự tạo lần đầu — CHỦ XE PHẢI THAY bằng biểu giá thật (Settings, Phase 6).
  - UI/nền tảng: `TripController` (Riverpod Notifier; flush 3 s, tick 1 s, restoreOnLaunch), `DashboardScreen` (tiếng Việt, Material 3 tối), `GeolocatorLocationService` (foreground notification qua geolocator), wakelock, quyền Android trong AndroidManifest.
  - Chưa làm (cố ý): mã hoá `raw_gps_points.decision` theo từng mẫu (engine không trả quyết định từng mẫu), chọn loại xe/vehicleType (đang CAR_4), icon launcher.
- **Next:** Phase 3 — VietQR tự viết (EMVCo TLV + CRC16, test vector trong skill vietqr-offline), BankRepository, QrPaymentDialog, luồng thanh toán (ghi `trip_payment`).

## Bảng tiến độ 7 Phase
| Phase | Nội dung | Trạng thái |
|---|---|---|
| 0 | GitHub Brain & CI | Xong (commit) |
| 1 | Flutter, Drift, TariffConfigV2, Engine (12 test), GpsPolicy (8 test) | Xong (CI xanh) |
| 2 | Foreground Service, TripActiveController, snapshot 3s, DashboardScreen | Xong (CI xanh) |
| 3 | VietQR, BankRepository, QrPaymentDialog, luồng thanh toán | Xong (CI xanh) |
| 4 | TripList/Detail, Tombstone, Trash, Revenue, Reconciliation | Xong (CI xanh) |
| 5 | MapScreen, LocalHttpTileServer, Traffic, biển QCVN, ReportReview | 5a-5c xong (CI xanh), còn 5d |
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
- Ý nghĩa test "E8" đã hiểu = replay fixture (`replay_golden_test.dart`); nếu khác, báo lại.

## Nhật ký
- 2026-11-26: Phase 5a-5c (dữ liệu biển báo/POI, PMTiles reader + tile server cục bộ, MapScreen, cảnh báo trên Dashboard); CI xanh.
- 2026-11-26: Phase 4 xong (chuyến đi, thùng rác, tombstone transaction, doanh thu, đối soát); CI xanh.
- 2026-11-26: Phase 3 code xong (VietQR, ngân hàng, thanh toán); sửa crash thiếu icon thông báo ở Phase 2.
- 2026-11-26: Phase 2 xong (session, TripStore + khôi phục sau crash, TripController, Dashboard, quyền GPS nền); CI xanh.
- 2026-11-25: Phase 1b (android/, APK build trên CI) và 1c (Drift schema + trigger sổ cái + test) xong; CI xanh, 59 test → Phase 1 hoàn thành, sẵn sàng Phase 2.
- 2026-11-24: Engine theo schema config 2.0 + 5 fixture E8 của chủ dự án; đổi package thành `ttx`; ghi lại expected 5 chuyến thật; CI xanh.
- 2026-11-24: Thêm 5 GPX golden replay + expected; viết lại test G1–G8 theo đặc tả chủ dự án; chủ dự án rút gọn còn 9 điều cấm (commit c949a12).
- 2026-11-24: Phase 1a — pubspec, lib/core (geo, tariff_config, gps_policy, taximeter_engine), 23 test; CI xanh; sửa audit CI chỉ khớp khóa dependency thật.
- 2026-11-24: Thay danh sách điều cấm bằng bản chính thức của chủ dự án.
- 2026-11-24: Phase 0 — tạo `.github/copilot-instructions.md`, 2 agent, 4 SKILL.md, `flutter-ci.yml`, `docs/CONTEXT_STATE.md`.

## Phase 5e — Bản đồ 3D kiểu dẫn đường (CI xanh)
- MapScreen luôn nghiêng 3D (tilt 60, nhà 3D fill-extrusion), không có chế độ 2D.
- Biển báo/camera/POI luôn hiển thị bằng biểu tượng vẽ bằng canvas (map_icons.dart).
- Nút nổi: vị trí, giao diện Tự động/Sáng/Tối (Auto theo giờ VN, 18h–6h tối), báo cáo, tốc độ, giới hạn tốc độ, tên đường; tự ẩn sau 5 s, chạm bản đồ hiện lại.
- Khoảng cách tới trạm xăng/trạm sạc gần nhất và tới các biển phía trước.
- Báo cáo biển: lưu traffic_report (PENDING).
- Chưa kiểm tra trên máy thật: 3D, queryRenderedFeatures (tên đường), addImage.
- Còn lại Phase 5d: TrafficRepository/TrafficListScreen/TrafficEditScreen/ReportReviewScreen + danh mục biển đầy đủ.

## Phase 5d — Sửa tay biển báo/camera + duyệt báo cáo (CI xanh) ⇒ Phase 5 HOÀN TẤT
- lib/domain/traffic/traffic_overrides.dart: validate, applyOverrides (thêm điểm / ẩn biển nguồn trong 30 m, source='REMOVE'), parse/format độ E7 bằng số nguyên.
- lib/data/traffic/traffic_repository.dart: CRUD traffic_override; approveReport/rejectReport (giao dịch: tạo override + đóng báo cáo).
- UI: TrafficListScreen (nút 🚦 trên Dashboard), TrafficEditScreen, ReportReviewScreen.
- signIndexProvider gộp override; sau khi sửa gọi ref.invalidate(signIndexProvider) (bản đồ cập nhật khi mở lại).
- Test: test/traffic/overrides_test.dart.
- Chưa có: danh mục biển QCVN đầy đủ (tìm theo mã) — cần dữ liệu từ chủ app.
- Tiếp theo: Phase 6 (Cài đặt 12 nhóm, Backup/Restore/Purge, CSV, "XOA").

## Phase 5f — Style bản đồ 3D offline (CI xanh)
- assets/styles/{standard,modern}-{day,night}.json (từ MapCar, schema OpenMapTiles). lib/data/map/style_adapter.dart đổi nguồn sang tile server 127.0.0.1, bỏ lớp raster/symbol (không có font/sprite offline), bỏ source-layer không có trong file. Không phải OpenMapTiles → dùng style tự sinh.
- Nút phải (vị trí, giao diện, kiểu bản đồ, chọn file) tự ẩn 5 s; chip POI, biển phía trước, tốc độ, báo cáo, tên đường luôn hiện.
- Không dùng: satellite*.json (MapTiler trả phí + online, vi phạm cấm #1), day/night phẳng (luôn 3D).
- road-signs.txt: chỉ là danh sách mã biển/ghi công ảnh Wikimedia; chưa có ảnh/tên → chưa làm danh mục biển.

## Phase 5g — Bản đồ nhãn chữ, tải liên tục phía trước, tên đường, danh mục biển (CI xanh)
- Font Việt offline: tool/gen_glyphs.py sinh assets/glyphs/DejaVuSans-{Regular,Bold,Oblique}/*.pbf (SDF, dải 0-255, 256-511, 7680-7935, 8192-8447); tile server phục vụ /fonts/{stack}/{range}.pbf. style_adapter giữ lớp nhãn chữ (name:vi → name), bỏ icon/sprite/POI nền.
- Biển/POI: khi bám theo xe chỉ vẽ phía trước xe ≤ 2 km, nạp lại khi xe đi ≥ 40 m hoặc đổi hướng ≥ 20° (aheadSigns/poiAhead/needsAheadRefresh). Kéo bản đồ → thôi bám xe, nút vị trí bật lại.
- Cảnh báo khoảng cách biển 200/300/500 m (nút "Kiểu bản đồ", pref warn_m). Zoom bám xe 18.2, tối đa 20.5.
- Tên đường: street_name.dart đọc MVT transportation_name trực tiếp từ PMTiles (offline); dự phòng queryRenderedFeatures.
- Danh mục biển: assets/data/sign_catalog.json (390 mã từ road-signs.txt, 246 có tên từ voh.com.vn — trang Wikipedia không tải được), bảng chọn tab + tìm; báo cáo theo mã; duyệt → SignKind.other hiển thị trên bản đồ bằng icon mã.
- Chưa kiểm tra trên máy thật: vị trí dọc của nhãn chữ (top glyph), hiệu năng tải liên tục. Ảnh biển chưa có (cần tệp ảnh).
