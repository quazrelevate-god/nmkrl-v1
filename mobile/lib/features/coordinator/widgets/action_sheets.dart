import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/glass.dart';
import '../../../core/theme.dart';
import '../../../domain/departments.dart';
import '../../../domain/geo_utils.dart';
import '../../../domain/models/issue.dart';
import '../../../domain/ticket.dart';
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
      child: GlassContainer(
        variant: Glass.strong,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: NkColors.slate900.withValues(alpha: 0.55),
            blurRadius: 80,
            offset: const Offset(0, 30),
            spreadRadius: -20,
          ),
        ],
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 32,
                    width: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NkColors.brand50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: NkColors.brand.withValues(alpha: 0.2)),
                    ),
                    child: Icon(icon, size: 16, color: NkColors.brand),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
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
                    child: const Icon(Icons.close,
                        size: 18, color: NkColors.slate400),
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
        borderRadius: BorderRadius.circular(12),
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
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: NkColors.slate200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
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
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
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

class TransferSheet extends StatefulWidget {
  const TransferSheet({super.key, required this.issue, required this.onSubmit});

  final Issue issue;

  /// Fired when the coordinator submits the form; the sheet then shows the
  /// WhatsApp dispatch stage (mirrors the web two-stage flow).
  final Future<void> Function(String department, String notes) onSubmit;

  static Future<void> open(
    BuildContext context, {
    required Issue issue,
    required Future<void> Function(String department, String notes) onSubmit,
  }) =>
      _openActionSheet(
          context, TransferSheet(issue: issue, onSubmit: onSubmit));

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  late String _department;
  late final String _aiSuggested;
  final _notes = TextEditingController();
  final _evidence = EvidenceController();
  bool _dispatchStage = false;
  bool _dispatched = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _aiSuggested = kDepartments.containsKey(widget.issue.department)
        ? widget.issue.department!
        : kDepartments.keys.first;
    _department = _aiSuggested;
    _evidence.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _notes.dispose();
    _evidence.dispose();
    super.dispose();
  }

  String get _waMessage {
    final i = widget.issue;
    final highlights = i.summaryHighlights.join(', ');
    final deadline = formatShortDate(slaDeadline(i.createdAt, _department));
    final loc = i.areaName != null
        ? '${i.areaName} (${i.latitude.toStringAsFixed(5)}, ${i.longitude.toStringAsFixed(5)})'
        : '${i.latitude.toStringAsFixed(5)}, ${i.longitude.toStringAsFixed(5)}';
    final note =
        _notes.text.trim().isEmpty ? '' : '\n\n*Coordinator note:* ${_notes.text.trim()}';
    return '🏛️ *FixMyStreet Grievance Dispatch*\n\n'
        '*Ticket:* ${ticketNumber(i.id)}\n'
        '*Ward No:* ${i.wardNo ?? '—'}\n'
        '*Issue:* ${i.title}\n'
        '*Details:* ${i.transcript ?? (highlights.isEmpty ? '—' : highlights)}\n'
        '*Location:* $loc\n'
        '*Reported:* ${i.createdAt != null ? formatShortDate(i.createdAt!) : '—'}\n'
        '*SLA Deadline:* $deadline$note\n\n'
        'Kindly action this grievance before the SLA deadline.';
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_department, _notes.text.trim());
      if (mounted) setState(() => _dispatchStage = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = departmentMeta(_department);
    final overridden = _department != _aiSuggested;

    return _SheetShell(
      icon: Icons.send_outlined,
      title: 'Department Transfer',
      subtitle: _dispatchStage
          ? 'WhatsApp dispatch to the department'
          : 'AI-detected route — change if needed',
      children: [
        _IssuePreview(issue: widget.issue),
        if (!_dispatchStage) ...[
          // AI suggestion banner
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
                    Text(
                      'AI ROUTED TO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: NkColors.brand,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _aiSuggested,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: NkColors.slate800,
                  ),
                ),
                Text(
                  'SLA · ${departmentMeta(_aiSuggested).slaDays} days',
                  style: const TextStyle(
                      fontSize: 10, color: NkColors.slate500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.business, size: 13, color: NkColors.slate600),
              const SizedBox(width: 6),
              const Text(
                'Route to department',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: NkColors.slate600,
                ),
              ),
              if (overridden) ...[
                const SizedBox(width: 6),
                const Text(
                  '· overridden',
                  style: TextStyle(fontSize: 10, color: NkColors.amber600),
                ),
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
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: NkColors.slate800,
                ),
                items: [
                  for (final d in kDepartments.keys)
                    DropdownMenuItem(
                      value: d,
                      child: Text('${departmentMeta(d).short} · $d',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _department = v ?? _department),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'SLA · ${meta.slaDays} days · ${meta.phone}',
              style: const TextStyle(fontSize: 10, color: NkColors.slate500),
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
          // ── WhatsApp dispatch preview ──
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                Container(
                  color: const Color(0xFF075E54),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        child: const Text(
                          'W',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${meta.short} Dept.',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            meta.phone,
                            style: const TextStyle(
                                fontSize: 10, color: NkColors.emerald100),
                          ),
                        ],
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
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.72),
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFDCF8C6),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(12),
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          child: Text(
                            _waMessage,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: NkColors.slate800,
                            ),
                          ),
                        ),
                      ),
                      if (_dispatched)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '✓ Message queued for the department (demo)',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        onTap: _dispatched
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                setState(() => _dispatched = true);
                              },
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
                  onTap: () => setState(() => _dispatchStage = false),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NkColors.slate300),
                    ),
                    child: const Text(
                      'Edit dispatch',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: NkColors.slate700,
                      ),
                    ),
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
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
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
