import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

/// The three segments of the home sheet, in display order.
enum _HomeTab { mine, ward, supports }

/// Sheet snap fractions — collapsed shows only the pinned pills+tabs block,
/// normal is the landing state, expanded gives the list the most room.
const double _kSheetMin = 0.18;
const double _kSheetNormal = 0.52;
const double _kSheetMax = 0.78;

/// Midpoints between the snaps — the band that counts as "resting at normal".
const double _kNormalLowerEdge = (_kSheetMin + _kSheetNormal) / 2;
const double _kNormalUpperEdge = (_kSheetNormal + _kSheetMax) / 2;

/// Height of the pinned grip + filter pills + segmented tabs block.
/// grip 8+4+10, pills 38+10, segments ~39, trailing 12 ≈ 121. Held a few
/// px above that: the sliver extent is fixed, so slack is invisible white
/// space whereas a short value would clip the tab row.
const double _kSheetHeaderHeight = 126;

/// Backend statuses grouped behind each filter pill.
const Map<String, Set<String>> _kStatusBuckets = {
  'open': {'SUBMITTED', 'ACTIVE'},
  'progress': {'FORWARDED', 'IN_PROGRESS'},
  'resolved': {'CLOSED'},
};

/// Royal-navy accent pair, shared by the active segment and the report FAB.
const Color _kRoyalBlue = Color(0xFF1A3A8F);
const Color _kDeepNavy = Color(0xFF0D1F3C);

