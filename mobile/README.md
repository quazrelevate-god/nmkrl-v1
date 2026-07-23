# நம் குரல் — Citizen App (Flutter)

Native Android (iOS-ready) rewrite of the phase-1 citizen web app. One
codebase, the same FastAPI backend, the same design system (royal navy +
gold, iOS-style glassmorphism), rebuilt with native camera / voice / GPS.

## What's inside

| Screen / flow | Source | Web counterpart |
|---|---|---|
| Animated government splash | `lib/features/splash/` | `SplashScreen.js` |
| Citizen sign-in (mock OTP) | `lib/features/login/` | `app/login/page.js` |
| Home: profile + constituency highlights | `lib/features/home/widgets/profile_header.dart` | `CitizenProfileHeader.js` |
| Grievance map (OSM + GCC boundaries + pins) | `lib/features/home/widgets/map_card.dart` | `MapView.js` + `BoundaryLayer.js` |
| In My Ward / My Reports + lifecycle cards | `lib/features/home/widgets/issue_card.dart` | `IssueCard` (web home) |
| Report flow: camera, voice (m4a), swipe-submit, duplicate check | `lib/features/report/` | `ReportModal.js` + `DuplicateModal.js` |
| Support (upvote) + success overlays | `lib/features/upvote/`, `report/widgets/success_overlay.dart` | `UpvoteModal.js` + `SuccessOverlay.js` |
| Story viewer (gestures: tap/hold/swipe-down) | `lib/features/story/` | `StoryViewer.js` |

Architecture: Riverpod (DI + auth state) · go_router · dio (+1 retry, friendly
errors) · flutter_map · geolocator · image_picker · record/audioplayers ·
shared_preferences. Pure-logic ports (`lib/domain/`) are unit-tested against
the web behavior.

## Auth is mock (by design, phase 1)

OTP is illustrative: any 6-digit code verifies; the demo code hint (246813)
and the "Continue as Raj Kumar" pill mirror the web PoC. Replace
`AuthNotifier` + the login screen with a real OTP/token flow in phase 2.

## Run it

```bash
export PATH="$HOME/development/flutter/bin:$PATH"   # SDK on this machine

cd mobile
flutter pub get
flutter test                 # 39 tests
flutter analyze              # zero issues

# Android emulator against the LOCAL backend (default API base
# http://10.0.2.2:8000 = your machine's localhost:8000):
cd ../backend && venv/bin/uvicorn main:app --port 8000 &
flutter run

# Physical device against local backend:
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_BASE=http://localhost:8000

# Against the deployed Railway backend:
flutter run --dart-define=API_BASE=https://nmkrl-v1-production-587d.up.railway.app

# Release build (needs Android SDK / Android Studio installed):
flutter build apk --release --dart-define=API_BASE=https://nmkrl-v1-production-587d.up.railway.app
```

Cleartext HTTP is allowed **only** for `10.0.2.2` / `localhost` (see
`android/.../network_security_config.xml`); production traffic must be https.

## Notes

* App id: `com.nammakural.app` (locked at first Play upload).
* Demo photos are bundled under `assets/community/` (`community-01` was
  converted AVIF → JPG; Flutter doesn't decode AVIF).
* Voice notes record as AAC `.m4a` — the backend maps `audio/mp4` straight
  to Gemini for transcription.
* iOS folder ships with the right permission strings already (phase 2).
