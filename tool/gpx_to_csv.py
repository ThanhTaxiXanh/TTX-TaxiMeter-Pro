#!/usr/bin/env python3
"""Chuyen GPX (Odo/Speedometer) sang CSV so nguyen cho golden replay.

Dung mot lan de tao test/golden/*.csv. Cot: ts_ms,lat_e7,lng_e7,speed_mmps.
GPX khong co accuracy -> test dung accuracy co dinh 5 m.

Cach dung: python3 tool/gpx_to_csv.py <file.gpx> <ten_slug>
"""
import datetime
import re
import sys

src, slug = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
pat = re.compile(
    r'<trkpt lat="([-\d.]+)" lon="([-\d.]+)">\s*<ele>[^<]*</ele>\s*'
    r'<time>([^<]+)</time>\s*<speed>([^<]+)</speed>'
)
rows = []
for lat, lon, ts, spd in pat.findall(text):
    t = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=datetime.timezone.utc
    )
    rows.append((int(t.timestamp()) * 1000, round(float(lat) * 1e7),
                 round(float(lon) * 1e7), round(float(spd) * 1000)))
out = f"test/golden/{slug}.csv"
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("ts_ms,lat_e7,lng_e7,speed_mmps\n")
    for r in rows:
        f.write(",".join(str(x) for x in r) + "\n")
print(out, len(rows))
