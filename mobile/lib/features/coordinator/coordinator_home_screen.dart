import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/glass.dart';
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
import '../shared/notification_banner.dart';
import '../shared/notification_bell.dart';
import '../shared/wave_mark.dart';
import 'widgets/action_sheets.dart';

/// Coordinator home — single-page treatment for staff:
///   glass header + expandable profile (fixed constituency, ward switcher),
///   Ward | My Reports | Escalated | Previous tabs,
///   sort dropdown (Recent | Priority), per-ward assigned counts,
///   in-app notification banner for new grievances in this ward.
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
  List<Issue> _mineAllWards = [];
  Issue? _selected;
  final Map<String, GlobalKey> _cardKeys = {};
  LatLng? _center;
  String? _error;
  String? _busyId;
  String? _toast;

  late String _ward; // starts at coord.homeWard, user can switch within AC
  CoordinatorTab _tab = CoordinatorTab.ward;
  String? _expandedId;
  String _sort = 'recent'; // 'recent' | 'priority'

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
    _loadMine();
  }

  List<String> get _wardsInConstituency {
    final list = List<String>.from(kChennaiAcMap[_me.constituency] ?? []);
    list.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    return list;
  }

  /// per-ward count of grievances the signed-in coordinator has taken
  /// ownership of (mine + escalated + previous — anything with our username).
  Map<String, int> get _mineCountByWard {
    final m = <String, int>{};
    for (final i in _mineAllWards) {
      if (i.wardNo == null) continue;
      final w = '${i.wardNo}';
      m[w] = (m[w] ?? 0) + 1;
    }
    return m;
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

  Future<void> _loadMine() async {
    try {
      final list = await ref
          .read(apiClientProvider)
          .fetchCoordinatorMine(_me.username);
      if (!mounted) return;
      setState(() => _mineAllWards = list);
    } catch (_) {}
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
      await _loadMine();
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
      await _loadMine();
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
        await _loadMine();
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
      await _loadMine();
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
      await _loadMine();
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
                  await Future.wait([_loadBoundaries(), _loadWard(), _loadMine()]);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    _buildHeader(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(context.tr('Ward grievance map'),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                      color: NkColors.slate900,
                                    )),
                                Text('Ward $_ward',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: NkColors.slate400)),
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
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: MapCard(
                              center: _center,
                              issues: current,
                              selected: _selected,
                              onSelect: _onMapSelect,
                              boundaries: _boundaries,
                              currentWard: int.tryParse(_ward),
                              showLocateChip: false,
                              searchHint: context.tr('Search grievances in this ward'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildConstituencyChip(),
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
                                    child: Text(_error!,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: NkColors.rose600)),
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

            // Floating notification banner — polls /api/notifications every
            // 15s while this screen is foregrounded.
            Positioned(
              top: 0, left: 0, right: 0,
              child: NotificationPoller(
                recipientType: 'coordinator',
                recipientId: _me.username,
                onNewGrievanceInMyWard: (_) {
                  _loadWard();
                  _loadMine();
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
                      child: const Text('STAFF',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: NkColors.gold200,
                          )),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const LangToggle(),
                    const SizedBox(width: 6),
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
                          height: 36, width: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: NkColors.brandDark,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Text(me.initials,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: NkColors.gold200,
                              )),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Constituency is a fixed chip — no dropdown (assigned in admin console).
  Widget _buildConstituencyChip() {
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
          Text(context.tr('CONSTITUENCY'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: NkColors.slate500,
              )),
          const Spacer(),
          Text(shortAC(_me.constituency),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: NkColors.slate700,
              )),
          const SizedBox(width: 6),
          const Icon(Icons.lock_outline,
              size: 11, color: NkColors.slate400),
        ],
      ),
    );
  }

  Widget _buildWardSelector() {
    final counts = _mineCountByWard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 4, left: 2),
          child: Text(context.tr('WARD'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: NkColors.slate400,
              )),
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
                  DropdownMenuItem(
                    value: w,
                    child: Row(
                      children: [
                        Text('Ward $w'),
                        if ((counts[w] ?? 0) > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: NkColors.brand50,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: NkColors.brand100),
                            ),
                            child: Text(
                              '${counts[w]} assigned',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: NkColors.brand,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
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
      ({List<Issue> ward, List<Issue> mine, List<Issue> escalated, List<Issue> previous}) parts) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NkColors.slate200.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (tab, icon, label) in [
            (CoordinatorTab.ward,
                Icons.groups_outlined, '${context.tr('Open')} (${parts.ward.length})'),
            (CoordinatorTab.mine,
                Icons.description_outlined, '${context.tr('Assigned')} (${parts.mine.length})'),
            (CoordinatorTab.escalated,
                Icons.keyboard_double_arrow_up,
                '${context.tr('Escalated')} (${parts.escalated.length})'),
            (CoordinatorTab.previous,
                Icons.assignment_outlined,
                '${context.tr('Resolved')} (${parts.previous.length})'),
          ])
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _tab = tab);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: NkMotion.settle,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _tab == tab ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _tab == tab
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Icon(icon,
                          size: 12,
                          color: _tab == tab
                              ? NkColors.slate900
                              : NkColors.slate500),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _tab == tab
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
                _loadMine();
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
