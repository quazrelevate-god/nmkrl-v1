# Tambaram ward-map extraction — working notes

Source: /Users/verdecs/Downloads/Tambaram-Municipal-Corporation-Ward-Map_Display-map.pdf (10.8 MB)

## Why
The pilot moves to the **Tambaram Corporation MLA** (not Chennai/Egmore). We need
every Tambaram ward's boundary + its zone, extracted from this PDF, to replicate
on the real map (lat/lng), like backend/geodata/wards.kml + zones.kml for GCC.

## Legend (from the user)
- **RED line  = ward boundary**
- **BLUE line = zone boundary**
- Both matter: every ward must be tagged with its zone.
- (Earlier the user said "yellow" — superseded; use the PDF legend.)

## Expected shape
- ~70 wards, 5 zones:
  - Zone 1: Pammal
  - Zone 2: Pallavaram (Chrompet area)
  - Zone 3: Sembakkam (Rajakilpakkam area)
  - Zone 4: Perungalathur (Old Perungalathur area)
  - Zone 5: East Tambaram (Selaiyur area)

## Plan
1. Inspect PDF: vector vs raster (decides method).
2. Isolate red (ward) + blue (zone) lines; everything else is clutter.
3. Polygonize → ~70 ward polygons + 5 zone polygons; assign each ward to the zone polygon containing it.
4. Label ward numbers (read from map; verify count = 70).
5. Georeference: ground-control points → lat/lng. Validate on a real map.
6. Export in the same shape as GCC's wards.kml / zones.kml (props: ward, zone, zone_name).

## Open decisions (not blocking extraction)
- Ward numbers collide with GCC's (both have ward 12). Tambaram-only deployment
  vs corporation+ward key. Decide before importing into the app.
- Which assembly constituency the pilot MLA represents (Tambaram spans >1 AC).
- Egmore demo seed, default tenant "16 - Egmore", test-location picker are
  Chennai-specific and switch over when we import.

## Tools
Have: OpenCV (system python), Shapely + NumPy (backend venv), PIL.
Missing: PyMuPDF (asked the user; not yet explicitly approved), GDAL, QGIS, tesseract.

