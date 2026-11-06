import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../domain/constituencies.dart';
import '../../domain/coordinator_data.dart';
import '../../domain/demo_stories.dart';
import '../../domain/geo_utils.dart';
import '../../domain/models/boundary_data.dart';
import '../../domain/models/corporation.dart';
import '../../domain/models/issue.dart';
import '../../domain/models/story.dart';
import '../../state/providers.dart';
import '../home/widgets/issue_card.dart';
import '../home/widgets/profile_header.dart';
import '../../domain/models/duplicate_info.dart';
import '../home/widgets/map_card.dart';
import '../shared/nature_backdrop.dart';
import '../shared/notification_banner.dart';
import '../stories/story_composer.dart';
import '../stories/story_rail.dart';
import 'widgets/action_sheets.dart';

/// Coordinator home — map-first treatment for staff:
///   full-bleed ward map under a frosted app bar + read-only constituency·ward
///   chip (both assigned in the admin console), Open | Assigned | Escalated |
///   Resolved tabs in a draggable sheet, sort dropdown (Recent | Priority),
///   in-app notification banner for new grievances in this ward.

/// Sheet snap fractions — same composition as the citizen home: the floor is
/// the landing size AND the minimum, sized to the pinned header plus ~2 cards,
/// and it is the only resting place below the near-full expanded snap.
const double _kSheetMax = 0.86;

/// Nature band behind the app bar — identical geometry to the citizen home, so
/// the two apps open on the same masthead.
/// Spill BELOW the capsule. At 10 the band was a sliver: the capsule covered
/// the sky, the Bay was a few pixels and the palms were squeezed against the
/// top edge. 30 gives the horizon somewhere to sit and the scene reads as a
/// coast, at the cost of 20dp of map.
/// Breathing room under the app-bar capsule before the story rail begins.
const double _kBackdropSpill = 6;

/// Top edge of the app-bar capsule.
///
/// Back at the top of the screen. It used to be driven down to the gopuram's
/// base so the temple in the old coastal photo stood clear above it; the sky
/// asset has no subject to clear, so the bar reclaims that space and the map
/// gets it back.
double kCoordAppBarTop(double topInset) => topInset + 8;

/// The sky band + capsule block, story rail excluded.
///
/// At least tall enough for the bar and its spill, and at least as tall as the
/// image itself so the band is never cut short of its own last row — on a wide
/// screen the image is the taller of the two.
double kCoordBackdropHeight(double topInset, double screenWidth) => math.max(
      kCoordAppBarTop(topInset) + kAppBarHeight + _kBackdropSpill,
      NatureBackdrop.imageHeight(screenWidth),
    );

/// Fixed-duration settle, matching the citizen sheet, so a flick and a slow
/// drag travel at the same speed instead of on a velocity-driven simulation.
const Duration _kSheetSnapDuration = Duration(milliseconds: 320);

/// Rough on-screen footprint of one grievance card, used to size the floor.
const double _kCardFootprint = 96;

/// Pinned grip + 4-segment tab block. grip 8+4+10, track ~49, trailing 12 ≈ 83;
/// held above that since the sliver extent is fixed and slack is invisible.
const double _kSheetHeaderHeight = 88;

/// The one corner radius in the composition — it belongs to the white sheet.
const double _kSheetCornerRadius = 22;

class CoordinatorHomeScreen extends ConsumerStatefulWidget {
  const CoordinatorHomeScreen({super.key});

  @override
  ConsumerState<CoordinatorHomeScreen> createState() =>
      _CoordinatorHomeScreenState();
}

