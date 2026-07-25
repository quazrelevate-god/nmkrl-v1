import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../domain/constituencies.dart';
import '../../domain/geo_utils.dart';
import '../../domain/models/boundary_data.dart';
import '../../domain/models/issue.dart';
import '../../domain/models/locate_result.dart';
import '../../state/providers.dart';
import '../report/report_sheet.dart';
import '../shared/notification_banner.dart';
import '../upvote/upvote_sheet.dart';
import 'widgets/issue_card.dart';
import 'widgets/map_card.dart';
import 'widgets/profile_header.dart';

/// Fallback location (Anna Nagar, Chennai) when GPS is denied/unavailable —
/// mirrors DEFAULT_LOCATION in lib/hooks.js so the app stays usable.
const kDefaultLocation = LatLng(13.0827, 80.2081);

/// Home — the citizen map screen (port of the phase-1 web home): profile
/// header, the grievance map card, and the In My Ward / My Reports lists,
/// with the floating "+" report button.
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
  bool _profileOpen = false;
  int _tab = 0; // 0 = ward, 1 = mine
  String? _expandedId;

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

  Future<void> _signOut() async {
    await ref.read(authProvider.notifier).signOut();
    if (mounted) context.go('/login');
  }

  double? _distanceKm(Issue issue) {
    final c = _coords;
    if (c == null) return null;
    return haversineKm(
        c.latitude, c.longitude, issue.latitude, issue.longitude);
  }

  void _toggleExpand(String id) =>
      setState(() => _expandedId = _expandedId == id ? null : id);

  /// A tapped map pin highlights + brings forward the matching grievance
  /// ribbon in the list (#6) — no separate sheet. Expands it, scrolls it into
  /// view, and switches to the ward tab if the issue is a ward grievance.
  void _onMapSelect(Issue? i) {
    setState(() {
      _selected = i;
      if (i != null) {
        _expandedId = i.id;
        if (_wardIssues.any((w) => w.id == i.id)) _tab = 0;
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
    final pendingVerify =
        _history.where((i) => i.status == 'PENDING_VERIFICATION').toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            // Soft app background (port of .app-bg)
            const Positioned.fill(child: _AppBackground()),

            SafeArea(
              bottom: false,
              // Header pinned outside the scrollable: only the content below
              // scrolls, and pull-to-refresh never drags the app bar.
              child: Column(
                children: [
                  ProfileHeader(
                    profileOpen: _profileOpen,
                    onToggleProfile: () =>
                        setState(() => _profileOpen = !_profileOpen),
                    onSignOut: _signOut,
                    stats: _stats,
                  ),
                  // ── Map section (pinned) ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                context.tr('Grievance map'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: NkColors.slate900,
                                ),
                              ),
                              Text(
                                context.tr('Tap a pin for details'),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: NkColors.slate400),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 300,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: MapCard(
                            center: _coords,
                            issues: _wardIssues,
                            selected: _selected,
                            onSelect: _onMapSelect,
                            boundaries: _boundaries,
                            currentWard: _currentWard,
                            locate: _locate,
                            locating: _locating,
                            egmoreActive: _override != null,
                            onJumpEgmore: _jumpToEgmore,
                            onUpvote: _upvote,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Tab switcher (pinned) ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: NkColors.slate200.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          for (final (idx, icon, label) in [
                            (
                              0,
                              Icons.groups_outlined,
                              '${context.tr('In My Ward')}${_currentWard != null ? ' (${_wardIssues.length})' : ''}'
                            ),
                            (
                              1,
                              Icons.description_outlined,
                              '${context.tr('My Reports')} (${_history.length})'
                            ),
                          ])
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _tab = idx);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 260),
                                  curve: NkMotion.settle,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _tab == idx
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: _tab == idx
                                        ? [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.06),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(icon,
                                          size: 13,
                                          color: _tab == idx
                                              ? NkColors.slate900
                                              : NkColors.slate500),
                                      const SizedBox(width: 6),
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _tab == idx
                                              ? NkColors.slate900
                                              : NkColors.slate500,
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

                  // Only the grievance list scrolls; pull-to-refresh is
                  // scoped here so the map and tabs stay pinned.
                  Expanded(
                    child: RefreshIndicator(
                      color: NkColors.brand,
                      onRefresh: () async {
                        await Future.wait([
                          _loadHistory(),
                          _loadBoundaries(),
                          if (_currentWard != null) _loadWard(_currentWard!),
                        ]);
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics()),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                        children: [
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
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
                                          fontSize: 12,
                                          color: NkColors.rose600),
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
                          ],
                          const SizedBox(height: 12),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: NkMotion.settle,
                            child: _tab == 0
                                ? _buildWardList()
                                : _buildMyReports(pendingVerify),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Floating notification banner for status updates ──
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

            // ── Floating "+" report button ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: GestureDetector(
                  onTap: _openReport,
                  child: Container(
                    height: 64,
                    width: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: nkBrandGradient,
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
                    child: const Icon(Icons.add, size: 32, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWardList() {
    return Column(
      key: const ValueKey('ward'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Public grievances ${_currentWard != null ? 'in Ward $_currentWard' : 'in your ward'}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: NkColors.slate900,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                final w = _currentWard;
                if (w != null) _loadWard(w);
              },
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
        ),
        const SizedBox(height: 8),
        if (_currentWard == null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              context.tr('Locating your ward…'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: NkColors.slate400),
            ),
          )
        else if (_wardIssues.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                const Icon(Icons.groups_outlined,
                    size: 32, color: NkColors.slate300),
                const SizedBox(height: 8),
                Text(
                  'No public grievances in Ward $_currentWard yet.',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 14, color: NkColors.slate400),
                ),
              ],
            ),
          )
        else
          for (final issue in _wardIssues)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _selectableCard(
                issue,
                IssueCard(
                  issue: issue,
                  expanded: _expandedId == issue.id,
                  onToggle: () => _toggleExpand(issue.id),
                  distanceKm: _distanceKm(issue),
                  onUpvote: _upvote,
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildMyReports(List<Issue> pendingVerify) {
    return Column(
      key: const ValueKey('mine'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Action-required verification cards
        for (final issue in pendingVerify)
          Container(
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
          ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My Grievances',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: NkColors.slate900,
              ),
            ),
            GestureDetector(
              onTap: _loadHistory,
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
        ),
        const SizedBox(height: 8),
        if (_histLoading)
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
          )
        else if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(Icons.place_outlined, size: 32, color: NkColors.slate300),
                SizedBox(height: 8),
                Text(
                  'No reports yet. Submit one from the "+" button.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: NkColors.slate400),
                ),
              ],
            ),
          )
        else
          for (final issue in _history)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _selectableCard(
                issue,
                IssueCard(
                  issue: issue,
                  expanded: _expandedId == issue.id,
                  onToggle: () => _toggleExpand(issue.id),
                  distanceKm: _distanceKm(issue),
                ),
              ),
            ),
      ],
    );
  }
}

/// Soft radial-tinted background (port of .app-bg).
class _AppBackground extends StatelessWidget {
  const _AppBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFBFCFD)),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            child: _blob(NkColors.brand.withValues(alpha: 0.06), 420),
          ),
          Positioned(
            top: 40,
            right: -140,
            child: _blob(NkColors.gold300.withValues(alpha: 0.06), 360),
          ),
          Positioned(
            bottom: -160,
            left: 60,
            child: _blob(NkColors.brand.withValues(alpha: 0.045), 380),
          ),
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) => Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      );
}