## Findings (from inspecting the PDF)
- ONE page. **Raster** — 96 embedded images, no decodable vector paths.
- Rendered WITHOUT installing anything: `qlmanage -t -s 6000 -o <dir> <pdf>`
  → scratchpad/tambaram/Tambaram-Municipal-Corporation-Ward-Map_Display-map.pdf.png
  (6000×5000). overview.png = 1600px copy. (Read tool can't render PDFs: no poppler.)
  → PyMuPDF NOT needed after all.
- **70 wards confirmed** (circled numbers 1–70). Each ward is a **colour-filled
  pastel polygon** (pink/green/yellow/purple/orange/blue), adjacent wards differ.
- Ward boundary = thin RED line. Zone boundary = thick DARK NAVY line. Outer
  corporation edge = navy. Outside the map is white. Legend top-left (yellow box).
- Map labels ZONE 1–5 in red text (authoritative numbering):
  Z1 north (Pammal/Anakaputhur), Z2 north-east (Pallavaram/Madipakkam),
  Z3 centre-east (Chitlapakkam/Hasthinapuram/Sembakkam),
  Z4 west/south-west (Tambaram W/Mudichur/Perungalathur),
  Z5 south (Selaiyur/Madambakkam/Noothencheri).
- **No lat/lng grid** → georeference with ground-control points. Good GCPs:
  railway + Chennai–Trichy Highway (the diagonal), GST Rd, Velachery Main Rd,
  Mudichur Rd, 200 Feet Radial Rd, Periya Eri, Madambakkam Lake, Kadaperi Lake,
  IAF Tambaram, MEPZ, MCC.
- **Printed area: 87.64 sq km** → use to sanity-check the georeferenced scale.

## Chosen method
1. Sample exact RGB of red (ward) and navy (zone) lines from the full-res image.
2. Boundary mask = red ∪ navy, dilated slightly to seal gaps where roads/labels
   cross the thin red lines (else flood fills leak between wards).
3. Seed each ward at its numbered circle → flood-fill the non-boundary area →
   one polygon per ward, already labelled by its number (no OCR needed).
4. Zones: flood-fill with the navy mask alone → 5 zone regions; a ward's zone =
   the zone region containing its seed.
5. Georeference (GCPs), check total area ≈ 87.64 km², export KML/GeoJSON.

## Progress log
- (start) notes written.
- PDF inspected + rendered; method chosen (above). Next: sample line colours.
- Line colours (legend): ward RED ≈ RGB(208,32,32); zone NAVY ≈ RGB(32,32,112).
  Masks: red=(r>150&g<110&b<110&r-g>80); navy=(b>80&b-r>40&b-g>40&r<110&g<110).
  Saved red.npy / navy.npy (full-res).
- Circle detection was unreliable (white-disc 47/70, Hough 24/70) — circles
  merge with white minor roads. ABANDONED for seeding.
- Region approach: complement of dilated (red|navy), drop edge-touching.
  dilate 3/5/7/9px → 11/39/50/55 regions >15k px. Plateaus <70 → leaks where
  gaps exceed dilation (likely major roads drawn over red lines). Next: visualise
  leaks, then seal with manual separator segments or fill-colour splitting.
- 9px regions visualised (regions_view.png): ~15 leaks merge neighbouring wards.
- **seeds_1600.json**: all 70 ward-circle centres + 5 "ZONE N" label centres,
  READ VISUALLY off the 1600-px render (multiply by 3.75 for full-res). Precious.
- Plan now: snap each seed to the nearest white disc at full-res; within any
  9px region holding >1 seed, split with cv2.watershed on the COLOUR image
  (wards have different fills, so the watershed line lands where the missing
  red line should be). Zones: navy-only regions, labelled by zone_labels.
- seeds_full.json = seeds snapped to full-res disc centres (57/70 snapped).
- Merged 9px regions: {10:[6,7,8,10,11,12], 23:[14,15], 61:[19,20],
  74:[26,27,28], 126:[32,52,55,56], 137:[33,49], 132:[35,36], 229:[45,46,66]}.
- Watershed split on colour: markers at circle centres got walled in by the
  circle ring (fixed by inpainting circles → clean.png), but still unreliable
  where neighbours share similar fills (32/33/19 tiny). ALSO BUG: region lookup
  must EXCLUDE the edge-touching outside component (ward 18 grabbed 17M px).
- NEXT: seal gaps at the source — skeletonise red|navy, find loose line ends,
  join nearby end pairs; then label regions by seed; watershed only as fallback.
- ✅ ORIENTED CLOSING WORKS (line kernels, 12 angles, on (red|navy) dilated 3px):
  L25 → 68/70 own region, 1 merge [26,28]; L41 same; L61 → 0 merges but 9,29 lost;
  L81 worse. Use L25 everywhere + L61 labels only to split the 26/28 region.
  Then fill every unlabelled map pixel with its nearest ward (tiling), zones from
  navy, vectorise with findContours+approxPolyDP.
- ✅ CHECKPOINT: wards_final.npy (int16 label map, full-res, tiled) +
  polygons_px.json {ward:{zone, px:[[x,y]...]}}. 70 wards, all single pieces.
  Zones (navy regions named by ZONE labels): Z1 14 [1-8,10-12,29-31],
  Z2 13 [13-21,24,26-28], Z3 14 [22,23,25,34-44], Z4 15 [32,33,49-61],
  Z5 13 [45-48,62-70]. Ward 9 = zone None + only 7931 px (suspect);
  ward 50 = 15165 px (suspect). ~7.4 m²/px (11.85M px ↔ 87.64 km²).
  NEXT: visual check (verify.png), fix 9/50, then georeference.
- verify.png v1: outlines+zones match the original well. FLAW: dark unassigned
  edge patches (ward 9 strip, near 13, 18-east, 57/58/61 SW) = where roads exit
  the corporation; road drawn over outer navy line → leaked to "outside".
  FIX: outside = near-white PAPER component touching page edge (paper can't
  leak through an orange road); interior = rest, minus title/legend/logo,
  holes filled, keep CCs holding seeds. Free space = interior & ~bnd25.
- ✅ EXTRACTION DONE — build.py (reproducible, ~12 s). Fixes since v1:
  * outside = blank-paper components >200k px (page margin + white non-corp
    land; the black frame made v1's "edge-touching" test fail) + water hatch
    connected to them (river strip W of wards 1/3/4/5) + clip to the area the
    outer navy line encloses (road stubs "To Chengalpattu/Airport/Guindy").
  * cores = L25 regions; leftovers grown by watershed on a flat image (BFS
    along open paths; barrier = seal(red,25) | navy dilated) instead of
    straight-line nearest fill, which jumped navy lines.
  * pockets no core reaches (ward 9 south lobe behind a navy pinch; 58's RMK
    Nagar strip; 52's strip under "ZONE 4") join the adjacent ward with the
    matching fill colour (LAB dist 0-1 vs next >=17); verified by eye.
  * ward 9 = ZONE 2 (read by eye: its strip joins 13/14/27 with no navy line;
    navy separates it from zone 1). Detected automatically now too.
  RESULT: land 12,458,067 px, 70 single-piece wards, every ward >=90% inside
  one zone. Z1 14 [1-8,10-12,29-31] Z2 14 [9,13-21,24,26-28]
  Z3 14 [22,23,25,34-44] Z4 15 [32,33,49-61] Z5 13 [45-48,62-70].
  Outputs: wards_final.npy, polygons_px.json, zones_final.json, verify.png.
  NEXT: georeference with OpenStreetMap.
- ✅ GEOREFERENCED (georef.py). OSM via maps.mail.ru Overpass mirror
  (overpass-api.de kept 504-ing) + Nominatim for lake relations.
  15 control points: 4 stations (RS icons: Pallavaram, Chromepet, Tambaram
  Sanatorium, Perungalathur) + 11 lakes (blob centroid <-> OSM polygon
  centroid). Affine, 2.503 m/px, rot +0.24 deg, x/y scale 2.484/2.522.
  Final RMS 60 m; leave-one-out median 37 m, max 166 m (Perungalathur RS,
  the SW extreme). Check: Tambaram RS (no icon) 106 m.
  Pairings settled by fit: Periya Eri = OSM "Tiruneermalai Eri"; L7 = Kadaperi
  Lake (not Kadaperi Tank); L8 = Irumbuliyur; L11 = Balaji Nagar; L13 = OSM
  "New Perungalathur Lake"; L9 = Rajakilpakkam. NOT usable: map's
  "Madambakkam Lake" (ward 69) != OSM "Madambakkam Lake" (Gowriwakkam).
  POI checks: MIT 130 m, Vels 86 m, Nat. Inst. Siddha 15 m, Thiruneermalai
  temple 77 m; OSM BIHER point = map's "Bharath Medical College" label.
- AREA: drawn land = 78.06 km2 vs printed "87.64 Sq. Km" (-10.9%). Scale is
  pinned by stations 9 km apart (<1%), so the drawing itself covers less than
  the official figure. Reported, not "fixed".
- ✅ EXPORT (export.py, backend venv: shapely 2.1): exact pixel polygons ->
  segmentize(1px) so shared borders match point for point -> coverage_simplify
  1.5 px -> affine -> lon/lat. Coverage valid before+after, overlap 0 m2.
  Z1 PAMMAL 14.15 km2, Z2 PALLAVARAM 12.00, Z3 SEMBAKKAM 12.26,
  Z4 PERUNGALATHUR 20.14, Z5 EAST TAMBARAM 19.52.
  Outputs: tambaram_wards.geojson, tambaram_zones.geojson, wards.kml,
  zones.kml (fields boundaries.py reads), tambaram_ward_list.csv.
  overlay.py -> osm_overlay.png / osm_zoom_chromepet.png: aligns with the
  railway, lakes, Adyar river at street level.
