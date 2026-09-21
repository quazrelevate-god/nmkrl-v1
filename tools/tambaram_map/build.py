"""Tambaram ward map -> labelled ward raster + pixel polygons + zones.

Inputs (same dir): the 6000x5000 render, red.npy / navy.npy line masks,
bnd_best.npy (red|navy sealed with L25 line closing), seeds_full.json
(ward circle centres, full-res), seeds_1600.json (zone label centres).
Outputs: wards_final.npy, zones_final.json, polygons_px.json, verify.png.
"""
import json
from collections import Counter, defaultdict

import cv2
import numpy as np
from scipy import ndimage as ndi

img = cv2.imread("Tambaram-Municipal-Corporation-Ward-Map_Display-map.pdf.png")
H, W = img.shape[:2]
red = np.load("red.npy")
navy = np.load("navy.npy")
b25 = np.load("bnd_best.npy")
seeds = {int(w): tuple(v) for w, v in json.load(open("seeds_full.json")).items()}
S = json.load(open("seeds_1600.json"))
k = W / 1600
zlab = {int(z): (int(x * k), int(y * k)) for z, (x, y) in S["zone_labels"].items()}

# Read off the map by eye (ward9_orig.png / ward9_south.png): ward 9's strip runs
# south into zone 2 (wards 13/14/27) with no navy line between them; a navy
# line separates it from zone 1 on the west.
ZONE_OVERRIDE = {9: 2}

# 1) Outside = large blank-paper areas. Only two exist: the page margin outside
#    the black frame, and the white non-corporation land inside the frame.
#    Everything else white is small (circles, text, lake hatching) and is land.
paper = (img > 235).all(2).astype(np.uint8)
n, pl, st, _ = cv2.connectedComponentsWithStats(paper, connectivity=4)
big = [i for i in range(1, n) if st[i, cv2.CC_STAT_AREA] > 200_000]
# Water drawn outside the navy boundary (the river strip on the west edge) is
# white + cyan hatching, so it breaks into small paper bits that would count as
# land. Water connected to the outside paper is outside; lakes inside the city
# are walled off from it by navy/red lines.
b_, g_, r_ = [img[..., i].astype(np.int16) for i in range(3)]
water = (paper > 0) | ((b_ >= 180) & (g_ >= 130) & (b_ - r_ >= 40) & (r_ <= 215))
_, wl = cv2.connectedComponents(water.astype(np.uint8), connectivity=4)
outside = np.isin(wl, np.unique(wl[np.isin(pl, big)]))
interior = ~outside
interior[:300, :] = False            # title bar
interior[:1990, :1580] = False       # legend box
cl, _ = ndi.label(interior)
keep = np.unique([cl[y, x] for x, y in seeds.values()])
interior = np.isin(cl, keep[keep > 0])
print("big paper components:", [int(st[i, cv2.CC_STAT_AREA]) for i in big])
print("interior px:", int(interior.sum()), "| pieces kept:", int((keep > 0).sum()))


def regions(bnd):
    free = (interior & (bnd == 0)).astype(np.uint8)
    return cv2.connectedComponents(free, connectivity=4)[1]


def region_at(lab, sx, sy):
    win = lab[max(sy - 22, 0):sy + 22, max(sx - 22, 0):sx + 22].ravel()
    win = win[win > 0]
    return int(np.bincount(win).argmax()) if win.size else 0


def line_kernel(L, ang):
    kk = np.zeros((L, L), np.uint8)
    c = (L - 1) / 2
    a = np.deg2rad(ang)
    p0 = (int(round(c - np.cos(a) * c)), int(round(c - np.sin(a) * c)))
    p1 = (int(round(c + np.cos(a) * c)), int(round(c + np.sin(a) * c)))
    cv2.line(kk, p0, p1, 1, 1)
    return kk


