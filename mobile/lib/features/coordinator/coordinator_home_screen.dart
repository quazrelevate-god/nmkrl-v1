import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../domain/constituencies.dart';
import '../../domain/coordinator_data.dart';
import '../../domain/geo_utils.dart';
import '../../domain/models/boundary_data.dart';
import '../../domain/models/issue.dart';
import '../../state/providers.dart';
import '../home/widgets/issue_card.dart';
import '../home/widgets/map_card.dart';
import '../profile/profile_screen.dart';
import '../search/search_overlay.dart';
import '../shared/notification_banner.dart';
import '../shared/notification_bell.dart';
import 'widgets/action_sheets.dart';

/// Coordinator home — map-first treatment for staff:
///   full-bleed ward map under a frosted app bar + read-only constituency·ward
///   chip (both assigned in the admin console), Open | Assigned | Escalated |
///   Resolved tabs in a draggable sheet, sort dropdown (Recent | Priority),
///   in-app notification banner for new grievances in this ward.

/// Sheet snap fractions — same composition as the citizen home: the floor is
/// the landing size AND the minimum, sized to the pinned header plus ~2 cards.
const double _kSheetMid = 0.62;
const double _kSheetMax = 0.86;

/// Rough on-screen footprint of one grievance card, used to size the floor.
const double _kCardFootprint = 96;

/// Pinned grip + 4-segment tab block. grip 8+4+10, track ~49, trailing 12 ≈ 83;
/// held above that since the sliver extent is fixed and slack is invisible.
const double _kSheetHeaderHeight = 88;

/// The one corner radius in the composition — it belongs to the white sheet.
const double _kSheetCornerRadius = 22;

/// Height of the solid app bar's content, below the status-bar inset.
const double _kAppBarContentHeight = 62;

/// Rendered height of the ward chip — the status legend is lifted by this so
/// the chip can sit directly beneath it.
const double _kWardPillHeight = 38;

class CoordinatorHomeScreen extends ConsumerStatefulWidget {
  const CoordinatorHomeScreen({super.key});

  @override
  ConsumerState<CoordinatorHomeScreen> createState() =>
      _CoordinatorHomeScreenState();
}

