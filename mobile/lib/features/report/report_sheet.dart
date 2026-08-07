import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../data/media.dart';
import '../../domain/daily_limit.dart';
import '../../domain/models/issue.dart';
import '../../domain/ticket.dart';
import '../../state/providers.dart';
import '../shared/status_chip.dart';
import 'widgets/success_overlay.dart';
import 'widgets/swipe_to_confirm.dart';
import 'widgets/voice_recorder.dart';

const _kDailyMax = 1;

/// Upload tiles are a FIXED height so the sheet never reflows when a photo is
/// added or audio is recorded — only the tile's inner content changes.
const double _kTileHeight = 82;

/// "Report Street Issue" floating glass sheet (port of ReportModal.js):
/// location card, camera + voice capture side by side, fair-use banner and
/// the swipe-to-submit control. Handles the backend's duplicate check with a
/// confirm sheet (upvote instead / submit anyway).
class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({
    super.key,
    required this.coords,
    required this.areaName,
    required this.geoStatus,
    required this.accuracy,
    required this.onRefreshLocation,
    required this.onSubmitted,
    required this.onUpvoteExisting,
  });

  final LatLng? coords;
  final String areaName;

  /// 'ready' | 'loading' | 'fallback'
  final String geoStatus;
  final double? accuracy;
  final VoidCallback onRefreshLocation;
  final VoidCallback onSubmitted;
  final Future<void> Function(Issue existing) onUpvoteExisting;

  static Future<void> open(
    BuildContext context, {
    required LatLng? coords,
    required String areaName,
    required String geoStatus,
    required double? accuracy,
    required VoidCallback onRefreshLocation,
    required VoidCallback onSubmitted,
    required Future<void> Function(Issue existing) onUpvoteExisting,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.45),
      builder: (_) => ReportSheet(
        coords: coords,
        areaName: areaName,
        geoStatus: geoStatus,
        accuracy: accuracy,
        onRefreshLocation: onRefreshLocation,
        onSubmitted: onSubmitted,
        onUpvoteExisting: onUpvoteExisting,
      ),
    );
  }

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  final _picker = ImagePicker();
  final _recorder = VoiceRecorderController();
  final List<XFile> _images = [];

  bool _submitting = false;
  String? _error;
  int _resetToken = 0;

  @override
  void initState() {
    super.initState();
    _recorder.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    HapticFeedback.selectionClick();
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (shot != null) setState(() => _images.add(shot));
    } catch (_) {
      setState(() => _error =
          'Camera unavailable. Check the camera permission and try again.');
    }
  }

  void _bumpReset() => setState(() => _resetToken++);

  /// Both attachments are mandatory — see the guard in [_submit].
  bool get _canSubmit => _images.isNotEmpty && _recorder.file != null;

  Future<void> _submit({bool force = false}) async {
    setState(() => _error = null);
    final coords = widget.coords;
    // Fair-use counter is display-only for the demo — never blocks submission.
    if (coords == null) {
      setState(() => _error = 'Waiting for your location…');
      _bumpReset();
      return;
    }
    // BOTH are required: the photo is the evidence a coordinator triages on,
    // the voice note is the citizen's account of it. One without the other has
    // repeatedly produced grievances that cannot be acted on.
    final noPhoto = _images.isEmpty;
    final noVoice = _recorder.file == null;
    if (noPhoto || noVoice) {
      setState(() => _error = context.tr(
            noPhoto && noVoice
                ? 'Add both a photo and a voice note to submit.'
                : noPhoto
                    ? 'Add a photo — a voice note alone is not enough.'
                    : 'Record a voice note — a photo alone is not enough.',
          ));
      _bumpReset();
      return;
    }

    setState(() => _submitting = true);
    final api = ref.read(apiClientProvider);
    final prefs = ref.read(prefsProvider);
    try {
      final outcome = await api.reportIssue(
        latitude: coords.latitude,
        longitude: coords.longitude,
        userId: prefs.userId,
        force: force,
        image: _images.isEmpty ? null : File(_images.first.path),
        audio: _recorder.file,
      );

      if (outcome.isDuplicate) {
        setState(() => _submitting = false);
        _bumpReset();
        if (!mounted) return;
        final action = await _DuplicateSheet.ask(context, outcome.duplicate!);
        if (action == _DuplicateAction.upvote) {
          await widget.onUpvoteExisting(outcome.duplicate!);
          if (mounted) Navigator.of(context).pop();
        } else if (action == _DuplicateAction.submitAnyway) {
          await _submit(force: true);
        }
        return;
      }

      final issue = outcome.issue!;
      // Attach the authenticated account's contact details (phone was
      // OTP-verified at login) — non-blocking, same as the web flow.
      try {
        await api.confirmIssue(issue.id, prefs.citizenPhone,
            name: prefs.citizenName);
      } catch (_) {}

      await ref
          .read(dailyLimitProvider)
          .consume(kGrievanceLimitKey, _kDailyMax);

      if (!mounted) return;
      Navigator.of(context).pop(); // close the sheet under the overlay
      await SuccessOverlay.show(
        context,
        title: context.tr('Grievance Submitted'),
        message:
            'Your report is on its way to the ward coordinator. Track it anytime under My Reports.',
        ticket: issue.ticketNo ?? ticketNumber(issue.id),
      );
      widget.onSubmitted();
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = '$e';
      });
      _bumpReset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        // Layer 1 — flat navy outer, only the top corners rounded so it reads
        // as a bottom-attached sheet, not a floating card.
        color: NkColors.refBlue,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: safeBottom + viewInset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                height: 4,
                width: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Layer 2 — slightly lighter inner container wrapping the two white
            // upload tiles (layer 3). Tiles are fixed height, so adding a photo
            // or recording audio swaps only their contents — never resizes.
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: NkColors.refBlueInner,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Expanded(child: _cameraTile()),
                  const SizedBox(width: 8),
                  Expanded(child: _voiceTile()),
                ],
              ),
            ),

            if (_error != null || _recorder.error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error ?? _recorder.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFFFFB4B4)),
              ),
            ],

            // Fair use policy row — aligned with the tiles above.
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_outlined,
                    size: 16, color: Colors.white.withValues(alpha: 0.66)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    context.tr(
                        'Fair use policy: you can report 1 grievance per day'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),

            // Swipe to submit.
            const SizedBox(height: 16),
            SwipeToConfirm(
              label: context.tr(_canSubmit
                  ? 'Swipe to submit grievance'
                  : 'Add a photo and a voice note'),
              uppercaseLabel: true,
              busyLabel: 'Submitting…',
              busy: _submitting,
              // Inert until both attachments exist — the requirement reads off
              // the control itself instead of only failing on swipe.
              disabled: !_canSubmit,
              resetToken: _resetToken,
              onConfirm: _submit,
              height: 62,
              radius: 22,
              thumbWidth: 84,
              trackColor: Colors.white,
              thumbColor: Colors.white ,
              thumbIconColor: NkColors.refBlue,
              labelColor: const Color(0xFF8B90A0),
              hintColor: const Color(0xFF8B90A0),
              fillColor: NkColors.refBlue.withValues(alpha: 0.08),
            ),
          ],
        ),
      ),
    );
  }

  // ── Upload tiles — fixed height, content swaps per state ──────────────────

  Widget _iconCircle(IconData icon,
          {Color bg = NkColors.slate100, Color fg = NkColors.refBlue}) =>
      Container(
        height: 44,
        width: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, size: 22, color: fg),
      );

  Widget _tile({
    required Widget leading,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: _kTileHeight,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: NkColors.slate900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.2,
                      color: NkColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _cameraTile() {
    if (_images.isNotEmpty) {
      return _tile(
        onTap: _capturePhoto,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(_images.first.path),
              height: 44, width: 44, fit: BoxFit.cover),
        ),
        title:
            _images.length > 1 ? 'Added (${_images.length})' : 'Photo added',
        subtitle: context.tr('Tap to add another'),
        trailing: GestureDetector(
          onTap: () => setState(() => _images.clear()),
          child: const Icon(Icons.delete_outline,
              size: 18, color: NkColors.slate400),
        ),
      );
    }
    return _tile(
      onTap: _capturePhoto,
      leading: _iconCircle(Icons.photo_camera_outlined),
      title: context.tr('Upload Photo'),
      subtitle: context.tr('Add clear photos of the issue'),
    );
  }

  Widget _voiceTile() {
    final r = _recorder;
    if (r.isRecording) {
      return _tile(
        onTap: () {
          HapticFeedback.mediumImpact();
          r.stop();
        },
        leading: _iconCircle(Icons.stop,
            bg: NkColors.rose100, fg: NkColors.rose600),
        title: r.clock,
        subtitle: context.tr('Tap to stop'),
      );
    }
    if (r.file != null) {
      return _tile(
        leading: GestureDetector(
          onTap: r.togglePlayback,
          child: _iconCircle(r.isPlaying ? Icons.pause : Icons.play_arrow,
              bg: NkColors.refBlue, fg: Colors.white),
        ),
        title: context.tr('Voice note'),
        subtitle: r.clock,
        trailing: GestureDetector(
          onTap: r.reset,
          child: const Icon(Icons.delete_outline,
              size: 18, color: NkColors.slate400),
        ),
      );
    }
    return _tile(
      onTap: () {
        HapticFeedback.selectionClick();
        r.start();
      },
      leading: _iconCircle(Icons.mic_none),
      title: context.tr('Record Voice'),
      subtitle: context.tr('Describe the issue in your voice'),
    );
  }
}