def seal(mask, L):
    base = cv2.dilate(mask.astype(np.uint8),
                      cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
    acc = base.copy()
    for ang in range(0, 180, 15):
        acc |= cv2.morphologyEx(base, cv2.MORPH_CLOSE, line_kernel(L, ang))
    return acc


# Roads drawn past the boundary ("To Chengalpattu", "To Airport") are land-
# coloured and would hang off wards 61/13/16 as spikes. The corporation is
# what the outer navy line encloses (sealed so roads crossing it don't open it).
corp = ndi.binary_fill_holes(seal(navy > 0, 61) > 0)
corp = cv2.dilate(corp.astype(np.uint8), np.ones((7, 7), np.uint8)) > 0
clipped = interior & ~corp
interior &= corp
cl, _ = ndi.label(interior)
keep = np.unique([cl[y, x] for x, y in seeds.values()])
interior = np.isin(cl, keep[keep > 0])
nc, cc_, st_, cen_ = cv2.connectedComponentsWithStats(clipped.astype(np.uint8), connectivity=8)
print("clipped outside the navy boundary:",
      [(int(st_[i, 4]), (int(cen_[i][0] / k), int(cen_[i][1] / k))) for i in range(1, nc) if st_[i, 4] > 500],
      "| interior px now:", int(interior.sum()))


# 2) Wards: one sealed region per circle; split merged regions with L61.
lab25 = regions(b25)
reg = {w: region_at(lab25, *seeds[w]) for w in seeds}
cnt = Counter(reg.values())
merged = [sorted(w for w in seeds if reg[w] == r) for r, c in cnt.items() if c > 1]
print("merged groups:", merged, "| no region:", [w for w in seeds if reg[w] == 0])
wardmap = np.zeros((H, W), np.int16)
lab61 = regions(seal((red | navy) > 0, 61)) if merged else None
for w, r in reg.items():
    if cnt[r] == 1:
        wardmap[lab25 == r] = w
    else:
        wardmap[(lab25 == r) & (lab61 == region_at(lab61, *seeds[w]))] = w
# Grow the cores along open paths (breadth-first, via watershed on a flat
# image) so leftover land joins the ward it is actually connected to. Sealing
# red lines hard stops leaks through road gaps; navy lines are only thickened,
# because sealing them closes wards squeezed between two navy lines (ward 9).
# Straight-line nearest fill jumped such lines and gave ward 9's south strip
# to wards 10 and 13.
barrier = seal(red > 0, 25) | cv2.dilate(navy.astype(np.uint8),
                                        cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
elev3 = cv2.merge([np.where((barrier > 0) | ~interior, 255, 0).astype(np.uint8)] * 3)


def grow(cores):
    markers = cores.astype(np.int32)
    markers[~interior] = 100
    cv2.watershed(elev3, markers)
    g = np.where((markers > 0) & (markers < 100) & interior, markers, 0).astype(np.int16)
    # Whatever is left (watershed ridge pixels) joins its nearest ward.
    _, idx = ndi.distance_transform_edt(g == 0, return_indices=True)
    out = g[idx[0], idx[1]]
    out[~interior] = 0
    return out


first = grow(wardmap)

# Pockets: walled-off land no core reaches along open paths (ward 9's south
# lobe behind a navy pinch, 58's RMK Nagar strip, 52's strip under "ZONE 4").
# The flood hands them to whichever neighbour crosses a line first. Neighbouring
# wards always differ in fill colour, so a pocket instead joins the ward
# touching it (after the first grow) whose fill matches -- only when the match
# is unambiguous; otherwise the flood's answer stands.
lab_img = cv2.cvtColor(img, cv2.COLOR_BGR2LAB).astype(np.float32)
fillpx = (img.max(2) < 235) & (img.min(2) > 120)


def fill_colour(mask):
    m = mask & fillpx
    return np.median(lab_img[m], 0) if m.sum() > 50 else None


free = (interior & (barrier == 0)).astype(np.uint8)
n, cc, st, cen = cv2.connectedComponentsWithStats(free, connectivity=4)
reached = set(np.unique(cc[wardmap > 0]).tolist())
core_col = {w: fill_colour(wardmap == w) for w in seeds}
for i in range(1, n):
    if i in reached or st[i, cv2.CC_STAT_AREA] < 3000:
        continue
    x, y, w_, h_, a = st[i]
    pad = 40
    ys, xs = slice(max(y - pad, 0), y + h_ + pad), slice(max(x - pad, 0), x + w_ + pad)
    pm = cc[ys, xs] == i
    ring = cv2.dilate(pm.astype(np.uint8), np.ones((61, 61), np.uint8)).astype(bool) & ~pm
    nbrs = [int(v) for v in np.unique(first[ys, xs][ring]) if v > 0]
    sub = np.zeros((H, W), bool)
    sub[ys, xs] = pm
    pc = fill_colour(sub)
    d = sorted((float(np.linalg.norm(pc - core_col[v])), v) for v in nbrs
               if pc is not None and core_col[v] is not None)
    ok = bool(d) and d[0][0] < 6 and (len(d) == 1 or d[1][0] > 12)
    where = (int(cen[i][0] / k), int(cen[i][1] / k))
    print(f"pocket {int(a)}px at {where}@1600: flood gave {int(np.bincount(first[sub]).argmax())}; "
          f"colour distances {[(round(a_, 1), v) for a_, v in d]}"
          f" -> {'ward ' + str(d[0][1]) if ok else 'keep flood'}")
    if ok:
        wardmap[sub] = d[0][1]

full = grow(wardmap)

# Specks: a ward fragment joined to its ward only diagonally (or not at all)
# becomes a separate polygon piece. Hand each one to the ward around it.
for w in seeds:
    m = (full == w).astype(np.uint8)
    n_, cc_ = cv2.connectedComponents(m, connectivity=4)
    if n_ <= 2:
        continue
    sizes = np.bincount(cc_.ravel())[1:]
    main = int(np.argmax(sizes)) + 1
    for i in range(1, n_):
        if i == main:
            continue
        piece = cc_ == i
        ring = cv2.dilate(piece.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool) & ~piece
        nb = full[ring]
        nb = nb[(nb > 0) & (nb != w)]
        if nb.size:
            full[piece] = np.bincount(nb).argmax()
            print(f"speck of ward {w} ({int(piece.sum())} px) -> ward {int(np.bincount(nb).argmax())}")
np.save("wards_final.npy", full)

# 3) Zones: navy-only regions, named by the ZONE N labels.
zl = regions(seal(navy > 0, 25))
zreg = {z: region_at(zl, *p) for z, p in zlab.items()}
inv = {r: z for z, r in zreg.items()}
wz, wz_share = {}, {}
for w in seeds:
    v = zl[full == w]
    v = v[np.isin(v, list(inv))]
    if v.size:
        best = int(np.bincount(v).argmax())
        wz[w] = inv[best]
        wz_share[w] = float((v == best).mean())
    else:
        wz[w] = None
for w, z in ZONE_OVERRIDE.items():
    print(f"override ward {w}: detected zone {wz[w]} -> {z}")
    wz[w] = z
json.dump({str(w): wz[w] for w in sorted(wz)}, open("zones_final.json", "w"), indent=1)

# 4) Vectorise.
polys, pieces = {}, {}
for w in seeds:
    cs, _ = cv2.findContours((full == w).astype(np.uint8), cv2.RETR_EXTERNAL,
                             cv2.CHAIN_APPROX_NONE)
    pieces[w] = cv2.connectedComponents((full == w).astype(np.uint8), connectivity=4)[0] - 1
    polys[w] = cv2.approxPolyDP(max(cs, key=cv2.contourArea), 2.0, True)[:, 0, :].tolist()
json.dump({"wards": {str(w): {"zone": wz[w], "px": polys[w]} for w in seeds}},
          open("polygons_px.json", "w"))

bz = defaultdict(list)
for w, z in sorted(wz.items()):
    bz[z].append(w)
for z in sorted(bz, key=lambda v: (v is None, v)):
    print(f"  zone {z}: {len(bz[z])} wards {bz[z]}")
areas = {w: int((full == w).sum()) for w in seeds}
print("multi-piece:", {w: p for w, p in pieces.items() if p > 1})
print("smallest:", sorted((a, w) for w, a in areas.items())[:4])
print("largest:", sorted((a, w) for w, a in areas.items())[-3:])
print("weak zone majority (<90%):",
      {w: round(s, 2) for w, s in wz_share.items() if s < 0.9})
print("unassigned land px:", int((interior & (full == 0)).sum()),
      "| total ward px:", sum(areas.values()))

# 5) Verify render: ward outlines (red), zone tint, ward numbers.
ZC = {1: (80, 80, 230), 2: (60, 170, 60), 3: (220, 120, 40), 4: (180, 60, 180), 5: (40, 190, 220)}
small = cv2.resize(img, (2000, 1667), interpolation=cv2.INTER_AREA)
fs = cv2.resize(full, (2000, 1667), interpolation=cv2.INTER_NEAREST)
tint = small.copy()
for w, z in wz.items():
    if z:
        tint[fs == w] = ZC[z]
vis = cv2.addWeighted(small, 0.55, tint, 0.45, 0)
vis[(fs == 0) & (cv2.resize(interior.astype(np.uint8), (2000, 1667),
                            interpolation=cv2.INTER_NEAREST) > 0)] = (0, 0, 0)
edges = (cv2.morphologyEx(fs, cv2.MORPH_GRADIENT, np.ones((3, 3), np.uint8)) > 0)
vis[edges] = (0, 0, 180)
s = 2000 / W
for w, (x, y) in seeds.items():
    cv2.putText(vis, str(w), (int(x * s) - 12, int(y * s) + 6),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 2)
cv2.imwrite("verify.png", vis)
print("wrote verify.png")
