import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../domain/constituencies.dart';
import '../../domain/models/boundary_data.dart';
import '../../domain/models/issue.dart';
import '../../domain/models/locate_result.dart';
import '../../state/providers.dart';
import '../report/report_sheet.dart';
import '../shared/notification_banner.dart';
import '../upvote/upvote_sheet.dart';
import 'widgets/grievance_card.dart';
import 'widgets/map_card.dart';
import 'widgets/profile_header.dart';

/// Fallback location (Anna Nagar, Chennai) when GPS is denied/unavailable —
/// mirrors DEFAULT_LOCATION in lib/hooks.js so the app stays usable.
const kDefaultLocation = LatLng(13.0827, 80.2081);

/// The two destinations of the bottom nav bar, in display order. "My Supports"
/// is no longer a destination — it became a scope filter inside [_HomeTab.ward].
enum _HomeTab { mine, ward }

/// Scope of the ward feed, chosen from the feed's dropdown.
enum _WardScope { all, supports }

/// Ordering of the ward feed, chosen from the same dropdown.
enum _WardSort { recent, priority }

/// Sheet snap fractions. The FLOOR (min == landing) is computed per-device so
/// it shows the pinned pills+tabs header plus exactly ~2 grievance cards, and
/// the user can never collapse below it — see [_sheetFloorFraction]. There are
/// exactly two resting places: that floor and the expanded snap, which is
/// computed per-device by [_sheetMaxFraction] rather than fixed.

/// What the expanded snap must leave uncovered, measured down from the status
/// bar: the app bar (8 gap + 56 tall), the ward pill (10 gap + 32 tall) and a
/// breathing gap under it. Below this the sheet would swallow both chips.
const double _kAppBarBlockHeight = 8 + 56 + 10 + 32;
const double _kExpandedTopGap = 18;

/// Fixed-duration settle between the two snaps. Without this the sheet lands on
/// a velocity-driven ballistic simulation, so a flick and a slow drag settle at
/// very different speeds; a set duration makes the travel read the same either
/// way, which is what "smooth" means here.
const Duration _kSheetSnapDuration = Duration(milliseconds: 320);

/// Rough on-screen footprint of one grievance card (thumbnail row + selection
/// border + inter-card gap), used to size the sheet floor to ~2 cards.
const double _kCardFootprint = 96;

/// Easing for a destination change. Symmetric on purpose: the outgoing page
/// has to accelerate away exactly as fast as the incoming one decelerates in.
/// A decelerate-only curve (our usual NkMotion.settle) makes the exit crawl
/// behind the entrance and the two read as separate, unrelated moves.
const Curve _kTabCurve = Curves.easeInOutCubic;

/// Pinned sheet header. There is no title row any more: grip + status pills is
/// the base, and the ward feed can reveal one row of filter pills under it.
/// These are the two SETTLED extents — the header interpolates between them
/// rather than snapping, so each value is held a px above the measured content:
/// slack is invisible white space, a short value would clip.
/// base: grip 8+4+10 + pills 29 + trailing 12 = 63.
/// ward (revealed): base + 8 + filter pills 26 + 4 = 101.
/// The BASE value must land inside the 8px gap that opens the ward block, not
/// inside the pills themselves, or a collapsed header shows a sliver of them.
const double _kSheetHeaderBase = 64;
const double _kSheetHeaderWard = 102;

/// A swipe across the sheet changes destination if EITHER the flick is quick
/// enough or the finger travelled far enough — so a fast flick and a slow,
/// deliberate drag both work, while an accidental nudge during a vertical
/// scroll does nothing.
const double _kSwipeMinVelocity = 250; // logical px per second
const double _kSwipeMinDistance = 56; // logical px of net travel

/// Width reserved for the ward feed's funnel button — and mirrored on the left
/// of the pill row. Reserving it in BOTH destinations is the point: the pills
/// then occupy the same pixels either side of a tab change, so the pinned
/// header (which does not slide) has nothing to twitch.
const double _kFunnelSlot = 34;

/// Floating bottom nav bar: a flat capsule with everything — including the
/// centre "+" — living INSIDE it, so this is the whole component's height.
const double _kNavBarHeight = 52;

/// Small consistent inset between the capsule and the home-indicator area.
const double _kNavBarBottomGap = 8;

/// The one corner radius in the composition — it belongs to the white sheet.
const double _kSheetCornerRadius = 22;

/// Backend statuses grouped behind each filter pill.
const Map<String, Set<String>> _kStatusBuckets = {
  'open': {'SUBMITTED', 'ACTIVE'},
  'progress': {'FORWARDED', 'IN_PROGRESS'},
  'resolved': {'CLOSED'},
};

/// The filter pills in display order — (bucket key, label, foreground, fill).
/// They share the row width equally.
const List<(String, String, Color, Color)> _kFilterPills = [
  ('open', 'Pending', Color(0xFFB4791F), Color(0xFFFBF0DA)), // sand / amber-brown
  // Blue is the exact #004AAD sampled from the logo SVG, on its own pale tint.
  ('progress', 'In-progress', NkColors.refBlue, Color(0xFFE2EAF7)),
  ('resolved', 'Resolved', Color(0xFF1F8A5B), Color(0xFFDFF3E7)), // mint
];

