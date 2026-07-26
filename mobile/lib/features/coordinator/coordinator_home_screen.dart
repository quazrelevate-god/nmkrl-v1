import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../domain/constituencies.dart';
import '../../domain/coordinator_data.dart';
import '../../domain/geo_utils.dart';
import '../../domain/models/boundary_data.dart';
import '../../domain/models/issue.dart';
import '../../state/providers.dart';
import '../home/widgets/issue_card.dart';
import '../home/widgets/map_card.dart';
import '../profile/profile_screen.dart';
import '../shared/wave_mark.dart';
import 'widgets/action_sheets.dart';

// ── Reskin palette (matching citizen home) ──────────────────────────────────
const _kBlue = Color(0xFF1A3A8F);
const _kDarkNavy = Color(0xFF1A2A4A);
const _kMuted = Color(0xFF7A8799);

class CoordinatorHomeScreen extends ConsumerStatefulWidget {
  const CoordinatorHomeScreen({super.key});

  @override
  ConsumerState<CoordinatorHomeScreen> createState() =>
      _CoordinatorHomeScreenState();
}

class _CoordinatorHomeScreenState extends ConsumerState<CoordinatorHomeScreen> {
  BoundaryData? _boundaries;
  List<Issue> _wardIssues = [];
  Issue? _selected;
  LatLng? _center;
  String? _error;
  String? _busyId;
  String? _toast;

  late String _constituency;
  late String _ward;
  int _tab = 0; // 0 ward · 1 mine · 2 escalated · 3 previous
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

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ── Actions (mirror the web handlers) ──────────────────────────────────

  Future<void> _assign(Issue issue) async {
    HapticFeedback.mediumImpact();
    setState(() => _busyId = issue.id);
    try {
      await ref.read(apiClientProvider).coordinatorVerify(issue.id);
      await ref.read(coordinatorStoreProvider).verify(_me.username, issue.id);
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

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final parts = partitionWardIssues(_wardIssues, _verifiedIds);
    final escalated =
        parts.mine.where((i) => _actionKinds[i.id] == 'escalate').toList();
    final myActive =
        parts.mine.where((i) => _actionKinds[i.id] != 'escalate').toList();

    final current = switch (_tab) {
      1 => myActive,
      2 => escalated,
      3 => parts.previous,
      _ => parts.ward,
    };

    final topInset = MediaQuery.of(context).padding.top;
    const kAppBarBody = 78.0 + 8.0 + 34.0 + 6.0;
    final gradientHeight = topInset + kAppBarBody;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F3FA),
        body: Stack(
          children: [
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
                    colors: [Color(0xFF1A3A8F), Color(0x001A3A8F)],
                  ),
                ),
              ),
            ),

            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(),

                  _CoordWardPill(ward: _ward, constituency: _constituency),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                    child: Container(
                      height: 260,
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
                        center: _center,
                        issues: current,
                        selected: _selected,
                        onSelect: (i) => setState(() => _selected = i),
                        boundaries: _boundaries,
                        currentWard: int.tryParse(_ward),
                        showLocateChip: false,
                        showSearch: false,
                        borderRadius: 16,
                      ),
                    ),
                  ),

                  _CoordStatsRow(me: _me),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildConstituencySelector(),
                        const SizedBox(height: 8),
                        _buildWardSelector(),
                      ],
                    ),
                  ),

                  _buildTabs(parts.ward.length, myActive.length,
                      escalated.length, parts.previous.length),

                  Expanded(
                    child: RefreshIndicator(
                      color: _kBlue,
                      onRefresh: () async {
                        await Future.wait([_loadBoundaries(), _loadWard()]);
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics()),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                          _buildList(current),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_toast != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 100,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    final firstName = me.name.split(' ').first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandMark(color: Colors.white),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: const Text(
                  'STAFF',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: Color(0xFFDDC689),
                  ),
                ),
              ),
              const Spacer(),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.notifications_outlined,
                      size: 24,
                      color: Colors.white.withValues(alpha: 0.9)),
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      height: 16,
                      width: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4D4D),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF1A3A8F), width: 1.5),
                      ),
                      child: const Text(
                        '3',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfileScreen(),
                    ),
                  );
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
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
                          color: const Color(0xFF1A3A8F),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(
                          me.initials,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFDDC689),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -1,
                      right: -1,
                      child: Container(
                        height: 12,
                        width: 12,
                        decoration: BoxDecoration(
                          color: NkColors.emerald500,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_greeting()}, $firstName',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
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
          const Icon(Icons.account_balance, size: 13, color: NkColors.slate500),
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
      int wardCount, int mineCount, int escalatedCount, int previousCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          for (final (idx, icon, label) in [
            (0, Icons.groups_outlined, 'Ward ($wardCount)'),
            (1, Icons.description_outlined, 'Mine ($mineCount)'),
            (2, Icons.keyboard_double_arrow_up, 'Escalated ($escalatedCount)'),
            (3, Icons.assignment_outlined, 'Previous ($previousCount)'),
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
                          size: 13,
                          color: _tab == idx ? _kBlue : _kMuted),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: _tab == idx
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _tab == idx ? _kBlue : _kMuted,
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
      'Escalated grievances',
      'Previous reports',
    ];
    final empties = [
      'No unverified grievances in Ward $_ward.',
      'Verify grievances from the ward tab to see them here.',
      'No escalated grievances yet.',
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
                  color: _kDarkNavy,
                ),
              ),
            ),
            GestureDetector(
              onTap: _loadWard,
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
        const SizedBox(height: 8),
        if (current.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(
                  switch (_tab) {
                    0 => Icons.groups_outlined,
                    1 => Icons.description_outlined,
                    2 => Icons.keyboard_double_arrow_up,
                    _ => Icons.assignment_outlined,
                  },
                  size: 32,
                  color: NkColors.slate300,
                ),
                const SizedBox(height: 8),
                Text(
                  empties[_tab],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: _kMuted),
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
                onToggle: () => setState(() =>
                    _expandedId = _expandedId == issue.id ? null : issue.id),
                distanceKm: _distanceKm(issue),
                badge: _tab != 0
                    ? _ActionStatusBadge(
                        kind: _actionKinds[issue.id], status: issue.status)
                    : null,
                actions: switch (_tab) {
                  0 => _wardActions(issue),
                  1 => _mineActions(issue),
                  2 => _mineActions(issue),
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

class _CoordWardPill extends StatelessWidget {
  const _CoordWardPill({required this.ward, required this.constituency});

  final String ward;
  final String constituency;

  @override
  Widget build(BuildContext context) {
    final ac = shortAC(constituency);
    final parts = <String>['Ward $ward', ac];

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

class _CoordStatsRow extends StatelessWidget {
  const _CoordStatsRow({required this.me});

  final Coordinator me;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          for (final (icon, value, label, iconColor, isLast) in [
            (Icons.star_outline, '${me.civicScore}', 'Civic Score',
                const Color(0xFFD97706), false),
            (Icons.assignment_outlined, '${me.reports}', 'Reports',
                const Color(0xFF3FA8A0), false),
            (Icons.check_circle_outline, '${me.resolved}', 'Resolved',
                const Color(0xFF2F9E6E), false),
            (Icons.schedule, me.tenure, 'Tenure',
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
