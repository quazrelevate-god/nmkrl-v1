"""Base OSM image + printed map warped onto the same Web Mercator pixel grid."""
import json, math, os, subprocess
import cv2, numpy as np
UA = "namkural-tambaram-georef/0.1 (pilot ward mapping)"
Z = 15
LON0, LAT0, LON1, LAT1 = 80.0700, 12.8790, 80.2010, 12.9965   # corp bbox + ~800 m

def fx(lon): return (lon + 180) / 360 * 256 * 2 ** Z
def fy(lat): return (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * 256 * 2 ** Z
def lon_of(x): return x / (256 * 2 ** Z) * 360 - 180
def lat_of(y): return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / (256 * 2 ** Z)))))

X0, X1 = int(fx(LON0)), int(math.ceil(fx(LON1)))
Y0, Y1 = int(fy(LAT1)), int(math.ceil(fy(LAT0)))
W, H = X1 - X0, Y1 - Y0
base = np.full((H, W, 3), 242, np.uint8)
for ty in range(Y0 // 256, Y1 // 256 + 1):
    for tx in range(X0 // 256, X1 // 256 + 1):
        p = f"tiles/{Z}_{tx}_{ty}.png"
        if not os.path.exists(p):
            subprocess.run(["curl", "-s", "-m", "30", "-A", UA, "-o", p,
                            f"https://tile.openstreetmap.org/{Z}/{tx}/{ty}.png"], check=False)
        t = cv2.imread(p)
        if t is None:
            continue
        ox, oy = tx * 256 - X0, ty * 256 - Y0
        xs, ys = max(ox, 0), max(oy, 0)
        xe, ye = min(ox + 256, W), min(oy + 256, H)
        base[ys:ye, xs:xe] = t[ys - oy:ye - oy, xs - ox:xe - ox]
cv2.imwrite("page_base.jpg", base, [cv2.IMWRITE_JPEG_QUALITY, 68])

# Printed map: for every output pixel, lat/lon -> local metres -> map pixel.
g = json.load(open("georef_affine.json")); M = np.array(g["M"]); A, t = M[:2], M[2]
Ainv = np.linalg.inv(A.T)
xs = np.array([lon_of(X0 + i + 0.5) for i in range(W)])
ys = np.array([lat_of(Y0 + j + 0.5) for j in range(H)])
mx = (xs - g["lon0"]) * g["kx"]; my = (ys - g["lat0"]) * g["ky"]
MX, MY = np.meshgrid(mx, my)
V = np.stack([MX.ravel() - t[0], MY.ravel() - t[1]])
P = Ainv @ V
mapx = P[0].reshape(H, W).astype(np.float32); mapy = P[1].reshape(H, W).astype(np.float32)
src = cv2.imread("Tambaram-Municipal-Corporation-Ward-Map_Display-map.pdf.png")
printed = cv2.remap(src, mapx, mapy, cv2.INTER_AREA if False else cv2.INTER_LINEAR,
                    borderMode=cv2.BORDER_CONSTANT, borderValue=(255, 255, 255))
cv2.imwrite("page_printed.jpg", printed, [cv2.IMWRITE_JPEG_QUALITY, 62])
bounds = [[lat_of(Y1), lon_of(X0)], [lat_of(Y0), lon_of(X1)]]
json.dump({"bounds": bounds, "size": [W, H]}, open("page_bounds.json", "w"))
print("grid", W, "x", H, "bounds", bounds)
for f in ("page_base.jpg", "page_printed.jpg"):
    print(f, os.path.getsize(f) // 1024, "KB")
