import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Voice-note recorder (port of useRecorder in lib/hooks.js), producing
/// AAC-in-MP4 (.m4a) — the format the backend maps straight to Gemini.
class VoiceRecorderController extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool isRecording = false;
  bool isPlaying = false;
  int seconds = 0;
  File? file;
  String? error;
  Timer? _timer;

  VoiceRecorderController() {
    _player.onPlayerComplete.listen((_) {
      isPlaying = false;
      notifyListeners();
    });
  }

  Future<void> start() async {
    error = null;
    try {
      if (!await _recorder.hasPermission()) {
        error =
            'Microphone access denied or unavailable. Please allow mic permission.';
        notifyListeners();
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/nk_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      isRecording = true;
      seconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        seconds++;
        notifyListeners();
      });
      notifyListeners();
    } catch (_) {
      error =
          'Microphone access denied or unavailable. Please allow mic permission.';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (!isRecording) return;
    _timer?.cancel();
    try {
      final path = await _recorder.stop();
      if (path != null) file = File(path);
    } catch (_) {
      error = 'Recording failed. Please try again.';
    }
    isRecording = false;
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    final f = file;
    if (f == null) return;
    if (isPlaying) {
      await _player.pause();
      isPlaying = false;
    } else {
      await _player.play(DeviceFileSource(f.path));
      isPlaying = true;
    }
    notifyListeners();
  }

  Future<void> reset() async {
    _timer?.cancel();
    if (isRecording) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    if (isPlaying) {
      try {
        await _player.stop();
      } catch (_) {}
    }
    final old = file;
    file = null;
    isRecording = false;
    isPlaying = false;
    seconds = 0;
    error = null;
    notifyListeners();
    if (old != null && old.existsSync()) {
      try {
        old.deleteSync();
      } catch (_) {}
    }
  }

  String get clock {
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }
}
