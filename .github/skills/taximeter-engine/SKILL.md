---
name: taximeter-engine
description: Đặc tả tính cước số nguyên (TaximeterEngine PURE), bậc thang, hysteresis chờ, phụ phí, làm tròn, fareHash, 12 unit test T1–T12 và golden GPX replay.
---

# Skill: taximeter-engine

File: `lib/core/taximeter_engine.dart` (PURE). Đầu vào: danh sách điểm ACCEPTED (từ GpsPolicy), `TariffConfigV2`, `tripId`. Đầu ra: `FareResult` + `fareHash`.

## Quy tắc
- Chỉ `int`. Mét, giây, VND, permille. Không `double`, không `DateTime.now()`, không `Random`, không I/O.
- Cùng đầu vào → cùng kết quả byte-for-byte.

## Thuật toán (API: `compute(samples, config, contexts, tripId)`)
1. Lọc GPS thô bằng GpsPolicy (cấu hình từ `config.gps`). Quãng đường dùng **toạ độ thô** của điểm ACCEPTED (toạ độ làm mượt chỉ để hiển thị).
2. Mỗi đoạn giữa hai điểm ACCEPTED: khoảng cách (mm, equirectangular số nguyên), tốc độ (ưu tiên `speed_mmps` ≥ 0, ngược lại suy ra từ khoảng cách/thời gian).
3. Chờ: hysteresis theo tốc độ đoạn (vào < `enterThresholdKmh`, ra > `exitThresholdKmh`); đợt chờ < `minWaitSegmentSeconds` bị bỏ; trừ `graceSeconds` TỪNG đợt; tiền chờ = giây tính tiền x `ratePerHourVnd` / 3600. `EXCLUSIVE_FROM_DISTANCE`: đoạn thuộc đợt chờ không cộng vào quãng đường.
4. `distanceM = Σ mm ~/ 1000`; hiệu chuẩn theo `gps.calibrationApplyOrder` (BEFORE/AFTER_OPENING_KM); `billableM` sau khi trừ `opening.includedMeters`.
5. Luỹ tiến bậc thang trên `billableM` (`upToMeters` inclusive, null = vô hạn).
6. Phụ phí theo `surchargePipeline`: MULTIPLIER nhân từng thành phần trong `appliesTo`, sau đó FIXED cộng; điều kiện `TIME_RANGE` đánh giá theo `contexts.tripStartTimeMs` (TRIP_START_TIME).
7. **Làm tròn đúng 1 lần ở cuối** theo `rounding.unitVnd`/`mode` (ROUND_HALF_UP, FLOOR, CEIL).
8. `fareHash = sha256(contentSha256 + fareTotal + tripId)`; `contentSha256` = sha256 của config bỏ khoá `integrity`.

### Thang số nguyên
Trung gian ở thang `fareScale = 18000` (VND x 18000): distance = đơn giá/km x m x 18; waiting = đơn giá/giờ x giây x 5; phụ phí nhân permille trên thang này; cuối cùng chia thang và làm tròn. Chi tiết quyết định: `docs/CONTEXT_STATE.md`.

## Edge cases
- Chuyến 0 điểm / 1 điểm → distance 0, chỉ tính opening.
- `calibratedM <= includedMeters` → distance fare 0.
- Đúng biên `upToMeters` (inclusive) chuyển bậc.
- Chờ ngắn hơn `graceSeconds` → 0.
- Tốc độ dao động quanh ngưỡng → hysteresis không nháy trạng thái.
- Nhiều phụ phí MULTIPLIER cùng lúc; phụ phí FIXED sau cùng.
- Làm tròn mọi mode (HALF_UP, UP, DOWN, bội số 500/1000 VND nếu config hỗ trợ).
- Số rất lớn (chuyến dài >500 km) không tràn (Dart int 64-bit).

## Fixture mẫu (đã tính tay)
Opening 10 000 VND gồm 1 000 m; bậc 1 đến 30 000 m billable: 15 000 VND/km (bậc 2: 12 000); chờ 120 000 VND/giờ, grace 30 s; calibration 1000‰; không phụ phí (xem `test/test_support.dart`). Chuyến 3 000 m → billable 2 000 m → distance 30 000 → total **40 000 VND**.

## 12 unit test bắt buộc
- T1: chuyến 0 m → chỉ opening.
- T2: distance < includedMeters → distance fare 0.
- T3: ví dụ fixture 3 000 m → 40 000 VND.
- T4: chuyển bậc đúng biên `upToMeters` (inclusive).
- T5: calibration BEFORE_OPENING_KM vs AFTER_OPENING_KM.
- T6: chờ < grace → waiting 0.
- T7: chờ > grace → tính theo giờ, trừ grace; đoạn chờ không tính vào quãng đường (EXCLUSIVE_FROM_DISTANCE).
- T8: hysteresis enter/exit không nháy.
- T9: phụ phí MULTIPLIER một lần trên baseFare (nhiều hệ số).
- T10: phụ phí FIXED cộng sau bước nhân.
- T11: làm tròn một lần duy nhất, mọi mode.
- T12: `fareHash` ổn định; đổi 1 trường → hash đổi; replay hai lần khớp từng byte.
- Bổ sung: T7b (đợt chờ ngắn bị bỏ), T8b (tốc độ -1 suy ra từ vị trí), T9b (appliesTo), T10b (phụ phí đêm theo TRIP_START_TIME, biên 22:00, nửa đêm, ngày trong tuần), kiểm `fromJson`.
- E8: `test/golden/replay_golden_test.dart` + `test/fixtures/trip_00*.json` (do chủ dự án cung cấp).

## Golden replay
5 file GPX mẫu trong `test/golden/` (+ `.expected.json` chứa distance_m, waiting_sec, fare_total_vnd, fare_hash). Test chạy GpsPolicy → Engine và so khớp byte-for-byte. Thay đổi expected phải có lý do ghi trong CONTEXT_STATE.
