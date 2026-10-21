# UI bug log — citizen app

Targeted UI/visual fixes only. No backend, API, data-fetching, state or
navigation logic is touched by anything recorded here.

Each entry records the **symptom** as reported, the **cause** found in the
code, and the **fix** — so a later reader can tell whether a regression is the
same bug returning or a new one wearing its clothes.

---

## 1. Report sheet sits half-risen, with a clipped white box at the bottom edge

**Cause.** `report_sheet.dart` translated the **whole sheet body** down by
`_kSwipeBlockHeight` (78lp) via `Transform.translate` whenever the photo +
voice pair was still missing, to park the submit slider below the screen.
Translating the body moves its bottom edge off-screen too, so the sheet read as
half-risen and the white slider was left clipped at the bottom. The intent was
deliberate; the mechanism was the bug.

**Fix.** The sheet no longer moves. The swipe block reveals by growing **its own
height** (`SizeTransition` on the same eased `_reveal`), so the sheet stays
flush to the bottom edge at every stage and nothing hangs off-screen.

**Verify.** Open the report sheet with nothing attached. Its bottom edge must
sit flush on the screen edge with no clipped control below it. Adding both
attachments grows the swipe block into view.

---

## 2. Content "stretches" and tears away from its container when pulled past the end

Seen in the home sheet (cards pull clear of the sheet, the pinned header loses
its grip) and in the grievance dialog (the photo is pushed down behind a white
band).

**Cause.** `_NkScrollBehavior` in `app.dart` set `BouncingScrollPhysics`
app-wide but never overrode `buildOverscrollIndicator`, so
`MaterialScrollBehavior` **also** installed Android 12+'s
`StretchingOverscrollIndicator`. That is one root cause producing two artifacts,
both of which read as "stretching":

1. The indicator applies a **scale transform to the whole viewport**, pinned
   headers included. It is a paint-time effect, so it is invisible to physics,
   sliver and layout changes.
2. The bouncing physics **translates content past its end**, opening the
   container's own background behind it.

Being app-wide is why it appeared in the grievance dialog — a separate widget
with its own `SingleChildScrollView` — as well as in the home sheet.

**Fix.** Both in `_NkScrollBehavior`:

- `buildOverscrollIndicator` returns the child unchanged — no stretch transform.
- `getScrollPhysics` is `ClampingScrollPhysics` — no overscroll translation.

`AlwaysScrollableScrollPhysics` is kept as the parent: the home sheet relies on
a short list still accepting a drag so it can resize itself.

This reverses an earlier deliberate choice ("rubber-band overscroll
everywhere"). Lists now stop dead at their ends across the whole app — sheet,
dialog, profile, search.

**Verify.** Pull the home sheet's cards up, and pull down inside a grievance
dialog. Content must stop dead; nothing may scale or detach from its container.

---

## 3. A long constituency name collides with the ward selector

**Cause.** The ward pill and the test-location picker were two independent
`Positioned` chips in the same `Stack` — one pinned `left: 14`, the other
`right: 14`, neither aware of the other. The pill had no width bound and its
constituency `Text` had no `overflow`, so a long name ("Thiru-Vi-Ka-Nagar")
grew the pill rightwards until it ran under the picker, pushing the ward number
out of view.

**Fix.** Merged both into one `Positioned(left: 14, right: 14)` row. The picker
keeps its intrinsic width (its dropdown is a fixed 96lp); the pill takes the
remainder via `Expanded`. Inside the pill, **only** the constituency is
`Flexible` with `ellipsis` — the divider, the "Ward" label and the number keep
their intrinsic width, so a long name truncates itself rather than evicting the
ward number.

**Verify.** Pick a ward in a long-named constituency (Thiru-Vi-Ka-Nagar,
Dr. Radhakrishnan Nagar). The pill must ellipsise its own name and the ward
number must stay visible. *Confirmed on device.*

---

## Also fixed along the way

Two genuine defects found while tracking down #2. Neither was its cause, and
both are worth keeping.

**Sheet header broke its own extent contract.** On the In my Ward tab the
header's content was 101lp — grip, status pills, *and* the scope/sort filter
block, which was built unconditionally and merely hidden by a `ClipRect` —
while the delegate declared `minExtent == maxExtent == 64`. A
`SliverPersistentHeaderDelegate` must build to exactly its declared extent. The
filter block is now built only while revealed, so content matches the declared
extent in both settled states; the `OverflowBox` remains solely to absorb the
brief mismatch *while* the extent animates between 64 and 102.

**The expanded snap outran its content.** `maxChildSize` was a fixed per-device
ceiling (~0.84) regardless of card count, so expanding with two or three cards
opened a tall band of empty white below them. `_sheetMaxFraction` now takes the
live card count and caps the expanded snap at the content's own height, still
bounded by the device ceiling: 3 cards → 0.512, 5 cards → 0.722, 8+ → the
ceiling with the list scrolling as before. A `floor + 0.06` minimum keeps the
two snap stops ascending and the sheet draggable when the list is tiny.

---

## Status

Bugs 2 and the two items above are **unverified on device** — the emulator sits
behind the app's 4-digit PIN lock, and its `/data` is 94% full with a
`system_server` that has already restarted once. Test
`app-arm64-v8a-release.apk` on a real phone.