/// Home — the citizen map screen: a full-bleed map with the app bar floating
/// over it behind a fading gradient, and every list surface living in a
/// draggable bottom sheet with status filter pills and three segments.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Location
  LatLng? _geoCoords;
  LatLng? _override; // demo: jump to an Egmore ward
  String _geoStatus = 'loading'; // loading | ready | fallback
  double? _accuracy;
  String _areaName = '';

  // Data
  BoundaryData? _boundaries;
  LocateResult? _locate;
  bool _locating = false;
  List<Issue> _wardIssues = [];
  List<Issue> _history = [];

  bool _histLoading = true;
  Issue? _selected;
  final Map<String, GlobalKey> _cardKeys = {};
  String? _error;
  String? _busyId;

  // UI state
  _HomeTab _tab = _HomeTab.mine;

  /// Ward-feed scope + ordering, driven by the feed's dropdown.
  _WardScope _wardScope = _WardScope.all;
  _WardSort _wardSort = _WardSort.recent;

  /// Grievances this account has upvoted — the "My Supports" scope. Loaded
  /// lazily the first time that scope is chosen.
  List<Issue> _supported = [];
  bool _supportedLoading = false;

  /// Active status filter pill (null = show everything).
  String? _statusFilter;

  final _sheetCtrl = DraggableScrollableController();

  /// The "no reports yet → land on My Ward" fallback only fires once.
  bool _autoTabApplied = false;

  LatLng? get _coords => _override ?? _geoCoords;

  int? get _currentWard =>
      (_locate?.inside ?? false) ? _locate?.wardNumber : null;

  /// Bounding box of the detected ward's polygon(s), or null when no ward is
  /// resolved yet (outside GCC, or before /api/locate returns). Drives the
  /// map's camera lock — the user can pan/zoom only within this.
  LatLngBounds? get _wardBounds {
    final w = _currentWard;
    final b = _boundaries;
    if (w == null || b == null) return null;
    final target = '$w';
    final pts = <LatLng>[];
    for (final f in b.wards) {
      if (f.ward != target) continue;
      for (final part in f.parts) {
        if (part.isNotEmpty) pts.addAll(part.first); // outer ring only
      }
    }
    if (pts.length < 3) return null;
    return LatLngBounds.fromPoints(pts);
  }

  /// Sheet floor fraction: the pinned header + ~2 grievance cards clear of the
  /// floating nav bar, as a fraction of the sheet's parent height. This is BOTH
  /// the landing size and the minimum — the sheet can be pulled up but never
  /// collapsed below it.
  double _sheetFloorFraction(double parentHeight, double bottomObstruction) {
    // Sized off the BASE header, so the floor clears exactly two cards in BOTH
    // destinations. It deliberately does NOT account for the ward's revealed
    // filter row: that costs _kSheetHeaderLift more, and the sheet is lifted by
    // [_syncSheetLift] to pay for it rather than the floor being raised — which
    // would either add a third snap stop or clamp the sheet up with a pop.
    final px =
        _kSheetHeaderBase + 8 + 2 * _kCardFootprint + bottomObstruction;
    return (px / parentHeight).clamp(0.28, 0.62);
  }

  /// Expanded snap: the tallest the sheet may get while still leaving the app
  /// bar AND the constituency·ward pill clear, with a gap under the pill.
  /// Per-device, since the status-bar inset varies.
  static double _sheetMaxFraction(double parentHeight, double topInset) {
    final reserved = topInset + _kAppBarBlockHeight + _kExpandedTopGap;
    return ((parentHeight - reserved) / parentHeight).clamp(0.5, 0.9);
  }

  /// Extra sheet height the revealed ward filter row needs, as a fraction of
  /// [parentHeight] — exactly the header growth, so the two cards below it stay
  /// where they were and only the sheet's top edge moves.
  double _sheetLiftFraction(double parentHeight) =>
      (_kSheetHeaderWard - _kSheetHeaderBase) / parentHeight;

  /// The two snap stops, cached so the list keeps its IDENTITY across rebuilds.
  /// DraggableScrollableSheet compares snapSizes by identity and schedules a
  /// post-frame re-snap whenever it differs — a fresh literal every build would
  /// re-snap the sheet on every unrelated setState and cancel the lift below.
  List<double>? _snapCache;
  List<double> _snapSizes(double floor, double max) {
    final cached = _snapCache;
    if (cached != null && cached.first == floor && cached.last == max) {
      return cached;
    }
    return _snapCache = [floor, max];
  }

  /// Hold the resting sheet at exactly two clear cards. The ward's revealed
  /// filters need [_sheetLiftFraction] more height; everything else sits on the
  /// floor. Only ever nudges a sheet that is already resting low — one the user
  /// has pulled up to the max snap is left exactly where they put it.
  void _syncSheetLift() {
    if (!_sheetCtrl.isAttached) return;
    final parentH = MediaQuery.sizeOf(context).height;
    final navCover = _kNavBarHeight +
        _kNavBarBottomGap * 2 +
        MediaQuery.paddingOf(context).bottom;
    final floor = _sheetFloorFraction(parentH, navCover);
    final lift = _sheetLiftFraction(parentH);
    final target =
        floor + (_sheetHeaderHeight > _kSheetHeaderBase ? lift : 0);
    // Above the low band means the user dragged it there. Not ours to move.
    if (_sheetCtrl.size > floor + lift + 0.02) return;
    if ((_sheetCtrl.size - target).abs() < 0.001) return;
    _sheetCtrl.animateTo(
      target,
      duration: _kSheetSnapDuration,
      curve: _kTabCurve,
    );
  }

  /// Whether the ward feed's scope + sort pills are revealed. Collapsed by
  /// default, which is what makes the ward header the SAME height as My
  /// Reports' — the destination change then has no vertical step to make.
  bool _wardFiltersOpen = false;

  /// The pinned header's settled extent for the active destination.
  double get _sheetHeaderHeight =>
      (_tab == _HomeTab.ward && _wardFiltersOpen)
          ? _kSheetHeaderWard
          : _kSheetHeaderBase;

  /// The extent the header is animating away from, held for the length of a
  /// destination change so [_liveHeaderHeight] can travel between the two.
  double _prevHeaderHeight = _kSheetHeaderBase;

  /// The header's extent *right now*, on the same clock and curve as the cards.
  double get _liveHeaderHeight {
    final t = _kTabCurve.transform(_tabAnimCtrl.value);
    return _prevHeaderHeight + (_sheetHeaderHeight - _prevHeaderHeight) * t;
  }

  /// Web-Mercator zoom at which [b] just fills [viewport] — used as the map's
  /// zoom floor while locked, so the user can't pull back past the whole ward.
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
    // A hair below the exact fit so the opening (whole-ward) view is valid.
    return (math.min(zx, zy) - 0.15).clamp(1.0, 18.0);
  }

  /// Drives the destination change: the outgoing cards slide out while the
  /// incoming ones slide in, and the pinned header's extent travels between its
  /// two heights on the same clock so the two never fight each other.
  late final AnimationController _tabAnimCtrl;

  /// +1 when moving toward the right-hand destination, -1 toward the left, so
  /// the cards travel the same way the nav bar selection does.
  double _slideDir = 1;

  /// The sheet's own scroll controller, handed to us by DraggableScrollableSheet
  /// in its builder. Kept so a destination change can reset the list to its top.
  ScrollController? _sheetScrollCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1, // first paint is already settled — nothing slides on launch
    );
    _locateDevice();
    _loadBoundaries();
    _loadHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabAnimCtrl.dispose();
    _sheetCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // See the coordinator screen: polling pauses in the background, so a
    // status that changed while away would otherwise stay stale on return.
    if (state != AppLifecycleState.resumed) return;
    _loadHistory();
    final w = _currentWard;
    if (w != null) _loadWard(w);
  }


  // ── Location (port of useGeolocation) ──────────────────────────────────

  Future<void> _locateDevice() async {
    setState(() => _geoStatus = 'loading');
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _useFallbackLocation();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final c = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _geoCoords = c;
        _accuracy = pos.accuracy;
        _geoStatus = 'ready';
      });
      _afterLocationChanged();
      final name = await ref
          .read(apiClientProvider)
          .reverseGeocode(c.latitude, c.longitude);
      if (mounted) setState(() => _areaName = name);
    } catch (_) {
      _useFallbackLocation();
    }
  }

  void _useFallbackLocation() {
    setState(() {
      _geoCoords = kDefaultLocation;
      _accuracy = null;
      _areaName = '';
      _geoStatus = 'fallback';
    });
    _afterLocationChanged();
  }

  void _afterLocationChanged() {
    _resolveWard();
  }

  // ── Data loads (ports of the web loaders) ──────────────────────────────

  Future<void> _loadBoundaries() async {
    try {
      final b = await ref.read(apiClientProvider).fetchBoundaries();
      if (mounted) setState(() => _boundaries = b);
    } catch (_) {
      // Map still renders tiles; boundaries retry on refresh.
    }
  }

  Future<void> _resolveWard() async {
    final c = _coords;
    if (c == null) return;
    setState(() => _locating = true);
    try {
      final r =
          await ref.read(apiClientProvider).locate(c.latitude, c.longitude);
      if (!mounted) return;
      setState(() {
        _locate = r;
        _locating = false;
      });
      final w = r.inside ? r.wardNumber : null;
      if (w != null) _loadWard(w);
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _loadWard(int ward) async {
    try {
      final list = await ref.read(apiClientProvider).fetchWardIssues(ward);
      if (mounted) setState(() => _wardIssues = list);
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    setState(() => _histLoading = true);
    try {
      final list = await ref
          .read(apiClientProvider)
          .fetchHistory(ref.read(userIdProvider));
      if (mounted) {
        setState(() {
          _history = list;
          _histLoading = false;
          // Landing on an empty My Reports is a dead end — switch to My Ward
          // silently the first time we learn the account has no reports.
          if (!_autoTabApplied) {
            _autoTabApplied = true;
            if (_tab == _HomeTab.mine && list.isEmpty) _tab = _HomeTab.ward;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _histLoading = false;
        });
      }
    }
  }

  /// Grievances this account has upvoted. Loaded on demand — the ward feed only
  /// needs it once the user actually picks the "My Supports" scope.
  Future<void> _loadSupported() async {
    if (_supportedLoading) return;
    setState(() => _supportedLoading = true);
    try {
      final list = await ref
          .read(apiClientProvider)
          .fetchSupported(ref.read(userIdProvider));
      if (mounted) setState(() => _supported = list);
      // Same fetch backs every Support button's disabled state — keep the
      // app-wide set in step rather than issuing a second identical request.
      ref
          .read(supportedIssuesProvider.notifier)
          .setAll([for (final i in list) i.id]);
    } catch (_) {/* empty state covers it */} finally {
      if (mounted) setState(() => _supportedLoading = false);
    }
  }

  // ── Filtering ──────────────────────────────────────────────────────────

  /// The unfiltered list backing the active destination. In the ward feed the
  /// dropdown's scope picks the source and its sort orders the result.
  List<Issue> get _tabIssues => switch (_tab) {
        _HomeTab.mine => _history,
        _HomeTab.ward => _sortWard(
            _wardScope == _WardScope.supports ? _supported : _wardIssues,
          ),
      };

  /// Ward-feed ordering. 'priority' is most-supported first (matching the
  /// coordinator's sort); 'recent' is newest first.
  List<Issue> _sortWard(List<Issue> list) {
    final out = [...list];
    switch (_wardSort) {
      case _WardSort.priority:
        out.sort((a, b) {
          final byVotes = b.upvotes.compareTo(a.upvotes);
          if (byVotes != 0) return byVotes;
          return _newestFirst(a, b);
        });
      case _WardSort.recent:
        out.sort(_newestFirst);
    }
    return out;
  }

  static int _newestFirst(Issue a, Issue b) {
    final ad = a.createdAt, bd = b.createdAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  }

  List<Issue> _applyStatusFilter(List<Issue> list) {
    final bucket = _kStatusBuckets[_statusFilter];
    if (bucket == null) return list;
    return list.where((i) => bucket.contains(i.status)).toList();
  }

  int _bucketCount(List<Issue> list, String key) {
    final bucket = _kStatusBuckets[key]!;
    return list.where((i) => bucket.contains(i.status)).length;
  }

  void _toggleStatusFilter(String key) {
    HapticFeedback.selectionClick();
    setState(() => _statusFilter = _statusFilter == key ? null : key);
  }

  /// Reveal/hide the ward feed's scope + sort row. Rides the SAME controller as
  /// a destination change, so the header grows on the identical curve — but the
  /// body's key is untouched, so the cards do not slide for this.
  void _toggleWardFilters() {
    HapticFeedback.selectionClick();
    _prevHeaderHeight = _sheetHeaderHeight;
    setState(() => _wardFiltersOpen = !_wardFiltersOpen);
    _tabAnimCtrl.forward(from: 0);
    // Same duration and curve as the header growth, so the sheet's top edge and
    // the filter row arrive together and the cards below never move.
    _syncSheetLift();
  }

  /// Net horizontal travel of the swipe in progress, accumulated because
  /// DragEndDetails reports velocity but not distance — and a slow, deliberate
  /// drag carries almost no velocity yet clearly means to change destination.
  double _swipeDx = 0;

  /// Horizontal flick across the sheet: same destination change as tapping the
  /// nav bar, routed through [_selectTab] so the slide, the haptic, the scroll
  /// reset and the sheet lift are all identical either way.
  void _onSheetSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final flicked = velocity.abs() >= _kSwipeMinVelocity;
    final dragged = _swipeDx.abs() >= _kSwipeMinDistance;
    if (!flicked && !dragged) return; // an idle nudge, not an intent
    // Trust velocity when there is any; otherwise fall back to net travel. A
    // leftward swipe advances to the right-hand destination, like a page turn.
    final direction = flicked ? velocity : _swipeDx;
    _selectTab(direction < 0 ? _HomeTab.ward : _HomeTab.mine);
  }

  void _selectTab(_HomeTab tab) {
    if (_tab == tab) return;
    HapticFeedback.selectionClick();
    // Which way the cards travel — mine sits left of ward in the nav bar.
    _slideDir = tab.index > _tab.index ? 1 : -1;
    // Where the pinned header is travelling FROM. Read before the tab flips,
    // because _sheetHeaderHeight is derived from _tab. Without this the header
    // snapped 64→100 in one frame and shoved the outgoing cards down 36px
    // mid-slide, which is what stopped this reading as a page transition.
    _prevHeaderHeight = _sheetHeaderHeight;
    setState(() => _tab = tab);
    // Restarting from 0 also cancels an in-flight transition, so rapid taps
    // never leave a list stranded part-way across.
    _tabAnimCtrl.forward(from: 0);
    // Land the new list at its top: without this a scrolled ward feed hands
    // its offset to a shorter reports list and opens part-way down, or blank.
    if (_sheetScrollCtrl?.hasClients ?? false) _sheetScrollCtrl!.jumpTo(0);
    // Leaving the ward with its filters still open gives that height back, so
    // My Reports lands on the same clean two cards; returning takes it again.
    _syncSheetLift();
  }

  void _setWardScope(_WardScope scope) {
    if (_wardScope == scope) return;
    HapticFeedback.selectionClick();
    setState(() => _wardScope = scope);
    if (scope == _WardScope.supports && _supported.isEmpty) _loadSupported();
  }

  void _setWardSort(_WardSort sort) {
    if (_wardSort == sort) return;
    HapticFeedback.selectionClick();
    setState(() => _wardSort = sort);
  }

  // ── Actions ────────────────────────────────────────────────────────────

  /// Demo shortcut: our GPS may be outside GCC, so jump the detected location
  /// to Egmore Ward 108 so ward-level data can be visualised. Once toggled on
  /// the override propagates to every consumer of [_coords] — including the
  /// report sheet's "Current Location" — until the user pulls to refresh.
  void _jumpToEgmore() {
    final feats = _boundaries?.wards ?? const <BoundaryFeature>[];
    BoundaryFeature? f;
    // Prefer Ward 108 (the canonical demo target); fall back to any Egmore
    // ward if 108's boundary isn't loaded yet.
    for (final ft in feats) {
      if (ft.ward == '108') { f = ft; break; }
    }
    if (f == null) {
      for (final ft in feats) {
        if (ft.ward != null && kEgmoreWards.contains(ft.ward)) { f = ft; break; }
      }
    }
    if (f == null) return;
    setState(() {
      _override = f!.centroid();
      // Reset the reverse-geocoded label so the report sheet doesn't show a
      // stale real-GPS neighbourhood; _resolveWard will replace it with the
      // ward-derived zone once /api/locate returns.
      _areaName = 'Egmore · Ward 108';
    });
    _afterLocationChanged();
  }

  Future<void> _upvote(Issue issue) {
    return UpvoteSheet.open(
      context,
      issue: issue,
      onConfirm: () async {
        final updated = await ref.read(apiClientProvider).upvoteIssue(
              issue.id,
              ref.read(userIdProvider),
              name: ref.read(prefsProvider).citizenName,
            );
        if (!mounted) return;
        setState(() {
          _wardIssues = [
            for (final i in _wardIssues) i.id == updated.id ? updated : i
          ];
          if (_selected?.id == updated.id) _selected = updated;
        });
        // The grievance just joined "My Supports" — refresh that scope and the
        // counters behind it so the dropdown badge is not stale.
        _loadSupported();
          },
    );
  }

  Future<void> _verify(Issue issue, String response) async {
    setState(() => _busyId = issue.id);
    try {
      await ref.read(apiClientProvider).verifyIssue(
            issue.id,
            ref.read(userIdProvider),
            response,
          );
      await _loadHistory();
      final w = _currentWard;
      if (w != null) await _loadWard(w);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _openReport() {
    ReportSheet.open(
      context,
      coords: _coords,
      areaName: _areaName,
      geoStatus: _override != null ? 'ready' : _geoStatus,
      accuracy: _accuracy,
      // No detected ward => the point is outside GCC and the backend will
      // refuse the report; the sheet says so instead of letting them record.
      insideGcc: _currentWard != null,
      onRefreshLocation: () {
        // Refresh clears any Egmore-jump override so the sheet's location
        // returns to real-device GPS detection.
        setState(() => _override = null);
        _locateDevice();
      },
      onSubmitted: () {
        _loadHistory();
        final w = _currentWard;
        if (w != null) _loadWard(w);
      },
      onUpvoteExisting: (existing) async {
        await ref.read(apiClientProvider).upvoteIssue(
              existing.id,
              ref.read(userIdProvider),
              name: ref.read(prefsProvider).citizenName,
            );
        final w = _currentWard;
        if (w != null) await _loadWard(w);
      },
    );
  }

  /// A tapped map pin highlights + brings forward the matching grievance
  /// ribbon in the sheet (#6), and switches to the ward segment if the issue is
  /// a ward grievance. Tapping the card itself opens the detail dialog.
  ///
  /// The sheet is deliberately left where it is: with only a floor and a
  /// near-full snap, the only lift available would bury the map you just tapped.
  /// The floor already shows ~2 cards, and ensureVisible scrolls the sheet's own
  /// list to the selected one.
  void _onMapSelect(Issue? i) {
    setState(() {
      _selected = i;
      if (i != null && _wardIssues.any((w) => w.id == i.id)) {
        _tab = _HomeTab.ward;
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

  /// Wraps a card with the selection highlight (elevated + scaled + gold ring)
  /// and a stable key so [_onMapSelect] can scroll to it.
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
          border: selected
              ? Border.all(color: NkColors.gold300, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
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

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;

    // The sheet now runs to the bottom of the screen — the nav bar floats over
    // it — so its fractions are relative to the full height, and its floor has
    // to clear whatever the nav bar covers.
    final sheetParentH = screenH;
    // The solid nav bar occupies this whole strip at the bottom of the screen.
    final navCover = _kNavBarHeight + _kNavBarBottomGap * 2 + bottomInset;
    final sheetFloor = _sheetFloorFraction(sheetParentH, navCover);
    final sheetMax = _sheetMaxFraction(sheetParentH, topInset);

    // Everything the sheet covers at its floor, used to bias the ward fit into
    // the band that stays visible above it.
    final lockBounds = _wardBounds;
    final sheetCoverPx = sheetFloor * sheetParentH;
    final lockPadding = EdgeInsets.only(
      top: topInset + 96,
      bottom: sheetCoverPx + 16,
      left: 28,
      right: 28,
    );
    // Zoom-out floor = the ward filling the band visible above the sheet.
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
      // Dark glyphs — the pale basemap now runs right up under the status bar.
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        // The map is the background — never let the keyboard or the sheet
        // resize it out from under the stack.
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ── 1. Full-bleed map, edge to edge and behind everything ──
            Positioned.fill(
              child: MapCard(
                center: _coords,
                // Pins follow the active segment, same source the pills count
                // and the list renders. Feeding the ward feed here regardless
                // of tab made the map contradict them — 0 in every pill while
                // ward pins were still plotted.
                issues: _applyStatusFilter(_tabIssues),
                selected: _selected,
                onSelect: _onMapSelect,
                boundaries: _boundaries,
                currentWard: _currentWard,
                locate: _locate,
                locating: _locating,
                onUpvote: _upvote,
                borderRadius: 0,
                showLegend: false,
                showLocateChip: false,
                // Reference look: pale basemap, no inline search bar (search
                // lives in the app bar), no zoom/locate chrome.
                showSearch: false,
                showControls: false,
                paleTiles: true,
                // Three-colour pins matching the filter pills; FALSE petitions
                // are not plotted at all in the citizen app.
                citizenPins: true,
                // Once a ward is detected the map is locked to it: opens fitted
                // to the ward, pan/zoom stay inside, no roaming outside.
                lockBounds: lockBounds,
                lockPadding: lockPadding,
                lockMinZoom: lockMinZoom,
              ),
            ),

            // ── 2. Frosted app-bar capsule floating over the map ──
            Positioned(
              key: const ValueKey('home-appbar'),
              top: topInset + 8,
              left: 14,
              right: 14,
              child: ProfileHeader(
                searchIssues: [..._wardIssues, ..._history],
                onUpvote: _upvote,
              ),
            ),

            // ── 3. Constituency · ward chip under the app bar, left aligned
            // to the same 14pt inset so its left edge lines up with the
            // wordmark above it rather than floating on its own centre. ──
            if (_currentWard != null)
              Positioned(
                key: const ValueKey('home-wardpill'),
                top: topInset + 8 + 56 + 10,
                left: 14,
                child: _WardPill(
                  constituency: (_locate?.constituencies.isEmpty ?? true)
                      ? ''
                      : shortAC(_locate!.constituencies.first),
                  ward: '$_currentWard',
                ),
              ),

            // ── 3b. Sneaky demo button: jump the detected location to Egmore
            // Ward 108 so ward-level data + the camera lock can be tested when
            // real GPS is outside GCC limits. ──
            Positioned(
              key: const ValueKey('home-demojump'),
              top: topInset + 8 + 56 + 10,
              right: 14,
              child: _DemoJumpButton(
                active: _override != null,
                onTap: _jumpToEgmore,
              ),
            ),

            // ── 4. The draggable content sheet. It now runs to the bottom of
            // the screen; the floating nav bar sits over it, and the list keeps
            // enough bottom padding that no card hides behind the bar. ──
            Positioned(
              key: const ValueKey('home-sheet'),
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: DraggableScrollableSheet(
                controller: _sheetCtrl,
                // Landing == floor == minimum: opens showing the header + ~2
                // grievance cards and can never be collapsed below that.
                initialChildSize: sheetFloor,
                minChildSize: sheetFloor,
                maxChildSize: sheetMax,
                snap: true,
                // Exactly two stops, and the SAME list instance every build —
                // see [_snapSizes]. The ward's filter lift rides on top of this
                // as a resting offset; it does not add a stop.
                snapSizes: _snapSizes(sheetFloor, sheetMax),
                snapAnimationDuration: _kSheetSnapDuration,
                builder: (context, scrollController) {
                  _sheetScrollCtrl = scrollController;
                  return GestureDetector(
                    // HORIZONTAL only, and only over the sheet. The sheet's own
                    // vertical drag and the list's scroll keep winning the
                    // gesture arena for vertical motion, so this never competes
                    // with them; taps on cards and pills are untouched because
                    // a tap does not travel far enough to claim the arena. The
                    // map is deliberately excluded — it owns its own panning.
                    onHorizontalDragStart: (_) => _swipeDx = 0,
                    onHorizontalDragUpdate: (d) => _swipeDx += d.delta.dx,
                    onHorizontalDragEnd: _onSheetSwipe,
                    child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    // The sheet owns the only rounded corners in the
                    // composition; the map runs full-bleed behind it.
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(_kSheetCornerRadius),
                    ),
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
                      top: Radius.circular(_kSheetCornerRadius),
                    ),
                    child: CustomScrollView(
                      controller: scrollController,
                      // iOS-style rubber-band overscroll — the list now settles
                      // instead of stopping dead at the ends.
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      slivers: [
                        // AnimatedBuilder is a plain widget, but its build
                        // returns a sliver, so the element tree still yields a
                        // RenderSliver here — that is what lets the extent
                        // animate without rebuilding the whole scroll view.
                        AnimatedBuilder(
                          animation: _tabAnimCtrl,
                          // Built once per destination change, NOT per frame:
                          // the header's chips are the expensive part and
                          // re-running them 60× would cost the frames we are
                          // trying to save.
                          child: _buildSheetHeader(),
                          builder: (context, child) => SliverPersistentHeader(
                            pinned: true,
                            delegate: _SheetHeaderDelegate(
                              height: _liveHeaderHeight,
                              child: child!,
                            ),
                          ),
                        ),
                        SliverPadding(
                          // Bottom clearance so the last card clears the
                          // floating nav bar rather than hiding under it.
                          padding:
                              EdgeInsets.fromLTRB(14, 0, 14, navCover + 16),
                          // Page-style slide: the outgoing list travels a
                          // FULL width out while the incoming one comes a full
                          // width in, so at any instant you see one list, not
                          // two ghosts overlapping. Both trees are alive during
                          // the transition, which is why this is a boxed child
                          // rather than a lazy SliverList.
                          sliver: SliverToBoxAdapter(
                            child: AnimatedSwitcher(
                              duration: _tabAnimCtrl.duration!,
                              // Same curve the header extent runs on, so the
                              // vertical and horizontal motion stay locked.
                              switchInCurve: _kTabCurve,
                              switchOutCurve: _kTabCurve,
                              // Anchor both lists to the top; the default
                              // centres them, so a short list would bob
                              // vertically against a long one mid-slide.
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.topCenter,
                                children: [
                                  ...previous,
                                  if (current != null) current,
                                ],
                              ),
                              transitionBuilder: (child, animation) {
                                // Runs for BOTH children. The one whose key
                                // matches the live tab is arriving; the other
                                // is leaving and must exit the opposite way,
                                // or they slide home together.
                                final key = child.key as ValueKey<_HomeTab>?;
                                final incoming = key?.value == _tab;
                                final dx = incoming ? _slideDir : -_slideDir;
                                // No fade — a page slide translates, it does
                                // not dissolve. Fading during the travel is
                                // what made this read as a wash before.
                                return SlideTransition(
                                  position: Tween<Offset>(
                                    begin: Offset(dx, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  // Without this the entire card list — photos
                                  // and all — re-rasterises on every frame of
                                  // the travel, because a translate alone is
                                  // not a repaint boundary. Cached as a layer
                                  // it is composited, which is the difference
                                  // between a stutter and a glide.
                                  child: RepaintBoundary(child: child),
                                );
                              },
                              child: Column(
                                key: ValueKey<_HomeTab>(_tab),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _buildSheetBody(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                );
                },
              ),
            ),

            // ── 5. Solid nav plate: a white bar attached to the bottom edge
            // that the nav pill sits on. It replaces the old fade — content
            // scrolling under the pill is now cleanly cut off rather than
            // dissolving through it — and its top edge carries a soft shadow
            // that separates the bar from the grievance list above.
            //
            // Height is the pill plus one [_kNavBarBottomGap] above and below
            // (the safe-area inset sits under the lower gap), so the pill reads
            // evenly inset from the plate's boundaries. The pill's own position
            // is unchanged. ──
            Positioned(
              key: const ValueKey('home-navplate'),
              left: 0,
              right: 0,
              bottom: 0,
              height: navCover,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                        spreadRadius: -1,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── 6. Floating bottom nav bar — My Reports | + | In my Ward.
            // The "+" is the grievance CTA that used to be the footer plate. ──
            Positioned(
              key: const ValueKey('home-navbar'),
              left: 0,
              right: 0,
              bottom: _kNavBarBottomGap + bottomInset,
              child: _HomeNavBar(
                tab: _tab,
                myCount: _history.length,
                wardCount: _wardIssues.length,
                onTab: _selectTab,
                onSubmit: _openReport,
              ),
            ),

            // ── 6. Floating notification banner for status updates ──
            Positioned(
              key: const ValueKey('home-notif'),
              top: 0, left: 0, right: 0,
              child: NotificationPoller(
                recipientType: 'citizen',
                recipientId: ref.watch(userIdProvider),
                onAnyNotification: () {
                  _loadHistory();
                  final w = _currentWard;
                  if (w != null) _loadWard(w);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sheet: pinned header (grip + filter pills + segments) ──────────────

  Widget _buildSheetHeader() {
    final source = _tabIssues;
    final ward = _tab == _HomeTab.ward;
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

          // Status filter pills — replace the old map legend. Three chips that
          // hug their own content, centred as a group between two equal slots:
          // an empty one on the left and the ward feed's funnel on the right.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                // Dead mirror of the funnel. Its only job is to keep the pills
                // optically centred AND pixel-identical across destinations.
                const SizedBox(width: _kFunnelSlot),
                Expanded(
                  // Last-resort guard: a longer translation or a large system
                  // font scales the group down instead of overflowing the row.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _kFilterPills.length; i++) ...[
                          _FilterPill(
                            count: _bucketCount(source, _kFilterPills[i].$1),
                            label: context.tr(_kFilterPills[i].$2),
                            fg: _kFilterPills[i].$3,
                            bg: _kFilterPills[i].$4,
                            active: _statusFilter == _kFilterPills[i].$1,
                            onTap: () =>
                                _toggleStatusFilter(_kFilterPills[i].$1),
                          ),
                          if (i < _kFilterPills.length - 1)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: _kFunnelSlot,
                  child: ward
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: _WardFilterToggle(
                            open: _wardFiltersOpen,
                            filtered: _wardScope != _WardScope.all ||
                                _wardSort != _WardSort.recent,
                            onTap: _toggleWardFilters,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),

          // Trailing padding of the BASE header — deliberately above the ward
          // block so _kSheetHeaderBase clips exactly where My Reports ends.
          const SizedBox(height: 12),

          // Ward feed only: scope + sort. Built whenever the ward is active,
          // never conditionally removed — the header's ClipRect is what hides
          // it, so revealing and hiding are one motion played both ways. A
          // widget torn out of the tree would blink instead of sliding.
          if (ward) ...[
            const SizedBox(height: 8),
            _buildWardFilterPills(),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  /// Scope (All / My Supports) and sort (Recent / Priority) as four pills that
  /// hug their own content, separated by a constant gap and centred as a group
  /// on the row — not spread edge to edge.
  Widget _buildWardFilterPills() {
    const gap = SizedBox(width: 7);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _WardFilterPill(
            label: context.tr('All'),
            active: _wardScope == _WardScope.all,
            onTap: () => _setWardScope(_WardScope.all),
          ),
          gap,
          _WardFilterPill(
            label: context.tr('My Supports'),
            active: _wardScope == _WardScope.supports,
            onTap: () => _setWardScope(_WardScope.supports),
          ),
          gap,
          _WardFilterPill(
            label: context.tr('Recent'),
            active: _wardSort == _WardSort.recent,
            onTap: () => _setWardSort(_WardSort.recent),
          ),
          gap,
          _WardFilterPill(
            label: context.tr('Priority'),
            active: _wardSort == _WardSort.priority,
            onTap: () => _setWardSort(_WardSort.priority),
          ),
        ],
      ),
    );
  }

  // ── Sheet: scrolling body ──────────────────────────────────────────────

  List<Widget> _buildSheetBody() {
    final out = <Widget>[];

    if (_error != null) {
      out.add(
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
                child: Text(
                  _error!,
                  style: const TextStyle(
                      fontSize: 12, color: NkColors.rose600),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _error = null),
                child: const Icon(Icons.close,
                    size: 14, color: NkColors.rose600),
              ),
            ],
          ),
        ),
      );
    }

    out.add(const SizedBox(height: 4));

    // Cards fade+rise in on their own short stagger, and the whole list
    // cross-fades when the destination or ward scope changes.
    final cards = switch (_tab) {
      _HomeTab.ward => _wardCards(),
      _HomeTab.mine => _myReportCards(),
    };
    for (var i = 0; i < cards.length; i++) {
      out.add(_StaggeredEntry(index: i, child: cards[i]));
    }
    return out;
  }

  Widget _emptyState(IconData icon, String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(icon, size: 32, color: NkColors.slate300),
            const SizedBox(height: 8),
            Text(
              // Unknown strings (the ward-number ones) pass through as English.
              context.tr(message),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: NkColors.slate400),
            ),
          ],
        ),
      );

  List<Widget> _wardCards() {
    if (_currentWard == null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            context.tr('Locating your ward…'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: NkColors.slate400),
          ),
        ),
      ];
    }

    final supports = _wardScope == _WardScope.supports;
    if (supports && _supportedLoading && _supported.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: NkColors.brand),
            ),
          ),
        ),
      ];
    }

    final list = _applyStatusFilter(_tabIssues);
    if (list.isEmpty) {
      return [
        _emptyState(
          supports ? Icons.thumb_up_outlined : Icons.groups_outlined,
          supports
              ? (_statusFilter != null
                  ? 'No matching grievances among your supports.'
                  : 'You have not supported any grievance yet.')
              : (_statusFilter != null
                  ? 'No matching grievances in Ward $_currentWard.'
                  : 'No public grievances in Ward $_currentWard yet.'),
        ),
      ];
    }

    return [
      for (final issue in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _selectableCard(
            issue,
            GrievanceCard(issue: issue, onUpvote: _upvote),
          ),
        ),
    ];
  }

  List<Widget> _myReportCards() {
    final out = <Widget>[];

    // Action-required verification cards always show — they are blocking.
    for (final issue
        in _history.where((i) => i.status == 'PENDING_VERIFICATION')) {
      out.add(_verifyCard(issue));
    }

    if (_histLoading) {
      out.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: NkColors.brand),
            ),
          ),
        ),
      );
      return out;
    }

    final list = _applyStatusFilter(_history);
    if (list.isEmpty) {
      out.add(
        _emptyState(
          Icons.place_outlined,
          _statusFilter != null
              ? 'No matching reports.'
              : 'No reports yet. Submit one from the "+" button.',
        ),
      );
      return out;
    }

    for (final issue in list) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _selectableCard(
            issue,
            GrievanceCard(issue: issue),
          ),
        ),
      );
    }
    return out;
  }

  Widget _verifyCard(Issue issue) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NkColors.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NkColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 14, color: NkColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Action Required — ${issue.title}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: NkColors.slate700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Authority marked this issue as RESOLVED. Has it really been fixed?',
            style: TextStyle(fontSize: 12, color: NkColors.slate500),
          ),
          // The proof the coordinator was required to capture. Asking someone
          // to approve a repair they cannot see is asking them to guess.
          _ClosureProof(issue: issue),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _busyId == issue.id
                      ? null
                      : () => _verify(issue, 'APPROVED'),
                  child: Opacity(
                    opacity: _busyId == issue.id ? 0.6 : 1,
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: NkColors.emerald600,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 13, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Approve & Close',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _busyId == issue.id
                      ? null
                      : () => _verify(issue, 'REJECTED'),
                  child: Opacity(
                    opacity: _busyId == issue.id ? 0.6 : 1,
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NkColors.slate300),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cancel_outlined,
                              size: 13, color: NkColors.slate600),
                          SizedBox(width: 4),
                          Text(
                            'Reject / Not Fixed',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: NkColors.slate600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fixed-height pinned block at the top of the sheet.
class _SheetHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SheetHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    // [height] is mid-flight during a destination change, so the incoming
    // header's natural height rarely matches it. Let the child lay out at its
    // own size and clip the difference: a tight box here would throw a
    // RenderFlex overflow on every frame of the transition.
    return SizedBox(
      height: height,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: child,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SheetHeaderDelegate old) =>
      old.height != height || old.child != child;
}

