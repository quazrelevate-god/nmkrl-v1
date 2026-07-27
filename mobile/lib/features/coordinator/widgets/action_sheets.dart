import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../domain/dept_routing.dart';
import '../../../domain/departments.dart';
import '../../../domain/geo_utils.dart';
import '../../../domain/models/issue.dart';
import '../../../domain/ticket.dart';
import '../../../state/providers.dart';
import 'evidence_section.dart';

/// The four coordinator action sheets — ports of ActionModals.js:
///   • EscalateSheet       reason (min 8 chars) + optional evidence
///   • TransferSheet       AI-routed dept dropdown + notes + evidence, then a
///                         WhatsApp-styled dispatch preview stage
///   • CloseSheet          MANDATORY live photo + voice note (+ notes)
///   • FalsePetitionSheet  reason dropdown (+ details, required for "Other")
///
/// Each resolves with the collected payload map, or null when dismissed.
Future<T?> _openActionSheet<T>(BuildContext context, Widget child) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.45),
    builder: (_) => child,
  );
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: NkColors.slate900.withValues(alpha: 0.35),
              blurRadius: 60,
              offset: const Offset(0, 24),
              spreadRadius: -16,
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: NkColors.slate300.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: NkColors.brand50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 20, color: NkColors.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: NkColors.slate900,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: NkColors.slate500),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 32,
                      width: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: NkColors.slate200.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 17, color: NkColors.slate500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared issue preview strip.
class _IssuePreview extends StatelessWidget {
  const _IssuePreview({required this.issue});

  final Issue issue;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NkColors.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NkColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            issue.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: NkColors.slate800,
            ),
          ),
          if (issue.areaName != null) ...[
            const SizedBox(height: 2),
            Text(
              issue.areaName!,
              style:
                  const TextStyle(fontSize: 12, color: NkColors.slate500),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              for (final chip in [
                '#${issue.id.length >= 8 ? issue.id.substring(0, 8) : issue.id}',
                if (issue.wardNo != null) 'Ward ${issue.wardNo}',
              ])
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    chip,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: NkColors.slate500,
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

InputDecoration _fieldDec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: NkColors.slate400),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NkColors.slate200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NkColors.brand, width: 1.6),
      ),
    );

Widget _fieldLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: NkColors.slate600,
        ),
      ),
    );

Widget _submitButton({
  required String label,
  required IconData icon,
  required Color color,
  required bool enabled,
  required VoidCallback onTap,
}) =>
    GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );

/* ══════════════════════ Escalate ══════════════════════ */

class EscalateSheet extends StatefulWidget {
  const EscalateSheet({super.key, required this.issue});

  final Issue issue;

  /// Resolves {description} or null.
  static Future<Map<String, dynamic>?> open(BuildContext context, Issue issue) =>
      _openActionSheet(context, EscalateSheet(issue: issue));

  @override
  State<EscalateSheet> createState() => _EscalateSheetState();
}

class _EscalateSheetState extends State<EscalateSheet> {
  final _description = TextEditingController();
  final _evidence = EvidenceController();

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
    _evidence.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    _evidence.dispose();
    super.dispose();
  }

  bool get _canSubmit => _description.text.trim().length >= 8;

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      icon: Icons.keyboard_double_arrow_up,
      title: 'Escalate Grievance',
      subtitle: 'Raise to a higher authority — stays In Progress',
      children: [
        _IssuePreview(issue: widget.issue),
        _fieldLabel('Reason for escalation *'),
        TextField(
          controller: _description,
          maxLines: 3,
          decoration: _fieldDec(
              'e.g. Beyond ward capacity — escalating to Public Works for structural action.'),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Minimum 8 characters',
              style: TextStyle(fontSize: 10, color: NkColors.slate400)),
        ),
        const SizedBox(height: 14),
        EvidenceSection(evidence: _evidence),
        const SizedBox(height: 14),
        _submitButton(
          label: 'Submit & Escalate',
          icon: Icons.keyboard_double_arrow_up,
          color: NkColors.slate800,
          enabled: _canSubmit,
          onTap: () => Navigator.of(context)
              .pop({'description': _description.text.trim()}),
        ),
      ],
    );
  }
}

