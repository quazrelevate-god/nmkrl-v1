"""wards_final.npy + georef_affine.json -> Tambaram GeoJSON + KML.

Run with the backend venv (numpy + shapely 2.1):
  backend/venv/bin/python export.py

Wards are built from their exact pixels (row runs -> boxes -> union), so
neighbours share identical edges; coverage_simplify then removes the pixel
staircase without opening gaps or overlaps between wards. Zones are the
dissolve of their wards. KML matches what backend/boundaries.py reads:
zones carry ZONE (roman) + ZONE_NAME, wards carry SimpleData name = ward no.
"""
import json
from xml.sax.saxutils import escape

import numpy as np
import shapely
from shapely.geometry import mapping

ZONE_NAMES = {  # from the user; matches the map's ZONE 1-5 labels
    1: "PAMMAL",
    2: "PALLAVARAM",
    3: "SEMBAKKAM",
    4: "PERUNGALATHUR",
    5: "EAST TAMBARAM",
}
ROMAN = {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V"}
TOL_PX = 1.5  # ~3.8 m

lab = np.load("wards_final.npy")
zones_of = {int(w): z for w, z in json.load(open("zones_final.json")).items()}
g = json.load(open("georef_affine.json"))
M = np.array(g["M"])

# 1) Exact pixel polygons (pixel-edge coordinates).
H, W = lab.shape
boxes = {w: [] for w in zones_of}
for y in range(H):
    row = lab[y]
    change = np.flatnonzero(np.diff(row)) + 1
    starts = np.concatenate([[0], change])
    ends = np.concatenate([change, [W]])
    for s, e in zip(starts, ends):
        v = int(row[s])
        if v:
            boxes[v].append((s, y, e, y + 1))
wards = sorted(zones_of)
px_geoms = []
for w in wards:
    b = np.array(boxes[w], dtype=float)
    px_geoms.append(shapely.union_all(shapely.box(b[:, 0], b[:, 1], b[:, 2], b[:, 3])))
px_geoms = np.array(px_geoms, dtype=object)
print("pieces per ward (should all be 1):",
      {w: shapely.get_num_geometries(gm) for w, gm in zip(wards, px_geoms)
       if shapely.get_num_geometries(gm) != 1} or "all 1")

# 2) Node the coverage: box unions drop collinear points, so one ward may have
#    a vertex mid-way along an edge its neighbour draws straight through, and
#    coverage_simplify then treats the edge as unshared. Every edge runs along
#    whole-pixel lines, so a vertex at every pixel step makes both sides of a
#    shared border identical point for point.
px_geoms = shapely.segmentize(px_geoms, 1.0)
print("coverage valid before simplify:", bool(shapely.coverage_is_valid(px_geoms)))

# 3) Simplify the coverage as a whole.
simp = shapely.coverage_simplify(px_geoms, tolerance=TOL_PX)
print("coverage valid after simplify:", bool(shapely.coverage_is_valid(simp)))


# 4) Pixel -> lon/lat. Edge coords -> pixel-index coords (-0.5), the
#    convention the control points were measured in.
def to_lonlat(xy):
    P = np.column_stack([xy[:, 0] - 0.5, xy[:, 1] - 0.5, np.ones(len(xy))])
    m = P @ M
    return np.column_stack([g["lon0"] + m[:, 0] / g["kx"], g["lat0"] + m[:, 1] / g["ky"]])


def to_metres(xy):
    P = np.column_stack([xy[:, 0] - 0.5, xy[:, 1] - 0.5, np.ones(len(xy))])
    return P @ M


ll = shapely.transform(simp, to_lonlat)
met = shapely.transform(simp, to_metres)
ll = np.array([shapely.make_valid(x) if not x.is_valid else x for x in ll], dtype=object)

area_km2 = {w: float(shapely.area(m)) / 1e6 for w, m in zip(wards, met)}
total = sum(area_km2.values())
overlap = sum(area_km2.values()) - float(shapely.area(shapely.union_all(met))) / 1e6
print(f"total ward area {total:.2f} km2 (printed map says 87.64); overlap {overlap * 1e6:.1f} m2")

zone_ll = {z: shapely.union_all([gm for w, gm in zip(wards, ll) if zones_of[w] == z])
           for z in sorted(set(zones_of.values()))}
zone_km2 = {z: sum(a for w, a in area_km2.items() if zones_of[w] == z) for z in zone_ll}

# 5) GeoJSON (the shape the app's /boundaries endpoint serves).
def rnd(geom):
    return shapely.set_precision(geom, 1e-7)


wards_fc = {"type": "FeatureCollection", "features": [
    {"type": "Feature",
     "properties": {"ward": str(w), "zone": str(zones_of[w]),
                    "zone_name": ZONE_NAMES[zones_of[w]], "area_km2": round(area_km2[w], 3)},
     "geometry": mapping(rnd(gm))}
    for w, gm in zip(wards, ll)]}
zones_fc = {"type": "FeatureCollection", "features": [
    {"type": "Feature",
     "properties": {"zone": str(z), "zone_name": ZONE_NAMES[z], "area_km2": round(zone_km2[z], 2),
                    "wards": [w for w in wards if zones_of[w] == z]},
     "geometry": mapping(rnd(gm))}
    for z, gm in zone_ll.items()]}
json.dump(wards_fc, open("tambaram_wards.geojson", "w"))
json.dump(zones_fc, open("tambaram_zones.geojson", "w"))


# 6) KML, in the fields backend/boundaries.py reads.
def kml_polys(geom):
    out = []
    for p in getattr(geom, "geoms", [geom]):
        if p.geom_type != "Polygon":
            continue
        def ring(r):
            return " ".join(f"{x:.7f},{y:.7f},0" for x, y in r.coords)
        inner = "".join(f"<innerBoundaryIs><LinearRing><coordinates>{ring(i)}</coordinates>"
                        f"</LinearRing></innerBoundaryIs>" for i in p.interiors)
        out.append(f"<Polygon><outerBoundaryIs><LinearRing><coordinates>{ring(p.exterior)}"
                   f"</coordinates></LinearRing></outerBoundaryIs>{inner}</Polygon>")
    return "<MultiGeometry>" + "".join(out) + "</MultiGeometry>"


HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<kml xmlns="http://www.opengis.net/kml/2.2"><Document><name>{}</name>\n')
with open("wards.kml", "w") as f:
    f.write(HEAD.format("Tambaram-Wards"))
    for w, gm in zip(wards, ll):
        f.write(f'<Placemark><name>{w}</name><ExtendedData><SchemaData schemaUrl="#tambaram_wards">'
                f'<SimpleData name="id_2">TMB_{w:02d}</SimpleData><SimpleData name="name">{w}</SimpleData>'
                f'<SimpleData name="zone">{zones_of[w]}</SimpleData>'
                f'</SchemaData></ExtendedData>{kml_polys(gm)}</Placemark>\n')
    f.write("</Document></kml>\n")
with open("zones.kml", "w") as f:
    f.write(HEAD.format("Tambaram-Zones"))
    for z, gm in zone_ll.items():
        f.write(f'<Placemark><name>{escape(ZONE_NAMES[z])}</name><ExtendedData>'
                f'<SchemaData schemaUrl="#tambaram_zones"><SimpleData name="Region">TAMBARAM</SimpleData>'
                f'<SimpleData name="ZONE">{ROMAN[z]}</SimpleData>'
                f'<SimpleData name="ZONE_NAME">{escape(ZONE_NAMES[z])}</SimpleData>'
                f'</SchemaData></ExtendedData>{kml_polys(gm)}</Placemark>\n')
    f.write("</Document></kml>\n")

# 7) Ward list (for the user / Yokesh).
with open("tambaram_ward_list.csv", "w") as f:
    f.write("ward,zone,zone_name,area_km2,centre_lat,centre_lng\n")
    for w, gm in zip(wards, ll):
        c = gm.representative_point()
        f.write(f"{w},{zones_of[w]},{ZONE_NAMES[zones_of[w]]},{area_km2[w]:.3f},{c.y:.6f},{c.x:.6f}\n")
for z in zone_ll:
    ws = [w for w in wards if zones_of[w] == z]
    print(f"zone {z} {ZONE_NAMES[z]:14s} {len(ws):2d} wards {zone_km2[z]:6.2f} km2  {ws}")
print("vertices per ward: median", int(np.median([shapely.get_num_coordinates(x) for x in ll])))
print("bbox lon/lat:", [round(v, 4) for v in shapely.total_bounds(ll)])