/// The floating bottom navigation bar: My Reports | + | In my Ward.
///
/// Built to the isolated navbar reference: ONE flat capsule of fixed height
/// with uniform padding, and all three sections living inside it — the centre
/// "+" no longer rises above the track, it is a peer of the two side tabs and
/// shares their inner height and vertical centre line.
///
/// Deliberately no Expanded / spaceEvenly: the side widths are computed from
/// the measured capsule width minus the reserved centre slot, so the geometry
/// is explicit rather than distributed by the layout algorithm.
class _HomeNavBar extends StatelessWidget {
  const _HomeNavBar({
    required this.tab,
    required this.myCount,
    required this.wardCount,
    required this.onTab,
    required this.onSubmit,
  });

  final _HomeTab tab;
  final int myCount;
  final int wardCount;
  final ValueChanged<_HomeTab> onTab;
  final VoidCallback onSubmit;

  /// Inset from the screen edges.
  static const double _sideMargin = 16;

  /// Uniform padding between the capsule edge and its contents.
  static const double _capsulePad = 5;

  /// Reserved width of the centre button — proportional to the side tabs, not
  /// a raised element competing with them.
  static const double _plusWidth = 60;

  /// Track left visible either side of the centre button, so the active pill
  /// never butts up against it. The side segments are sized from whatever is
  /// left after this, so widening the gap narrows them rather than overflowing —
  /// and their labels are Flexible + ellipsis, so they truncate if squeezed.
  static const double _plusGap = 14;