class _CoordinatorHomeScreenState extends ConsumerState<CoordinatorHomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  BoundaryData? _boundaries;
  // The whole constituency feed. The visible list is this, filtered to the
  // selected ward (see the _parts getter). Notifications stay ward-locked
  // server-side; this screen is the browse/claim surface across the AC.
  List<Issue> _allIssues = [];
  Issue? _selected;
  final Map<String, GlobalKey> _cardKeys = {};
  LatLng? _center;
  String? _error;
  String? _busyId;
  String? _toast;

  // The AC's wards (from the live corporation's table — see _wardsFor) and
  // which one the list is filtered to.
  // '' means "All wards" (the whole constituency). Defaults to the coordinator's
  // own home ward — their priority, and the ward their notifications come from.
  // Not final: a home-ward or constituency change made in the admin console
  // re-scopes this when the profile refreshes (see _refreshProfile).
  late List<String> _acWards;
  late String _ward;
  CoordinatorTab _tab = CoordinatorTab.ward;
  String? _expandedId;
  String _sort = 'recent'; // 'recent' | 'priority'

  /// Drives the destination page-slide: restarted on every segment change.
  /// Same composition, duration and curve as the citizen home so both screens
  /// read as one system.
  late final AnimationController _tabAnimCtrl;

  /// Real collapsed card heights, per segment tab, measured off the sheet
  /// rather than copied from the citizen's constant — the coordinator card is
  /// a different widget (1-line title, pill wrap, optional duplicate ribbon)
  /// and a wrong constant either hides the second card's bottom half or opens
  /// a gap under it. The floor is header + 8 + 2 × the active tab's
  /// measurement; 0 means "not measured yet, use [_kFootprintFallback]".
  /// Sampled twice per tab (imperfect screen raster, hairline kerning) and
  /// then settled; only fully-collapsed states are sampled, so an expanded
  /// card's height never pollutes the floor.
  final Map<int, double> _cardFootprintByTab = {};
  double? _cardSample;

  /// What a fully-collapsed card of the active tab measured. Called from the
  /// [_MeasureHeight] wrapper sitting around the sheet's first two cards.
  ///
  /// Two agreeing samples (within 1px — subpixel raster differences between
  /// builds shouldn't be trusted alone) settle the tab's footprint; the floor
  /// formula then reads it. Samples are taken only while no card is expanded
  /// (an expanded card's height would inflate the floor) and only for the
  /// active tab, since the ribbon/badge heights differ per tab.
  void _onCardMeasured(int tabIndex, double height) {
    if (_expandedId != null) return;
    final settled = _cardFootprintByTab[tabIndex];
    // Already conclusive — and this value still agrees with the settled one,
    // so nothing to do and no setState churn.
    if (settled != null && (settled - height).abs() <= 1) {
      _cardSample = null;
      return;
    }
    final first = _cardSample;
    if (first == null) {
      _cardSample = height;
      return;
    }
    if ((first - height).abs() <= 1) {
      final mean = (first + height) / 2;
      _cardSample = null;
      // Floor and snap read this — tell the sheet.
      setState(() => _cardFootprintByTab[tabIndex] = mean);
    } else {
      // Disagreement: trust the newest reading, wait for the next build.
      _cardSample = height;
    }
  }

  /// Measured height of the list chrome (error banner + ward filter +
  /// heading row) for a tab — the space the sheet must open before any card
  /// starts. Unlike cards, this is stored directly from the latest sample
  /// (settle-guarded): the chrome is rebuilt every build and its height
  /// legitimately changes between frames (error banner appears/disappears,
  /// ward chip arrives), so a two-sample lock would go stale.
  final Map<int, double> _chromeFootprintByTab = {};

  void _onChromeMeasured(int tabIndex, double height) {
    final settled = _chromeFootprintByTab[tabIndex];
    // Only re-tell the sheet when the value actually moved.
    if (settled != null && (settled - height).abs() <= 0.5) return;
    setState(() => _chromeFootprintByTab[tabIndex] = height);
  }

  /// The snap list the sheet is handed, rebuilt ONLY when the floor value
  /// moves. DraggableScrollableSheet re-snaps when snapSizes changes
  /// identity — fresh literals every build re-snap on every rebuild.
  List<double> _snapCache = const [0.14, 0.28, 0.86];

  /// Direction the incoming list travels from: +1 when moving toward a
  /// higher-index segment, -1 toward a lower one — the page enters from the
  /// side the selection moved.
  double _slideDir = 1;

  /// Cards keyed by every field they render + a generation stamp. An
  /// unchanged payload hands back the SAME instance, and the framework
  /// short-circuits a child updated to an identical widget — so switching
  /// segments (or the ward filter, which does no reload) does not rebuild
  /// cards at all: no image re-resolve, no perch state, no ink. Real changes
  /// land in the key directly — a fresh payload changes status/upvotes/
  /// distance, a reload bumps [_dataStamp] as a catch-all for fields the
  /// key does not spell out (the title).
  final Map<String, Widget> _cardMemo = <String, Widget>{};
  int _dataStamp = 0;

  Widget _memoCard(int tabIndex, Issue issue) {
    final key = 'c$tabIndex|x$_dataStamp|${issue.id}|${issue.status}|'
        '${issue.upvotes}|${_expandedId == issue.id}|'
        '${issue.awaitingDuplicateReview}|${issue.rejectedAt != null}'
        // Distance is rendered on the card against the map centre; carrying
        // it in the key (not a blanket stamp) is what lets a ward-filter
        // switch re-render only the cards whose distance actually moved
        // while every other card keeps its element and its loaded image.
        '|${_distanceKm(issue)?.toStringAsFixed(1) ?? '-'}'
        // The map-selection treatment (gold ring + scale in _selectableCard)
        // is part of the card's look, so it must be in the key too. Without
        // it, the instance memoised while the issue was map-selected is
        // handed back on a later expand — a gold glow "hover" with no pin
        // selected.
        '|${_selected?.id == issue.id ? 'Y' : 'n'}';
    return _cardMemo[key] ??= Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Flagged by the duplicate check and not yet ruled on. It
          // sits above the card because it is a gate: assigning a
          // grievance that is about to be merged wastes the visit.
          if (issue.awaitingDuplicateReview) _duplicateRibbon(issue),
          _selectableCard(
            issue,
            IssueCard(
              issue: issue,
              expanded: _expandedId == issue.id,
              onToggle: () => setState(() =>
                  _expandedId = _expandedId == issue.id ? null : issue.id),
              distanceKm: _distanceKm(issue),
              badge: tabIndex != CoordinatorTab.ward.index
                  ? _ActionStatusBadge(
                      status: issue.status, rejected: issue.rejectedAt != null)
                  : null,
              actions: switch (CoordinatorTab.values[tabIndex]) {
                CoordinatorTab.ward => _wardActions(issue),
                CoordinatorTab.mine => _mineActions(issue),
                CoordinatorTab.escalated => _escalatedActions(issue),
                CoordinatorTab.previous => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The four tabs. The ward chip narrows the Open tab (the ward pool) only:
  /// Assigned, Escalated and Previous are this coordinator's own work in any
  /// ward. Filtering those too — with the chip reset to the home ward on
  /// every open — made their own grievances elsewhere read "0".
  ({List<Issue> ward, List<Issue> mine, List<Issue> escalated, List<Issue> previous})
      get _parts {
    final p = partitionForCoordinator(_allIssues, _me.username);
    return (
      ward: _ward.isEmpty
          ? p.ward
          : p.ward.where((i) => '${i.wardNo}' == _ward).toList(),
      mine: p.mine,
      escalated: p.escalated,
      previous: p.previous,
    );
  }

  final _sheetCtrl = DraggableScrollableController();

  /// The scroll position inside the sheet, captured in its builder. Held so a
  /// segment change can reset the list to its top (see [_selectTab]).
  ScrollController? _listScrollCtrl;

  /// Live sheet extent. A notifier, not setState state: only the map legend
  /// listens, so dragging never rebuilds the map underneath.
  final _sheetExtent = ValueNotifier<double>(0);

  /// Ward stories. The coordinator app both reads AND writes these — the
  /// "Your Story" tile on the rail is the only difference from the citizen
  /// app's version of the same strip.
  List<StoryRing> _storyRings = const [];
  bool _storiesLoading = true;
  String? _storyFetchInFlightFor;

  /// Stories for the ward currently filtered to. 'All' (no single ward) falls
  /// back to the coordinator's home ward, which is the one they post for.
  int? get _storyWard =>
      int.tryParse(_ward.trim()) ?? int.tryParse(_me.homeWard.trim());

  Future<void> _loadStories() async {
    final ward = _storyWard;
    if (ward == null) {
      if (mounted) setState(() => _storiesLoading = false);
      return;
    }
    final key = '$ward';
    if (_storyFetchInFlightFor == key) return;
    _storyFetchInFlightFor = key;
    try {
      final rings = await ref.read(apiClientProvider).fetchStories(ward);
      if (mounted && _storyFetchInFlightFor == key) {
        setState(() {
          // Demo rings stand in ONLY while the ward has none of its own.
          _storyRings = rings.isEmpty && kUseDemoStories
              ? demoStoryRings(ward)
              : rings;
          _storiesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (kUseDemoStories) _storyRings = demoStoryRings(ward);
          _storiesLoading = false;
        });
      }
    }
    _storyFetchInFlightFor = null;
  }

  /// Open the composer, then refetch so the new frame is on the rail at once.
  Future<void> _composeStory() async {
    final posted = await StoryComposer.open(
      context,
      api: ref.read(apiClientProvider),
      ward: _storyWard,
      existingTitles: [for (final r in _storyRings) r.title],
    );
    if (posted && mounted) {
      setState(() => _storiesLoading = true);
      _storyFetchInFlightFor = null;
      await _loadStories();
      if (mounted) _showToast(context.tr('Story posted.'));
    }
  }

  /// Take one of our own stories down, then refetch.
  Future<void> _removeStory(Story story) async {
    try {
      await ref.read(apiClientProvider).deleteStory(story.id);
    } catch (_) {
      if (mounted) _showToast(context.tr('Could not remove that story.'));
    }
    _storyFetchInFlightFor = null;
    await _loadStories();
  }

  /// Bounding box the map camera locks to. A single ward's polygon(s) when one
  /// is selected; the union of every ward in the constituency when "All wards"
  /// is selected — so the map follows the ward filter. Null until boundaries
  /// load.
  LatLngBounds? get _wardBounds {
    final b = _boundaries;
    if (b == null) return null;
    final wanted = _ward.isEmpty ? _acWards.toSet() : {_ward};
    final pts = <LatLng>[];
    for (final f in b.wards) {
      if (!wanted.contains(f.ward)) continue;
      for (final part in f.parts) {
        if (part.isNotEmpty) pts.addAll(part.first); // outer ring only
      }
    }
    if (pts.length < 3) return null;
    return LatLngBounds.fromPoints(pts);
  }

  /// Sheet floor: pinned header + the list chrome (error banner + ward
  /// filter + heading) + exactly 2 collapsed cards, as a fraction of the
  /// parent height. Card and chrome heights are runtime measurements (see
  /// [_onCardMeasured]/[_onChromeMeasured]) — the coordinator chrome is
  /// much taller than the citizen's, so a copied constant hides the second
  /// card entirely.
  ///
  /// It reads the measurements ACROSS ALL TABS, not the active one's. Per-tab
  /// figures gave every segment its own floor, so switching to a tab whose
  /// cards were a few px taller — or to an empty one, which has no cards to
  /// measure and fell back to the constant — resized the sheet mid-change.
  /// That is the bump: the list slides sideways while the whole sheet jumps
  /// under it. One floor for all four segments means the only thing that
  /// moves on a tab change is the content.
  double _sheetFloorFraction(double parentHeight) {
    final card = _commonCardFootprint;
    final chrome = _commonChromeFootprint;
    final px = _kSheetHeaderHeight + chrome + 2 * card;
    return (px / parentHeight).clamp(0.28, 0.5);
  }

  /// The tallest card footprint any tab has reported, so two cards always fit
  /// whichever segment is showing. An empty tab contributes nothing and
  /// inherits the rest.
  double get _commonCardFootprint => _cardFootprintByTab.values.isEmpty
      ? _kCardFootprint
      : _cardFootprintByTab.values.reduce(math.max);

  /// Likewise for the list chrome above the cards.
  double get _commonChromeFootprint => _chromeFootprintByTab.values.isEmpty
      ? 0.0
      : _chromeFootprintByTab.values.reduce(math.max);

  /// The MINIMUM snap: the pinned header's tab track and nothing else. The
  /// sheet drops here the moment the coordinator reaches for the map.
  double _sheetMiniFraction(double parentHeight) =>
      (_kSheetHeaderHeight / parentHeight).clamp(0.10, 0.4);

  /// Held for [_collapseForMap], which runs outside build.
  double _sheetMiniNow = 0.14;

  /// Our own collapse animation is running — see the citizen home for why this
  /// flag has to exist.
  bool _collapsing = false;

  /// Parked low because of a map gesture.
  bool _mapCollapsed = false;

  void _collapseForMap() {
    if (!_sheetCtrl.isAttached) return;
    if (_sheetCtrl.size <= _sheetMiniNow + 0.01) return;
    _mapCollapsed = true;
    _collapsing = true;
    _sheetCtrl
        .animateTo(
          _sheetMiniNow,
          duration: _kSheetSnapDuration,
          curve: Curves.easeInOutCubic,
        )
        .whenComplete(() => _collapsing = false);
  }

  /// Web-Mercator zoom at which [b] just fills [viewport] — the zoom floor
  /// while locked, so the user can't pull back past the whole ward.
  static double _fitZoom(LatLngBounds b, Size viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return 12;
    const worldPx = 256.0;
    double mercY(double latDeg) {
      final s = (math.sin(latDeg * math.pi / 180)).clamp(-0.9999, 0.9999);
      return 0.5 * math.log((1 + s) / (1 - s));
    }

    final yFrac = (mercY(b.north) - mercY(b.south)).abs() / (2 * math.pi);
    final xFrac = (b.east - b.west).abs() / 360.0;
    if (yFrac <= 0 || xFrac <= 0) return 12;
    final zx = math.log(viewport.width / (worldPx * xFrac)) / math.ln2;
    final zy = math.log(viewport.height / (worldPx * yFrac)) / math.ln2;
    // 0.04, not 0.15: the larger backoff was a sixth of a zoom level of
    // slack around the ward on every open, which left it floating in its
    // surroundings rather than being the subject.
    return (math.min(zx, zy) - 0.04).clamp(1.0, 18.0);
  }

  Coordinator get _me =>
      ref.read(coordinatorAuthProvider) ??
      const Coordinator(
        id: '', username: '', name: '?', role: '',
        constituency: '', homeWard: '',
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(corporationProvider); // starts loading the live corporation's table
    _acWards = _wardsFor(_me);
    _ward = _me.homeWard; // start on the coordinator's own ward (their priority)
    _tabAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1, // first paint is already settled — nothing slides on launch
    );
    _loadBoundaries();
    _loadConstituency();
    _loadStories();
    _refreshProfile();
  }

  /// The coordinator's constituency's wards in the live corporation's table,
  /// or just their home ward until that table has arrived.
  List<String> _wardsFor(Coordinator c) =>
      activeAcMap[c.constituency] ??
      (c.homeWard.isNotEmpty ? [c.homeWard] : const <String>[]);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabAnimCtrl.dispose();
    _sheetCtrl.dispose();
    _sheetExtent.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Polling stops while the app is backgrounded, so anything that happened
    // in the meantime is invisible on return. Reloading here is what makes
    // reopening the app show the truth without a force-quit.
    if (state == AppLifecycleState.resumed) {
      _loadConstituency();
      _refreshProfile();
      ref.read(corporationProvider.notifier).refresh();
    }
  }

  /// Pull the latest profile the MLA office holds for this coordinator.
  ///
  /// Mostly this brings the admin-uploaded photo onto the phone. It also
  /// carries a changed home ward or constituency, which re-scopes the ward
  /// chips — the old profile was fixed at sign-in, so those edits never
  /// arrived until the coordinator signed out and back in.
  Future<void> _refreshProfile() async {
    final before = _me;
    await ref.read(coordinatorAuthProvider.notifier).refreshProfile();
    if (!mounted) return;
    final after = _me;
    final moved = after.constituency != before.constituency ||
        after.homeWard != before.homeWard;
    setState(() {
      if (moved) {
        _acWards = _wardsFor(after);
        // '' is "All wards" — keep it. A specific ward that is no longer in
        // this coordinator's constituency falls back to the new home ward.
        if (_ward.isNotEmpty && !_acWards.contains(_ward)) {
          _ward = after.homeWard;
        }
      }
    });
    if (moved) _loadConstituency();
  }

  Future<void> _loadBoundaries() async {
    try {
      final b = await ref.read(apiClientProvider).fetchBoundaries();
      if (!mounted) return;
      setState(() => _boundaries = b);
      _recenter();
    } catch (_) {}
  }

  void _recenter() {
    final feats = _boundaries?.wards ?? const <BoundaryFeature>[];
    // Centre on the selected ward, or the AC's first ward when "All" is chosen.
    final target = _ward.isEmpty
        ? (_acWards.isNotEmpty ? _acWards.first : '')
        : _ward;
    for (final f in feats) {
      if (f.ward == target) {
        setState(() => _center = f.centroid());
        return;
      }
    }
  }

  /// True when both lists describe the same data per position. A reload that
  /// discovered nothing replaces nothing — otherwise every poll cycle would
  /// hand freshly-parsed Issue instances to the cards (the memo invalidates,
  /// ink and image subtrees rebuild) and a visible flash would ride along.
  static bool _sameIssues(List<Issue> a, List<Issue> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.status != y.status ||
          x.upvotes != y.upvotes ||
          x.title != y.title) {
        return false;
      }
    }
    return true;
  }

  /// Load the whole constituency once; the ward filter narrows it client-side,
  /// so switching wards is instant and needs no round trip.
  Future<void> _loadConstituency() async {
    try {
      final list =
          await ref.read(apiClientProvider).fetchCoordinatorConstituencyIssues(
                coordinator: _me.username,
                sort: _sort,
              );
      if (!mounted) return;
      if (_sameIssues(_allIssues, list) && _dataStamp > 0) return;
      setState(() => _allIssues = list);
      _dataStamp++; // stale memoised cards were built from the old payload
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Switch segments with the same page-slide the citizen home uses: the
  /// whole card list translates in from the side the selection moved, over
  /// one controller, and lands at its top. The chrome above the cards (ward
  /// filter, heading, refresh) stays put; only the list is a page.
  void _selectTab(CoordinatorTab tab) {
    if (_tab == tab) return;
    HapticFeedback.selectionClick();
    _slideDir = tab.index > _tab.index ? 1 : -1;
    setState(() => _tab = tab);
    // Restarting from 0 also cancels an in-flight transition, so rapid taps
    // never leave a list stranded part-way across.
    _tabAnimCtrl.forward(from: 0);
    // A scrolled Queued/Assigned feed handing its offset to a shorter one
    // opens part-way down or blank — land at the top like the citizen sheet.
    if (_listScrollCtrl?.hasClients ?? false) _listScrollCtrl!.jumpTo(0);
  }

  /// Switch the ward filter and move the map to match.
  void _selectWard(String ward) {
    if (ward == _ward) return;
    HapticFeedback.selectionClick();
    setState(() {
      _ward = ward;
      _expandedId = null;
      _selected = null;
      _storiesLoading = true;
    });
    _storyFetchInFlightFor = null;
    _loadStories();
    _recenter();
  }

  void _showToast(String t) {
    setState(() => _toast = t);
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted && _toast == t) setState(() => _toast = null);
    });
  }

  double? _distanceKm(Issue issue) {
    final c = _center;
    if (c == null) return null;
    return haversineKm(
        c.latitude, c.longitude, issue.latitude, issue.longitude);
  }

  /// Map pin tap → highlight + bring forward the matching ribbon in the list
  /// (#6); switches to whichever tab currently holds the issue.
  void _onMapSelect(Issue? i) {
    setState(() {
      _selected = i;
      if (i != null) {
        _expandedId = i.id;
        final parts = _parts;
        if (parts.ward.any((x) => x.id == i.id)) {
          _tab = CoordinatorTab.ward;
        } else if (parts.mine.any((x) => x.id == i.id)) {
          _tab = CoordinatorTab.mine;
        } else if (parts.escalated.any((x) => x.id == i.id)) {
          _tab = CoordinatorTab.escalated;
        } else if (parts.previous.any((x) => x.id == i.id)) {
          _tab = CoordinatorTab.previous;
        }
      }
    });
    if (i == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _cardKeys[i.id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 420),
            curve: NkMotion.settle,
            alignment: 0.1);
      }
    });
  }

  Widget _selectableCard(Issue issue, Widget card) {
    final selected = _selected?.id == issue.id;
    return AnimatedScale(
      key: _cardKeys.putIfAbsent(issue.id, () => GlobalKey()),
      scale: selected ? 1.025 : 1,
      duration: const Duration(milliseconds: 260),
      curve: NkMotion.settle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? NkColors.gold300 : Colors.transparent,
              width: 2),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: NkColors.gold300.withValues(alpha: 0.35),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: card,
      ),
    );
  }

  // ── Actions (all backend-persistent now) ────────────────────────────────

  Future<void> _assign(Issue issue) async {
    HapticFeedback.mediumImpact();
    setState(() => _busyId = issue.id);
    try {
      await ref
          .read(apiClientProvider)
          .coordinatorVerify(issue.id, _me.username);
      _showToast('Assigned · moved to My Reports');
      setState(() => _expandedId = null);
      await _loadConstituency();
    } catch (e) {
      setState(() => _error = '$e');
      // Refused (usually taken by a colleague, or moved by the MLA office):
      // reload, so the stale card leaves instead of offering dead buttons.
      _loadConstituency();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _escalate(Issue issue) async {
    final data = await EscalateSheet.open(context, issue);
    if (data == null) return;
    setState(() => _busyId = issue.id);
    try {
      await ref.read(apiClientProvider).coordinatorEscalate(
            issue.id,
            description: '${data['description']}',
            coordinator: _me.username,
            photo: data['photo'] as File?,
            voice: data['voice'] as File?,
          );
      _showToast('Escalated · moved to Escalated tab');
      setState(() => _expandedId = null);
      await _loadConstituency();
    } catch (e) {
      setState(() => _error = '$e');
      // Refused (usually taken by a colleague, or moved by the MLA office):
      // reload, so the stale card leaves instead of offering dead buttons.
      _loadConstituency();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _transfer(Issue issue) async {
    await TransferSheet.open(
      context,
      issue: issue,
      onSubmit: (department, notes, officer, photo, voice) async {
        await ref.read(apiClientProvider).coordinatorTransfer(
              issue.id,
              department,
              notes: notes,
              officer: officer,
              coordinator: _me.username,
              photo: photo,
              voice: voice,
            );
        _showToast('Transferred to $department');
        await _loadConstituency();
      },
    );
    if (!mounted) return;
    // Reload whatever happened in the sheet: a refused transfer means the
    // grievance changed hands, and its card must not stay.
    _loadConstituency();
    setState(() => _expandedId = null);
  }

  Future<void> _close(Issue issue) async {
    final data = await CloseSheet.open(context, issue);
    if (data == null) return;
    setState(() => _busyId = issue.id);
    try {
      await ref.read(apiClientProvider).coordinatorClose(
            issue.id,
            notes: '${data['notes'] ?? ''}',
            coordinator: _me.username,
            // The close sheet will not submit without both — this is the proof
            // of work the admin console shows against the resolution.
            photo: data['photo'] as File?,
            voice: data['voice'] as File?,
          );
      _showToast('Closed · awaiting citizen verification');
      setState(() => _expandedId = null);
      await _loadConstituency();
    } catch (e) {
      setState(() => _error = '$e');
      // Refused (usually taken by a colleague, or moved by the MLA office):
      // reload, so the stale card leaves instead of offering dead buttons.
      _loadConstituency();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _markFalse(Issue issue) async {
    final data = await FalsePetitionSheet.open(context, issue);
    if (data == null) return;
    setState(() => _busyId = issue.id);
    try {
      await ref.read(apiClientProvider).coordinatorMarkFalse(
            issue.id,
            '${data['reason']}',
            details: '${data['details'] ?? ''}',
            coordinator: _me.username,
            photo: data['photo'] as File?,
            voice: data['voice'] as File?,
          );
      _showToast('Flagged as false · moved to Previous Reports');
      setState(() => _expandedId = null);
      await _loadConstituency();
    } catch (e) {
      setState(() => _error = '$e');
      // Refused (usually taken by a colleague, or moved by the MLA office):
      // reload, so the stale card leaves instead of offering dead buttons.
      _loadConstituency();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // The live corporation's table can land after this screen opens (first
    // launch); re-scope the ward chips when it does.
    ref.listen<Corporation?>(corporationProvider, (prev, next) {
      if (next == null) return;
      final wards = _wardsFor(_me);
      if (wards.join(',') != _acWards.join(',')) {
        setState(() => _acWards = wards);
        if (prev?.id != next.id) _loadBoundaries();
      }
    });
    final parts = _parts;
    final current = switch (_tab) {
      CoordinatorTab.ward => parts.ward,
      CoordinatorTab.mine => parts.mine,
      CoordinatorTab.escalated => parts.escalated,
      CoordinatorTab.previous => parts.previous,
    };

    final topInset = MediaQuery.paddingOf(context).top;
    final screenH = MediaQuery.sizeOf(context).height;
    final sheetFloor = _sheetFloorFraction(screenH);
    final sheetMini = _sheetMiniFraction(screenH);
    _sheetMiniNow = sheetMini;
    // The masthead: nature band + story rail. The coordinator always has the
    // composer tile, so the rail never collapses to nothing here.
    final screenW = MediaQuery.sizeOf(context).width;
    final barTop = kCoordAppBarTop(topInset);
    final backdropH = kCoordBackdropHeight(topInset, screenW);
    final railH = storyRailHeight(
      canPost: true,
      hasRings: _storyRings.isNotEmpty,
      loading: _storiesLoading,
    );
    // One picture behind the app bar AND the stories. See the citizen home.
    final mastheadH = backdropH + railH;
    // The expanded snap must leave the masthead uncovered — a pulled-up sheet
    // may never hide the stories.
    final sheetMax = ((screenH - (backdropH + railH + 18)) / screenH)
        .clamp(sheetFloor + 0.06, _kSheetMax);
    // Identity-stable snap list: refreshed only when a measured stop actually
    // moves (first sample landing, tab with a different ribbon, rail arriving).
    if (_snapCache[0] != sheetMini ||
        _snapCache[1] != sheetFloor ||
        _snapCache[2] != sheetMax) {
      _snapCache = [sheetMini, sheetFloor, sheetMax];
    }

    // Lock the map to the selected ward, fitting it into the band that stays
    // visible above the sheet at its floor.
    final lockBounds = _wardBounds;
    final lockPadding = EdgeInsets.only(
      // Clear of the nature band and the story rail under it. Same clearance
      // the citizen map lock uses for its identical chrome stack.
      top: mastheadH + 12,
      bottom: sheetFloor * screenH + 16,
      // Halved, so the fit fills the band with the selected ward rather than
      // its neighbours. Same change as the citizen map.
      left: 14,
      right: 14,
    );
    final lockMinZoom = lockBounds == null
        ? 12.0
        : _fitZoom(
            lockBounds,
            Size(
              MediaQuery.sizeOf(context).width - lockPadding.horizontal,
              screenH - lockPadding.vertical,
            ),
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // DARK glyphs again. They were flipped to light for the coast photo,
      // whose top-left was near-black palm foliage; the sky asset is pale
      // right across the top, so white glyphs would now be the ones that
      // disappear. The scrim that used to carry that contrast went with it.
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ── 1. Full-bleed map, edge to edge and behind everything ──
            Positioned.fill(
              child: MapCard(
                center: _center,
                issues: current,
                selected: _selected,
                onSelect: _onMapSelect,
                boundaries: _boundaries,
                currentWard: int.tryParse(_ward),
                showLocateChip: false,
                borderRadius: 0,
                // The legend is drawn by this screen instead (see below) so
                // its opacity can track the sheet without rebuilding the map.
                showLegend: false,
                showControls: false,
                // Search moved into the app bar as an icon; no inline bar.
                showSearch: false,
                paleTiles: true,
                lockBounds: lockBounds,
                lockPadding: lockPadding,
                lockMinZoom: lockMinZoom,
                // Reaching for the map drops the sheet to its tab track.
                onInteract: _collapseForMap,
              ),
            ),

            // ── 1b. Nature band + the ward's story rail, with the "Your
            // Story" composer tile that only staff get. ──
            Positioned(
              key: const ValueKey('coord-masthead'),
              top: 0,
              left: 0,
              right: 0,
              child: MastheadCard(
                child: SizedBox(
                  height: mastheadH,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: NatureBackdrop(height: mastheadH),
                      ),
                      // The rail rides ON the photograph's washed lower half,
                      // not on a white strip below it.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: railH,
                        child: StoryRail(
                          rings: _storyRings,
                          loading: _storiesLoading,
                          canPost: true,
                          onAdd: _composeStory,
                          onDelete: _removeStory,
                          ownerUsername: _me.username,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── 2. Home app bar capsule — the SAME widget the citizen home
            // floats, in coordinator mode (STAFF tag after the wordmark, bell
            // polling the coordinator id, office-uploaded photo or initials).
            // Floating over the map, inset 8 from the status bar and 14 from
            // the edges — identical geometry to the citizen's.
            Positioned(
              key: const ValueKey('coord-appbar'),
              // Parked at the temple's base so it stands whole above the bar.
              top: barTop,
              left: 14,
              right: 14,
              child: ProfileHeader(
                searchIssues: _allIssues,
                // Over the whole constituency feed, matching the old bar.
                recipientType: 'coordinator',
                recipientId: _me.username,
                profile: (initials: _me.initials, photoUrl: _me.photo),
                badge: 'STAFF',
              ),
            ),

            // ── 3. Constituency · ward chip and the status legend above it,
            // both parked just clear of the sheet's resting edge.
            //
            // They fade out in BOTH directions, not just upward. Their
            // position is pinned to the FLOOR, so once the sheet leaves it
            // they are no longer sitting above anything: pulled up, the sheet
            // slides over them; dropped to the mini snap, they are left
            // stranded in the middle of a map with the sheet far below. One
            // fade keyed on distance from the floor covers both — they are
            // visible exactly when they are in the right place. ──
            ValueListenableBuilder<double>(
              valueListenable: _sheetExtent,
              builder: (context, extent, child) {
                final up = ((extent - sheetFloor) / (sheetMax - sheetFloor))
                    .clamp(0.0, 1.0);
                final down = sheetFloor <= sheetMini
                    ? 0.0
                    : ((sheetFloor - extent) / (sheetFloor - sheetMini))
                        .clamp(0.0, 1.0);
                // Away from the floor in either direction hides them; the
                // steeper of the two wins.
                final opacity = 1.0 - math.max(up, down);
                return Positioned(
                  left: 14,
                  bottom: sheetFloor * screenH + 12,
                  child: IgnorePointer(
                    ignoring: opacity < 0.02,
                    child: Opacity(opacity: opacity, child: child),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MapStatusLegend(),
                  const SizedBox(height: 8),
                  _CoordWardPill(
                    constituency: compactAC(_me.constituency),
                    ward: _ward.isEmpty ? context.tr('All') : _ward,
                  ),
                ],
              ),
            ),

            // ── 4. The draggable content sheet ──
            Positioned(
              key: const ValueKey('coord-sheet'),
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: NotificationListener<DraggableScrollableNotification>(
                onNotification: (n) {
                  _sheetExtent.value = n.extent;
                  // Pulling the sheet back up out of the mini snap ends the
                  // map-collapsed state.
                  if (_mapCollapsed &&
                      !_collapsing &&
                      n.extent > _sheetMiniNow + 0.04) {
                    _mapCollapsed = false;
                  }
                  return false;
                },
                child: DraggableScrollableSheet(
                controller: _sheetCtrl,
                initialChildSize: sheetFloor,
                minChildSize: sheetMini,
                maxChildSize: sheetMax,
                snap: true,
                snapSizes: _snapCache,
                snapAnimationDuration: _kSheetSnapDuration,
                builder: (context, scrollController) {
                  _listScrollCtrl = scrollController;
                  final tabBody = _cardsOfTab(current);
                  return DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(_kSheetCornerRadius)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(_kSheetCornerRadius)),
                    child: CustomScrollView(
                      controller: scrollController,
                      // CLAMPING, not bouncing — and explicitly here, since an
                      // explicit physics overrides the app-wide clamping
                      // behavior. The bouncing pair used to let a short list
                      // rubber-band past its end, dragging the cards up off
                      // the top and stretching open a white void below them —
                      // the same artifact the citizen sheet shipped and had
                      // fixed (see 895ebd0). Clamping stops dead at both ends;
                      // the only thing a drag past the end can do is resize
                      // the sheet.
                      physics: const ClampingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      slivers: [
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _CoordSheetHeaderDelegate(
                            height: _kSheetHeaderHeight,
                            child: _buildSheetHeader(parts),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(14, 0, 14,
                              40 + MediaQuery.paddingOf(context).bottom),
                          // A lazy, per-child sliver. The first child is the
                          // static chrome (error banner + ward filter +
                          // heading); every card after it rides the page-slide
                          // (see _selectTab) and is memoised so a segment
                          // switch hands back identical widgets — Flutter then
                          // skips the card update entirely and nothing inside
                          // them replays.
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                if (i == 0) {
                                  return _MeasureHeight(
                                    onHeight: (h) =>
                                        _onChromeMeasured(_tab.index, h),
                                    child: _buildListChrome(current),
                                  );
                                }
                                return _TabSlide(
                                  animation: _tabAnimCtrl,
                                  dx: _slideDir,
                                  child: tabBody[i - 1],
                                );
                              },
                              childCount: 1 + tabBody.length,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );}
                ),
              ),
            ),

            // Floating notification banner — polls /api/notifications every
            // 15s while this screen is foregrounded.
            Positioned(
              top: 0, left: 0, right: 0,
              child: NotificationPoller(
                recipientType: 'coordinator',
                recipientId: _me.username,
                // Any notification means something moved underneath this list:
                // a new grievance, a citizen signing off a closure, an admin
                // action. Reload on all of them — reloading only for arrivals
                // is what left a closed ticket reading "Pending verification"
                // until the app was force-quit.
                onAnyNotification: _loadConstituency,
              ),
            ),

            if (_toast != null)
              Positioned(
                left: 24, right: 24, bottom: 40,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: NkColors.slate900.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(_toast!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Pinned sheet header: grip + the four coordinator segments.
  Widget _buildSheetHeader(
      ({
        List<Issue> ward,
        List<Issue> mine,
        List<Issue> escalated,
        List<Issue> previous
      }) parts) {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            height: 4,
            width: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFD0D5DD),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFEDEFF3),
                borderRadius: BorderRadius.circular(999),
              ),
              child: LayoutBuilder(builder: (context, box) {
                // A sliding white pill instead of per-segment
                // AnimatedContainers — the old treatment faded the capsule
                // out on the old segment and in on the new, which read as a
                // blink. One capsule now glides between segments (same 260ms
                // settle as the rest of this sheet) while the segment labels
                // swap their colours beneath it.
                final segW = box.maxWidth / 4;
                final activeIdx = _tab.index;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 260),
                      curve: NkMotion.settle,
                      left: activeIdx * segW,
                      top: 0,
                      bottom: 0,
                      width: segW,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final (tab, icon, label, count) in [
                          (
                            CoordinatorTab.ward,
                            Icons.groups_outlined,
                            context.tr('Open'),
                            parts.ward.length
                          ),
                          (
                            CoordinatorTab.mine,
                            Icons.description_outlined,
                            context.tr('Assigned'),
                            parts.mine.length
                          ),
                          (
                            CoordinatorTab.escalated,
                            Icons.keyboard_double_arrow_up,
                            context.tr('Escalated'),
                            parts.escalated.length
                          ),
                          (
                            CoordinatorTab.previous,
                            Icons.assignment_outlined,
                            context.tr('Resolved'),
                            parts.previous.length
                          ),
                        ])
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _selectTab(tab),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                curve: NkMotion.settle,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                decoration: const BoxDecoration(),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(icon,
                                        size: 13,
                                        color: _tab == tab
                                            ? NkColors.slate900
                                            : NkColors.slate500),
                                    const SizedBox(height: 1),
                                    Text(
                                      '$label ($count)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: _tab == tab
                                            ? NkColors.slate900
                                            : NkColors.slate600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Horizontal ward filter for the constituency feed. The coordinator's own
  /// ward is pinned first (their priority); the rest of the AC's wards follow in
  /// number order, then an "All wards" chip. Each carries a count of everything
  /// the coordinator can see in that ward.
  Widget _buildWardFilter() {
    final home = _me.homeWard;
    final others = _acWards.where((w) => w != home).toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    final wards = [if (home.isNotEmpty) home, ...others];
    // The chip narrows the Open tab, so it counts what that tab would show:
    // open, unassigned grievances in the ward (it used to count every status).
    final pool = partitionForCoordinator(_allIssues, _me.username).ward;
    int countFor(String w) => pool.where((i) => '${i.wardNo}' == w).length;
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final w in wards)
            _wardChip(
              label: '${context.tr('Ward')} $w',
              count: countFor(w),
              selected: _ward == w,
              isHome: w == home,
              onTap: () => _selectWard(w),
            ),
          _wardChip(
            label: context.tr('All wards'),
            count: _allIssues.length,
            selected: _ward.isEmpty,
            isHome: false,
            onTap: () => _selectWard(''),
          ),
        ],
      ),
    );
  }

  Widget _wardChip({
    required String label,
    required int count,
    required bool selected,
    required bool isHome,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? NkColors.brand : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? NkColors.brand : NkColors.slate200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isHome)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.push_pin,
                      size: 11,
                      color: selected ? Colors.white : NkColors.brand),
                ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : NkColors.slate700,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : NkColors.slate100,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : NkColors.slate500,
                      )),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Everything above the cards: the error banner, the ward filter, the
  /// per-segment heading + sort + refresh row. Static — the page-slide rides
  /// only the cards (see the list sliver in build), so this chrome never
  /// travels even though its heading text changes per segment.
  Widget _buildListChrome(List<Issue> current) {
    final scope = _ward.isEmpty
        ? shortAC(_me.constituency)
        : '${context.tr('Ward')} $_ward';
    final headings = [
      '${context.tr('Open grievances')} · $scope',
      context.tr('Assigned to me'),
      context.tr('Escalated grievances'),
      context.tr('Resolved & closed'),
    ];
    final idx = _tab.index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: NkColors.rose50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 12, color: NkColors.rose600)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _error = null),
                  child: const Icon(Icons.close,
                      size: 14, color: NkColors.rose600),
                ),
              ],
            ),
          ),
        _buildWardFilter(),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(headings[idx],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: NkColors.slate900,
                  )),
            ),
            _buildSortDropdown(),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                _loadConstituency();
              },
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 12, color: NkColors.brand),
                  SizedBox(width: 4),
                  Text(context.tr('Refresh'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: NkColors.brand,
                      )),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// The sliding body for the active segment — one memoised card per issue,
  /// or the segment's empty state (which slides with the page too, so a
  /// segment without grievances still reads as a page change).
  List<Widget> _cardsOfTab(List<Issue> current) {
    final idx = _tab.index;
    if (current.isEmpty) {
      final empties = [
        _ward.isEmpty
            ? 'No unverified grievances in ${shortAC(_me.constituency)}.'
            : 'No unverified grievances in Ward $_ward.',
        'Verify grievances from the Open tab to see them here.',
        'Escalated grievances land here until resolved.',
        'Closed grievances and false petitions land here.',
      ];
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(
                [
                  Icons.groups_outlined,
                  Icons.description_outlined,
                  Icons.keyboard_double_arrow_up,
                  Icons.assignment_outlined,
                ][idx],
                size: 32,
                color: NkColors.slate300,
              ),
              const SizedBox(height: 8),
              Text(empties[idx],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: NkColors.slate400)),
            ],
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < current.length; i++)
        // The first two collapsed cards are wrapped in a height sampler that
        // sizes the sheet floor so exactly 2 cards show at minimum height
        // (see _onCardMeasured). The cards themselves stay the memoised
        // instances — the wrapper sits around them and never rebuilds them.
        (i < 2)
            ? _MeasureHeight(
                onHeight: (h) => _onCardMeasured(idx, h),
                child: _memoCard(idx, current[i]),
              )
            : _memoCard(idx, current[i]),
    ];
  }

  /// Amber strip over a grievance the duplicate check flagged.
  Widget _duplicateRibbon(Issue issue) {
    final busy = _busyId == issue.id;
    return GestureDetector(
      onTap: busy ? null : () => _reviewDuplicate(issue),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        decoration: BoxDecoration(
          color: NkColors.amber50,
          border: Border.all(color: NkColors.amber200),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            const Icon(Icons.call_merge_rounded,
                size: 15, color: NkColors.amber700),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                context.tr('Possible duplicate'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: NkColors.amber800,
                ),
              ),
            ),
            if (busy)
              const SizedBox(
                height: 13,
                width: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: NkColors.amber700),
              )
            else ...[
              Text(
                context.tr('Review'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: NkColors.amber700,
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 17, color: NkColors.amber700),
            ],
          ],
        ),
      ),
    );
  }

  /// Compare a flagged grievance with the original, then merge or keep it.
  ///
  /// The original is fetched rather than taken from the ward list: detection
  /// ignores ward boundaries, so it is often one this coordinator's own list
  /// does not contain.
  Future<void> _reviewDuplicate(Issue issue) async {
    setState(() => _busyId = issue.id);
    final api = ref.read(apiClientProvider);
    DuplicateInfo info;
    try {
      info = await api.coordinatorDuplicateContext(issue.id,
          coordinator: _me.username);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      _loadConstituency();
      return;
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
    if (!mounted) return;

    final choice =
        await MergeDuplicateSheet.open(context, issue: issue, info: info);
    if (choice == null) return;

    setState(() => _busyId = issue.id);
    try {
      if (choice == 'merge') {
        final parent = info.parent!.issue;
        await api.coordinatorMerge(issue.id, parent.id,
            coordinator: _me.username);
        _showToast('Merged into ${parent.ticketNo ?? 'the original'}');
      } else {
        await api.coordinatorKeepSeparate(issue.id,
            coordinator: _me.username);
        _showToast('Kept as a separate grievance');
      }
      setState(() => _expandedId = null);
      await _loadConstituency();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      _loadConstituency();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Widget _buildSortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: NkColors.slate200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _sort,
          isDense: true,
          icon: const Icon(Icons.expand_more,
              size: 14, color: NkColors.slate500),
          borderRadius: BorderRadius.circular(14),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: NkColors.slate700,
          ),
          items: [
            DropdownMenuItem(value: 'recent', child: Text(context.tr('Recent'))),
            DropdownMenuItem(value: 'priority', child: Text(context.tr('Priority'))),
          ],
          onChanged: (v) {
            if (v == null || v == _sort) return;
            setState(() => _sort = v);
            _loadConstituency();
          },
        ),
      ),
    );
  }

  Widget _wardActions(Issue issue) {
    final busy = _busyId == issue.id;
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: busy ? 'Assigning…' : context.tr('Assign Grievance'),
            icon: Icons.verified_user_outlined,
            bg: NkColors.brand,
            fg: Colors.white,
            onTap: busy ? null : () => _assign(issue),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            label: context.tr('False Petition'),
            icon: Icons.block,
            bg: Colors.white,
            fg: NkColors.rose600,
            border: NkColors.rose200,
            onTap: busy ? null : () => _markFalse(issue),
          ),
        ),
      ],
    );
  }

  Widget _mineActions(Issue issue) {
    // Lifecycle:
    //   FORWARDED (dept transfer done)     → Transfer disabled + labeled Transferred
    //   PENDING_VERIFICATION (Close done)  → hide Transfer + Escalate, replace
    //                                        Close with a disabled "Pending
    //                                        Verification" chip.
    final closed = issue.status == 'PENDING_VERIFICATION';
    final transferred = issue.status == 'FORWARDED';

    if (closed) {
      return Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: NkColors.amber50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NkColors.amber200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_top,
                size: 13, color: NkColors.amber700),
            const SizedBox(width: 6),
            Text(context.tr('Pending Verification'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: NkColors.amber700,
                )),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionButton(
                label: transferred ? context.tr('Transferred') : context.tr('Dept. Transfer'),
                icon:
                    transferred ? Icons.check_circle_outline : Icons.send_outlined,
                bg: transferred ? NkColors.slate200 : NkColors.brand,
                fg: transferred ? NkColors.slate500 : Colors.white,
                onTap: transferred ? null : () => _transfer(issue),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                label: context.tr('Escalate'),
                icon: Icons.keyboard_double_arrow_up,
                bg: NkColors.slate800,
                fg: Colors.white,
                onTap: () => _escalate(issue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _actionButton(
          label: context.tr('Close'),
          icon: Icons.check_circle_outline,
          bg: NkColors.emerald600,
          fg: Colors.white,
          onTap: () => _close(issue),
        ),
      ],
    );
  }

  Widget _escalatedActions(Issue issue) {
    final closed = issue.status == 'PENDING_VERIFICATION';
    if (closed) {
      return Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: NkColors.amber50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NkColors.amber200),
        ),
        child: Text(context.tr('Pending Verification'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: NkColors.amber700,
            )),
      );
    }
    // Escalated tickets can still be closed; transfer stays open in case
    // the higher authority hands it back to a specific department.
    return _actionButton(
      label: context.tr('Close'),
      icon: Icons.check_circle_outline,
      bg: NkColors.emerald600,
      fg: Colors.white,
      onTap: () => _close(issue),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color bg,
    required Color fg,
    Color? border,
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.6 : 1,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: border != null ? Border.all(color: border) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: fg)),
              ],
            ),
          ),
        ),
      );
}

