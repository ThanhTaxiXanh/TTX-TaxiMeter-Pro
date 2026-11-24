---
name: gps-and-offline-map
description: Bộ lọc GPS 6 tầng (GpsPolicy PURE, G1–G8) và LocalHttpTileServer phục vụ PMTiles offline cho MapLibre qua HTTP Range.
---

# Skill: gps-and-offline-map

## A. GpsPolicy (`lib/core/gps_policy.dart`, PURE)
Không đọc đồng hồ hệ thống: thời gian lấy từ `tsMs` của điểm. Tọa độ `lat_e7/lng_e7`, độ chính xác `accuracy_mm`, tốc độ `speed_mmps` (int).

6 tầng tuần tự:
1. **Sanity:** lat/lng hợp lệ; `tsMs > prevTsMs`. Sai → REJECT.
2. **Mock:** `isMock` → gắn cờ SUSPICIOUS nhưng vẫn ACCEPT.
3. **Accuracy gate thích ứng theo thời gian mất GPS:** ngưỡng 20 m → nới 35 m → PAUSED (ngưỡng chuyển do config; đo bằng `tsMs`).
4. **Teleport gate:** nếu `dt >= 0.5 s` (500 ms) và vận tốc ngụ ý > `maxSpeedKmh` → REJECT (tính bằng số nguyên).
5. **Anchor drift guard:** tốc độ < 1.5 m/s (1500 mm/s) và accuracy > 8 m và khoảng cách tới anchor < 2 x accuracy → REJECT (đứng yên, chống trôi).
6. **Smoothing:** cửa sổ 3 mẫu, trọng số 1/accuracy² (dùng tỷ lệ số nguyên, không double).

Mỗi điểm lưu vào `raw_gps_points` với `decision` (ACCEPTED/REJECTED/PAUSED) và `reject_reason`.

### 8 unit test bắt buộc
- G1: tọa độ ngoài miền / ts không tăng → REJECT.
- G2: isMock → ACCEPT + cờ SUSPICIOUS.
- G3: accuracy 25 m khi vừa mất GPS → REJECT; sau thời gian dài → ngưỡng 35 m; quá nữa → PAUSED.
- G4: teleport (dt >= 0.5 s, v > max) → REJECT.
- G5: dt < 0.5 s → bỏ qua teleport gate.
- G6: anchor drift: đứng yên + accuracy xấu → REJECT; di chuyển thật → ACCEPT.
- G7: smoothing 3 mẫu đúng trọng số, kết quả int xác định.
- G8: replay cùng chuỗi điểm hai lần → quyết định giống hệt.

## B. LocalHttpTileServer (`lib/data/services/local_tile_server.dart`)
- `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` — cổng ngẫu nhiên, chỉ loopback.
- Đọc header (127 byte) và directory của file `.pmtiles` (v3) bằng Dart thuần, giải nén directory theo header (gzip qua `dart:io`/`archive`), tra tile theo (z, x, y) → offset/length.
- Phục vụ `GET /tiles/{z}/{x}/{y}.mvt` bằng đọc theo khoảng của file (RandomAccessFile), hỗ trợ **HTTP Range** (`206 Partial Content`, `Content-Range`, `Accept-Ranges: bytes`).
- Trả `Content-Encoding: gzip` nếu tile nén gzip; 404 nếu tile không có.
- `maplibre_gl` dùng style trỏ `http://127.0.0.1:<port>/tiles/{z}/{x}/{y}.mvt`. Dừng server khi thoát MapScreen/app.
- Test: file PMTiles nhỏ trong `test/fixtures/`, kiểm tra Range và 404.
- Phase 5 mới triển khai; không thêm gói mạng nào.

## C. Biển báo giới hạn tốc độ (QCVN)
Viền đỏ, nền trắng, chữ đen. Tốc độ mặc định theo loại đường (config); chạm biển trên map để tạo `traffic_override` (kind=SPEED_LIMIT) nhanh.