/// The filter pills in display order — (bucket key, label, foreground, fill).
/// They share the row width equally.
const List<(String, String, Color, Color)> _kFilterPills = [
  ('open', 'Open', NkColors.rose600, NkColors.rose50),
  ('progress', 'In progress', NkColors.sky700, NkColors.sky50),
  ('resolved', 'Resolved', NkColors.emerald700, NkColors.emerald50),
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

  /// Real per-account profile counters (null until first load → shows dashes).
  ({int reports, int upvotes, int resolved, int open})? _stats;
  bool _histLoading = true;
  Issue? _selected;
  final Map<String, GlobalKey> _cardKeys = {};
  String? _error;
  String? _busyId;

  // UI state
  _HomeTab _tab = _HomeTab.mine;

  /// Active status filter pill (null = show everything).
  String? _statusFilter;

  final _sheetCtrl = DraggableScrollableController();

  /// Live sheet extent, driven every drag frame. Deliberately a notifier and
  /// not `setState` state: only the ward pill listens, so dragging never
  /// rebuilds the map underneath.
  final _sheetExtent = ValueNotifier<double>(_kSheetNormal);

  /// True while the sheet rests at or below its normal snap — My Reports then
  /// shows a single card. Tracked as a bool rather than the raw extent so the
  /// drag only rebuilds when it actually crosses the threshold.
  bool _sheetAtOrBelowNormal = true;

  /// The FAB only belongs to the normal snap — collapsed it would cover the
  /// tab row, expanded it would cover the list.
  bool _sheetAtNormal = true;
  bool _fabVisible = true;

  /// The "no reports yet → land on My Ward" fallback only fires once.
  bool _autoTabApplied = false;

  LatLng? get _coords => _override ?? _geoCoords;

  int? get _currentWard =>
      (_locate?.inside ?? false) ? _locate?.wardNumber : null;

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
    _sheetExtent.dispose();
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
    _loadStats();
  }

  /// Real profile counters for the signed-in account (reports / upvotes cast /
  /// resolved / open-unassigned). Refreshed whenever history reloads.
  Future<void> _loadStats() async {
    try {
      final s = await ref
          .read(apiClientProvider)
          .fetchUserStats(ref.read(userIdProvider));
      if (mounted) setState(() => _stats = s);
    } catch (_) {/* leave previous values */}
  }

  // ── Filtering ──────────────────────────────────────────────────────────

  /// The unfiltered list backing the active segment.
  List<Issue> get _tabIssues => switch (_tab) {
        _HomeTab.ward => _wardIssues,
        _HomeTab.mine => _history,
        // No endpoint exposes "grievances I upvoted" yet — the segment shows
        // its cast-upvote count and an empty state until one exists.
        _HomeTab.supports => const <Issue>[],
      };

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
    if (_sheetCtrl.isAttached && _sheetCtrl.size < _kSheetNormal) {
      _sheetCtrl.animateTo(
        _kSheetNormal,
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
    final screenH = MediaQuery.sizeOf(context).height;
    final fabShown = _fabVisible && _sheetAtNormal;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
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
                issues: _applyStatusFilter(_wardIssues),
                selected: _selected,
                onSelect: _onMapSelect,
                boundaries: _boundaries,
                currentWard: _currentWard,
                locate: _locate,
                locating: _locating,
                egmoreActive: _override != null,
                onJumpEgmore: _jumpToEgmore,
                onUpvote: _upvote,
                borderRadius: 0,
                showLegend: false,
                showLocateChip: false,
                // Clear the floating app bar above and the sheet below.
                // 96 ≈ brand row (40) + gap (8) + greeting (21) + padding.
                searchTop: topInset + 96,
                searchHorizontal: 14,
                controlsBottomInset: screenH * _kSheetNormal + 10,
              ),
            ),

            // ── 2. App bar floating over the map behind a fading gradient ──
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ProfileHeader(),
            ),

            // ── 3. Constituency · ward pill — rides 10dp above the sheet's
            // top edge while the sheet is at or below its normal snap, then
            // parks there and lets the expanding sheet slide over it ──
            if (_currentWard != null)
              ValueListenableBuilder<double>(
                valueListenable: _sheetExtent,
                builder: (context, extent, child) => Positioned(
                  left: 14,
                  bottom: screenH *
                          (extent > _kSheetNormal ? _kSheetNormal : extent) +
                      10,
                  child: child!,
                ),
                child: _WardPill(
                  constituency: (_locate?.constituencies.isEmpty ?? true)
                      ? ''
                      : shortAC(_locate!.constituencies.first),
                  ward: '$_currentWard',
                ),
              ),

            // ── 4. The draggable content sheet ──
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (n) {
                // Drives the ward pill only — no setState, so the map does
                // not rebuild on every drag frame.
                _sheetExtent.value = n.extent;

                // These two genuinely change content, so they do rebuild —
                // but only when the extent crosses a threshold.
                final atOrBelow = n.extent < _kNormalUpperEdge;
                final atNormal =
                    n.extent > _kNormalLowerEdge && n.extent < _kNormalUpperEdge;
                if (atOrBelow != _sheetAtOrBelowNormal ||
                    atNormal != _sheetAtNormal) {
                  setState(() {
                    _sheetAtOrBelowNormal = atOrBelow;
                    _sheetAtNormal = atNormal;
                  });
                }
                return false;
              },
              child: NotificationListener<UserScrollNotification>(
                onNotification: (n) {
                  final hide = n.direction == ScrollDirection.reverse;
                  final show = n.direction == ScrollDirection.forward ||
                      n.direction == ScrollDirection.idle;
                  if (hide && _fabVisible) {
                    setState(() => _fabVisible = false);
                  } else if (show && !_fabVisible) {
                    setState(() => _fabVisible = true);
                  }
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: _sheetCtrl,
                  initialChildSize: _kSheetNormal,
                  minChildSize: _kSheetMin,
                  maxChildSize: _kSheetMax,
                  snap: true,
                  snapSizes: const [_kSheetMin, _kSheetNormal, _kSheetMax],
                  builder: (context, scrollController) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20)),
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
                          top: Radius.circular(20)),
                      child: CustomScrollView(
                        controller: scrollController,
                        physics: const ClampingScrollPhysics(),
                        slivers: [
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _SheetHeaderDelegate(
                              height: _kSheetHeaderHeight,
                              child: _buildSheetHeader(),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 118),
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
            ),

            // ── 5. Floating notification banner for status updates ──
            Positioned(
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

            // ── 6. Floating "+" report button (hides while scrolling down) ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: IgnorePointer(
                  ignoring: !fabShown,
                  child: AnimatedScale(
                    scale: fabShown ? 1 : 0.6,
                    duration: const Duration(milliseconds: 200),
                    curve: NkMotion.settle,
                    child: AnimatedOpacity(
                      opacity: fabShown ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: GestureDetector(
                        onTap: _openReport,
                        child: Container(
                          height: 64,
                          width: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_kRoyalBlue, _kDeepNavy],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: NkColors.brand.withValues(alpha: 0.45),
                                blurRadius: 40,
                                offset: const Offset(0, 12),
                                spreadRadius: -6,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.add,
                              size: 32, color: NkColors.gold300),
                        ),
                      ),
                    ),
                  ),
                ),
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
            child: SizedBox(
              height: 38,
              child: Row(
                children: [
                  for (var i = 0; i < _kFilterPills.length; i++) ...[
                    Expanded(
                      child: _FilterPill(
                        count: _bucketCount(source, _kFilterPills[i].$1),
                        label: context.tr(_kFilterPills[i].$2),
                        fg: _kFilterPills[i].$3,
                        bg: _kFilterPills[i].$4,
                        active: _statusFilter == _kFilterPills[i].$1,
                        onTap: () =>
                            _toggleStatusFilter(_kFilterPills[i].$1),
                      ),
                    ),
                    if (i < _kFilterPills.length - 1)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Three-segment control — the original slate/white pill styling.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: NkColors.slate200.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  for (final (tab, icon, label, count) in [
                    (
                      _HomeTab.mine,
                      Icons.description_outlined,
                      'My Reports',
                      _history.length
                    ),
                    (
                      _HomeTab.ward,
                      Icons.groups_outlined,
                      'My Ward',
                      _wardIssues.length
                    ),
                    (
                      _HomeTab.supports,
                      Icons.thumb_up_outlined,
                      'My Supports',
                      _stats?.upvotes ?? 0
                    ),
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_tab == tab) return;
                          HapticFeedback.selectionClick();
                          setState(() => _tab = tab);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: NkMotion.settle,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            // Active fill is a royal-navy gradient; inactive
                            // stays transparent. Geometry is unchanged.
                            gradient: _tab == tab
                                ? const LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [_kRoyalBlue, _kDeepNavy],
                                  )
                                : null,
                            color: _tab == tab ? null : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _tab == tab
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icon,
                                size: 13,
                                color: _tab == tab
                                    ? NkColors.gold300
                                    : NkColors.slate500,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${context.tr(label)} $count',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _tab == tab
                                        ? NkColors.gold300
                                        : NkColors.slate500,
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
            ),
          ),
          const SizedBox(height: 12),
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

    out.add(_sectionHeader());
    out.add(const SizedBox(height: 8));

    switch (_tab) {
      case _HomeTab.ward:
        out.addAll(_wardCards());
      case _HomeTab.mine:
        out.addAll(_myReportCards());
      case _HomeTab.supports:
        out.addAll(_supportCards());
    }
    return out;
  }

  Widget _sectionHeader() {
    final (title, onRefresh) = switch (_tab) {
      _HomeTab.ward => (
          'Public grievances ${_currentWard != null ? 'in Ward $_currentWard' : 'in your ward'}',
          () {
            final w = _currentWard;
            if (w != null) _loadWard(w);
          }
        ),
      _HomeTab.mine => ('My Grievances', _loadHistory),
      _HomeTab.supports => ('My Supports', _loadStats),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: NkColors.slate900,
            ),
          ),
        ),
        GestureDetector(
          onTap: onRefresh,
          child: Row(
            children: [
              Icon(Icons.refresh, size: 12, color: NkColors.brand),
              SizedBox(width: 4),
              Text(
                context.tr('Refresh'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: NkColors.brand,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState(IconData icon, String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(icon, size: 32, color: NkColors.slate300),
            const SizedBox(height: 8),
            Text(
              message,
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

    final list = _applyStatusFilter(_wardIssues);
    if (list.isEmpty) {
      return [
        _emptyState(
          Icons.groups_outlined,
          _statusFilter != null
              ? 'No matching grievances in Ward $_currentWard.'
              : 'No public grievances in Ward $_currentWard yet.',
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

    var list = _applyStatusFilter(_history);
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

    // At the normal snap only the most recent report is shown — pulling the
    // sheet up reveals the rest.
    if (_sheetAtOrBelowNormal) list = list.take(1).toList();

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

  List<Widget> _supportCards() => [
        _emptyState(
          Icons.thumb_up_outlined,
          'No supported grievances yet.',
        ),
      ];

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? fg : bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fg, width: 1.5),
        ),
        // The pill is stretched by an Expanded parent, so centre the content
        // and let the longest label ("In progress") ellipsise on narrow
        // screens rather than overflow.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: active ? Colors.white : fg,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating "Egmore | Ward 103" chip pinned to the map above the sheet.
class _WardPill extends StatelessWidget {
  const _WardPill({required this.constituency, required this.ward});

  final String constituency;
  final String ward;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (constituency.isNotEmpty) ...[
            Text(
              constituency,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A2A3A),
              ),
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 14, color: NkColors.slate300),
            const SizedBox(width: 8),
          ],
          Text(
            context.tr('Ward'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A2A3A),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2A3A),
              borderRadius: BorderRadius.circular(10),
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
