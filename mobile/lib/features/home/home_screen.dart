import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../domain/constituencies.dart';
import '../../domain/geo_utils.dart';
import '../../domain/models/boundary_data.dart';
import '../../domain/models/issue.dart';
import '../../domain/models/locate_result.dart';
import '../../domain/profile_data.dart';
import '../../state/providers.dart';
import '../report/report_sheet.dart';
import '../upvote/upvote_sheet.dart';
import 'widgets/issue_card.dart';
import 'widgets/map_card.dart';
import 'widgets/profile_header.dart';

/// Fallback location (Anna Nagar, Chennai) when GPS is denied/unavailable —
/// mirrors DEFAULT_LOCATION in lib/hooks.js so the app stays usable.
const kDefaultLocation = LatLng(13.0827, 80.2081);

// ── Reskin palette ──────────────────────────────────────────────────────────
const _kBlue = Color(0xFF1A3A8F);
const _kDarkNavy = Color(0xFF1A2A4A);
const _kMuted = Color(0xFF7A8799);

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
  bool _histLoading = true;
  Issue? _selected;
  String? _error;
  String? _busyId;

  // UI state
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
  }

  // ── Actions ────────────────────────────────────────────────────────────

  /// Demo shortcut: our GPS may be outside GCC, so jump the detected location
  /// to an Egmore ward so ward-level data can be visualised.
  void _jumpToEgmore() {
    final feats = _boundaries?.wards ?? const <BoundaryFeature>[];
    BoundaryFeature? f;
    for (final ft in feats) {
      if (ft.ward != null && kEgmoreWards.contains(ft.ward)) {
        f = ft;
        break;
      }
    }
    if (f == null) return;
    setState(() => _override = f!.centroid());
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
      onRefreshLocation: _locateDevice,
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

  double? _distanceKm(Issue issue) {
    final c = _coords;
    if (c == null) return null;
    return haversineKm(
        c.latitude, c.longitude, issue.latitude, issue.longitude);
  }

  void _toggleExpand(String id) =>
      setState(() => _expandedId = _expandedId == id ? null : id);

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pendingVerify =
        _history.where((i) => i.status == 'PENDING_VERIFICATION').toList();
    final screenHeight = MediaQuery.sizeOf(context).height;

    final topInset = MediaQuery.of(context).padding.top;
    // App bar region: status bar + profile header (~78dp) + gap (8)
    // + ward pill (~34dp) + gap (6) = ~126dp total above the map.
    const _kAppBarBody = 78.0 + 8.0 + 34.0 + 6.0;
    final gradientHeight = topInset + _kAppBarBody;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F3FA),
        body: Stack(
          children: [
            // Gradient covers only the app bar region (ends at map top)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: gradientHeight,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF1A3A8F),
                      Color(0x001A3A8F),
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const ProfileHeader(),

                  // ── Ward info pill ──
                  _WardPill(locate: _locate, locating: _locating),

                  // ── Map section (floating card with margins) ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                    child: Container(
                      height: (screenHeight * 0.36).clamp(220.0, 360.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: MapCard(
                        center: _coords,
                        issues: _wardIssues,
                        selected: _selected,
                        onSelect: (i) => setState(() => _selected = i),
                        boundaries: _boundaries,
                        currentWard: _currentWard,
                        locate: _locate,
                        locating: _locating,
                        egmoreActive: _override != null,
                        onJumpEgmore: _jumpToEgmore,
                        onUpvote: _upvote,
                        showSearch: false,
                        showLocateChip: false,
                        borderRadius: 16,
                      ),
                    ),
                  ),

                  // ── Stats row ──
                  const _StatsRow(),

                  // ── Tab switcher (underline style) ──
                  _buildTabs(),

                  // Only the grievance list scrolls; pull-to-refresh is
                  // scoped here so the map and tabs stay pinned.
                  Expanded(
                    child: RefreshIndicator(
                      color: _kBlue,
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
                          const SizedBox(height: 8),
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

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          for (final (idx, icon, label) in [
            (0, Icons.groups_outlined, 'My Ward'),
            (1, Icons.description_outlined, 'My Reports'),
          ])
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _tab = idx);
                },
                child: Container(
                  padding: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _tab == idx ? _kBlue : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 16,
                          color: _tab == idx ? _kBlue : _kMuted),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              _tab == idx ? FontWeight.w700 : FontWeight.w500,
                          color: _tab == idx ? _kBlue : _kMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
            const Expanded(
              child: Text(
                'Public complaints in your ward',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _kDarkNavy,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                final w = _currentWard;
                if (w != null) _loadWard(w);
              },
              child: const Row(
                children: [
                  Icon(Icons.refresh, size: 14, color: _kBlue),
                  SizedBox(width: 4),
                  Text(
                    'Refresh',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_currentWard == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Locating your ward…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _kMuted),
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
                  style: const TextStyle(fontSize: 14, color: _kMuted),
                ),
              ],
            ),
          )
        else
          for (final issue in _wardIssues)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IssueCard(
                issue: issue,
                expanded: _expandedId == issue.id,
                onToggle: () => _toggleExpand(issue.id),
                distanceKm: _distanceKm(issue),
                onUpvote: _upvote,
                citizenHome: true,
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
                    const Icon(Icons.tune, size: 14, color: _kBlue),
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
                color: _kDarkNavy,
              ),
            ),
            GestureDetector(
              onTap: _loadHistory,
              child: const Row(
                children: [
                  Icon(Icons.refresh, size: 14, color: _kBlue),
                  SizedBox(width: 4),
                  Text(
                    'Refresh',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_histLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: _kBlue),
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
                  style: TextStyle(fontSize: 14, color: _kMuted),
                ),
              ],
            ),
          )
        else
          for (final issue in _history)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IssueCard(
                issue: issue,
                expanded: _expandedId == issue.id,
                onToggle: () => _toggleExpand(issue.id),
                distanceKm: _distanceKm(issue),
                citizenHome: true,
              ),
            ),
      ],
    );
  }
}

