"""
gemini_service.py
-----------------
Wraps the Google Gen AI SDK (``google-genai``) to transcribe and summarise
civic grievance voice notes recorded in native Indian languages.
"""

import json
import os
import sys

GEMINI_MODEL = "gemini-2.5-flash"

PROMPT = """You are an assistant for a civic grievance app in India.
You will receive an audio voice note in which a citizen describes a street/civic
problem (pothole, water logging, broken streetlight, garbage, etc.), most likely
spoken in a native Indian language (Tamil, Hindi, Telugu, Bengali, etc.).

Do the following:
1. Transcribe the speech.
2. Translate the transcription into clear English.
3. Compose a short, specific title for the grievance in Title Case (4-8 words,
   no trailing punctuation). Describe the actual problem, e.g.
   "Large pothole on the main road", "Streetlight broken near bus stop",
   "Overflowing garbage bin at market", "Stormwater drain blocked".
4. Extract 2-4 short highlight tags describing the issue (e.g. "Broken road",
   "Large pothole", "Water logging", "Traffic hazard").

Respond with STRICT, minified JSON ONLY, no markdown fences, in exactly this shape:
{"title": "<short title>", "transcript": "<english transcript>", "highlights": ["tag1", "tag2"]}
"""

# Gemini-supported audio MIME types.
# Map browser-reported types to the closest supported equivalent.
MIME_NORMALISE = {
    "audio/mp4":        "audio/mp4",
    "video/mp4":        "audio/mp4",
    "audio/x-m4a":     "audio/mp4",
    "audio/m4a":        "audio/mp4",
    "audio/webm":       "audio/webm",
    "audio/ogg":        "audio/ogg",
    "audio/wav":        "audio/wav",
    "audio/wave":       "audio/wav",
    "audio/mpeg":       "audio/mp3",
    "audio/mp3":        "audio/mp3",
    "audio/aac":        "audio/aac",
    "audio/flac":       "audio/flac",
}


def _normalise_mime(mime: str) -> str:
    """Return a Gemini-accepted MIME type, defaulting to audio/webm."""
    if not mime:
        return "audio/webm"
    base = mime.split(";")[0].strip().lower()
    return MIME_NORMALISE.get(base, "audio/webm")


def _mock_result(reason: str) -> dict:
    print(f"[gemini_service] MOCK returned — reason: {reason}", file=sys.stderr)
    return {
        "title": "Large Pothole with Water Logging",
        "transcript": (
            "[Mock transcript - Gemini unavailable] A citizen reports a large "
            "pothole on the road causing water logging; vehicles and pedestrians "
            "are facing difficulty."
        ),
        "highlights": ["Broken road", "Large pothole", "Water logging"],
        "mock": True,
        "reason": reason,
    }


DUPLICATE_PROMPT = """You are checking whether a newly reported civic issue is a DUPLICATE of any existing issues nearby.

NEW ISSUE:
Title: {new_title}
Transcript: {new_transcript}
Highlights: {new_highlights}

EXISTING NEARBY ISSUES:
{existing_list}

Are any of the existing issues describing the SAME problem as the new issue?
Two issues are duplicates ONLY if they describe the same type of problem (e.g. both about potholes, both about streetlights, both about garbage).
Different problems at the same location are NOT duplicates (e.g. a pothole report and a streetlight report are different).

Respond with STRICT JSON ONLY, no markdown fences:
{{"is_duplicate": true/false, "matching_id": "<id of the matching existing issue or null>", "reason": "<one line explanation>"}}
"""


