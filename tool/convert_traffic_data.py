#!/usr/bin/env python3
"""Chuyen GeoJSON bien bao/POI thanh asset nho gon (so nguyen) cho app.

Dung: python3 tool/convert_traffic_data.py <signs.geojson> <poi.geojson>
Ra:   assets/data/signs.bin, assets/data/poi.json

signs.bin: 'TSG1' + u32 count + count * <i4 latE7, i4 lngE7, u1 cat, u2 dir, u2 value>
  cat = type_index cua nguon: 0 built_up_end, 1 built_up_start, 2 max_speed,
  3 no_overtaking, 4 p133, 5 rest_area, 6 speed_camera, 7 street_camera,
  8 toll_booth, 9 tunnel. dir: do (0..359) hoac 65535 neu khong co.
  value: toc do toi da km/h (max_speed) hoac 65535.
"""
import json, struct, sys

CATS = ['built_up_end', 'built_up_start', 'max_speed', 'no_overtaking', 'p133',
        'rest_area', 'speed_camera', 'street_camera', 'toll_booth', 'tunnel']
POI_KINDS = ['fuel', 'charging_station', 'charging_station_motorcycle']

def e7(v):
    return int(round(v * 10_000_000))

def main(signs_path, poi_path):
    feats = json.load(open(signs_path))['features']
    out = bytearray(b'TSG1' + struct.pack('<I', len(feats)))
    for f in feats:
        p = f['properties']
        lng, lat = f['geometry']['coordinates'][:2]
        cat = CATS.index(p['category'])
        assert cat == p['type_index'], (cat, p)
        d = p['direction_raw']
        out += struct.pack('<iiBHH', e7(lat), e7(lng), cat,
                           d if 0 <= d < 360 else 65535,
                           min(int(p['value_raw']), 65535))
    open('assets/data/signs.bin', 'wb').write(out)
    poi = []
    for f in json.load(open(poi_path))['features']:
        lng, lat = f['geometry']['coordinates'][:2]
        poi.append([e7(lat), e7(lng), POI_KINDS.index(f['properties']['kind']),
                    f['properties'].get('name') or ''])
    json.dump({'kinds': POI_KINDS, 'poi': poi}, open('assets/data/poi.json', 'w'),
              ensure_ascii=False, separators=(',', ':'))
    print(len(feats), 'signs;', len(poi), 'poi')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
