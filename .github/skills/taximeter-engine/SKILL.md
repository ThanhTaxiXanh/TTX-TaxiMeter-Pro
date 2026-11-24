---
name: taximeter-engine
description: Đặc tả tính cước số nguyên (TaximeterEngine PURE), bậc thang, hysteresis chờ, phụ phí, làm tròn, fareHash, 12 unit test T1–T12 và golden GPX replay.
---

# Skill: taximeter-engine

File: `lib/core/taximeter_engine.dart` (PURE). Đầu vào: danh sách điểm ACCEPTED (từ GpsPolicy), `TariffConfigV2`, `tripId`. Đầu ra: `FareResult` + `fareHash`.

## Quy tắc
- Chỉ `int`. Mét, giây, VND, permille. Không `double`, không `DateTime.now()`, không `Random`, không I/O.
- Cùng đầu vào → cùng kết quả byte-for-byte.

## Thuật toán
1. `cumulativeDistanceM`: tổng khoảng cách giữa các điểm ACCEPTED liên tiếp, làm tròn về mét nguyên theo cùng một hàm cố định (haversine số nguyên hoặc equirectangular từ lat_e7/lng_e7; chọn 1 cách ở Phase 1 và ghi vào CONTEXT_STATE, không đổi sau đó).
2. `calibratedM = cumulativeDistanceM * calibrationFactorPermille ~/ 1000` (áp dụng BEFORE_OPENING_KM hoặc AFTER_OPENING_KM theo config).
3. `billableM = max(0, calibratedM - opening.includedMeters)`.
4. Lũy tiến bậc thang trên `billableM`: mỗi bậc có `upToMeters` (inclusive, theo tổng billableM) và đơn giá VND/km. Mét nào rơi vào bậc nào tính theo bậc đó.
5. `waitingFare`: chỉ cộng khi state = WAITING.
   - Hysteresis: vào WAITING khi tốc độ < `enterThresholdKmh`, ra khi > `exitThresholdKmh` (exit > enter).
   - Trừ `graceSeconds` đầu mỗi đợt chờ, tính phần còn lại theo `countingPolicy`.
6. `baseFare = opening + distance + waiting` (VND).
7. Phụ phí MULTIPLIER: `baseFare * Π(permille) ~/ 1000` — một phép nhân trên tổng baseFare. Phụ phí FIXED: cộng thẳng sau bước nhân.
8. **Làm tròn đúng 1 lần ở cuối** theo `rounding.mode`.
9. `fareHash = sha256(configSha256 + fareTotalVnd + tripId)` (nối chuỗi thập phân, UTF-8, không dấu phân cách; ghi rõ trong code và test).

### Gợi ý độ chính xác số nguyên (đề xuất, chốt ở Phase 1)
Để làm tròn đúng 1 lần mà không dùng `double`, giữ trung gian ở thang `S = 60_000` (VND x 60000): distance = `rateVndPerKm * m * 60`, waiting = `rateVndPerMin * sec * 1000`, opening x 60000; phụ phí nhân permille trên thang này; cuối cùng chia S và làm tròn theo `rounding.mode`.

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
Opening 10 000 VND gồm 1 000 m; bậc 1 đến 30 000 m billable: 15 000 VND/km; calibration 1000‰; không chờ, không phụ phí. Chuyến 3 000 m → billable 2 000 m → distance 30 000 → total **40 000 VND**.

## 12 unit test bắt buộc
- T1: chuyến 0 m → chỉ opening.
- T2: distance < includedMeters → distance fare 0.
- T3: ví dụ fixture 3 000 m → 40 000 VND.
- T4: chuyển bậc đúng biên `upToMeters` (inclusive).
- T5: calibration BEFORE_OPENING_KM vs AFTER_OPENING_KM.
- T6: chờ < grace → waiting 0.
- T7: chờ > grace → tính đúng theo countingPolicy.
- T8: hysteresis enter/exit không nháy.
- T9: phụ phí MULTIPLIER một lần trên baseFare (nhiều hệ số).
- T10: phụ phí FIXED cộng sau bước nhân.
- T11: làm tròn một lần duy nhất, mọi mode.
- T12: `fareHash` ổn định; đổi 1 trường → hash đổi; replay hai lần khớp từng byte.

## Golden replay
5 file GPX mẫu trong `test/golden/` (+ `.expected.json` chứa distance_m, waiting_sec, fare_total_vnd, fare_hash). Test chạy GpsPolicy → Engine và so khớp byte-for-byte. Thay đổi expected phải có lý do ghi trong CONTEXT_STATE.
