"""
wards.py
--------
A deterministic, dependency-free division of the Chennai district bounding box
into exactly 200 numbered "wards" (blocks).

We can't fetch real ward polygons for a PoC, so we tessellate the bbox into a
*jittered* grid: rows of random heights, each split into a random number of
variable-width columns. The result looks like irregular blocks while remaining
a perfect tessellation (no gaps/overlaps), so every coordinate maps to exactly
one ward via a simple range check.

A fixed seed makes the grid stable across restarts, so a stored ``ward_no`` is
always reproducible. This module is the single source of truth — the frontend
fetches the rectangles from ``/api/wards`` rather than re-deriving them.
"""

# Chennai district approximate bounding box.
LAT_MIN, LAT_MAX = 12.83, 13.25
LNG_MIN, LNG_MAX = 80.10, 80.32

SEED = 20260630
NUM_ROWS = 13
TOTAL_WARDS = 200


def _mulberry32(seed: int):
    """Tiny deterministic PRNG → floats in [0, 1)."""
    state = seed & 0xFFFFFFFF

    def rng() -> float:
        nonlocal state
        state = (state + 0x6D2B79F5) & 0xFFFFFFFF
        t = state
        t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
        t ^= (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
        t &= 0xFFFFFFFF
        return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

    return rng


def _generate() -> list[dict]:
    rng = _mulberry32(SEED)

    # 1) Distribute 200 columns across NUM_ROWS rows (sums to exactly 200).
    cols_per_row: list[int] = []
    remaining = TOTAL_WARDS
    for r in range(NUM_ROWS):
        rows_left = NUM_ROWS - r
        if rows_left == 1:
            c = remaining
        else:
            avg = remaining / rows_left
            c = round(avg * (0.7 + 0.6 * rng()))
            c = max(1, min(c, remaining - (rows_left - 1)))
        cols_per_row.append(c)
        remaining -= c

    # 2) Random row heights (normalised to span the latitude range).
    row_weights = [0.5 + rng() for _ in range(NUM_ROWS)]
    row_total = sum(row_weights)

    wards: list[dict] = []
    number = 0
    lat0 = LAT_MIN
    for r in range(NUM_ROWS):
        height = (LAT_MAX - LAT_MIN) * row_weights[r] / row_total
        lat1 = LAT_MAX if r == NUM_ROWS - 1 else lat0 + height

        # 3) Random column widths within this row.
        c = cols_per_row[r]
        col_weights = [0.5 + rng() for _ in range(c)]
        col_total = sum(col_weights)

        lng0 = LNG_MIN
        for k in range(c):
            width = (LNG_MAX - LNG_MIN) * col_weights[k] / col_total
            lng1 = LNG_MAX if k == c - 1 else lng0 + width
            number += 1
            wards.append({
                "number": number,
                "lat_min": round(lat0, 6),
                "lat_max": round(lat1, 6),
                "lng_min": round(lng0, 6),
                "lng_max": round(lng1, 6),
            })
            lng0 = lng1
        lat0 = lat1

    return wards


# Generated once at import — stable for the process lifetime.
WARDS: list[dict] = _generate()


def ward_for_coords(lat: float, lng: float) -> int | None:
    """Return the ward number containing (lat, lng), or None if outside Chennai."""
    if lat is None or lng is None:
        return None
    for w in WARDS:
        if w["lat_min"] <= lat <= w["lat_max"] and w["lng_min"] <= lng <= w["lng_max"]:
            return w["number"]
    return None