def check_duplicate(new_title: str, new_transcript: str, new_highlights: list,
                    existing_issues: list[dict]) -> dict | None:
    """
    Ask Gemini whether the new issue duplicates any of the existing nearby issues.
    Returns the matching issue dict if duplicate, else None.
    """
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key or not existing_issues:
        return None

    existing_lines = []
    for iss in existing_issues:
        highlights = iss.get("summary_highlights", [])
        if isinstance(highlights, str):
            try:
                highlights = json.loads(highlights)
            except Exception:
                highlights = []
        existing_lines.append(
            f"- ID: {iss['id']} | Title: {iss['title']} | "
            f"Transcript: {iss.get('transcript', '')} | "
            f"Highlights: {', '.join(highlights)}"
        )

    prompt = DUPLICATE_PROMPT.format(
        new_title=new_title,
        new_transcript=new_transcript,
        new_highlights=", ".join(new_highlights),
        existing_list="\n".join(existing_lines),
    )

    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=api_key)
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=[types.Content(role="user", parts=[types.Part(text=prompt)])],
        )
        text = (response.text or "").strip()
        if text.startswith("```"):
            text = text.strip("`")
            if text.lower().startswith("json"):
                text = text[4:]
            text = text.strip()

        parsed = json.loads(text)
        print(f"[gemini_service] Duplicate check: {parsed}", file=sys.stderr)

        if parsed.get("is_duplicate") and parsed.get("matching_id"):
            mid = parsed["matching_id"]
            for iss in existing_issues:
                if iss["id"] == mid:
                    return iss
        return None
    except Exception as exc:
        print(f"[gemini_service] Duplicate check error: {exc}", file=sys.stderr)
        return None


# ── Department routing ────────────────────────────────────────────────────────
# Canonical department names. Gemini must return one of these verbatim.
DEPARTMENTS = [
    "Solid Waste Management Department",
    "Electrical Department",
    "Works & Roads Department",
    "Storm Water Drain Department",
    "Public Health Department",
    "Parks & Playfields Department",
    "Allied Utilities",
]
_DEFAULT_DEPARTMENT = "Works & Roads Department"

# Keyword fallback used when Gemini is unavailable (offline-safe).
_DEPT_KEYWORDS = [
    ("Solid Waste Management Department", ["garbage", "trash", "waste", "dump", "litter", "dustbin", "clean"]),
    ("Electrical Department",            ["streetlight", "street light", "lamp", "light", "dark", "bulb", "lighting"]),
    ("Storm Water Drain Department",     ["flood", "rain", "waterlog", "water logg", "stagnant", "storm", "drain overflow"]),
    ("Public Health Department",         ["mosquito", "dengue", "malaria", "sanitation", "spray", "fogging", "disease"]),
    ("Parks & Playfields Department",    ["tree", "park", "garden", "green", "playground", "branch"]),
    ("Allied Utilities",                 ["sewage", "sewer", "water supply", "drinking water", "tangedco", "cmwssb", "power cut", "electricity"]),
    ("Works & Roads Department",         ["road", "pothole", "footpath", "pavement", "speed breaker", "tar"]),
]

DEPARTMENT_PROMPT = """You route civic grievances to the correct municipal department.

GRIEVANCE:
Title: {title}
Transcript: {transcript}
Highlights: {highlights}

Choose EXACTLY ONE department from this list (focus area in brackets):
1. Solid Waste Management Department (garbage and cleanliness)
2. Electrical Department (public street lighting)
3. Works & Roads Department (roads and footpaths)
4. Storm Water Drain Department (rainwater flood prevention)
5. Public Health Department (mosquitoes and sanitation)
6. Parks & Playfields Department (trees and green-spaces)
7. Allied Utilities (sewage, water, electricity — CMWSSB/TANGEDCO)

Respond with STRICT JSON ONLY, no markdown fences:
{{"department": "<exact department name from the list>", "reason": "<one short line>"}}
"""


def keyword_department(text: str) -> str:
    """Offline keyword classifier — returns a canonical department name."""
    t = (text or "").lower()
    for dept, words in _DEPT_KEYWORDS:
        if any(w in t for w in words):
            return dept
    return _DEFAULT_DEPARTMENT