  /// Inner content height, shared by all three sections.
  static const double _innerHeight = _kNavBarHeight - _capsulePad * 2;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _sideMargin),
      child: Container(
        height: _kNavBarHeight,
        padding: const EdgeInsets.all(_capsulePad),
        decoration: BoxDecoration(
          // Light neutral track; the active pill is the only pure white.
          color: const Color(0xFFF1F2F4),
          borderRadius: BorderRadius.circular(_kNavBarHeight / 2),
          // Neumorphic pair: one soft shadow below-right, one light bloom
          // above-left, so the bar reads as pressed UP out of the surface
          // rather than dropped on top of it. Kept low-contrast on purpose —
          // it floats over a live map, and a strong pair would fight the tiles.
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF9AA5B4).withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(4, 6),
              spreadRadius: -4,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.85),
              blurRadius: 12,
              offset: const Offset(-3, -3),
              spreadRadius: -4,
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sideWidth =
                ((constraints.maxWidth - _plusWidth - _plusGap * 2) / 2)
                    .clamp(0.0, 400.0);
            return Row(
              children: [
                SizedBox(
                  width: sideWidth,
                  height: _innerHeight,
                  child: _NavSegment(
                    label: context.tr('My Reports'),
                    count: myCount,
                    active: tab == _HomeTab.mine,
                    onTap: () => onTab(_HomeTab.mine),
                  ),
                ),
                const SizedBox(width: _plusGap),
                SizedBox(
                  width: _plusWidth,
                  height: _innerHeight,
                  child: _NavPlusButton(onTap: onSubmit),
                ),
                const SizedBox(width: _plusGap),
                SizedBox(
                  width: sideWidth,
                  height: _innerHeight,
                  child: _NavSegment(
                    label: context.tr('In my Ward'),
                    count: wardCount,
                    active: tab == _HomeTab.ward,
                    onTap: () => onTab(_HomeTab.ward),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One destination on the nav track: a compact white pill when active, bare
/// track when not. Badge and label share the capsule's vertical centre line.
class _NavSegment extends StatelessWidget {
  const _NavSegment({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: NkMotion.settle,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          // The active tab is raised off the track with the same two-light
          // logic as the bar, one step quieter so it reads as nested inside it.
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFF9AA5B4).withValues(alpha: 0.34),
                    blurRadius: 6,
                    offset: const Offset(2, 3),
                    spreadRadius: -2,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.95),
                    blurRadius: 5,
                    offset: const Offset(-2, -2),
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Perfect 20pt circle for one- and two-digit counts; only a
            // three-digit count stretches it, and then symmetrically.
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: NkMotion.settle,
              height: 20,
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Subtle, not bright: a light neutral either way, one step
                // apart so the badge reads on both the pill and the track.
                color: active
                    ? const Color(0xFFEDEFF3)
                    : const Color(0xFFE3E6EB),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: NkColors.slate600,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 280),
                curve: NkMotion.settle,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1,
                  letterSpacing: 0,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? NkColors.slate900 : NkColors.slate500,
                ),
                child:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The centre navy "+" — the grievance CTA. Sized to the capsule's inner
/// height so it sits flush inside the track rather than floating over it.
class _NavPlusButton extends StatefulWidget {
  const _NavPlusButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_NavPlusButton> createState() => _NavPlusButtonState();
}

class _NavPlusButtonState extends State<_NavPlusButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 160),
        curve: NkMotion.settle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: NkMotion.settle,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // A soft top-left-lit gradient rather than a flat fill: the light
            // has to come from the same direction as the bar's own for the
            // raised read to hold.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _down
                  ? const [NkColors.refBlueDeep, NkColors.refBlueInner]
                  : const [NkColors.refBlueInner, NkColors.refBlueDeep],
            ),
            borderRadius: BorderRadius.circular(14),
            // Raised at rest; on press the cast shadow collapses and a tight
            // dark halo takes over, so the button reads as pushed INTO the
            // track instead of merely shrinking.
            boxShadow: _down
                ? [
                    BoxShadow(
                      color: const Color(0xFF7E8A99).withValues(alpha: 0.45),
                      blurRadius: 4,
                      offset: const Offset(1, 1),
                      spreadRadius: -1,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: const Color(0xFF6C7A8B).withValues(alpha: 0.45),
                      blurRadius: 9,
                      offset: const Offset(3, 4),
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.95),
                      blurRadius: 6,
                      offset: const Offset(-2, -2),
                      spreadRadius: -2,
                    ),
                  ],
          ),
          child: const Icon(
            Icons.add_rounded,
            size: 22,
            // Cream-gold, sampled from the wordmark gradient in the logo SVG.
            color: Color(0xFFFFEEB8),
          ),
        ),
      ),
    );
  }
}