class _CoordinatorHomeScreenState
    extends ConsumerState<CoordinatorHomeScreen> {
  BoundaryData? _boundaries;
  List<Issue> _wardIssues = [];
  Issue? _selected;
  final Map<String, GlobalKey> _cardKeys = {};
  LatLng? _center;
  String? _error;
  String? _busyId;
  String? _toast;

  late String _ward; // fixed to coord.homeWard — assigned in the admin console
  CoordinatorTab _tab = CoordinatorTab.ward;
  String? _expandedId;
  String _sort = 'recent'; // 'recent' | 'priority'

  final _sheetCtrl = DraggableScrollableController();

  /// Live sheet extent. A notifier, not setState state: only the map legend
  /// listens, so dragging never rebuilds the map underneath.
  final _sheetExtent = ValueNotifier<double>(0);

  /// Bounding box of the selected ward's polygon(s) — drives the map's camera
  /// lock, exactly as on the citizen home. Null until boundaries load.
  LatLngBounds? get _wardBounds {
    final b = _boundaries;
    if (b == null) return null;
    final pts = <LatLng>[];
    for (final f in b.wards) {
      if (f.ward != _ward) continue;
      for (final part in f.parts) {
        if (part.isNotEmpty) pts.addAll(part.first); // outer ring only
      }
    }
    if (pts.length < 3) return null;
    return LatLngBounds.fromPoints(pts);
  }

  /// Sheet floor: pinned header + ~2 cards, as a fraction of the parent height.
  double _sheetFloorFraction(double parentHeight) {
    const px = _kSheetHeaderHeight + 8 + 2 * _kCardFootprint;
    return (px / parentHeight).clamp(0.28, 0.5);
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
    return (math.min(zx, zy) - 0.15).clamp(1.0, 18.0);
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
    _ward = _me.homeWard;
    _loadBoundaries();
    _loadWard();
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    _sheetExtent.dispose();
    super.dispose();
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
    for (final f in feats) {
      if (f.ward == _ward) {
        setState(() => _center = f.centroid());
        return;
      }
    }
  }

  Future<void> _loadWard() async {
    final w = int.tryParse(_ward);
    if (w == null) return;
    try {
      final list = await ref.read(apiClientProvider).fetchCoordinatorWardIssues(
            w,
            coordinator: _me.username,
            sort: _sort,
          );
      if (!mounted) return;
      setState(() => _wardIssues = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
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
        final parts = partitionForCoordinator(_wardIssues, _me.username);
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
      await _loadWard();
    } catch (e) {
      setState(() => _error = '$e');
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
          );
      _showToast('Escalated · moved to Escalated tab');
      setState(() => _expandedId = null);
      await _loadWard();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _transfer(Issue issue) async {
    await TransferSheet.open(
      context,
      issue: issue,
      onSubmit: (department, notes, officer) async {
        await ref.read(apiClientProvider).coordinatorTransfer(
              issue.id,
              department,
              notes: notes,
              officer: officer,
            );
        _showToast('Transferred to $department');
        await _loadWard();
      },
    );
    setState(() => _expandedId = null);
  }

  Future<void> _close(Issue issue) async {
    final data = await CloseSheet.open(context, issue);
    if (data == null) return;
    setState(() => _busyId = issue.id);
    try {
      await ref
          .read(apiClientProvider)
          .coordinatorClose(issue.id, notes: '${data['notes'] ?? ''}');
      _showToast('Closed · awaiting citizen verification');
      setState(() => _expandedId = null);
      await _loadWard();
    } catch (e) {
      setState(() => _error = '$e');
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
          );
      _showToast('Flagged as false · moved to Previous Reports');
      setState(() => _expandedId = null);
      await _loadWard();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final parts = partitionForCoordinator(_wardIssues, _me.username);
    final current = switch (_tab) {
      CoordinatorTab.ward => parts.ward,
      CoordinatorTab.mine => parts.mine,
      CoordinatorTab.escalated => parts.escalated,
      CoordinatorTab.previous => parts.previous,
    };

    final topInset = MediaQuery.paddingOf(context).top;
    final screenH = MediaQuery.sizeOf(context).height;
    final sheetFloor = _sheetFloorFraction(screenH);

    // Lock the map to the selected ward, fitting it into the band that stays
    // visible above the sheet at its floor.
    final lockBounds = _wardBounds;
    final lockPadding = EdgeInsets.only(
      // Clear of the app bar and the ward chip parked beneath it.
      top: topInset + _kAppBarContentHeight + 48,
      bottom: sheetFloor * screenH + 16,
      left: 28,
      right: 28,
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
      // Dark glyphs — the pale basemap runs up under the status bar.
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
              ),
            ),

            // ── 2. Solid app bar, edge to edge across the top ──
            Positioned(
              key: const ValueKey('coord-appbar'),
              top: 0,
              left: 0,
              right: 0,
              child: _buildAppBar(),
            ),

            // ── 3. Constituency · ward chip, parked directly under the
            // status legend at the bottom-left of the map. ──
            Positioned(
              key: const ValueKey('coord-wardpill'),
              bottom: sheetFloor * screenH + 12,
              left: 14,
              child: _CoordWardPill(
                constituency: shortAC(_me.constituency),
                ward: _ward,
              ),
            ),

            // ── 3b. Status legend, bottom-left of the map. Fades out as the
            // sheet is pulled up and back in as it is pushed down; at zero
            // opacity it must not swallow map touches. ──
            ValueListenableBuilder<double>(
              valueListenable: _sheetExtent,
              builder: (context, extent, child) {
                final t = ((extent - sheetFloor) / (_kSheetMax - sheetFloor))
                    .clamp(0.0, 1.0);
                final opacity = 1.0 - t;
                return Positioned(
                  left: 14,
                  // Lifted to make room for the ward pill beneath it.
                  bottom: sheetFloor * screenH + 12 + _kWardPillHeight + 8,
                  child: IgnorePointer(
                    ignoring: opacity < 0.02,
                    child: Opacity(opacity: opacity, child: child),
                  ),
                );
              },
              child: const MapStatusLegend(),
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
                  return false;
                },
                child: DraggableScrollableSheet(
                controller: _sheetCtrl,
                initialChildSize: sheetFloor,
                minChildSize: sheetFloor,
                maxChildSize: _kSheetMax,
                snap: true,
                snapSizes: [sheetFloor, _kSheetMid, _kSheetMax],
                builder: (context, scrollController) => DecoratedBox(
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
                      // Rubber-band overscroll, matching the citizen sheet.
                      physics: const BouncingScrollPhysics(
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
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              if (_error != null)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: NkColors.rose50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(_error!,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: NkColors.rose600)),
                                      ),
                                      GestureDetector(
                                        onTap: () =>
                                            setState(() => _error = null),
                                        child: const Icon(Icons.close,
                                            size: 14,
                                            color: NkColors.rose600),
                                      ),
                                    ],
                                  ),
                                ),
                              _buildList(current),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                onNewGrievanceInMyWard: (_) {
                  _loadWard();
                },
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

  /// Solid app bar — a flat white surface running edge to edge under the
  /// status bar, with dark glyphs. Brand + STAFF badge on the left; search,
  /// notification bell and avatar on the right.
  Widget _buildAppBar() {
    final me = _me;
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, topInset + 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The light-surface cut of the wordmark — the navy-tuned
                // BrandLogo asset washes out on this white bar.
                Flexible(
                  child: SvgPicture.asset(
                    'assets/brand/நம்குரல் llight.svg',
                    height: 30,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    // Solid dark pill on the white bar, gold lettering.
                    color: NkColors.refBlueDeep,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('STAFF',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: NkColors.gold200,
                      )),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Replaces the old full-width map search bar — same overlay the
              // citizen home opens, scoped to this ward's feed.
              GestureDetector(
                onTap: () => SearchOverlay.open(
                  context,
                  issues: _wardIssues,
                ),
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(
                  height: 36,
                  width: 36,
                  child: Icon(Icons.search,
                      size: 22, color: NkColors.refBlueDeep),
                ),
              ),
              const SizedBox(width: 2),
              NotificationBell(
                recipientType: 'coordinator',
                recipientId: me.username,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfileScreen(),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    gradient: nkGoldGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    height: 34,
                    width: 34,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: NkColors.refBlue,
                      shape: BoxShape.circle,
                    ),
                    child: Text(me.initials,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: NkColors.gold300,
                        )),
                  ),
                ),
              ),
            ],
          ),
        ],
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
              child: Row(
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
                        onTap: () {
                          if (_tab == tab) return;
                          HapticFeedback.selectionClick();
                          setState(() => _tab = tab);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: NkMotion.settle,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color:
                                _tab == tab ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: _tab == tab
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.10),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
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
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildList(List<Issue> current) {
    final headings = [
      '${context.tr('Open grievances in Ward')} $_ward',
      context.tr('Assigned to me'),
      context.tr('Escalated grievances'),
      context.tr('Resolved & closed'),
    ];
    final empties = [
      'No unverified grievances in Ward $_ward.',
      'Verify grievances from the ward tab to see them here.',
      'Escalated grievances land here until resolved.',
      'Closed grievances and false petitions land here.',
    ];
    final idx = _tab.index;

    return Column(
      key: ValueKey('tab-$idx-sort-$_sort'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                _loadWard();
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
        if (current.isEmpty)
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
          )
        else
          for (final issue in current)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _selectableCard(
                issue,
                IssueCard(
                  issue: issue,
                  expanded: _expandedId == issue.id,
                  onToggle: () => setState(() =>
                      _expandedId = _expandedId == issue.id ? null : issue.id),
                  distanceKm: _distanceKm(issue),
                  badge: _tab != CoordinatorTab.ward
                      ? _ActionStatusBadge(
                          status: issue.status,
                          rejected: issue.rejectedAt != null)
                      : null,
                  actions: switch (_tab) {
                    CoordinatorTab.ward => _wardActions(issue),
                    CoordinatorTab.mine => _mineActions(issue),
                    CoordinatorTab.escalated => _escalatedActions(issue),
                    CoordinatorTab.previous => const SizedBox.shrink(),
                  },
                ),
              ),
            ),
      ],
    );
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
            _loadWard();
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
