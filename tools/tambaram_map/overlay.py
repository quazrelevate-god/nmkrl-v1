"""Draw the exported wards over OpenStreetMap tiles (for checking by eye)."""
import json, math, os, subprocess, sys
import cv2, numpy as np
UA = "namkural-tambaram-georef/0.1 (pilot ward mapping)"

def lonlat_to_tile(lon, lat, z):
    n = 2 ** z
    x = (lon + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return x, y

def render(bbox, z, out, label=True, width=None):
    lon0, lat0, lon1, lat1 = bbox
    x0, y1 = lonlat_to_tile(lon0, lat0, z); x1, y0 = lonlat_to_tile(lon1, lat1, z)
    tx = range(int(x0), int(x1) + 1); ty = range(int(y0), int(y1) + 1)
    canvas = np.zeros((len(ty) * 256, len(tx) * 256, 3), np.uint8)
    for j, y in enumerate(ty):
        for i, x in enumerate(tx):
            p = f"tiles/{z}_{x}_{y}.png"
            if not os.path.exists(p):
                subprocess.run(["curl", "-s", "-m", "30", "-A", UA, "-o", p,
                                f"https://tile.openstreetmap.org/{z}/{x}/{y}.png"], check=False)
            t = cv2.imread(p)
            if t is not None:
                canvas[j * 256:(j + 1) * 256, i * 256:(i + 1) * 256] = t
    ox, oy = tx[0], ty[0]
    def px(lon, lat):
        x, y = lonlat_to_tile(lon, lat, z)
        return (int(round((x - ox) * 256)), int(round((y - oy) * 256)))
    W = json.load(open("tambaram_wards.geojson")); Z = json.load(open("tambaram_zones.geojson"))
    C = {"1": (79, 83, 217), "2": (79, 157, 46), "3": (214, 111, 47), "4": (181, 63, 155), "5": (0, 154, 217)}
    tint = canvas.copy()
    def rings(geom):
        polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
        for p in polys:
            yield [np.array([px(lo, la) for lo, la in r], np.int32) for r in p]
    for f in W["features"]:
        for rs in rings(f["geometry"]):
            cv2.fillPoly(tint, rs, C[f["properties"]["zone"]])
    canvas = cv2.addWeighted(canvas, 0.78, tint, 0.22, 0)
    for f in W["features"]:
        for rs in rings(f["geometry"]):
            cv2.polylines(canvas, rs, True, (0, 0, 200), 1, cv2.LINE_AA)
    for f in Z["features"]:
        for rs in rings(f["geometry"]):
            cv2.polylines(canvas, rs, True, (110, 26, 26), 3, cv2.LINE_AA)
    if label:
        rows = [l.strip().split(",") for l in open("tambaram_ward_list.csv").readlines()[1:]]
        for r in rows:
            x, y = px(float(r[5]), float(r[4]))
            cv2.putText(canvas, r[0], (x - 9, y + 5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 3, cv2.LINE_AA)
            cv2.putText(canvas, r[0], (x - 9, y + 5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1, cv2.LINE_AA)
    a, b = px(lon0, lat1), px(lon1, lat0)
    canvas = canvas[max(a[1], 0):b[1], max(a[0], 0):b[0]]
    if width:
        canvas = cv2.resize(canvas, (width, int(canvas.shape[0] * width / canvas.shape[1])), interpolation=cv2.INTER_AREA)
    cv2.imwrite(out, canvas)
    print("wrote", out, canvas.shape)

if __name__ == "__main__":
    render((80.074, 12.881, 80.197, 12.994), 14, "osm_overlay.png")
