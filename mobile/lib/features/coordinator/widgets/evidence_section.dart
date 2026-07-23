import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme.dart';
import '../../report/widgets/voice_recorder.dart';

/// Shared evidence capture (live photo + voice note) used across the
/// coordinator action sheets — port of useEvidence/EvidenceSection in
/// ActionModals.js. Owns an [ImagePicker] photo + a [VoiceRecorderController].
class EvidenceController extends ChangeNotifier {
  final recorder = VoiceRecorderController();
  final _picker = ImagePicker();
  File? photo;

  EvidenceController() {
    recorder.addListener(notifyListeners);
  }

  Future<void> capturePhoto() async {
    HapticFeedback.selectionClick();
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (shot != null) {
        photo = File(shot.path);
        notifyListeners();
      }
    } catch (_) {/* camera unavailable — leave empty */}
  }

  void clearPhoto() {
    photo = null;
    notifyListeners();
  }

  bool get hasPhoto => photo != null;

  bool get hasVoice => recorder.file != null;

  @override
  void dispose() {
    recorder.dispose();
    super.dispose();
  }
}

class EvidenceSection extends StatelessWidget {
  const EvidenceSection({
    super.key,
    required this.evidence,
    this.label = 'Attach evidence (optional)',
  });

  final EvidenceController evidence;
  final String label;

  @override
  Widget build(BuildContext context) {
    final rec = evidence.recorder;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NkColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_file, size: 13, color: NkColors.slate700),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: NkColors.slate700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live photo tile
              Expanded(
                child: evidence.hasPhoto
                    ? Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              evidence.photo!,
                              height: 96,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: evidence.clearPhoto,
                              child: Container(
                                height: 24,
                                width: 24,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: NkColors.slate900
                                      .withValues(alpha: 0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      )
                    : GestureDetector(
                        onTap: evidence.capturePhoto,
                        child: Container(
                          height: 96,
                          decoration: BoxDecoration(
                            color: NkColors.brand50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    NkColors.brand.withValues(alpha: 0.15)),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo_camera_outlined,
                                  size: 20, color: NkColors.brand),
                              SizedBox(height: 4),
                              Text(
                                'Live photo',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: NkColors.brand,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              // Voice tile
              Expanded(
                child: Container(
                  height: 96,
                  decoration: BoxDecoration(
                    color: NkColors.brand50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: NkColors.brand.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          rec.isRecording ? rec.stop() : rec.start();
                        },
                        child: _PulsingMic(recording: rec.isRecording),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        rec.isRecording
                            ? rec.clock
                            : evidence.hasVoice
                                ? '✓ ${rec.clock}'
                                : 'Voice note',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: NkColors.brand,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (evidence.hasVoice && !rec.isRecording) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                GestureDetector(
                  onTap: rec.togglePlayback,
                  child: Container(
                    height: 30,
                    width: 30,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: NkColors.brand,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      rec.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Voice note · ${rec.clock}',
                    style: const TextStyle(
                        fontSize: 12, color: NkColors.slate600),
                  ),
                ),
                GestureDetector(
                  onTap: rec.reset,
                  child: const Icon(Icons.delete_outline,
                      size: 16, color: NkColors.rose500),
                ),
              ],
            ),
          ],
          if (rec.error != null) ...[
            const SizedBox(height: 6),
            Text(
              rec.error!,
              style: const TextStyle(fontSize: 11, color: NkColors.rose500),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulsingMic extends StatefulWidget {
  const _PulsingMic({required this.recording});

  final bool recording;

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.recording) _pulse.repeat();
  }

  @override
  void didUpdateWidget(_PulsingMic old) {
    super.didUpdateWidget(old);
    if (widget.recording && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.recording) _pulse.stop();
  }

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
        decoration: widget.recording
            ? BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444)
                        .withValues(alpha: 0.5 * (1 - _pulse.value)),
                    spreadRadius: 12 * _pulse.value,
                  ),
                ],
              )
            : null,
        child: child,
      ),
      child: Container(
        height: 42,
        width: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.recording ? NkColors.rose500 : NkColors.brand,
          shape: BoxShape.circle,
        ),
        child: Icon(
          widget.recording ? Icons.stop : Icons.mic_none,
          size: 18,
          color: Colors.white,
        ),
      ),
    );
  }
}
