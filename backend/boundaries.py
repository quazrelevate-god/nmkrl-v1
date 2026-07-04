"""
boundaries.py
-------------
Real geographic boundary detection for the Greater Chennai Corporation, replacing
the old deterministic mock grid (``wards.py``).

Two KML exports drive it:

  * ``geodata/zones.kml``  — 16 GCC zones. Each Placemark's <ExtendedData> carries
    ``ZONE`` (roman numeral, e.g. "III") and ``ZONE_NAME`` (e.g. "MADHAVARAM").
  * ``geodata/wards.kml``  — 200 GCC divisions (wards). Each Placemark's
    <ExtendedData> carries ``name`` (the ward number, e.g. "168").

Parsing notes (why this is written the way it is):

  * KML uses a *default* XML namespace (``http://www.opengis.net/kml/2.2``). With
    ``xml.etree.ElementTree`` there is no such thing as a "default" prefix when you
    query — every tag in that namespace must be addressed with an explicit prefix.
    So we register our own prefix (``kml``) in ``_NS`` and use it in every XPath
    (``.//kml:Placemark``, ``kml:SimpleData`` …). Forgetting this is the #1 reason
    KML ExtendedData "silently" returns nothing.
  * The ward export is pretty-printed, so every element's ``.text`` is wrapped in
    whitespace/newlines — we ``.strip()`` all extracted text.
  * A Placemark's geometry may be a <MultiGeometry> of several <Polygon>s (islands),
    and a <Polygon> may have holes (<innerBoundaryIs>). We build a shapely
    ``Polygon``/``MultiPolygon`` that honours both.

The parsed polygons are cached in-memory (module-level lists) and queried with a
point-in-polygon test. ``load_boundaries()`` is called once from the FastAPI
lifespan; ``locate(lat, lng)`` answers "which zone & ward is this coordinate in?".
"""

from __future__ import annotations

import os
import sys
import xml.etree.ElementTree as ET

from shapely.geometry import MultiPolygon, Point, Polygon, mapping
from shapely.strtree import STRtree

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
GEODATA_DIR = os.path.join(BASE_DIR, "geodata")
ZONES_KML = os.path.join(GEODATA_DIR, "zones.kml")
WARDS_KML = os.path.join(GEODATA_DIR, "wards.kml")

# The single KML namespace, registered under an explicit prefix for XPath queries.
_NS = {"kml": "http://www.opengis.net/kml/2.2"}

# Douglas–Peucker tolerance (~11m) used only for the GeoJSON we ship to the map;
# the full-resolution polygons are kept in memory for accurate point-in-polygon.
SIMPLIFY_TOLERANCE = 0.0001


# ── In-memory caches (populated once by load_boundaries) ─────────────────────
# Each entry: {"geometry": shapely (Multi)Polygon, ...metadata}
_ZONES: list[dict] = []
_WARDS: list[dict] = []

# Spatial indexes for O(log n) candidate lookup before the exact contains() test.
_ZONE_INDEX: STRtree | None = None
_WARD_INDEX: STRtree | None = None
_ZONE_GEOMS: list = []
_WARD_GEOMS: list = []

# Simplified GeoJSON FeatureCollections, built once and served to the map.
_GEOJSON: dict = {"zones": None, "wards": None}

_loaded = False


# ── KML geometry parsing ─────────────────────────────────────────────────────
def _parse_coordinates(text: str) -> list[tuple[float, float]]:
    """Parse a KML <coordinates> blob into a list of (lon, lat) tuples.

    KML coordinate tuples are ``lon,lat[,alt]`` separated by whitespace. We keep
    (lon, lat) order because shapely expects (x, y) = (longitude, latitude).
    """
    points: list[tuple[float, float]] = []
    for token in text.split():
        parts = token.split(",")
        if len(parts) < 2:
            continue
        try:
            lon, lat = float(parts[0]), float(parts[1])
        except ValueError:
            continue
        points.append((lon, lat))
    return points


def _polygon_from_element(poly_el: ET.Element) -> Polygon | None:
    """Build a shapely Polygon (with holes) from a KML <Polygon> element."""
    outer_el = poly_el.find(
        "kml:outerBoundaryIs/kml:LinearRing/kml:coordinates", _NS
    )
    if outer_el is None or not (outer_el.text or "").strip():
        return None
    shell = _parse_coordinates(outer_el.text)
    if len(shell) < 3:
        return None

    holes: list[list[tuple[float, float]]] = []
    for inner_el in poly_el.findall(
        "kml:innerBoundaryIs/kml:LinearRing/kml:coordinates", _NS
    ):
        if inner_el.text and inner_el.text.strip():
            ring = _parse_coordinates(inner_el.text)
            if len(ring) >= 3:
                holes.append(ring)

    try:
        return Polygon(shell, holes)
    except Exception as exc:  # malformed ring → skip rather than crash the load
        print(f"[boundaries] bad polygon skipped: {exc}", file=sys.stderr)
        return None


