# NamKural — engineering handoff

Written to hand this work to another engineer (or another AI coding session).
Everything here was verified against the repo, not recalled.

---

## 1. What this is

A civic grievance platform for Tamil Nadu local government. A citizen files a
grievance from the phone with a photo + voice note; Gemini transcribes and
summarises it; it is routed to a ward coordinator, who works it through a
status lifecycle; an admin console oversees the whole constituency.

Deployables in one repo:

| Path | What | Stack |
|---|---|---|
| `backend/` | API + AI + routing | FastAPI (Python), SQLite or PostgreSQL |
| `frontend/` | Admin / staff console | Next.js |
| `mobile/` | Citizen + coordinator app | Flutter |
| `tools/` | Map + seed data scripts | Python |
| `audit/`, `docs/` | Reports and logs | — |

**Two product names** (deliberate, commit `3eff584`): *Namkural GMS Portal*
for staff, *Namkural Connect* on phones.

---

## 2. Mobile app — the part under active work

- **Flutter 3.44.4 stable**. Package `com.nammakural.app`.
- `compileSdk = 36` — **pinned deliberately**: `file_picker` pulls in
  `flutter_plugin_android_lifecycle`, which requires API 36.
- State: **Riverpod**. Routing: **go_router**. HTTP: **dio**.
- Maps: **flutter_map** (OSM tiles). Location: **geolocator**.
- Media: **image_picker** (camera), **record** (voice), **file_picker**
  (optional petition PDF/DOC).
- Push: Firebase Cloud Messaging, project `nammakural-2927f`.
- App lock: 4-digit PIN, SHA-256 via **crypto**, never leaves the device.

### Files you will touch most

| File | Why it matters |
|---|---|
| `lib/features/home/home_screen.dart` | ~2,700 lines. Citizen home: map, draggable sheet, nav bar, ward pill, tab transitions. Most UI work lands here. |
| `lib/features/report/report_sheet.dart` | The "file a grievance" modal — photo, voice, petition, swipe-to-submit. |
| `lib/features/report/widgets/swipe_to_confirm.dart` | The swipe control. |
| `lib/app.dart` | MaterialApp, router, and `_NkScrollBehavior` (app-wide scroll feel). |
| `lib/domain/status_meta.dart` | Single source of truth for status labels, colours, and `supportable()`. |
| `lib/core/i18n.dart` | English to Tamil map. Lookups are **by English string**. |
| `lib/domain/constituencies.dart` | Ward to Assembly Constituency map, shipped client-side. |

### Conventions in this codebase

- Comments explain **why**, not what. Match that density — it is unusually
  high and deliberate.
- A UI task means UI only: do not touch backend, API calls, data fetching,
  state management, or navigation unless asked.
- `docs/ui-bug-log.xlsx` records every fix: symptom, cause, fix, how to
  verify, status, commit. Keep it current.

---

## 3. Environments

- **Backend (prod):** `https://nmkrl-v1-production-587d.up.railway.app`
  (Railway). Release builds point here; debug builds point at
  `http://10.0.2.2:8000`. See `lib/core/env.dart`.
- **Database:** SQLite by default; PostgreSQL when `DATABASE_URL` names one
  (commit `e264dce`).
- **Default corporation:** Tambaram; the admin sidebar switches to Chennai
  (commit `1b10121`).

---

## 4. Build and run

```bash
# from mobile/
flutter pub get
flutter analyze                       # must be clean before you commit
flutter build apk --release --split-per-abi
```

Use `--split-per-abi`. The fat APK is ~61 MB and **will not install on the dev
emulator** (its `/data` is ~94% full). The splits are ~22-26 MB:

- `app-arm64-v8a-release.apk` — real phones
- `app-x86_64-release.apk` — the emulator

```bash
adb install -r build/app/outputs/flutter-apk/app-x86_64-release.apk
```

If that fails with `INSUFFICIENT_STORAGE`, run
`adb uninstall com.nammakural.app` first — but that **clears the session and
the PIN**, so you land back at sign-in.

### Release signing