class _ActionStatusBadge extends StatelessWidget {
  const _ActionStatusBadge({required this.status, this.rejected = false});
  final String status;
  final bool rejected;
  @override
  Widget build(BuildContext context) {
    // Citizen-rejected closure takes visual priority — the coordinator needs
    // to act on it fast.
    if (rejected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: NkColors.rose50,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: NkColors.rose600.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 10, color: NkColors.rose600),
            SizedBox(width: 3),
            Text('Rejected — review ASAP',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: NkColors.rose600)),
          ],
        ),
      );
    }
    final (label, bg, fg) = switch (status) {
      'CLOSED' => ('Citizen approved · Closed', NkColors.emerald50, NkColors.emerald700),
      'FALSE' => (context.tr('False Petition'), NkColors.rose50, NkColors.rose700),
      'FORWARDED' => ('Transferred · In Progress', NkColors.sky50, NkColors.sky700),
      'IN_PROGRESS' => ('In Progress', NkColors.sky50, NkColors.sky700),
      'PENDING_VERIFICATION' =>
        ('Awaiting citizen verify', NkColors.amber50, NkColors.amber700),
      'ACTIVE' => ('Assigned', NkColors.brand50, NkColors.brand),
      _ => ('', Colors.transparent, Colors.transparent),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// Fixed-height pinned block at the top of the coordinator sheet.
class _CoordSheetHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CoordSheetHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox(height: height, child: child);

  @override
  bool shouldRebuild(_CoordSheetHeaderDelegate old) =>
      old.height != height || old.child != child;
}