/// Fades + lifts a list item in on a short per-index stagger, so a list that
/// changes (tab switch, filter change, refresh) settles instead of snapping.
class _StaggeredEntry extends StatefulWidget {
  const _StaggeredEntry({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<_StaggeredEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: NkMotion.settle);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    // Cap the stagger so a long list does not take a second to finish.
    final ms = (widget.index.clamp(0, 6)) * 45;
    if (ms == 0) {
      _c.forward();
    } else {
      _delay = Timer(Duration(milliseconds: ms), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(_a),
        child: widget.child,
      ),
    );
  }
}

/// A status filter chip — count + label, colored per status family.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.count,
    required this.label,
    required this.fg,
    required this.bg,
    required this.active,
    required this.onTap,
  });

  final int count;
  final String label;
  final Color fg;
  final Color bg;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: NkMotion.settle,
        padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
        decoration: BoxDecoration(
          // Soft filled pastel at rest; selecting deepens the fill and keeps
          // the same hue family rather than inverting to a solid block.
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? fg : Colors.transparent,
            width: 1.4,
          ),
        ),
        // Each pill hugs its own content; every pill shares one font size — no
        // FittedBox, which would scale the longest label and drop its baseline
        // a pixel or two below the other two.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Leading circular count badge.
            Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sneaky demo shortcut — a small frosted circle on the top-right of the map
