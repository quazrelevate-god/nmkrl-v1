"""
seed_grievances.py
------------------
Populate the database with realistic civic grievances for demo purposes —
PER_WARD grievances in every one of the 200 wards (1,200 total by default).

Coverage:
  * every ward gets PER_WARD grievances, with >= 5 PUBLIC (non-SUBMITTED) each,
    so the citizen "In My Ward" list is populated wherever the user stands
  * all 7 departments (cycled, so each is well represented)
  * all 5 statuses present in every ward (SUBMITTED, ACTIVE, IN_PROGRESS,
    PENDING_VERIFICATION, CLOSED)
  * a random point generated inside each ward's rectangle per grievance
  * appropriate mock AI summary (transcript + highlight tags) per grievance type
  * varied upvotes, reporter phones, and created_at dates (older = later lifecycle)

Run:  ./venv/bin/python3 seed_grievances.py
"""

import json
import random
import uuid
from datetime import datetime, timedelta, timezone

from database import get_connection, init_db
from wards import WARDS

random.seed(424242)  # reproducible dataset

STATUSES = ["SUBMITTED", "ACTIVE", "IN_PROGRESS", "PENDING_VERIFICATION", "CLOSED"]

# How many days ago a grievance was reported, by lifecycle stage (min, max).
AGE_BY_STATUS = {
    "SUBMITTED":            (0, 6),
    "ACTIVE":               (3, 20),
    "IN_PROGRESS":          (7, 30),
    "PENDING_VERIFICATION": (10, 40),
    "CLOSED":               (20, 70),
}

CHENNAI_AREAS = [
    "Anna Nagar", "T. Nagar", "Adyar", "Velachery", "Mylapore", "Guindy",
    "Tambaram", "Porur", "Mogappair", "Perambur", "Royapuram", "Egmore",
    "Kodambakkam", "Ashok Nagar", "Nungambakkam", "Triplicane", "Saidapet",
    "Chromepet", "Pallavaram", "Madipakkam", "Vadapalani", "Ambattur",
    "Avadi", "Thiruvanmiyur", "Besant Nagar", "Kotturpuram", "Nanganallur",
    "Choolaimedu", "Aminjikarai", "Villivakkam", "Korattur", "Kolathur",
    "Sholinganallur", "Pallikaranai", "Medavakkam", "Arumbakkam", "Ekkaduthangal",
    "Teynampet", "Washermanpet", "Tondiarpet",
]

