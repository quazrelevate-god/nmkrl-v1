import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

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
/// the user can never collapse below it — see [_sheetFloorFraction]. Above the
/// floor there is a comfortable mid snap and a near-full expanded snap.
const double _kSheetMid = 0.62;
const double _kSheetMax = 0.86;

/// Rough on-screen footprint of one grievance card (thumbnail row + selection
/// border + inter-card gap), used to size the sheet floor to ~2 cards.
const double _kCardFootprint = 96;

/// Pinned sheet header. There is no title row any more: grip + status pills is
/// the base, and the ward feed adds one row of filter pills under it. The
/// sliver extent is fixed, so each value is held a few px above the measured
/// content — slack is invisible white space, a short value would clip.
/// base: grip 8+4+10 + pills 29 + trailing 12 ≈ 63.
/// ward: base + 10 + filter pills 26 ≈ 99.
const double _kSheetHeaderBase = 64;
const double _kSheetHeaderWard = 100;

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

class _HomeScreenState extends ConsumerState<HomeScreen> {
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
    // Sized off the TALLER (ward) header so the floor does not jump when the
    // destination changes.
    final px =
        _kSheetHeaderWard + 8 + 2 * _kCardFootprint + bottomObstruction;
    return (px / parentHeight).clamp(0.28, 0.62);
  }

  /// The pinned header's fixed extent for the active destination.
  double get _sheetHeaderHeight =>
      _tab == _HomeTab.ward ? _kSheetHeaderWard : _kSheetHeaderBase;

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

  @override
  void initState() {
    super.initState();
    _locateDevice();
    _loadBoundaries();
    _loadHistory();
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    super.dispose();
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

  void _selectTab(_HomeTab tab) {
    if (_tab == tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = tab);
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
  /// ribbon in the sheet (#6). Lifts the sheet to its normal snap so the card
  /// is on screen, and switches to the ward segment if the issue is a ward
  /// grievance. Tapping the card itself opens the detail dialog.
  void _onMapSelect(Issue? i) {
    setState(() {
      _selected = i;
      if (i != null && _wardIssues.any((w) => w.id == i.id)) {
        _tab = _HomeTab.ward;
      }
    });
    if (i == null) return;
    if (_sheetCtrl.isAttached && _sheetCtrl.size < _kSheetMid) {
      _sheetCtrl.animateTo(
        _kSheetMid,
        duration: const Duration(milliseconds: 300),
        curve: NkMotion.settle,
      );
    }
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
    final navCover = _kNavBarHeight + _kNavBarBottomGap + bottomInset;
    final sheetFloor = _sheetFloorFraction(sheetParentH, navCover);

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

            // ── 3. Constituency · ward chip, centred under the app bar. Same
            // y as before; only the x anchoring changed (left → centred). ──
            if (_currentWard != null)
              Positioned(
                key: const ValueKey('home-wardpill'),
                top: topInset + 8 + 56 + 10,
                left: 0,
                right: 0,
                child: Center(
                  child: _WardPill(
                    constituency: (_locate?.constituencies.isEmpty ?? true)
                        ? ''
                        : shortAC(_locate!.constituencies.first),
                    ward: '$_currentWard',
                  ),
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
                maxChildSize: _kSheetMax,
                snap: true,
                snapSizes: [sheetFloor, _kSheetMid, _kSheetMax],
                builder: (context, scrollController) => DecoratedBox(
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
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _SheetHeaderDelegate(
                            height: _sheetHeaderHeight,
                            child: _buildSheetHeader(),
                          ),
                        ),
                        SliverPadding(
                          // Bottom clearance so the last card clears the
                          // floating nav bar rather than hiding under it.
                          padding: EdgeInsets.fromLTRB(14, 0, 14,
                              _kNavBarHeight + _kNavBarBottomGap + bottomInset + 24),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate(
                              _buildSheetBody(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── 5. Fade under the floating nav bar, so list content scrolling
            // beneath it dissolves into white instead of peeking through the
            // gaps around the track and the raised "+". ──
            Positioned(
              key: const ValueKey('home-navscrim'),
              left: 0,
              right: 0,
              bottom: 0,
              height: navCover + 26,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.92),
                        Colors.white,
                      ],
                      stops: const [0, 0.45, 0.7],
                    ),
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
                onStatusChange: (_) {
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

          // Status filter pills — replace the old map legend. They split the
          // row evenly rather than scrolling, so there is no dead space.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            // Independent chips that hug their own content and sit centred as a
            // group — not a full-width segmented control.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _kFilterPills.length; i++) ...[
                  _FilterPill(
                    count: _bucketCount(source, _kFilterPills[i].$1),
                    label: context.tr(_kFilterPills[i].$2),
                    fg: _kFilterPills[i].$3,
                    bg: _kFilterPills[i].$4,
                    active: _statusFilter == _kFilterPills[i].$1,
                    onTap: () => _toggleStatusFilter(_kFilterPills[i].$1),
                  ),
                  if (i < _kFilterPills.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),

          // Ward feed only: scope + sort as one evenly spaced row of pills.
          // The nav bar already names the destination, so there is no title.
          if (_tab == _HomeTab.ward) ...[
            const SizedBox(height: 10),
            _buildWardFilterPills(),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Scope (All / My Supports) and sort (Recent / Priority) as four pills on
  /// one row, evenly spaced — replaces the dropdown menu.
  Widget _buildWardFilterPills() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _WardFilterPill(
            label: context.tr('All'),
            active: _wardScope == _WardScope.all,
            onTap: () => _setWardScope(_WardScope.all),
          ),
          _WardFilterPill(
            label: context.tr('My Supports'),
            active: _wardScope == _WardScope.supports,
            onTap: () => _setWardScope(_WardScope.supports),
          ),
          _WardFilterPill(
            label: context.tr('Recent'),
            active: _wardSort == _WardSort.recent,
            onTap: () => _setWardSort(_WardSort.recent),
          ),
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
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox(height: height, child: child);

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
  /// never butts up against it.
  static const double _plusGap = 5;

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
          boxShadow: [
            // Very soft elevation — low opacity, modest blur.
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 14,
              offset: const Offset(0, 4),
              spreadRadius: -2,
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
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
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
        scale: _down ? 0.93 : 1,
        duration: const Duration(milliseconds: 160),
        curve: NkMotion.settle,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // Flat navy — no radial bloom, so it reads as part of the bar.
            color: NkColors.refBlueDeep,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: NkColors.refBlueDeep.withValues(alpha: 0.20),
                blurRadius: 7,
                offset: const Offset(0, 2),
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
      child: FrostedCapsule(
        padding: const EdgeInsets.all(9),
        child: Icon(
          Icons.account_balance,
          size: 16,
          color: active ? NkColors.gold300 : Colors.white,
        ),
      ),
    );
  }
}

/// One option in the ward feed's filter row. Compact pill: navy fill when
/// selected, quiet neutral when not. Scope and sort are independent, so one
/// pill from each pair reads as active at the same time.
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
    return FrostedCapsule(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          if (constituency.isNotEmpty) ...[
            Text(
              constituency,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Container(
                width: 1,
                height: 14,
                color: Colors.white.withValues(alpha: 0.45)),
            const SizedBox(width: 8),
          ],
          Text(
            context.tr('Ward'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 7),
          Container(
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NkColors.refBlue.withValues(alpha: 0.62),
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