/// that jumps the detected location to Egmore Ward 108 for testing when real
/// GPS falls outside GCC limits. Turns gold while the override is active.
class _DemoJumpButton extends StatelessWidget {
  const _DemoJumpButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SolidCapsule(
        padding: const EdgeInsets.all(10),
        child: Icon(
          Icons.account_balance,
          size: 16,
          color: active ? NkColors.gold300 : NkColors.slate500,
        ),
      ),
    );
  }
}

/// One option in the ward feed's filter row. Compact pill: navy fill when
/// selected, quiet neutral when not. Scope and sort are independent, so one
/// pill from each pair reads as active at the same time.
/// Funnel that reveals the ward feed's scope + sort row. Sized to sit inside
/// [_kFunnelSlot] and one px shorter than a status pill, so it rides the same
/// baseline without driving the row's height.
class _WardFilterToggle extends StatelessWidget {
  const _WardFilterToggle({
    required this.open,
    required this.filtered,
    required this.onTap,
  });

  final bool open;

  /// A non-default scope or sort is applied. Kept lit while the row is hidden,
  /// otherwise collapsing it would silently swallow the fact that the feed is
  /// filtered.
  final bool filtered;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lit = open || filtered;
    return Semantics(
      button: true,
      expanded: open,
      label: context.tr('Filter'),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: NkMotion.settle,
          height: 28,
          width: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: lit ? NkColors.refBlue : const Color(0xFFF1F3F7),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: lit ? NkColors.refBlue : const Color(0xFFE3E6EB),
            ),
          ),
          child: Icon(
            open ? Icons.filter_alt : Icons.filter_alt_outlined,
            size: 15,
            color: lit ? Colors.white : NkColors.slate600,
          ),
        ),
      ),
    );
  }
}