def _geometry_for_placemark(placemark: ET.Element):
    """Collect every <Polygon> under a Placemark into one shapely geometry.

    Handles a bare <Polygon>, a <MultiGeometry> of several polygons, and returns
    a Polygon when there is one and a MultiPolygon when there are several.
    """
    polygons: list[Polygon] = []
    for poly_el in placemark.findall(".//kml:Polygon", _NS):
        poly = _polygon_from_element(poly_el)
        if poly is not None and not poly.is_empty:
            # buffer(0) repairs self-touching rings that would otherwise be invalid.
            polygons.append(poly if poly.is_valid else poly.buffer(0))
    if not polygons:
        return None
    if len(polygons) == 1:
        return polygons[0]
    return MultiPolygon([p for p in polygons if p.geom_type == "Polygon"]) \
        if all(p.geom_type == "Polygon" for p in polygons) else _union(polygons)


def _union(geoms):
    from shapely.ops import unary_union
    return unary_union(geoms)


def _simple_data(placemark: ET.Element, name: str) -> str:
    """Read <ExtendedData>/<SchemaData>/<SimpleData name="..."> as stripped text."""
    for sd in placemark.findall(".//kml:SimpleData", _NS):
        if sd.get("name") == name:
            return (sd.text or "").strip()
    return ""


def _placemark_name(placemark: ET.Element) -> str:
    el = placemark.find("kml:name", _NS)
    return (el.text or "").strip() if el is not None else ""


# ── Loaders ──────────────────────────────────────────────────────────────────
def _load_kml(path: str, extract) -> list[dict]:
    """Parse one KML file into a list of {geometry, **metadata} dicts.

    ``extract(placemark)`` returns the metadata dict for a placemark (or None to
    skip it); we attach the parsed shapely geometry under ``geometry``.
    """
    tree = ET.parse(path)
    root = tree.getroot()
    out: list[dict] = []
    for placemark in root.findall(".//kml:Placemark", _NS):
        meta = extract(placemark)
        if meta is None:
            continue
        geom = _geometry_for_placemark(placemark)
        if geom is None or geom.is_empty:
            continue
        out.append({"geometry": geom, **meta})
    return out


_ROMAN = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}


def _roman_to_int(s: str):
    """Convert a roman numeral (e.g. "VIII") to an int (8), or None if invalid."""
    s = (s or "").strip().upper()
    if not s:
        return None
    total, prev = 0, 0
    for ch in reversed(s):
        val = _ROMAN.get(ch)
        if val is None:
            return None  # not a roman numeral — leave untouched
        total = total - val if val < prev else total + val
        prev = max(prev, val)
    return total


def _extract_zone(placemark: ET.Element) -> dict | None:
    zone = _simple_data(placemark, "ZONE")
    # Source data is inconsistent: one row stores "ZONE - IV" rather than "IV".
    # Keep only the roman-numeral part so the displayed zone is uniform.
    if zone.upper().startswith("ZONE"):
        zone = zone[4:].lstrip(" -").strip()
    # GCC zones are roman (I–XV) in the KML; expose them as plain integers.
    zone_int = _roman_to_int(zone)
    if zone_int is not None:
        zone = str(zone_int)
    zone_name = _simple_data(placemark, "ZONE_NAME") or _placemark_name(placemark)
    region = _simple_data(placemark, "Region")
    if not zone and not zone_name:
        return None
    return {"zone": zone, "zone_name": zone_name, "region": region}


def _extract_ward(placemark: ET.Element) -> dict | None:
    ward = _simple_data(placemark, "name") or _placemark_name(placemark)
    if not ward:
        return None
    ward_id = _simple_data(placemark, "id_2")
    return {"ward": ward, "ward_id": ward_id}