enum _DuplicateAction { upvote, submitAnyway, cancel }

/// "Duplicate Issue Found" confirm sheet (port of DuplicateModal.js).
class _DuplicateSheet extends StatelessWidget {
  const _DuplicateSheet({required this.issue});

  final Issue issue;

  static Future<_DuplicateAction> ask(BuildContext context, Issue issue) async {
    final r = await showModalBottomSheet<_DuplicateAction>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _DuplicateSheet(issue: issue),
    );
    return r ?? _DuplicateAction.cancel;
  }

  static Widget _photoFallback() => Container(
        height: 64,
        width: 64,
        color: NkColors.slate200,
        alignment: Alignment.center,
        child: const Text('🛣️', style: TextStyle(fontSize: 24)),
      );

  @override
  Widget build(BuildContext context) {
    final image = mediaImage(issue.imageUrl);
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                width: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: NkColors.amber50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    size: 22, color: NkColors.amber600),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Duplicate Issue Found',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: NkColors.slate900,
                      ),
                    ),
                    Text(
                      'An issue is already reported here and is under progress. Would you like to upvote it to increase priority instead?',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: NkColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Existing issue preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NkColors.slate50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NkColors.slate200),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: image != null
                      ? Image(
                          image: image,
                          height: 64,
                          width: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _photoFallback())
                      : _photoFallback(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        issue.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: NkColors.slate800,
                        ),
                      ),
                      if (issue.areaName != null)
                        Text(
                          issue.areaName!,
                          style: const TextStyle(
                              fontSize: 12, color: NkColors.slate500),
                        ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusChip(status: issue.status, fontSize: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.thumb_up_outlined,
                                  size: 11, color: NkColors.slate500),
                              const SizedBox(width: 3),
                              Text(
                                '${issue.upvotes}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: NkColors.slate500),
                              ),
                            ],
                          ),
                          if (issue.distanceM != null)
                            Text(
                              '${issue.distanceM!.round()} m away',
                              style: const TextStyle(
                                  fontSize: 12, color: NkColors.slate500),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () =>
                Navigator.of(context).pop(_DuplicateAction.upvote),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: NkColors.brand,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.thumb_up_outlined,
                      size: 15, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Upvote & Cancel',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () =>
                Navigator.of(context).pop(_DuplicateAction.submitAnyway),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NkColors.slate300),
              ),
              child: const Text(
                'Submit Anyway',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: NkColors.slate700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