class _WardFilterPill extends StatelessWidget {
  const _WardFilterPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: NkMotion.settle,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: active ? NkColors.refBlue : const Color(0xFFF1F3F7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? NkColors.refBlue : const Color(0xFFE3E6EB),
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          curve: NkMotion.settle,
          style: TextStyle(
            fontSize: 11,
            height: 1,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: active ? Colors.white : NkColors.slate600,
          ),
          child: Text(label, maxLines: 1),
        ),
      ),
    );
  }
}

/// Floating "🏛 Egmore | Ward (103)" chip — frosted like the app bar, parked
/// just under it on the top-left of the map.
class _WardPill extends StatelessWidget {
  const _WardPill({required this.constituency, required this.ward});

  final String constituency;
  final String ward;

  @override
  Widget build(BuildContext context) {
    return SolidCapsule(
      // Even inset both sides now that the ward number is plain text — the
      // asymmetric padding existed only to seat the blue circle.
      padding: const EdgeInsets.fromLTRB(12, 7, 13, 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance, size: 15, color: NkColors.refBlue),
          const SizedBox(width: 8),
          if (constituency.isNotEmpty) ...[
            Text(
              constituency,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: NkColors.slate900,
              ),
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 13, color: NkColors.slate200),
            const SizedBox(width: 8),
          ],
          Text(
            context.tr('Ward'),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: NkColors.slate500,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            ward,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: NkColors.slate900,
            ),
          ),
        ],
      ),
    );
  }
}