Release builds are **debug-signed** unless `android/key.properties` exists
(git-ignored, not in the repo). Play will reject a debug-signed upload.
Generate the keystore per the runbook referenced in
`android/app/build.gradle.kts`.

---

## 5. Git state

- Branch: **`phase1_flutter`** (not `main`).
- Remote: `https://github.com/quazrelevate-god/nmkrl-v1`
- Last pushed: **`da64715`**.

| Commit | What |
|---|---|
| `da64715` | swipe label, location retries, narrow-screen ward pill, Tamil fit, status chip |
| `dcc15ac` | report sheet rises flush; ward pill yields to the selector |
| `895ebd0` | lists stop at their ends instead of stretching past them |
| `927d571` | Pilot audit v1 (app + console) — not ours |

---

## 6. Session log — what was fixed and why

Full detail in `docs/ui-bug-log.xlsx`. Condensed:

1. **App-wide scroll stretching** (`895ebd0`). `_NkScrollBehavior` set bouncing
   physics but never overrode `buildOverscrollIndicator`, so Android 12+'s
   `StretchingOverscrollIndicator` was also installed. Two artifacts, one
   cause: a paint-time scale on the whole viewport (pinned headers included),
   and bouncing physics translating content past its end. Both removed.
   **This reversed a deliberate earlier choice** — there is no rubber band
   anywhere in the app now.
2. **Report sheet half-risen** (`dcc15ac`). It translated its whole body down
   78lp to hide the submit slider, pushing its bottom edge off-screen. The
   swipe block now reveals by growing its own height.
3. **Ward pill colliding with the ward selector** (`dcc15ac`).
4. **Sheet header broke its extent contract** (`dcc15ac`). It built to 101lp on
   the ward tab while declaring `minExtent == maxExtent == 64`. A
   `SliverPersistentHeaderDelegate` must build to exactly its declared extent.
5. **Expanded snap outran its content** (`dcc15ac`). `maxChildSize` is now
   capped at the content's own height.
6. **Swipe label hidden by the thumb** (`da64715`).
7. **Location failing on repeat attempts** (`da64715`). No guard against
   overlapping `_locateDevice` calls, plus a 10s limit too short for a warm GPS.
8. **Blank constituency on narrow screens** (`da64715`). Caused *by* fix 3 —
   its `Flexible` + ellipsis collapsed the name at 360lp.
9. **Tamil status chip overflow** (`da64715`). `PENDING_VERIFICATION` now reads
   "Resolved" + an exclamation glyph; Support withdrawn for that status via
   `status_meta.supportable()`.
10. **Tamil nav bar** (`da64715`).

### Uncommitted at handoff

- **Feed refresh flash after submit.** `_loadHistory()` raised `_histLoading`
  on every call, and `_myReportCards()` returns only a spinner while that flag
  is up — so the post-submit poller (every 3s for ~21s while Gemini works) tore
  the feed down seven times. The spinner now shows only when `_history` is
  empty.
- **Tab transition flicker.** Replacing the box adapter with a lazy
  `SliverList` had removed the page slide, leaving only per-card stagger — and
  because `_StaggeredEntry` has no keys, most cards reuse State and do not
  animate at all, so some moved and some did not. Every list child is now
  wrapped in `_TabSlide`, fed the same `_tabAnimCtrl`, so they translate
  together as one page.

---

## 7. Open items

### A. Camera restart loses the photo and the draft — **not fixed**

Cause in section 8. Options, increasing scope:

1. Call `ImagePicker().retrieveLostData()` on resume. Recovers the photo only.
2. Plus persist the in-progress report (photo path, voice path, ward) as each
   piece is captured, and reopen the sheet on relaunch. Covers the whole loss.
3. Plus a one-time prompt to exempt the app from battery optimisation.
   Intrusive and Play-policy sensitive.

`retrieveLostData()` is currently **not called anywhere** — verified.

### B. Swipe "progressive background" — **undecided**

A teammate asked for a progressive background on the swipe thumb. The control
**already has one**: `_fillWidth()` grows a fill behind the thumb. It is set to
navy at **8% opacity** on a white track, so it is nearly invisible. Decide
whether they want it strengthened, a colour-shift gradient, or the whole sheet
tinted — then implement. Do not guess.

