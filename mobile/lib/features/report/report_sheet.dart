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
  late DailyState _limit;

  @override
  void initState() {
    super.initState();
    _limit = ref.read(dailyLimitProvider).state(kGrievanceLimitKey, _kDailyMax);
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

  Future<void> _submit({bool force = false}) async {
    setState(() => _error = null);
    final coords = widget.coords;
    // Fair-use counter is display-only for the demo — never blocks submission.
    if (coords == null) {
      setState(() => _error = 'Waiting for your location…');
      _bumpReset();
      return;
    }
    if (_images.isEmpty && _recorder.file == null) {
      setState(() =>
          _error = context.tr('Add a photo or a voice note to describe the issue.'));
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle
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
              const SizedBox(height: 10),

              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('Report Street Issue'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: NkColors.slate900,
                          ),
                        ),
                        Text(
                          context.tr('Help us build better and safer streets'),
                          style: TextStyle(
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

              // Fair-use policy card (navy)
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: nkBrandGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: NkColors.brand.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      height: 46,
                      width: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1.5),
                      ),
                      child: const Icon(Icons.shield_outlined,
                          size: 22, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('Fair use policy'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                              children: [
                                TextSpan(
                                    text:
                                        '${context.tr('You can report 1 grievance per day.')} '),
                                TextSpan(
                                  text:
                                      '${_limit.remaining} of ${_limit.max} ${context.tr('remaining today')}.',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 44,
                      width: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Icon(Icons.checklist_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),

              // Location card
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: NkColors.slate200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 44,
                          width: 44,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: NkColors.slate100,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.place,
                              size: 20, color: NkColors.brand),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.tr('Current Location'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: NkColors.slate900,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                widget.coords == null
                                    ? 'Locating…'
                                    : widget.areaName.isNotEmpty
                                        ? widget.areaName
                                        : '${widget.coords!.latitude.toStringAsFixed(4)}° N, ${widget.coords!.longitude.toStringAsFixed(4)}° E',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: widget.areaName.isNotEmpty
                                      ? FontWeight.w500
                                      : FontWeight.w400,
                                  color: widget.areaName.isNotEmpty
                                      ? NkColors.slate600
                                      : NkColors.slate400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: widget.geoStatus == 'ready'
                                ? NkColors.emerald50
                                : NkColors.slate100,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                height: 6,
                                width: 6,
                                decoration: BoxDecoration(
                                  color: widget.geoStatus == 'ready'
                                      ? NkColors.emerald500
                                      : NkColors.slate400,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                widget.geoStatus == 'ready'
                                    ? '±${(widget.accuracy ?? 0).round()} m'
                                    : widget.geoStatus == 'fallback'
                                        ? 'Default'
                                        : 'Locating…',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: widget.geoStatus == 'ready'
                                      ? NkColors.emerald700
                                      : NkColors.slate600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: NkColors.slate200),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: widget.onRefreshLocation,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 24,
                            width: 24,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: NkColors.brand50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.refresh,
                                size: 14, color: NkColors.brand),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('Refresh location'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: NkColors.brand,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Capture row: camera + voice
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Camera column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_images.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final img in _images)
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      child: Image.file(
                                        File(img.path),
                                        height: 44,
                                        width: 44,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: -6,
                                      right: -6,
                                      child: GestureDetector(
                                        onTap: () => setState(
                                            () => _images.remove(img)),
                                        child: Container(
                                          height: 20,
                                          width: 20,
                                          alignment: Alignment.center,
                                          decoration: const BoxDecoration(
                                            color: NkColors.slate800,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close,
                                              size: 11,
                                              color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        _CaptureTile(
                          icon: Icons.photo_camera_outlined,
                          title: _images.isNotEmpty
                              ? 'Added (${_images.length})'
                              : context.tr('Upload Photo'),
                          subtitle:
                              context.tr('Add clear photos of the issue'),
                          onTap: _capturePhoto,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Voice column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_recorder.file != null &&
                            !_recorder.isRecording) ...[
                          _AudioPill(recorder: _recorder),
                          const SizedBox(height: 8),
                        ],
                        _recorder.isRecording
                            ? _RecordingTile(recorder: _recorder)
                            : _CaptureTile(
                                icon: Icons.mic_none,
                                title: _recorder.file != null
                                    ? 'Re-record'
                                    : context.tr('Record Voice'),
                                subtitle: context
                                    .tr('Describe the issue in your voice'),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  _recorder.start();
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              )),
              if (_recorder.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _recorder.error!,
                  style:
                      const TextStyle(fontSize: 12, color: NkColors.rose500),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: NkColors.rose50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NkColors.rose200),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        fontSize: 13, color: NkColors.rose600),
                  ),
                ),
              ],

              // Swipe to submit
              const SizedBox(height: 16),
              SwipeToConfirm(
                label: context.tr('Swipe to submit grievance'),
                busyLabel: 'Submitting…',
                busy: _submitting,
                resetToken: _resetToken,
                onConfirm: _submit,
              ),

              // Footer reassurance
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_outlined,
                      size: 13, color: NkColors.slate400),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      context.tr(
                          'Your report helps us build better communities'),
                      style: const TextStyle(
                          fontSize: 11.5, color: NkColors.slate400),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NkColors.slate200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 40,
              width: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: NkColors.slate100,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: NkColors.brand),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: NkColors.slate900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: NkColors.slate500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rose pulsing tile while recording, with the live timer.
class _RecordingTile extends StatefulWidget {
  const _RecordingTile({required this.recorder});

  final VoiceRecorderController recorder;

  @override
  State<_RecordingTile> createState() => _RecordingTileState();
}

class _RecordingTileState extends State<_RecordingTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444)
                  .withValues(alpha: 0.5 * (1 - _pulse.value)),
              spreadRadius: 18 * _pulse.value,
            ),
          ],
        ),
        child: child,
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.recorder.stop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: NkColors.rose500,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(Icons.stop, size: 20, color: Colors.white),
              const SizedBox(height: 4),
              Text(
                '${widget.recorder.clock} · Stop',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact playback pill above the recorder tile (port of AudioPill).
class _AudioPill extends StatelessWidget {
  const _AudioPill({required this.recorder});

  final VoiceRecorderController recorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: NkColors.brand50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NkColors.brand100),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: recorder.togglePlayback,
            child: Container(
              height: 28,
              width: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: NkColors.brand,
                shape: BoxShape.circle,
              ),
              child: Icon(
                recorder.isPlaying ? Icons.pause : Icons.play_arrow,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Static waveform bars
          Expanded(
            child: SizedBox(
              height: 16,
              child: Row(
                children: [
                  for (var i = 0; i < 14; i++)
                    Expanded(
                      child: Center(
                        child: Container(
                          height: 16 * (0.3 + ((i * 37) % 70) / 100),
                          width: 2,
                          decoration: BoxDecoration(
                            color: NkColors.brand.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            recorder.clock,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: NkColors.brand,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: recorder.reset,
            child: const Icon(Icons.delete_outline,
                size: 14, color: NkColors.slate400),
          ),
        ],
      ),
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