def classify_department(title: str, transcript: str, highlights: list) -> str:
    """
    Ask Gemini which department a grievance belongs to. Falls back to a keyword
    classifier when Gemini is unavailable or returns something unexpected.
    Always returns one of ``DEPARTMENTS``.
    """
    blob = " ".join([title or "", transcript or "", " ".join(highlights or [])])
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        return keyword_department(blob)

    prompt = DEPARTMENT_PROMPT.format(
        title=title or "",
        transcript=transcript or "",
        highlights=", ".join(highlights or []),
    )
    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=api_key)
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=[types.Content(role="user", parts=[types.Part(text=prompt)])],
        )
        text = (response.text or "").strip()
        if text.startswith("```"):
            text = text.strip("`")
            if text.lower().startswith("json"):
                text = text[4:]
            text = text.strip()
        parsed = json.loads(text)
        dept = str(parsed.get("department", "")).strip()
        print(f"[gemini_service] Department route: {dept}", file=sys.stderr)
        if dept in DEPARTMENTS:
            return dept
        # Tolerate minor variations by matching on a distinctive keyword.
        for canonical in DEPARTMENTS:
            if canonical.split()[0].lower() in dept.lower():
                return canonical
        return keyword_department(blob)
    except Exception as exc:
        print(f"[gemini_service] Department routing error: {exc}", file=sys.stderr)
        return keyword_department(blob)


def process_audio(audio_bytes: bytes, mime_type: str = "audio/webm") -> dict:
    """
    Send ``audio_bytes`` to Gemini and return
    ``{"transcript": str, "highlights": list[str], "mock": bool}``.
    Never raises — falls back to a labeled mock on any failure.
    """
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        return _mock_result("No GEMINI_API_KEY configured")

    if not audio_bytes:
        return _mock_result("Empty audio payload received")

    normalised_mime = _normalise_mime(mime_type)
    print(
        f"[gemini_service] Sending {len(audio_bytes)} bytes, "
        f"original_mime={mime_type!r} → normalised={normalised_mime!r}",
        file=sys.stderr,
    )

    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=api_key)

        # google-genai ≥1.0: contents must be a list of Content objects.
        # Mixing a plain string with a Part in the same list is not valid.
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=[
                types.Content(
                    role="user",
                    parts=[
                        types.Part(text=PROMPT),
                        types.Part.from_bytes(
                            data=audio_bytes,
                            mime_type=normalised_mime,
                        ),
                    ],
                )
            ],
        )

        text = (response.text or "").strip()
        print(f"[gemini_service] Raw response: {text[:300]}", file=sys.stderr)

        # Strip accidental markdown fences.
        if text.startswith("```"):
            text = text.strip("`")
            if text.lower().startswith("json"):
                text = text[4:]
            text = text.strip()

        parsed = json.loads(text)
        transcript = str(parsed.get("transcript", "")).strip()
        title = str(parsed.get("title", "")).strip().rstrip(".!?")
        highlights = parsed.get("highlights", [])
        if not isinstance(highlights, list):
            highlights = [str(highlights)]
        highlights = [str(h).strip() for h in highlights if str(h).strip()]

        if not transcript:
            return _mock_result("Empty transcript in Gemini response")

        print(f"[gemini_service] OK — title: {title!r}, transcript: {transcript[:80]}…",
              file=sys.stderr)
        return {
            "title": title,
            "transcript": transcript,
            "highlights": highlights,
            "mock": False,
        }

    except json.JSONDecodeError as exc:
        # Model returned prose instead of JSON — salvage the raw text.
        print(f"[gemini_service] JSON parse error: {exc}", file=sys.stderr)
        raw = text if "text" in dir() else ""
        return {
            "title": "",
            "transcript": raw,
            "highlights": [],
            "mock": False,
            "reason": "Non-JSON Gemini response salvaged as transcript",
        }
    except Exception as exc:
        print(f"[gemini_service] Exception: {type(exc).__name__}: {exc}", file=sys.stderr)
        return _mock_result(f"{type(exc).__name__}: {exc}")