### C. Verification debt

**Nine of the ten fixes in section 6 are unverified on a real device.** Only
the ward pill collision was confirmed visually. Reasons in section 9.

---

## 8. Why the app restarts when taking a photo

**It is not a crash.** Android is *destroying and recreating* the app, and
Flutter has no state left to come back to.

### The mechanism

1. `ImagePicker.pickImage(source: ImageSource.camera)` does **not** open a
   camera inside the app. It fires an `Intent` to the device's camera app, and
   our activity goes to the **background**.
2. A backgrounded activity is a candidate for destruction. Android reclaims it
   when memory is tight — and the camera is one of the most memory-hungry
   things a phone does.
3. On MIUI (Redmi 15A) this is far more aggressive than stock Android. MIUI's
   battery manager actively kills backgrounded processes rather than waiting
   for memory pressure. That is why it reproduces there and not on the
   emulator.
4. When the camera returns, Android recreates `MainActivity` **from scratch**.
   A new Flutter engine starts, `main()` runs again, and every widget's `State`
   is gone — including the whole report sheet.
5. The `onActivityResult` carrying the photo is delivered to an activity
   instance that no longer exists, so the result is dropped. This is known
   Android behaviour, not a plugin bug — it is exactly why `image_picker`
   ships `retrieveLostData()`.

### Why nothing survives it

The report sheet is a **modal holding all its state in memory**: `_images`,
the recorder, the selected ward. There is **no persistence at any point** —
verified, nothing writes a draft. A restart therefore loses the photo *and*
everything else the user had already done, with no trace that a submission was
ever in progress.

### Why `configChanges` does not help

`AndroidManifest.xml` declares a broad `configChanges` list, which prevents
recreation on rotation, locale and density changes. That has **no effect
here** — this is process death, not a configuration change.

### What a fix must do

- `retrieveLostData()` recovers the **photo** after a restart. Necessary, not
  sufficient.
- Durable draft state recovers **the rest**. Write each captured piece to disk
  as it is captured (they are already files in temp storage) and restore on
  launch.
- Treat it as a *when*, not an *if*: on MIUI, Vivo, Oppo and Samsung this will
  happen to real users routinely.

---

## 9. Environment gotchas that will waste your time

- **The emulator app is behind the 4-digit PIN lock.** You cannot drive the UI
  past it without the PIN. This blocked most device verification.
- **The emulator's `/data` is ~94% full** and its `system_server` has restarted
  at least once. Installs fail with `INSUFFICIENT_STORAGE`; `pm trim-caches`
  frees nothing. Consider wiping it.
- **adb can go `unauthorized`** after an emulator restart — accept the USB
  debugging prompt, or cold boot.
- **The emulator is 411lp wide; a Redmi 15A is 360lp.** Several bugs reproduce
  *only* at the narrower width:
  ```bash
  adb shell wm size 720x1600 && adb shell wm density 320
  adb shell wm size reset  && adb shell wm density reset   # afterwards
  ```
  **The override is currently still applied.**
- **`docs/ui-bug-log.xlsx` formulas show blank until opened.** The recalc
  helper needs LibreOffice, which cannot start on Windows here
  (`socket has no attribute 'AF_UNIX'`). Excel and Sheets compute on open.
- **`flutter analyze` is slow** — up to ~4 minutes on a cold run. It is not
  hung.

---

## 10. If you are an AI session picking this up

- Read `docs/ui-bug-log.xlsx` first — it has the causes, not just the fixes.
- Several bugs here were **caused by a previous fix**. Before blaming new code,
  check whether a recent change introduced the symptom (items 3 → 8 in
  section 6 are exactly that).
- Reproduce before diagnosing. Several wrong diagnoses in this session came
  from reasoning about the code instead of observing the device — in
  particular, testing at a width where the bug could not occur.
- Screenshot dimensions tell you which device a report came from: 720×1600 is
  the Redmi, 1080×2400 is the emulator. That one detail resolved a bug that had
  already taken several wrong turns.