# Per-department grievance templates: (title, transcript, [highlights]).
TEMPLATES = {
    "Solid Waste Management Department": [
        ("Garbage not collected for several days",
         "The garbage bins on our street have not been cleared for almost a week. Waste is overflowing onto the road and the smell is unbearable.",
         ["Garbage overflow", "Uncollected waste", "Foul smell"]),
        ("Overflowing dustbin attracting stray dogs",
         "The public dustbin near the market is overflowing and stray dogs are scattering the garbage everywhere.",
         ["Overflowing dustbin", "Stray dogs", "Public health risk"]),
        ("Illegal dumping of construction debris",
         "Someone has dumped a large pile of construction debris and household waste on the empty plot at the corner.",
         ["Illegal dumping", "Construction debris", "Roadside waste"]),
        ("Door-to-door garbage collection stopped",
         "The conservancy worker has not come for door-to-door collection in our lane for the past four days.",
         ["No collection", "Missed pickup", "Sanitation"]),
        ("Wet and dry waste not segregated at collection point",
         "At the local collection point all the waste is mixed together and left rotting; segregation is not happening.",
         ["No segregation", "Mixed waste", "Rotting garbage"]),
    ],
    "Electrical Department": [
        ("Street light not working for a week",
         "The street light in front of our house has not been working for over a week, making the road very dark at night.",
         ["Streetlight outage", "Dark road", "Safety concern"]),
        ("Multiple street lights off on main road",
         "Almost the entire stretch of street lights on the main road is switched off, the area is pitch dark after sunset.",
         ["Multiple lights off", "Main road", "Night safety"]),
        ("Flickering streetlight near junction",
         "The streetlight at the busy junction keeps flickering and goes off intermittently, confusing drivers.",
         ["Flickering light", "Junction", "Traffic hazard"]),
        ("Exposed electrical wires on lamp post",
         "There are exposed live wires hanging from the lamp post near the bus stop, it is very dangerous.",
         ["Exposed wires", "Live wire hazard", "Lamp post"]),
        ("Streetlight pole leaning dangerously",
         "An old streetlight pole is leaning heavily and looks like it could fall on pedestrians any time.",
         ["Leaning pole", "Falling hazard", "Urgent"]),
    ],
    "Works & Roads Department": [
        ("Large pothole causing accidents",
         "There is a very large pothole in the middle of the road and two-wheelers keep skidding and falling into it.",
         ["Large pothole", "Accident risk", "Damaged road"]),
        ("Broken footpath blocking pedestrians",
         "The footpath is completely broken with loose slabs and pedestrians are forced to walk on the busy road.",
         ["Broken footpath", "Pedestrian hazard", "Loose slabs"]),
        ("Road dug up and not restored",
         "The road was dug up for a cable line two months ago and has still not been re-laid, leaving deep trenches.",
         ["Unrestored road", "Open trench", "Incomplete work"]),
        ("Uneven speed breaker without markings",
         "An unmarked, oversized speed breaker has been laid and vehicles are getting damaged because it is not visible.",
         ["Unmarked speed breaker", "Vehicle damage", "No signage"]),
        ("Crumbling road edge near school",
         "The edge of the road near the school is crumbling away and children walking to school are at risk.",
         ["Crumbling road", "Near school", "Child safety"]),
    ],
    "Storm Water Drain Department": [
        ("Severe water logging after rain",
         "Even after a short spell of rain the entire street gets water logged knee-deep and stays flooded for hours.",
         ["Water logging", "Flooding", "Poor drainage"]),
        ("Storm water drain completely blocked",
         "The storm water drain is fully blocked with silt and plastic, so rainwater has nowhere to go.",
         ["Blocked drain", "Silt accumulation", "Overflow"]),
        ("Flooding near the subway",
         "The subway floods every monsoon and becomes impassable for vehicles and pedestrians.",
         ["Subway flooding", "Impassable", "Monsoon"]),
        ("Open storm water drain without cover",
         "A section of the storm water drain is left open without a slab cover and is a danger at night.",
         ["Open drain", "Missing cover", "Night hazard"]),
        ("Rainwater stagnating for days",
         "Stagnant rainwater has been collecting in front of the houses for several days and is not draining away.",
         ["Stagnant water", "No drainage", "Standing water"]),
    ],
    "Public Health Department": [
        ("Mosquito breeding in stagnant water",
         "Stagnant water in the area has become a major mosquito breeding ground and dengue cases are rising.",
         ["Mosquito breeding", "Dengue risk", "Stagnant water"]),
        ("No fogging done in weeks",
         "Mosquito fogging has not been carried out in our locality for several weeks and the menace is severe.",
         ["No fogging", "Mosquito menace", "Sanitation"]),
        ("Unhygienic public toilet",
         "The public toilet is in a filthy, unusable condition and has not been cleaned for a long time.",
         ["Unhygienic toilet", "Sanitation", "Health hazard"]),
        ("Stray animal carcass not removed",
         "A dead animal has been lying on the roadside for two days and is creating a serious health hazard.",
         ["Carcass removal", "Health hazard", "Foul smell"]),
        ("Open sewage causing health concerns",
         "Open sewage is flowing near the residential area and residents are worried about diseases spreading.",
         ["Open sewage", "Disease risk", "Sanitation"]),
    ],
    "Parks & Playfields Department": [
        ("Fallen tree branch blocking the path",
         "A large tree branch has fallen and is completely blocking the walking path in the park.",
         ["Fallen branch", "Blocked path", "Tree maintenance"]),
        ("Neighbourhood park not maintained",
         "The local park is overgrown with weeds, the lights are broken and children have no space to play.",
         ["Unmaintained park", "Overgrown weeds", "Broken lights"]),
        ("Dead tree needs urgent removal",
         "A large dead tree is standing dangerously close to the road and could fall during the next storm.",
         ["Dead tree", "Falling risk", "Urgent removal"]),
        ("Broken play equipment in park",
         "The swings and slides in the children's park are broken and have sharp edges that can injure kids.",
         ["Broken equipment", "Child safety", "Park repair"]),
        ("Park boundary fence damaged",
         "The fence around the park is damaged, letting stray cattle in and trampling the green space.",
         ["Damaged fence", "Stray cattle", "Green space"]),
    ],
    "Allied Utilities": [
        ("Sewage overflow on the street",
         "Sewage is overflowing from a manhole and flowing onto the street, the whole area stinks.",
         ["Sewage overflow", "Manhole", "Foul smell"]),
        ("No water supply for two days",
         "There has been no piped water supply in our area for the past two days and tankers are not coming.",
         ["No water supply", "Water shortage", "CMWSSB"]),
        ("Frequent unscheduled power cuts",
         "We are facing frequent unscheduled power cuts lasting several hours every day with no prior notice.",
         ["Power cuts", "Unscheduled outage", "TANGEDCO"]),
        ("Leaking water pipeline wasting water",
         "A drinking water pipeline is leaking heavily at the roadside and thousands of litres are being wasted.",
         ["Pipeline leak", "Water wastage", "Drinking water"]),
        ("Blocked underground sewer line",
         "The underground sewer line is blocked and waste water is backing up into household drains.",
         ["Sewer blockage", "Backflow", "Drainage"]),
    ],
}

