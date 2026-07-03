# FixMyStreet India — Civic Grievance App (PoC)

A mobile-first proof of concept for reporting and tracking civic street
grievances. Citizens snap a photo, record a voice note in their native Indian
language, and submit a geotagged report; the backend de-duplicates nearby
issues, runs the audio through **Gemini** for transcription + summary, and
exposes the lifecycle to an authority triage console.

```
┌──────────────────────────┐        multipart / JSON        ┌──────────────────────────┐
│  Next.js 14 (App Router)  │  ───────────────────────────►  │  FastAPI (Python 3)       │
│  Tailwind · react-leaflet │  ◄───────────────────────────  │  SQLite · Haversine       │
│  Mobile shell (max-w-md)  │                                 │  google-genai (Gemini)    │
└──────────────────────────┘                                 └──────────────────────────┘
        │  OpenStreetMap tiles                                        │  /uploads static files
        ▼                                                             ▼
   tile.openstreetmap.org                                       local disk (images/audio)
```

## Stack

| Layer    | Tech                                                              |
|----------|------------------------------------------------------------------|
| Frontend | Next.js 14 (App Router, JS), Tailwind CSS, react-leaflet/Leaflet  |
| Backend  | FastAPI, Uvicorn, stdlib `sqlite3` (no ORM), pure-Python Haversine|
| AI       | Google Gen AI SDK (`google-genai`), model `gemini-2.5-flash`      |
| Maps     | OpenStreetMap tiles via Leaflet                                   |

---

## Quick start

### 1. Backend (FastAPI)

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Optional: live transcription. Without a key, a clearly-labeled MOCK
# transcript is returned so the app still works end-to-end.
cp .env.example .env          # then edit GEMINI_API_KEY=...

uvicorn main:app --reload --port 8000
```

Backend runs at `http://localhost:8000` (interactive docs at `/docs`).
Seed demo data around Anna Nagar, Chennai:

```bash
curl -X POST "http://localhost:8000/api/seed?user_id=demo-user"
```

### 2. Frontend (Next.js)

```bash
cd frontend
npm install
cp .env.local.example .env.local   # NEXT_PUBLIC_API_BASE=http://localhost:8000
npm run dev
```

- Citizen app: `http://localhost:3000`
- Authority console: `http://localhost:3000/admin`

> The map and admin screens have a **“Load demo data”** button that calls
> `/api/seed` for you.

---

## Screens

| Route      | Screen            | Highlights                                                                 |
|------------|-------------------|---------------------------------------------------------------------------|
| `/`        | Report Issue      | Geolocation, camera/gallery upload, MediaRecorder voice note + visualizer, duplicate modal, AI summary |
| `/map`     | Explore Map       | Leaflet/OSM, status-colored pins, radius circle, click → bottom-sheet with upvote |
| `/history` | My History        | Lifecycle timeline, status badges, **verification panel** (Approve/Reject) |
| `/admin`   | Authority Console | Desktop split view: upvote-priority queue + detail pane (image, audio, transcript, pinpoint map) |

---

## API reference (integration boundary)

Each function in `frontend/lib/api.js` maps 1:1 to a route below.

| Method | Path                              | Purpose                                                            |
|--------|-----------------------------------|-------------------------------------------------------------------|
| POST   | `/api/issues/report`              | Report issue. 50m Haversine dedupe → `{duplicate_exists, existing_issue}`; else Gemini transcribe + save |
| POST   | `/api/issues/{id}/upvote`         | Upvote (one per `user_id`; second returns 409)                    |
| GET    | `/api/issues/nearby`              | `?lat&lng&radius` (m) — issues inside the circle for the map      |
| GET    | `/api/issues/history/{user_id}`   | A user's submissions, newest first                                |
| POST   | `/api/issues/{id}/verify`         | `APPROVED`→`CLOSED`, `REJECTED`→`IN_PROGRESS`                     |
| GET    | `/api/admin/issues`               | Open queue sorted by upvotes desc                                 |
| POST   | `/api/admin/issues/{id}/close`    | Mark resolved → `PENDING_VERIFICATION` + mock reporter notification |
| POST   | `/api/admin/issues/{id}/progress` | (helper) `ACTIVE` → `IN_PROGRESS`                                 |
| POST   | `/api/seed`                       | (dev) reset + insert demo issues                                  |

### Status state machine

```
ACTIVE ──(admin start)──► IN_PROGRESS ──(admin close)──► PENDING_VERIFICATION
   │                            ▲                                │
   └────(admin close)───────────┘                                │
                                                  ┌──────────────┴──────────────┐
                                          (citizen REJECTED)            (citizen APPROVED)
                                                  ▼                              ▼
                                            IN_PROGRESS                       CLOSED
```

---

## Data model (SQLite — `backend/database.py`)

- **issues**: `id (uuid)`, `title`, `image_url`, `audio_url`, `transcript`,
  `summary_highlights (json)`, `latitude`, `longitude`, `status`, `upvotes`,
  `notify_reporter`, `created_at`, `created_by`
- **upvotes**: `id`, `user_id`, `issue_id` — `UNIQUE(user_id, issue_id)`
- **verifications**: `id`, `issue_id`, `user_id`, `response`, `timestamp`

Radius queries use the Haversine formula in `backend/utils.py` (`haversine_m`)
— adequate for a PoC; swap for PostGIS in production.

---

## Notes & error handling

- **Gemini is optional.** No key → labeled mock transcript so demos never break.
  Parsing also tolerates markdown fences and non-JSON responses.
- **Geolocation** falls back to Anna Nagar, Chennai if permission is denied.
- **MediaRecorder** prefers `audio/webm`; the mic is released on stop.
- **CORS** is fully open in the PoC; lock down `allow_origins` for production.
- **No auth**: the browser gets a stable `localStorage` user id; `/admin` is
  unprotected (add an admin role before deploying).
- Leaflet components are imported with `next/dynamic { ssr: false }` because
  Leaflet touches `window` at module load.