/// Sampled height of a single child, reported once per rendered size.
///
/// Wraps the sheet's first two cards so the floor can be cut at exactly the
/// second card's bottom margin (the wrapper's box includes the card's 8px
/// bottom padding by construction). Reports from a post-frame callback —
/// during build the render box has no size yet — and re-samples whenever the
/// child widget changes (payload key changed, or expand/collapse toggled);
/// the [child] decides in _onCardMeasured when a reading is worth acting on.
class _MeasureHeight extends StatefulWidget {
  const _MeasureHeight({required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<_MeasureHeight> createState() => _MeasureHeightState();
}

class _MeasureHeightState extends State<_MeasureHeight> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(covariant _MeasureHeight old) {
    super.didUpdateWidget(old);
    if (old.child != widget.child || old.onHeight != widget.onHeight) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    }
  }

  void _report() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) widget.onHeight(box.size.height);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Page-slide for a segment change — ported from the citizen home so both
/// screens read as one system. The whole list translates together over one
/// controller (each card takes the SAME value from [_NkTabCurve]); settled
/// builds carry no transform and no opacity layer at all.
const Curve _nkTabCurve = Curves.easeInOutCubic;

class _TabSlide extends StatelessWidget {
  const _TabSlide({
    required this.animation,
    required this.dx,
    required this.child,
  });