DEPARTMENTS = list(TEMPLATES.keys())


def random_phone() -> str:
    return f"{random.choice('6789')}{random.randint(100000000, 999999999)}"


def point_in_ward(ward: dict):
    lat = random.uniform(ward["lat_min"], ward["lat_max"])
    lng = random.uniform(ward["lng_min"], ward["lng_max"])
    return round(lat, 6), round(lng, 6)


# Every ward gets this many grievances. The status cycle guarantees all five
# statuses appear and that at least 5 are PUBLIC (non-SUBMITTED) per ward, so
# the citizen "In My Ward" list is populated wherever the user stands.
PER_WARD = 6
WARD_STATUS_CYCLE = [
    "SUBMITTED", "ACTIVE", "IN_PROGRESS", "PENDING_VERIFICATION", "CLOSED", "ACTIVE",
]


def build_records():
    records = []
    idx = 0
    for ward in WARDS:
        statuses = WARD_STATUS_CYCLE[:]
        random.shuffle(statuses)
        for j in range(PER_WARD):
            department = DEPARTMENTS[idx % len(DEPARTMENTS)]
            status = statuses[j]
            title, transcript, highlights = random.choice(TEMPLATES[department])
            lat, lng = point_in_ward(ward)

            age_lo, age_hi = AGE_BY_STATUS[status]
            days_ago = random.randint(age_lo, age_hi)
            created = datetime.now(timezone.utc) - timedelta(
                days=days_ago, hours=random.randint(0, 23), minutes=random.randint(0, 59)
            )

            base = {"SUBMITTED": 3, "ACTIVE": 8, "IN_PROGRESS": 14,
                    "PENDING_VERIFICATION": 20, "CLOSED": 28}[status]
            upvotes = max(0, int(random.gauss(base, base * 0.6)))

            records.append({
                "id": str(uuid.uuid4()),
                "title": title,
                "transcript": transcript,
                "highlights": highlights,
                "lat": lat,
                "lng": lng,
                "area": random.choice(CHENNAI_AREAS),
                "ward_no": ward["number"],
                "department": department,
                "status": status,
                "upvotes": upvotes,
                "phone": random_phone(),
                "notify": 1 if status == "PENDING_VERIFICATION" else 0,
                "created_at": created.isoformat(),
                "created_by": f"citizen-{idx}",
            })
            idx += 1
    return records


def main():
    init_db()
    records = build_records()
    with get_connection() as conn:
        # Fresh, predictable dataset of exactly 100.
        conn.execute("DELETE FROM verifications")
        conn.execute("DELETE FROM upvotes")
        conn.execute("DELETE FROM issues")
        for r in records:
            conn.execute(
                """
                INSERT INTO issues (
                    id, title, image_url, audio_url, transcript, summary_highlights,
                    latitude, longitude, area_name, ward_no, department, phone,
                    status, upvotes, notify_reporter, created_at, created_by
                ) VALUES (?, ?, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    r["id"], r["title"], r["transcript"], json.dumps(r["highlights"]),
                    r["lat"], r["lng"], r["area"], r["ward_no"], r["department"], r["phone"],
                    r["status"], r["upvotes"], r["notify"], r["created_at"], r["created_by"],
                ),
            )

    # Summary
    from collections import Counter
    by_status = Counter(r["status"] for r in records)
    by_dept = Counter(r["department"] for r in records)
    print(f"Seeded {len(records)} grievances across {len({r['ward_no'] for r in records})} distinct wards.")
    print("By status:", dict(by_status))
    print("By department:")
    for d, c in by_dept.items():
        print(f"   {c:>3}  {d}")


if __name__ == "__main__":
    main()