/// The coordinator's proof of work, shown to the citizen with the verify
/// prompt: the live photo, the voice note, and whatever note was typed.
class _ClosureProof extends StatefulWidget {
  const _ClosureProof({required this.issue});

  final Issue issue;

  @override
  State<_ClosureProof> createState() => _ClosureProofState();
}

class _ClosureProofState extends State<_ClosureProof> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle(String url) async {
    HapticFeedback.selectionClick();
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _player.play(UrlSource(url));
    if (mounted) setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final photo = Env.mediaUrl(widget.issue.closureImageUrl);
    final audio = Env.mediaUrl(widget.issue.closureAudioUrl);
    final note = (widget.issue.coordinatorMessage ?? '').trim();
    if (photo == null && audio == null && note.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NkColors.emerald100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined,
                  size: 13, color: NkColors.emerald600),
              const SizedBox(width: 6),
              Text(
                context.tr('Proof of work'),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: NkColors.emerald600,
                ),
              ),
            ],
          ),
          if (photo != null || audio != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (photo != null)
                  GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          color: Colors.black87,
                          alignment: Alignment.center,
                          child: InteractiveViewer(
                            child: Image.network(photo, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        photo,
                        height: 56,
                        width: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 56,
                          width: 56,
                          color: NkColors.slate100,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined,
                              size: 18, color: NkColors.slate400),
                        ),
                      ),
                    ),
                  ),
                if (photo != null && audio != null) const SizedBox(width: 10),
                if (audio != null)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _toggle(audio),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: NkColors.emerald50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _playing
                                  ? Icons.stop_circle_outlined
                                  : Icons.play_circle_outline,
                              size: 20,
                              color: NkColors.emerald600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.tr(_playing
                                    ? 'Playing…'
                                    : "Coordinator's voice note"),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: NkColors.emerald700,
                                ),
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
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontStyle: FontStyle.italic,
                color: NkColors.slate600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