/* ══════════════════════ Close (photo + voice mandatory) ══════════════════════ */

class CloseSheet extends StatefulWidget {
  const CloseSheet({super.key, required this.issue});

  final Issue issue;

  /// Resolves {notes} or null.
  static Future<Map<String, dynamic>?> open(BuildContext context, Issue issue) =>
      _openActionSheet(context, CloseSheet(issue: issue));

  @override
  State<CloseSheet> createState() => _CloseSheetState();
}

class _CloseSheetState extends State<CloseSheet> {
  final _notes = TextEditingController();
  final _evidence = EvidenceController();

  @override
  void initState() {
    super.initState();
    _evidence.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _notes.dispose();
    _evidence.dispose();
    super.dispose();
  }

  bool get _canSubmit => _evidence.hasPhoto && _evidence.hasVoice;

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      icon: Icons.check_circle_outline,
      title: 'Mark as Closed',
      subtitle: 'Live photo + voice note required to close',
      children: [
        _IssuePreview(issue: widget.issue),
        EvidenceSection(
            evidence: _evidence, label: 'Closure evidence (both required) *'),
        if (!_canSubmit)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${[
                if (!_evidence.hasPhoto) 'live photo',
                if (!_evidence.hasVoice) 'voice note',
              ].join(' + ')} still needed',
              style: const TextStyle(fontSize: 11, color: NkColors.amber700),
            ),
          ),
        const SizedBox(height: 14),
        _fieldLabel('Notes (optional)'),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: _fieldDec('Any additional context'),
        ),
        const SizedBox(height: 14),
        _submitButton(
          label: 'Submit & Notify Pending Verification',
          icon: Icons.check_circle_outline,
          color: NkColors.emerald600,
          enabled: _canSubmit,
          onTap: () =>
              Navigator.of(context).pop({'notes': _notes.text.trim()}),
        ),
      ],
    );
  }
}

/* ══════════════════════ Department Transfer ══════════════════════ */

/// Fetches the TN grievance-routing taxonomy from
/// GET /api/departments/tree at open, deterministically resolves this
/// grievance to (Government Department → Sub-Department → Responsible Officer),
/// and lets the coordinator override the dept before dispatching.
///
/// On "Send", the WhatsApp preview stage opens `https://web.whatsapp.com/send?text=…`
/// so the message drops straight into WhatsApp Web instead of just displaying
/// a fake bubble.
class TransferSheet extends ConsumerStatefulWidget {
  const TransferSheet({super.key, required this.issue, required this.onSubmit});

  final Issue issue;

  /// Called with `(governmentDepartment, notes, responsibleOfficer)` when
  /// the coordinator confirms the transfer. Parent posts to the backend.
  final Future<void> Function(String department, String notes, String officer) onSubmit;

  static Future<void> open(
    BuildContext context, {
    required Issue issue,
    required Future<void> Function(String department, String notes, String officer) onSubmit,
  }) =>
      _openActionSheet(
          context, TransferSheet(issue: issue, onSubmit: onSubmit));

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  Map<String, dynamic>? _tree; // {gov dept name → {type → {subtype → {sd, ro}}}}
  String? _loadError;

