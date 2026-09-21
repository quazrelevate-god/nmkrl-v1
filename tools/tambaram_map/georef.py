"""Fit map pixels -> lat/lng from ground-control points (OpenStreetMap).

Anchors: railway stations (RS icons read off the map) and named lakes
(map lake blob centroid <-> OSM polygon centroid). Local metric plane around
LAT0/LON0; affine least squares; per-point residuals in metres.
"""
import json
import math

import numpy as np

LAT0, LON0 = 12.93, 80.12
KX = math.cos(math.radians(LAT0)) * 111_320.0
KY = 110_574.0
F = 6000 / 1600  # 1600-px map units -> full-res px


def to_xy(lat, lon):
    return ((lon - LON0) * KX, (lat - LAT0) * KY)


def to_ll(x, y):
    return (LAT0 + y / KY, LON0 + x / KX)


def ring_centroid(coords):
    """Area centroid of a closed lon/lat ring, in the local plane."""
    pts = np.array([to_xy(la, lo) for lo, la in coords])
    x, y = pts[:, 0], pts[:, 1]
    x1, y1 = np.roll(x, -1), np.roll(y, -1)
    cr = x * y1 - x1 * y
    a = cr.sum() / 2
    return (float(((x + x1) * cr).sum() / (6 * a)), float(((y + y1) * cr).sum() / (6 * a)), abs(a))


def poly_centroid(rings):
    """Area-weighted centroid over outer rings (lists of [lon, lat])."""
    cs = [ring_centroid(r) for r in rings]
    A = sum(c[2] for c in cs)
    return (sum(c[0] * c[2] for c in cs) / A, sum(c[1] * c[2] for c in cs) / A, A)


osm = {}
for e in json.load(open("osm_lakegeom.json"))["elements"]:
    ring = [[p["lon"], p["lat"]] for p in e["geometry"]]
    osm[f"way/{e['id']}"] = (e["tags"].get("name"), poly_centroid([ring]))
for fn in ["nom_Pallavaram_Lake.json", "nom_Keelkattalai_Lake.json"]:
    for x in json.load(open(fn)):
        if x["osm_type"] != "relation":
            continue
        g = x["geojson"]
        rings = [g["coordinates"][0]] if g["type"] == "Polygon" else [p[0] for p in g["coordinates"]]
        osm[f"relation/{x['osm_id']}"] = (x["display_name"].split(",")[0], poly_centroid(rings))
stations = {s["tags"]["name"]: to_xy(s["lat"], s["lon"])
            for s in json.load(open("osm_st.json"))["elements"]}

lakes_px = {f"L{L['id']}": (L["cx"], L["cy"]) for L in json.load(open("lakes_px.json"))}

# (label, map px full-res, OSM xy)
ANCHORS = [
    ("Pallavaram RS", (1043.8 * F, 341.5 * F), stations["Pallavaram"]),
    ("Chromepet RS", (912.1 * F, 537.6 * F), stations["Chromepet"]),
    ("Tambaram Sanatorium RS", (801.1 * F, 698.9 * F), stations["Tambaram Sanatorium"]),
    ("Perungalathur RS", (385.9 * F, 1064.0 * F), stations["Perungalattur"]),
    ("Pallavaram Lake (L2)", lakes_px["L2"], osm["relation/16916505"][1][:2]),
    ("Keelkattalai Lake (L4)", lakes_px["L4"], osm["relation/13671410"][1][:2]),
    ("Sembakkam Lake (L5)", lakes_px["L5"], osm["way/26433707"][1][:2]),
    ("Chitlapakkam Lake (L6)", lakes_px["L6"], osm["way/23648229"][1][:2]),
    ("Selaiyur Lake (L10)", lakes_px["L10"], osm["way/28260577"][1][:2]),
]
# Unsure pairings: judged by how far the fitted map puts them from OSM.
CHECKS = [
    ("Tambaram RS (no icon; yard by navy line)", (656 * F, 838 * F), stations["Tambaram"]),
    ("L3 Periya Eri ~ Tiruneermalai Eri", lakes_px["L3"], osm["way/23648233"][1][:2]),
    ("L7 Kadaperi ~ Kadaperi Lake", lakes_px["L7"], osm["way/23648227"][1][:2]),
    ("L7 Kadaperi ~ Kadaperi Tank", lakes_px["L7"], osm["way/384364812"][1][:2]),
    ("L9 ~ Rajakilpakkam Lake", lakes_px["L9"], osm["way/47572261"][1][:2]),
    ("L8 ~ Irumbuliyur Lake", lakes_px["L8"], osm["way/23648228"][1][:2]),
    ("L11 ~ Irumbuliyur Lake", lakes_px["L11"], osm["way/23648228"][1][:2]),
    ("L11 ~ Balaji Nagar Lake", lakes_px["L11"], osm["way/28261148"][1][:2]),
    ("L8 ~ Balaji Nagar Lake", lakes_px["L8"], osm["way/28261148"][1][:2]),
    ("L13 ~ New Perungalathur Lake", lakes_px["L13"], osm["way/32253842"][1][:2]),
    ("L12 ~ New Perungalathur Lake", lakes_px["L12"], osm["way/32253842"][1][:2]),
]


