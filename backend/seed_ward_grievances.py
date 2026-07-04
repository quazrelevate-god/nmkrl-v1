"""
seed_ward_grievances.py
-----------------------
Populate the DB with 5 realistic grievances per real GCC ward (≈1000 total) so
the admin queue, heatmap and analytics visualise well.

Unlike the old mock-grid seeder, every point is sampled *inside the real ward
polygon* (from boundaries.py), so each grievance gets an authentic ward, zone
and — via the AC map — constituency. Seeded rows are tagged created_by="seed-*"
so they can be cleaned in one query.

Run:  ./venv/bin/python seed_ward_grievances.py
      ./venv/bin/python seed_ward_grievances.py --clear     (remove seed rows)
"""

import json
import random
import sys
import uuid
from datetime import datetime, timedelta, timezone

from shapely.geometry import Point

import boundaries
from database import get_connection, init_db

random.seed(20260704)

PER_WARD = 5

# (title, transcript, highlights, department)
TEMPLATES = [
    ("Garbage not cleared for several days",
     "The garbage bin on our street has been overflowing for almost a week. Stray dogs scatter the waste every morning.",
     ["Solid waste", "Overflow", "Health hazard"], "Solid Waste Management Department"),
    ("Overflowing dustbin attracting stray animals",
     "Sir, the public dustbin near the market is overflowing and animals are spreading it around. Please arrange clearance.",
     ["Dustbin", "Sanitation"], "Solid Waste Management Department"),
    ("Street light not working for two weeks",
     "The street light in front of our house has not been working for two weeks. The lane is very dark at night.",
     ["Street light", "Safety", "Night"], "Electrical Department"),
    ("Frequent power fluctuations in the area",
     "We are facing frequent power cuts and voltage fluctuations. Two of my appliances got damaged.",
     ["Power cut", "Voltage"], "Electrical Department"),
    ("Large pothole on the main road",
     "There is a deep pothole on the main road near the bus stop. Two-wheelers keep skidding, especially in the rain.",
     ["Pothole", "Road", "Accident risk"], "Works & Roads Department"),
    ("Damaged footpath near the school",
     "The footpath tiles near the school are broken and uneven. Children and elderly people find it difficult to walk.",
     ["Footpath", "School zone"], "Works & Roads Department"),
    ("Stormwater drain blocked and overflowing",
     "The stormwater drain is completely blocked with silt and plastic. Even a small rain floods the whole street.",
     ["Drain", "Flooding", "Monsoon"], "Storm Water Drain Department"),
    ("Waterlogging after every rain",
     "Our street gets waterlogged after every rain because the drain is not desilted. Water enters the ground floor houses.",
     ["Waterlogging", "Desilting"], "Storm Water Drain Department"),
    ("Mosquito breeding in stagnant water",
     "There is stagnant water in the vacant plot behind our house and mosquitoes are breeding heavily. Requesting fogging.",
     ["Mosquito", "Fogging", "Dengue"], "Public Health Department"),
    ("Unhygienic public toilet needs cleaning",
     "The public toilet near the bus terminus is in a very unhygienic condition. It has not been cleaned for many days.",
     ["Public toilet", "Hygiene"], "Public Health Department"),
    ("Broken play equipment in the park",
     "The swings and slides in the neighbourhood park are broken and rusted. It is unsafe for the children to play.",
     ["Park", "Play equipment", "Safety"], "Parks & Playfields Department"),
    ("Park not maintained, overgrown with weeds",
     "The local park is overgrown with weeds and the walking track is damaged. Senior citizens have stopped using it.",
     ["Park", "Maintenance"], "Parks & Playfields Department"),
    ("Irregular water supply for a week",
     "We have been getting water supply only once in two days and the pressure is very low. Please look into it.",
     ["Water supply", "Low pressure"], "Allied Utilities"),
    ("Sewage overflow on the street",
     "The sewage line is overflowing onto the street and the smell is unbearable. It is a serious health concern.",
     ["Sewage", "Overflow", "Health"], "Allied Utilities"),
]

