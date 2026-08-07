"""
gemini_service.py
-----------------
Wraps the Google Gen AI SDK (``google-genai``) to transcribe and summarise
civic grievance voice notes recorded in native Indian languages.
"""

import json
import os
import re
import sys
import time

# Model chain, preferred first. Every Gemini call walks this list.
#
# Why a chain at all: gemini-2.5-flash has been answering TEXT requests fine
# while returning 503 UNAVAILABLE ("experiencing high demand") for AUDIO ones —
# observed hours apart, so it is a sustained capacity condition rather than a
# spike. With a single model and no retry, one 503 fell straight through to the
# labelled mock transcript, and that mock is then persisted on the issue row
# forever. gemini-flash-latest served the identical audio successfully.
#
# Override with GEMINI_MODELS="a,b,c" to re-order or extend without a deploy.
GEMINI_MODELS = [
    m.strip()
    for m in os.getenv(
        "GEMINI_MODELS", "gemini-2.5-flash,gemini-flash-latest"
    ).split(",")
    if m.strip()
]

# Kept as the canonical single-model name for callers that still import it.
GEMINI_MODEL = GEMINI_MODELS[0] if GEMINI_MODELS else "gemini-2.5-flash"

# Statuses worth waiting out on the SAME model — overload and rate limiting are
# expected to clear. Anything else (404 unknown model, 400 bad request, 403 bad
# key) will not improve with a retry, so those move straight to the next model.
_RETRY_STATUSES = frozenset({429, 500, 502, 503, 504})
_MAX_ATTEMPTS = 2
_BASE_DELAY = 0.7

PROMPT = """You are an assistant for a civic grievance app in India.
You will receive an audio voice note in which a citizen describes a street/civic
problem (pothole, water logging, broken streetlight, garbage, etc.), most likely
spoken in a native Indian language (Tamil, Hindi, Telugu, Bengali, etc.).

Do the following:
1. Transcribe the speech.
2. Translate the transcription into clear English.
3. Also provide the same transcript in clear Tamil (தமிழ்).
4. Compose a short, specific title for the grievance in Title Case (4-8 words,
   no trailing punctuation). Describe the actual problem, e.g.
   "Large pothole on the main road", "Streetlight broken near bus stop",
   "Overflowing garbage bin at market", "Stormwater drain blocked".
5. Extract 2-4 short highlight tags describing the issue (e.g. "Broken road",
   "Large pothole", "Water logging", "Traffic hazard").

Respond with STRICT, minified JSON ONLY, no markdown fences, in exactly this shape:
{"title": "<short title>", "transcript": "<english transcript>", "transcript_ta": "<tamil transcript>", "highlights": ["tag1", "tag2"]}
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


def _status_of(exc: Exception) -> int | None:
    """Best-effort HTTP status for a google-genai error.

    The SDK surfaces these inconsistently across versions, so fall back to
    reading the leading status out of the message text.
    """
    for attr in ("code", "status_code"):
        value = getattr(exc, attr, None)
        if isinstance(value, int):
            return value
    match = re.search(r"\b([45]\d{2})\b", str(exc))
    return int(match.group(1)) if match else None


def _generate(contents, *, label: str):
    """Run a Gemini request across the model chain with retry + fallback.

    Each model gets [_MAX_ATTEMPTS] tries, backing off between them, but only
    for the transient statuses above; everything else advances to the next
    model immediately. Raises the final exception once the chain is exhausted,
    so each caller keeps its own existing fallback behaviour.
    """
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError("No GEMINI_API_KEY configured")
    if not GEMINI_MODELS:
        raise RuntimeError("GEMINI_MODELS is empty")

    from google import genai

    client = genai.Client(api_key=api_key)
    last_exc: Exception | None = None

    for model in GEMINI_MODELS:
        for attempt in range(1, _MAX_ATTEMPTS + 1):
            try:
                response = client.models.generate_content(
                    model=model, contents=contents
                )
                # Only worth a line when the happy path did NOT hold, so the
                # logs show exactly when the chain is carrying us.
                if model != GEMINI_MODELS[0] or attempt > 1:
                    print(
                        f"[gemini_service] {label}: served by {model} "
                        f"on attempt {attempt}",
                        file=sys.stderr,
                    )
                return response
            except Exception as exc:  # noqa: BLE001 — reported, then retried
                last_exc = exc
                status = _status_of(exc)
                print(
                    f"[gemini_service] {label}: {model} attempt {attempt} "
                    f"failed — {type(exc).__name__} {status}: {str(exc)[:140]}",
                    file=sys.stderr,
                )
                if status in _RETRY_STATUSES and attempt < _MAX_ATTEMPTS:
                    time.sleep(_BASE_DELAY * (2 ** (attempt - 1)))
                    continue
                break  # next model in the chain

    raise last_exc if last_exc else RuntimeError("Gemini: no attempt was made")


def _mock_result(reason: str) -> dict:
    print(f"[gemini_service] MOCK returned — reason: {reason}", file=sys.stderr)
    return {
        "title": "Large Pothole with Water Logging",
        "transcript": (
            "[Mock transcript - Gemini unavailable] A citizen reports a large "
            "pothole on the road causing water logging; vehicles and pedestrians "
            "are facing difficulty."
        ),
        "transcript_ta": (
            "[மாதிரி வாக்கு - Gemini கிடைக்கவில்லை] சாலையில் பெரிய பள்ளம் "
            "காரணமாக தண்ணீர் தேங்குகிறது; வாகனங்களும் பாதசாரிகளும் சிரமப்படுகின்றனர்."
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
        from google.genai import types

        response = _generate(
            [types.Content(role="user", parts=[types.Part(text=prompt)])],
            label="Duplicate check",
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
        from google.genai import types

        response = _generate(
            [types.Content(role="user", parts=[types.Part(text=prompt)])],
            label="Department routing",
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
        from google.genai import types

        # google-genai ≥1.0: contents must be a list of Content objects.
        # Mixing a plain string with a Part in the same list is not valid.
        response = _generate(
            [
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
            label="Transcription",
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
        transcript_ta = str(parsed.get("transcript_ta", "")).strip()
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
            "transcript_ta": transcript_ta,
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
            "transcript_ta": "",
            "highlights": [],
            "mock": False,
            "reason": "Non-JSON Gemini response salvaged as transcript",
        }
    except Exception as exc:
        print(f"[gemini_service] Exception: {type(exc).__name__}: {exc}", file=sys.stderr)
        return _mock_result(f"{type(exc).__name__}: {exc}")