  String _department = '';
  String _officer = '';
  String _originalDept = '';
  final _notes = TextEditingController();
  final _evidence = EvidenceController();
  bool _dispatchStage = false;
  bool _dispatched = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _evidence.addListener(() => setState(() {}));
    _loadTaxonomy();
  }

  @override
  void dispose() {
    _notes.dispose();
    _evidence.dispose();
    super.dispose();
  }

  Future<void> _loadTaxonomy() async {
    try {
      final tree = await ref.read(apiClientProvider).fetchDepartmentsTree();
      final routing = resolveRouting(
        tree: tree,
        issueId: widget.issue.id,
        geminiDepartment: widget.issue.department,
      );
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _department = routing?.govDept ?? tree.keys.first;
        _originalDept = _department;
        _officer = routing?.officer ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Couldn\'t load department taxonomy — $e');
    }
  }

  RoutingResult? get _routing => _tree == null
      ? null
      : resolveRouting(
          tree: _tree!,
          issueId: widget.issue.id,
          geminiDepartment: _department == _originalDept
              ? widget.issue.department
              : _department,
        );

  String get _waMessage {
    final i = widget.issue;
    final r = _routing;
    final highlights = i.summaryHighlights.join(', ');
    final loc = i.areaName != null && i.areaName!.isNotEmpty
        ? '${i.areaName} (${i.latitude.toStringAsFixed(5)}, ${i.longitude.toStringAsFixed(5)})'
        : '${i.latitude.toStringAsFixed(5)}, ${i.longitude.toStringAsFixed(5)}';
    final note = _notes.text.trim().isEmpty
        ? ''
        : '\n\n*Coordinator note:* ${_notes.text.trim()}';
    return '🏛️ *நம் குரல் · Grievance Dispatch*\n\n'
        '*Ticket:* ${i.ticketNo ?? ticketNumber(i.id)}\n'
        '*Ward No:* ${i.wardNo ?? '—'}\n'
        '*Issue:* ${i.title}\n'
        '*Details:* ${i.transcript ?? (highlights.isEmpty ? '—' : highlights)}\n'
        '*Location:* $loc\n'
        '*Reported:* ${i.createdAt != null ? formatShortDate(i.createdAt!) : '—'}\n'
        '*Routed to:* $_department\n'
        '*Responsible officer:* ${r?.officer ?? _officer}${r?.subDept != null ? " · ${r!.subDept}" : ""}$note\n\n'
        'Kindly action this grievance at the earliest.';
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_department, _notes.text.trim(), _officer);
      if (mounted) setState(() => _dispatchStage = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWhatsAppWeb() async {
    HapticFeedback.mediumImpact();
    setState(() => _dispatched = true);
    final url = Uri.parse(
      'https://web.whatsapp.com/send?text=${Uri.encodeComponent(_waMessage)}',
    );
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* best-effort — the toast + dispatched state still show */
    }
  }

  @override
  Widget build(BuildContext context) {
    final overridden = _department.isNotEmpty && _department != _originalDept;
    final r = _routing;
    return _SheetShell(
      icon: Icons.send_outlined,
      title: 'Department Transfer',
      subtitle: _dispatchStage
          ? 'Sending via WhatsApp Web…'
          : 'AI routing → Responsible Officer',
      children: [
        _IssuePreview(issue: widget.issue),
        if (_loadError != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NkColors.rose50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_loadError!,
                style: const TextStyle(fontSize: 12, color: NkColors.rose600)),
          )
        else if (_tree == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: NkColors.brand),
              ),
            ),
          )
        else if (!_dispatchStage) ...[
          // AI ROUTING → RESPONSIBLE OFFICER panel (port of the /admin/routing UI)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NkColors.brand50.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NkColors.brand100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 11, color: NkColors.brand),
                    SizedBox(width: 6),
                    Text('AI ROUTING → RESPONSIBLE OFFICER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: NkColors.brand,
                        )),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_originalDept,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: NkColors.slate800,
                    )),
                if (r != null) ...[
                  const SizedBox(height: 4),
                  Text('${r.type} → ${r.subtype}',
                      style: const TextStyle(
                          fontSize: 11, color: NkColors.slate600)),
                  Text('Sub-department: ${r.subDept}',
                      style: const TextStyle(
                          fontSize: 11, color: NkColors.slate600)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person,
                            size: 11, color: NkColors.brand),
                        const SizedBox(width: 4),
                        Text(r.officer,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: NkColors.slate900,
                            )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.business, size: 13, color: NkColors.slate600),
              const SizedBox(width: 6),
              const Text('Route to Government Department',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: NkColors.slate600)),
              if (overridden) ...[
                const SizedBox(width: 6),
                const Text('· overridden',
                    style:
                        TextStyle(fontSize: 10, color: NkColors.amber600)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NkColors.slate200),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _department,
                isExpanded: true,
                borderRadius: BorderRadius.circular(14),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: NkColors.slate800),
                items: [
                  for (final d in govDepartments(_tree!))
                    DropdownMenuItem(
                      value: d,
                      child: Text(d,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
                onChanged: (v) => setState(() => _department = v ?? _department),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _fieldLabel('Notes (optional)'),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration:
                _fieldDec('Additional context for the receiving department'),
          ),
          const SizedBox(height: 14),
          EvidenceSection(evidence: _evidence),
          const SizedBox(height: 14),
          _busy
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: NkColors.brand),
                    ),
                  ),
                )
              : _submitButton(
                  label: 'Submit & Preview Dispatch',
                  icon: Icons.send,
                  color: NkColors.brand,
                  enabled: true,
                  onTap: _submit,
                ),
        ] else ...[
          // ── WhatsApp Web dispatch preview ──
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                Container(
                  color: const Color(0xFF075E54),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        height: 32,
                        width: 32,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFF25D366),
                          shape: BoxShape.circle,
                        ),
                        child: const Text('W',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            )),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_department,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                )),
                            Text('via WhatsApp Web',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: NkColors.emerald100.withValues(alpha: 0.9))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: const Color(0xFFECE5DD),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.72),
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFDCF8C6),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(12),
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          child: Text(_waMessage,
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                color: NkColors.slate800,
                              )),
                        ),
                      ),
                      if (_dispatched)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '✓ Opened in WhatsApp Web — send from the browser',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: NkColors.emerald700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: NkColors.slate100,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Templatised grievance dispatch ready…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: NkColors.slate400),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _dispatched ? null : _openWhatsAppWeb,
                        child: Container(
                          height: 36,
                          width: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366)
                                .withValues(alpha: _dispatched ? 0.6 : 1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _dispatched ? Icons.check : Icons.send,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _dispatchStage = false;
                    _dispatched = false;
                  }),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NkColors.slate300),
                    ),
                    child: const Text('Edit dispatch',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: NkColors.slate700)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NkColors.brand,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Done',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/* ══════════════════════ False Petition ══════════════════════ */