NAMES = [
    "Karthik Raja", "Meena Lakshmi", "Suresh Kumar", "Anand Prakash", "Priya Raman",
    "Ramesh Babu", "Divya Nathan", "Vignesh S", "Lakshmi Priya", "Arjun Mohan",
    "Kavya Sundaram", "Ganesh V", "Nithya Balaji", "Ravi Shankar", "Deepa Krishnan",
    "Mohan Raj", "Sowmya R", "Bala Murugan", "Janani R", "Senthil Kumar",
    "Revathi M", "Prakash Velu", "Anitha Devi", "Saravanan P", "Uma Maheswari",
    "Hari Prasad", "Vidya S", "Manoj Kumar", "Shalini R", "Dinesh Kannan",
]

# status → (weight, age-days range)
STATUS_POOL = [
    ("SUBMITTED", 14, (0, 8)),
    ("ACTIVE", 22, (2, 20)),
    ("FORWARDED", 16, (4, 25)),
    ("IN_PROGRESS", 20, (7, 35)),
    ("PENDING_VERIFICATION", 12, (12, 45)),
    ("CLOSED", 16, (20, 70)),
]
_STATUSES = [s for s, w, _ in STATUS_POOL for _ in range(w)]
_AGE = {s: age for s, _, age in STATUS_POOL}

AREAS = ["1st Main Road", "2nd Cross Street", "North Street", "Bazaar Road",
         "Gandhi Nagar", "Nehru Street", "Temple Street", "Market Road",
         "Rajaji Salai", "Kamaraj Avenue", "Bharathi Nagar", "Anna Street"]


def random_point_in(geom):
    minx, miny, maxx, maxy = geom.bounds
    for _ in range(300):
        p = Point(random.uniform(minx, maxx), random.uniform(miny, maxy))
        if geom.contains(p):
            return p
    return geom.representative_point()


def random_phone():
    return str(random.choice([6, 7, 8, 9])) + "".join(str(random.randint(0, 9)) for _ in range(9))


def build_records():
    boundaries.load_boundaries()
    rows = []
    for w in boundaries._WARDS:  # noqa: SLF001 — internal cache is the source of truth
        ward = w["ward"]
        zone = w.get("zone")
        zone_name = w.get("zone_name")
        geom = w["geometry"]
        for i in range(PER_WARD):
            title, transcript, highlights, dept = random.choice(TEMPLATES)
            status = random.choice(_STATUSES)
            lo, hi = _AGE[status]
            created = datetime.now(timezone.utc) - timedelta(
                days=random.randint(lo, hi), hours=random.randint(0, 23))
            pt = random_point_in(geom)
            upvotes = random.choices([0, 1, 2, 5, 9, 14, 22, 35],
                                     weights=[26, 18, 14, 12, 10, 8, 7, 5])[0]
            rows.append({
                "id": str(uuid.uuid4()),
                "title": title,
                "transcript": transcript,
                "highlights": highlights,
                "lat": pt.y, "lng": pt.x,
                "area": f"{random.choice(AREAS)}, {zone_name.title() if zone_name else 'Chennai'}",
                "ward": int(ward), "zone": zone, "zone_name": zone_name,
                "department": dept, "status": status, "upvotes": upvotes,
                "created_at": created.isoformat(),
                "created_by": f"seed-{ward}-{i}",
                "name": random.choice(NAMES), "phone": random_phone(),
            })
    return rows


def main():
    init_db()
    if "--clear" in sys.argv:
        with get_connection() as conn:
            n = conn.execute("DELETE FROM issues WHERE created_by LIKE 'seed-%'").rowcount
        print(f"Removed {n} seeded grievances.")
        return

    records = build_records()
    with get_connection() as conn:
        # Remove any prior seed rows first (idempotent re-seed).
        conn.execute("DELETE FROM issues WHERE created_by LIKE 'seed-%'")
        for r in records:
            conn.execute(
                """INSERT INTO issues
                   (id, title, image_url, audio_url, transcript, summary_highlights,
                    latitude, longitude, area_name, ward_no, zone, zone_name,
                    department, status, upvotes, notify_reporter, created_at,
                    created_by, name, phone)
                   VALUES (?, ?, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)""",
                (r["id"], r["title"], r["transcript"], json.dumps(r["highlights"]),
                 r["lat"], r["lng"], r["area"], r["ward"], r["zone"], r["zone_name"],
                 r["department"], r["status"], r["upvotes"], r["created_at"],
                 r["created_by"], r["name"], r["phone"]),
            )
    print(f"Seeded {len(records)} grievances across {len(records) // PER_WARD} wards.")


if __name__ == "__main__":
    main()