/// Horizontal stats row below the map: Reports, Upvotes, Resolved, Open.
class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          for (final (icon, value, label, iconColor, isLast) in [
            (Icons.assignment_outlined, '${ProfileData.reports}', 'Reports',
                const Color(0xFF3FA8A0), false),
            (Icons.thumb_up_outlined, '${ProfileData.upvotes}', 'Upvotes',
                const Color(0xFF2F9E6E), false),
            (Icons.check_circle_outline, '${ProfileData.resolved}', 'Resolved',
                const Color(0xFF2F9E6E), false),
            (Icons.schedule, '${ProfileData.open}', 'Open',
                const Color(0xFFFF9500), true),
          ]) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      height: 30,
                      width: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 16, color: iconColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _kDarkNavy,
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 11, color: _kMuted),
                    ),
                  ],
                ),
              ),
            ),
            if (!isLast) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

/// Compact pill above the map showing zone/ward info on one line.
class _WardPill extends StatelessWidget {
  const _WardPill({required this.locate, required this.locating});

  final LocateResult? locate;
  final bool locating;

  @override
  Widget build(BuildContext context) {
    final loc = locate;
    if (loc == null || locating || !loc.inside) {
      return const SizedBox(height: 8);
    }

    final zoneName = loc.zoneName != null ? titleCase(loc.zoneName!) : null;
    final ac = loc.constituencies.isEmpty ? null : shortAC(loc.constituencies.first);

    final parts = <String>[
      'Zone ${loc.zone}',
      if (zoneName != null) zoneName,
      'Ward ${loc.ward}',
      if (ac != null) ac,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F5F0),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0x1F1A2B46)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place, size: 14, color: _kBlue),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  parts.join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1A2A3A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