def fit(rows):
    P = np.array([[px, py, 1.0] for _, (px, py), _ in rows])
    Q = np.array([q for _, _, q in rows])
    M, *_ = np.linalg.lstsq(P, Q, rcond=None)
    return M  # 3x2


def apply(M, px, py):
    return tuple(np.array([px, py, 1.0]) @ M)


def report(M, rows, title):
    print(title)
    errs = []
    for name, (px, py), q in rows:
        x, y = apply(M, px, py)
        e = math.hypot(x - q[0], y - q[1])
        errs.append(e)
        print(f"  {name:44s} off by {e:6.0f} m  (dx {x - q[0]:+6.0f}, dy {y - q[1]:+6.0f})")
    return errs


# Lakes the first fit confirmed (each 8-113 m off; the rival pairings were
# 500-900 m off), promoted to anchors. Tambaram RS stays a check: no icon.
CONFIRMED = [c for c in CHECKS if c[0] in (
    "L3 Periya Eri ~ Tiruneermalai Eri", "L7 Kadaperi ~ Kadaperi Lake",
    "L9 ~ Rajakilpakkam Lake", "L8 ~ Irumbuliyur Lake",
    "L11 ~ Balaji Nagar Lake", "L13 ~ New Perungalathur Lake")]


def leave_one_out(rows):
    out = []
    for i, (name, (px, py), q) in enumerate(rows):
        M = fit(rows[:i] + rows[i + 1:])
        x, y = apply(M, px, py)
        out.append((name, math.hypot(x - q[0], y - q[1])))
    return out


if __name__ == "__main__":
    ALL = ANCHORS + CONFIRMED
    loo = leave_one_out(ALL)
    print("leave-one-out (each point predicted by a fit WITHOUT it):")
    for name, e in loo:
        print(f"  {name:44s} {e:6.0f} m")
    print(f"  median {np.median([e for _, e in loo]):.0f} m, max {max(e for _, e in loo):.0f} m")
    M = fit(ALL)
    e = report(M, ALL, "final fit on all %d points:" % len(ALL))
    print(f"  RMS {math.sqrt(np.mean(np.square(e))):.0f} m")
    report(M, CHECKS[:1], "check (not used in the fit):")
    A = M[:2, :]
    mpp = math.sqrt(abs(np.linalg.det(A)))
    rot = math.degrees(math.atan2(A[0, 1], A[0, 0]))
    sx = math.hypot(A[0, 0], A[0, 1]); sy = math.hypot(A[1, 0], A[1, 1])
    print(f"scale {mpp:.3f} m/px (x {sx:.3f}, y {sy:.3f}), rotation {rot:+.2f} deg")
    land = int((np.load("wards_final.npy") > 0).sum())
    print(f"land {land:,} px -> {land * abs(np.linalg.det(A)) / 1e6:.2f} km2 (printed: 87.64)")
    json.dump({"lat0": LAT0, "lon0": LON0, "kx": KX, "ky": KY, "M": M.tolist()},
              open("georef_affine.json", "w"), indent=1)