  final Animation<double> animation;

  /// +1 arrives from the right, -1 from the left.
  final double dx;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      // Built once, not per frame — only the transform changes.
      child: child,
      builder: (context, built) {
        final t = _nkTabCurve.transform(animation.value.clamp(0.0, 1.0));
        if (t >= 1) return built!; // settled: no transform, no opacity layer
        return FractionalTranslation(
          translation: Offset(dx * (1 - t), 0),
          child: Opacity(opacity: t, child: built),
        );
      },
    );
  }
}

/// Floating "🏛 Egmore | Ward (61) 🔒" chip — a solid white capsule with navy
/// content, parked directly under the status legend. Read-only: both the
/// constituency and the ward are assigned in the admin console, so this only
/// ever displays them.
class _CoordWardPill extends StatelessWidget {
  const _CoordWardPill({
    required this.constituency,
    required this.ward,
  });

  final String constituency;
  final String ward;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance,
              size: 15, color: NkColors.refBlueDeep),
          if (constituency.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              constituency,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: NkColors.refBlueDeep,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Container(width: 1, height: 14, color: NkColors.slate300),
          const SizedBox(width: 8),
          Text(
            context.tr('Ward'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: NkColors.refBlueDeep,
            ),
          ),
          const SizedBox(width: 7),
          Container(
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NkColors.refBlueDeep,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              ward,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
