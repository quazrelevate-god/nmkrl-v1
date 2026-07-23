import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/glass.dart';
import '../../core/theme.dart';
import '../../domain/constituencies.dart';
import '../../domain/coordinator_data.dart';
import '../../domain/geo_utils.dart';
import '../../domain/models/boundary_data.dart';
import '../../domain/models/issue.dart';
import '../../state/providers.dart';
import '../home/widgets/issue_card.dart';
import '../home/widgets/map_card.dart';
import '../shared/wave_mark.dart';
import 'widgets/action_sheets.dart';
import 'widgets/post_composer.dart';

/// Coordinator home — the same single-page treatment as the citizen app, but
/// for staff (port of /coordinator/grievance): glass header + profile,
/// constituency + ward selectors, the ward map, three tabs (Ward / My
/// Reports / Previous) with per-status action buttons, and a "+" that opens
/// the post/poll composer.
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
  LatLng? _center;
  String? _error;
  String? _busyId;
  String? _toast;

  bool _profileOpen = false;
  late String _constituency;
  late String _ward;
  int _tab = 0; // 0 ward · 1 mine · 2 previous
  String? _expandedId;
  Set<String> _verifiedIds = {};
  Map<String, String> _actionKinds = {};

  Coordinator get _me =>
      ref.read(coordinatorAuthProvider) ?? kCoordinators.first;

  @override
  void initState() {
    super.initState();
    _constituency = _me.constituency;
    _ward = _me.homeWard;
    _refreshLocalState();
    _loadBoundaries();
    _loadWard();
  }

  void _refreshLocalState() {
    final store = ref.read(coordinatorStoreProvider);
    _verifiedIds = store.verifiedIds(_me.username);
    _actionKinds = store.latestActionKindByIssue();
  }

  List<String> get _wardsInConstituency {
    final list = List<String>.from(kChennaiAcMap[_constituency] ?? []);
    list.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    return list;
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
      final list =
          await ref.read(apiClientProvider).fetchCoordinatorWardIssues(w);
      if (!mounted) return;
      setState(() {
        _wardIssues = list;
        _refreshLocalState();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _selectWard(String w) {
    setState(() {
      _ward = w;
      _selected = null;
      _expandedId = null;
    });
    _recenter();
    _loadWard();
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

  // ── Actions (mirror the web handlers) ──────────────────────────────────

  Future<void> _assign(Issue issue) async {
    HapticFeedback.mediumImpact();
    setState(() => _busyId = issue.id);
    try {
      await ref.read(apiClientProvider).coordinatorVerify(issue.id);
      await ref
          .read(coordinatorStoreProvider)
          .verify(_me.username, issue.id);
      _showToast(
          'Assigned · ${issue.title.substring(0, issue.title.length.clamp(0, 30))} moved to My Reports');
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
    // Web parity: escalation moves the ticket forward LOCALLY so it stays in
    // My Reports as In Progress (never reverts to pending or vanishes).
    await ref.read(coordinatorStoreProvider).addAction(
          coordinator: _me.username,
          issueId: issue.id,
          kind: 'escalate',
          data: data,
        );
    setState(() {
      _wardIssues = [
        for (final i in _wardIssues)
          i.id == issue.id
              ? Issue.fromJson({
                  'id': i.id,
                  'title': i.title,
                  'image_url': i.imageUrl,
                  'audio_url': i.audioUrl,
                  'transcript': i.transcript,
                  'latitude': i.latitude,
                  'longitude': i.longitude,
                  'status': 'IN_PROGRESS',
                  'upvotes': i.upvotes,
                  'created_at': i.createdAt?.toIso8601String(),
                  'area_name': i.areaName,
                  'ward_no': i.wardNo,
                  'zone': i.zone,
                  'department': i.department,
                  'coordinator_message': i.coordinatorMessage,
                  'summary_highlights': i.summaryHighlights,
                })
              : i
      ];
      _refreshLocalState();
      _expandedId = null;
    });
    _showToast('Escalated · now In Progress');
  }

  Future<void> _transfer(Issue issue) async {
    await TransferSheet.open(
      context,
      issue: issue,
      onSubmit: (department, notes) async {
        await ref
            .read(apiClientProvider)
            .coordinatorTransfer(issue.id, department, notes: notes);
        await ref.read(coordinatorStoreProvider).addAction(
              coordinator: _me.username,
              issueId: issue.id,
              kind: 'transfer',
              data: {'department': department, 'notes': notes},
            );
        _showToast('Transferred to department');
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
      await ref.read(coordinatorStoreProvider).addAction(
            coordinator: _me.username,
            issueId: issue.id,
            kind: 'close',
            data: data,
          );
      _showToast('Closed · citizen must verify to move to Previous Reports');
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
          );
      final store = ref.read(coordinatorStoreProvider);
      // Terminal state → lands in Previous Reports (needs ownership record).
      await store.verify(_me.username, issue.id);
      await store.addAction(
        coordinator: _me.username,
        issueId: issue.id,
        kind: 'false',
        data: data,
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

  Future<void> _openComposer() async {
    final published = await PostComposer.open(context, _me);
    if (published == true) {
      _showToast('Submitted for admin review · pending');
    }
  }

  Future<void> _signOut() async {
    await ref.read(coordinatorAuthProvider.notifier).signOut();
    if (mounted) context.go('/login');
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final parts = partitionWardIssues(_wardIssues, _verifiedIds);
    final current = switch (_tab) {
      1 => parts.mine,
      2 => parts.previous,
      _ => parts.ward,
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFFBFCFD),
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: NkColors.brand,
                onRefresh: () async {
                  await Future.wait([_loadBoundaries(), _loadWard()]);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    _buildHeader(),

                    // ── Map ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Ward grievance map',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: NkColors.slate900,
                                  ),
                                ),
                                Text(
                                  'Ward $_ward',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: NkColors.slate400),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 260,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: MapCard(
                              center: _center,
                              issues: current,
                              selected: _selected,
                              onSelect: (i) =>
                                  setState(() => _selected = i),
                              boundaries: _boundaries,
                              currentWard: int.tryParse(_ward),
                              showLocateChip: false,
                              searchHint: 'Search grievances in this ward',
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Selectors + tabs + lists ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildConstituencySelector(),
                          const SizedBox(height: 8),
                          _buildWardSelector(),
                          const SizedBox(height: 12),
                          _buildTabs(parts),
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
                                    onTap: () =>
                                        setState(() => _error = null),
                                    child: const Icon(Icons.close,
                                        size: 14, color: NkColors.rose600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _buildList(current),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── "+" composer button ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: GestureDetector(
                  onTap: _openComposer,
                  child: Container(
                    height: 64,
                    width: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [NkColors.slate800, NkColors.brandDark],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: NkColors.gold300.withValues(alpha: 0.5)),
                      boxShadow: [
                        BoxShadow(
                          color:
                              NkColors.brandDark.withValues(alpha: 0.45),
                          blurRadius: 40,
                          offset: const Offset(0, 12),
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add,
                        size: 32, color: NkColors.gold200),
                  ),
                ),
              ),
            ),

            // ── Toast ──
            if (_toast != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 100,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: NkColors.slate900.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _toast!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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

  Widget _buildHeader() {
    final me = _me;
    return GlassContainer(
      variant: Glass.clear,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      boxShadow: [
        BoxShadow(
          color: NkColors.slate900.withValues(alpha: 0.25),
          blurRadius: 36,
          offset: const Offset(0, 16),
          spreadRadius: -22,
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const BrandMark(),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: NkColors.brandDark,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'STAFF',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: NkColors.gold200,
                        ),
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _profileOpen = !_profileOpen);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      gradient: nkGoldGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      height: 36,
                      width: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: NkColors.brandDark,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        me.initials,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: NkColors.gold200,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expandable coordinator profile
          AnimatedSize(
            duration: const Duration(milliseconds: 420),
            curve: NkMotion.settle,
            alignment: Alignment.topCenter,
            child: !_profileOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                gradient: nkGoldGradient,
                                shape: BoxShape.circle,
                              ),
                              child: Container(
                                height: 52,
                                width: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: NkColors.brandDark,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                ),
                                child: Text(
                                  me.initials,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: NkColors.gold200,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    me.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: NkColors.slate900,
                                    ),
                                  ),
                                  Text(
                                    '${me.role} · ${shortAC(me.constituency)} · Ward ${me.homeWard}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: NkColors.slate500),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _profileOpen = false),
                              icon: const Icon(Icons.keyboard_arrow_up,
                                  size: 20, color: NkColors.slate400),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            for (final (value, label) in [
                              ('${me.civicScore}', 'Civic Score'),
                              ('${me.reports}', 'Reports'),
                              ('${me.resolved}', 'Resolved'),
                              (me.tenure, 'Tenure'),
                            ]) ...[
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    border: Border.all(
                                        color: NkColors.slate200
                                            .withValues(alpha: 0.7)),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        value,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: NkColors.slate800,
                                        ),
                                      ),
                                      Text(
                                        label,
                                        style: const TextStyle(
                                            fontSize: 9,
                                            color: NkColors.slate500),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (label != 'Tenure')
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _signOut,
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: NkColors.slate200),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.logout,
                                    size: 13, color: NkColors.slate600),
                                SizedBox(width: 6),
                                Text(
                                  'Sign out',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: NkColors.slate600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConstituencySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 44,
      decoration: BoxDecoration(
        color: NkColors.slate100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NkColors.slate200),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance,
              size: 13, color: NkColors.slate500),
          const SizedBox(width: 6),
          const Text(
            'CONSTITUENCY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: NkColors.slate500,
            ),
          ),
          const Spacer(),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _constituency,
              isDense: true,
              borderRadius: BorderRadius.circular(14),
              icon: const Icon(Icons.keyboard_arrow_down,
                  size: 14, color: NkColors.slate400),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: NkColors.slate500,
              ),
              items: [
                for (final c in kConstituencies)
                  DropdownMenuItem(value: c, child: Text(shortAC(c))),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _constituency = v);
                final wards = _wardsInConstituency;
                if (!wards.contains(_ward) && wards.isNotEmpty) {
                  _selectWard(wards.first);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWardSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4, left: 2),
          child: Text(
            'WARD',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: NkColors.slate400,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NkColors.slate200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _wardsInConstituency.contains(_ward)
                  ? _ward
                  : (_wardsInConstituency.isEmpty
                      ? null
                      : _wardsInConstituency.first),
              isExpanded: true,
              borderRadius: BorderRadius.circular(14),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: NkColors.slate800,
              ),
              items: [
                for (final w in _wardsInConstituency)
                  DropdownMenuItem(value: w, child: Text('Ward $w')),
              ],
              onChanged: (v) {
                if (v != null) _selectWard(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabs(
      ({List<Issue> ward, List<Issue> mine, List<Issue> previous}) parts) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NkColors.slate200.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (idx, icon, label) in [
            (0, Icons.groups_outlined, 'Ward (${parts.ward.length})'),
            (1, Icons.description_outlined, 'My Reports (${parts.mine.length})'),
            (2, Icons.assignment_outlined, 'Previous (${parts.previous.length})'),
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _tab == idx ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _tab == idx
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
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
                          size: 12,
                          color: _tab == idx
                              ? NkColors.slate900
                              : NkColors.slate500),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _tab == idx
                                ? NkColors.slate900
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
    );
  }

  Widget _buildList(List<Issue> current) {
    final headings = [
      'Public grievances in Ward $_ward',
      'Verified by me',
      'Previous reports',
    ];
    final empties = [
      'No unverified grievances in Ward $_ward.',
      'Verify grievances from the ward tab to see them here.',
      'Closed grievances and false petitions land here.',
    ];

    return Column(
      key: ValueKey('tab-$_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                headings[_tab],
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: NkColors.slate900,
                ),
              ),
            ),
            GestureDetector(
              onTap: _loadWard,
              child: const Row(
                children: [
                  Icon(Icons.refresh, size: 12, color: NkColors.brand),
                  SizedBox(width: 4),
                  Text(
                    'Refresh',
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
        if (current.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(
                  _tab == 0
                      ? Icons.groups_outlined
                      : _tab == 1
                          ? Icons.description_outlined
                          : Icons.assignment_outlined,
                  size: 32,
                  color: NkColors.slate300,
                ),
                const SizedBox(height: 8),
                Text(
                  empties[_tab],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: NkColors.slate400),
                ),
              ],
            ),
          )
        else
          for (final issue in current)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: IssueCard(
                issue: issue,
                expanded: _expandedId == issue.id,
                onToggle: () => setState(
                    () => _expandedId = _expandedId == issue.id ? null : issue.id),
                distanceKm: _distanceKm(issue),
                badge: _tab != 0
                    ? _ActionStatusBadge(
                        kind: _actionKinds[issue.id], status: issue.status)
                    : null,
                actions: switch (_tab) {
                  0 => _wardActions(issue),
                  1 => _mineActions(issue),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
      ],
    );
  }

  Widget _wardActions(Issue issue) {
    final busy = _busyId == issue.id;
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: busy ? 'Assigning…' : 'Assign Grievance',
            icon: Icons.verified_user_outlined,
            bg: NkColors.brand,
            fg: Colors.white,
            onTap: busy ? null : () => _assign(issue),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            label: 'False Petition',
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
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionButton(
                label: 'Dept. Transfer',
                icon: Icons.send_outlined,
                bg: NkColors.brand,
                fg: Colors.white,
                onTap: () => _transfer(issue),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                label: 'Escalate',
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
          label: 'Close',
          icon: Icons.check_circle_outline,
          bg: NkColors.emerald600,
          fg: Colors.white,
          onTap: () => _close(issue),
        ),
      ],
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
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Port of ActionStatusBadge — the latest coordinator action or terminal
/// status on My Reports / Previous cards.
class _ActionStatusBadge extends StatelessWidget {
  const _ActionStatusBadge({required this.kind, required this.status});

  final String? kind;
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch ((status, kind)) {
      ('CLOSED', _) => (
          'Citizen approved · Closed',
          NkColors.emerald50,
          NkColors.emerald700
        ),
      ('FALSE', _) => ('False Petition', NkColors.rose50, NkColors.rose700),
      (_, 'escalate') => (
          'Escalated · In Progress',
          NkColors.sky50,
          NkColors.sky700
        ),
      (_, 'transfer') => (
          'Transferred · In Progress',
          NkColors.sky50,
          NkColors.sky700
        ),
      (_, 'close') => (
          'Awaiting citizen verify',
          NkColors.amber50,
          NkColors.amber700
        ),
      (_, 'false') => ('False Petition', NkColors.rose50, NkColors.rose700),
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
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