def load_boundaries() -> dict:
    """Parse both KML files once and build the in-memory caches + spatial indexes.

    Idempotent: subsequent calls are no-ops. Returns a small summary dict.
    """
    global _ZONES, _WARDS, _ZONE_INDEX, _WARD_INDEX, _ZONE_GEOMS, _WARD_GEOMS, _loaded
    if _loaded:
        return {"zones": len(_ZONES), "wards": len(_WARDS), "cached": True}

    if not os.path.exists(ZONES_KML) or not os.path.exists(WARDS_KML):
        print(
            f"[boundaries] KML files missing under {GEODATA_DIR}; locate() disabled.",
            file=sys.stderr,
        )
        _loaded = True
        return {"zones": 0, "wards": 0, "error": "kml_missing"}

    _ZONES = _load_kml(ZONES_KML, _extract_zone)
    _WARDS = _load_kml(WARDS_KML, _extract_ward)

    _ZONE_GEOMS = [z["geometry"] for z in _ZONES]
    _WARD_GEOMS = [w["geometry"] for w in _WARDS]
    _ZONE_INDEX = STRtree(_ZONE_GEOMS) if _ZONE_GEOMS else None
    _WARD_INDEX = STRtree(_WARD_GEOMS) if _WARD_GEOMS else None

    # Tag each ward with its parent zone (via a representative interior point),
    # so the map can colour wards by zone and the admin can filter wards by zone.
    for w in _WARDS:
        pt = w["geometry"].representative_point()
        zrec = _match(pt, _ZONES, _ZONE_INDEX, _ZONE_GEOMS)
        w["zone"] = zrec["zone"] if zrec else None
        w["zone_name"] = zrec["zone_name"] if zrec else None

    _build_geojson()

    _loaded = True
    print(
        f"[boundaries] loaded {len(_ZONES)} zones, {len(_WARDS)} wards.",
        file=sys.stderr,
    )
    return {"zones": len(_ZONES), "wards": len(_WARDS)}


def _build_geojson() -> None:
    """Precompute simplified GeoJSON FeatureCollections for zones and wards."""
    global _GEOJSON

    def feature(geom, props):
        simple = geom.simplify(SIMPLIFY_TOLERANCE, preserve_topology=True)
        return {"type": "Feature", "properties": props, "geometry": mapping(simple)}

    zone_features = [
        feature(z["geometry"], {
            "zone": z["zone"], "zone_name": z["zone_name"], "region": z["region"],
        })
        for z in _ZONES
    ]
    ward_features = [
        feature(w["geometry"], {
            "ward": w["ward"], "zone": w.get("zone"), "zone_name": w.get("zone_name"),
        })
        for w in _WARDS
    ]
    _GEOJSON = {
        "zones": {"type": "FeatureCollection", "features": zone_features},
        "wards": {"type": "FeatureCollection", "features": ward_features},
    }


def geojson() -> dict:
    """Return the cached {zones, wards} GeoJSON FeatureCollections for the map."""
    if not _loaded:
        load_boundaries()
    return _GEOJSON


# ── Point-in-polygon lookup ──────────────────────────────────────────────────
def _match(point: Point, records: list[dict], index: STRtree | None, geoms: list):
    """Return the record whose geometry contains ``point`` (or None).

    Uses the STRtree to shortlist candidates by bounding box, then confirms with
    an exact ``contains`` test.
    """
    if index is None:
        # Fallback: linear scan (still correct, just slower).
        for rec in records:
            if rec["geometry"].contains(point) or rec["geometry"].intersects(point):
                return rec
        return None
    for idx in index.query(point):  # shapely 2.x returns integer positions
        geom = geoms[int(idx)]
        if geom.contains(point) or geom.intersects(point):
            return records[int(idx)]
    return None


def locate(lat: float, lng: float) -> dict:
    """Resolve (lat, lng) to its GCC zone and ward via point-in-polygon.

    Returns a dict with ``zone``, ``zone_name``, ``ward`` (any of which may be
    None if the point falls outside GCC limits) plus an ``inside`` flag.
    """
    if not _loaded:
        load_boundaries()

    point = Point(lng, lat)  # shapely is (x=lon, y=lat)

    zone_rec = _match(point, _ZONES, _ZONE_INDEX, _ZONE_GEOMS)
    ward_rec = _match(point, _WARDS, _WARD_INDEX, _WARD_GEOMS)

    return {
        "zone": zone_rec["zone"] if zone_rec else None,
        "zone_name": zone_rec["zone_name"] if zone_rec else None,
        "region": zone_rec["region"] if zone_rec else None,
        "ward": ward_rec["ward"] if ward_rec else None,
        "inside": bool(zone_rec or ward_rec),
    }


def summary() -> dict:
    """Lightweight status for health/info endpoints."""
    return {"loaded": _loaded, "zones": len(_ZONES), "wards": len(_WARDS)}