class FalsePetitionSheet extends StatefulWidget {
  const FalsePetitionSheet({super.key, required this.issue});

  final Issue issue;

  /// Resolves {reason, details} or null.
  static Future<Map<String, dynamic>?> open(BuildContext context, Issue issue) =>
      _openActionSheet(context, FalsePetitionSheet(issue: issue));

  @override
  State<FalsePetitionSheet> createState() => _FalsePetitionSheetState();
}

class _FalsePetitionSheetState extends State<FalsePetitionSheet> {
  String _reason = kFalseReasons.first;
  final _details = TextEditingController();
  final _evidence = EvidenceController();

  @override
  void initState() {
    super.initState();
    _details.addListener(() => setState(() {}));
    _evidence.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _details.dispose();
    _evidence.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _reason != 'Other' || _details.text.trim().length >= 6;

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      icon: Icons.block,
      title: 'Mark as False Petition',
      subtitle: 'Select a reason before flagging',
      children: [
        _IssuePreview(issue: widget.issue),
        _fieldLabel('Reason *'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NkColors.slate200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _reason,
              isExpanded: true,
              borderRadius: BorderRadius.circular(14),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: NkColors.slate800,
              ),
              items: [
                for (final r in kFalseReasons)
                  DropdownMenuItem(value: r, child: Text(r)),
              ],
              onChanged: (v) => setState(() => _reason = v ?? _reason),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _fieldLabel(
            'Additional details ${_reason == 'Other' ? '*' : '(optional)'}'),
        TextField(
          controller: _details,
          maxLines: 3,
          decoration: _fieldDec('Explain why this is a false petition'),
        ),
        const SizedBox(height: 14),
        EvidenceSection(evidence: _evidence),
        const SizedBox(height: 14),
        _submitButton(
          label: 'Submit & Flag as False',
          icon: Icons.block,
          color: NkColors.rose600,
          enabled: _canSubmit,
          onTap: () => Navigator.of(context).pop({
            'reason': _reason,
            'details': _details.text.trim(),
          }),
        ),
      ],
    );
  }
}
