import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/glass.dart';
import '../../../core/theme.dart';
import '../../../domain/constituencies.dart';
import '../../../domain/coordinator_data.dart';
import '../../../domain/departments.dart';
import '../../../state/providers.dart';

/// The coordinator "+" composer — port of PostComposer.js. Two content types,
/// each capped at 1/day:
///   Post: title + photo/video/capture + description with live @mention and
///         #hashtag extraction
///   Poll: question + 2–4 options
/// plus GPS-or-manual location and a multi-select target-audience picker.
/// Publishes into the local moderation feed as "pending" (mirrors web).
class PostComposer extends ConsumerStatefulWidget {
  const PostComposer({super.key, required this.me});

  final Coordinator me;

  static Future<bool?> open(BuildContext context, Coordinator me) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.45),
      builder: (_) => PostComposer(me: me),
    );
  }

  @override
  ConsumerState<PostComposer> createState() => _PostComposerState();
}

class _PostComposerState extends ConsumerState<PostComposer> {
  final _picker = ImagePicker();

  String _kind = 'post'; // 'post' | 'poll'
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];

  File? _media;
  String? _mediaKind; // 'image' | 'video'

  bool _useGps = true;
  bool _locating = false;
  String? _gpsLabel;
  late String _manualConstituency = widget.me.constituency;
  late String _manualWard = widget.me.homeWard;

  final Set<String> _audience = {'Ward Residents'};

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _body, _question, ..._options]) {
      c.addListener(() => setState(() {}));
    }
    _detectGps();
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _question, ..._options]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _detectGps() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('denied');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(timeLimit: Duration(seconds: 8)),
      );
      if (mounted) {
        setState(() {
          _gpsLabel =
              'GPS · ${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}';
          _locating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gpsLabel = null;
          _locating = false;
        });
      }
    }
  }

  ({List<String> mentions, List<String> hashtags}) get _extracted {
    final text = _kind == 'post' ? _body.text : _question.text;
    return (
      mentions: RegExp(r'@(\w+)')
          .allMatches(text)
          .map((m) => m.group(1)!)
          .toList(),
      hashtags: RegExp(r'#(\w+)')
          .allMatches(text)
          .map((m) => m.group(1)!)
          .toList(),
    );
  }

  List<String> get _validOptions =>
      _options.map((o) => o.text.trim()).where((t) => t.isNotEmpty).toList();

  bool get _canPost => ref.read(coordinatorStoreProvider).canPost(widget.me.username);

  bool get _canPoll => ref.read(coordinatorStoreProvider).canPoll(widget.me.username);

  bool get _canSubmit => _kind == 'post'
      ? (_canPost && (_media != null || _body.text.trim().length >= 4))
      : (_canPoll &&
          _question.text.trim().length >= 4 &&
          _validOptions.length >= 2);

  String get _manualLabel =>
      'Ward $_manualWard, ${shortAC(_manualConstituency)}';

  List<String> get _wardsInAc {
    final list = List<String>.from(kChennaiAcMap[_manualConstituency] ?? []);
    list.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    return list;
  }

  Future<void> _pickMedia(ImageSource source, {bool video = false}) async {
    HapticFeedback.selectionClick();
    try {
      final f = video
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(
              source: source, maxWidth: 1600, imageQuality: 85);
      if (f != null) {
        setState(() {
          _media = File(f.path);
          _mediaKind = video ? 'video' : 'image';
        });
      }
    } catch (_) {}
  }

  Future<void> _publish() async {
    if (!_canSubmit) return;
    HapticFeedback.mediumImpact();
    final store = ref.read(coordinatorStoreProvider);
    final location = _useGps
        ? (_gpsLabel ?? shortAC(widget.me.constituency))
        : _manualLabel;
    final ex = _extracted;

    bool ok;
    if (_kind == 'post') {
      ok = await store.addPost(widget.me.username, {
        'title': _title.text.trim().isNotEmpty
            ? _title.text.trim()
            : (_body.text.trim().isNotEmpty
                ? _body.text.trim().substring(
                    0, _body.text.trim().length.clamp(0, 60))
                : 'Update'),
        'body': _body.text.trim(),
        'mediaPath': _media?.path,
        'mediaKind': _mediaKind,
        'location': location,
        'mentions': ex.mentions,
        'hashtags': ex.hashtags,
        'audience': _audience.toList(),
      });
    } else {
      ok = await store.addPoll(widget.me.username, {
        'question': _question.text.trim(),
        'options': _validOptions,
        'location': location,
        'audience': _audience.toList(),
      });
    }
    if (mounted) Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final ex = _extracted;
    final limitOk = _kind == 'post' ? _canPost : _canPoll;

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
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create ${_kind == 'post' ? 'Post' : 'Poll'}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: NkColors.slate900,
                          ),
                        ),
                        Text(
                          limitOk
                              ? 'Publishing to community · 1 $_kind/day'
                              : 'Daily $_kind limit reached',
                          style: TextStyle(
                            fontSize: 12,
                            color: limitOk
                                ? NkColors.slate500
                                : NkColors.rose600,
                          ),
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

              // Kind toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: NkColors.slate100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    for (final (key, label, icon) in [
                      ('post', 'Post', Icons.chat_bubble_outline),
                      ('poll', 'Poll', Icons.bar_chart),
                    ])
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _kind = key);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
                            curve: NkMotion.settle,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _kind == key
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _kind == key
                                  ? [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.06),
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
                                    size: 13,
                                    color: _kind == key
                                        ? NkColors.slate900
                                        : NkColors.slate500),
                                const SizedBox(width: 6),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _kind == key
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
              ),
              const SizedBox(height: 14),

              if (_kind == 'post') ..._buildPostBody(ex) else ..._buildPollBody(),

              const SizedBox(height: 14),
              _buildLocationCard(),
              const SizedBox(height: 14),
              _buildAudienceCard(),
              const SizedBox(height: 16),

              GestureDetector(
                onTap: _canSubmit ? _publish : null,
                child: Opacity(
                  opacity: _canSubmit ? 1 : 0.5,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: NkColors.brand,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: NkColors.brand.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send, size: 15, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Publish ${_kind == 'post' ? 'Post' : 'Poll'}',
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPostBody(
      ({List<String> mentions, List<String> hashtags}) ex) {
    return [
      _label('Title (optional)'),
      TextField(controller: _title, decoration: _dec('Short headline')),
      const SizedBox(height: 14),

      // Media
      if (_media != null)
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _mediaKind == 'image'
                  ? Image.file(
                      _media!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      height: 120,
                      color: NkColors.slate900,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam,
                              size: 28, color: Colors.white),
                          const SizedBox(height: 6),
                          Text(
                            _media!.uri.pathSegments.last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: NkColors.slate300),
                          ),
                        ],
                      ),
                    ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => setState(() {
                  _media = null;
                  _mediaKind = null;
                }),
                child: Container(
                  height: 30,
                  width: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NkColors.slate900.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.close, size: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        )
      else
        Row(
          children: [
            for (final (label, icon, tap) in [
              (
                'Photo',
                Icons.image_outlined,
                () => _pickMedia(ImageSource.gallery)
              ),
              (
                'Video',
                Icons.videocam_outlined,
                () => _pickMedia(ImageSource.gallery, video: true)
              ),
              (
                'Capture',
                Icons.photo_camera_outlined,
                () => _pickMedia(ImageSource.camera)
              ),
            ]) ...[
              Expanded(
                child: GestureDetector(
                  onTap: tap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: label == 'Photo'
                          ? NkColors.brand50
                          : NkColors.slate100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: label == 'Photo'
                            ? NkColors.brand.withValues(alpha: 0.15)
                            : NkColors.slate200,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(icon,
                            size: 18,
                            color: label == 'Photo'
                                ? NkColors.brand
                                : NkColors.slate600),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: label == 'Photo'
                                ? NkColors.brand
                                : NkColors.slate600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (label != 'Capture') const SizedBox(width: 8),
            ],
          ],
        ),
      const SizedBox(height: 14),

      _label('Description'),
      TextField(
        controller: _body,
        maxLines: 4,
        decoration: _dec('Share an update… use @mentions and #hashtags'),
      ),
      if (ex.mentions.isNotEmpty || ex.hashtags.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final m in ex.mentions)
              _tagChip('@$m', NkColors.brand50, NkColors.brand),
            for (final h in ex.hashtags)
              _tagChip('#$h', NkColors.teal50, NkColors.teal700),
          ],
        ),
      ],
    ];
  }

  List<Widget> _buildPollBody() {
    return [
      _label('Poll question'),
      TextField(
        controller: _question,
        maxLines: 2,
        decoration: _dec('What do residents think about…?'),
      ),
      const SizedBox(height: 12),
      Text(
        'Options (${_options.length}/4)',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: NkColors.slate600,
        ),
      ),
      const SizedBox(height: 6),
      for (var i = 0; i < _options.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                height: 28,
                width: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: NkColors.slate100,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: NkColors.slate500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _options[i],
                  decoration: _dec('Option ${i + 1}'),
                ),
              ),
              if (_options.length > 2)
                IconButton(
                  onPressed: () => setState(() {
                    _options.removeAt(i).dispose();
                  }),
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: NkColors.slate400),
                ),
            ],
          ),
        ),
      if (_options.length < 4)
        GestureDetector(
          onTap: () => setState(() {
            final c = TextEditingController();
            c.addListener(() => setState(() {}));
            _options.add(c);
          }),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: NkColors.slate300,
                style: BorderStyle.solid,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 14, color: NkColors.slate500),
                SizedBox(width: 6),
                Text(
                  'Add option',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: NkColors.slate500,
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _buildLocationCard() {
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
          const Row(
            children: [
              Icon(Icons.place_outlined, size: 12, color: NkColors.slate500),
              SizedBox(width: 6),
              Text(
                'LOCATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: NkColors.slate500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: NkColors.slate100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                for (final (gps, label) in [
                  (true, 'Current location'),
                  (false, 'Add manually'),
                ])
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _useGps = gps);
                        if (gps && _gpsLabel == null) _detectGps();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _useGps == gps
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (gps && _locating)
                              const SizedBox(
                                height: 10,
                                width: 10,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                    color: NkColors.slate500),
                              )
                            else if (gps)
                              const Icon(Icons.place,
                                  size: 12, color: NkColors.slate600),
                            if (gps) const SizedBox(width: 4),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _useGps == gps
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
          ),
          const SizedBox(height: 8),
          if (_useGps)
            Text(
              _locating
                  ? 'Detecting…'
                  : (_gpsLabel ?? 'GPS unavailable'),
              style: const TextStyle(fontSize: 11, color: NkColors.slate500),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _smallDropdown<String>(
                    value: _manualConstituency,
                    items: [
                      for (final c in kConstituencies)
                        DropdownMenuItem(value: c, child: Text(shortAC(c))),
                    ],
                    onChanged: (v) => setState(() {
                      _manualConstituency = v!;
                      final wards = _wardsInAc;
                      if (!wards.contains(_manualWard) && wards.isNotEmpty) {
                        _manualWard = wards.first;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _smallDropdown<String>(
                    value: _wardsInAc.contains(_manualWard)
                        ? _manualWard
                        : _wardsInAc.first,
                    items: [
                      for (final w in _wardsInAc)
                        DropdownMenuItem(value: w, child: Text('Ward $w')),
                    ],
                    onChanged: (v) => setState(() => _manualWard = v!),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAudienceCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NkColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_outlined,
                  size: 12, color: NkColors.slate500),
              const SizedBox(width: 6),
              Text(
                'TARGET AUDIENCE (${_audience.length} SELECTED)',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: NkColors.slate500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in kAudiences)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _audience.contains(a)
                          ? _audience.remove(a)
                          : _audience.add(a);
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _audience.contains(a)
                          ? NkColors.brand
                          : NkColors.slate100,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      a,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _audience.contains(a)
                            ? Colors.white
                            : NkColors.slate600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NkColors.slate200),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            borderRadius: BorderRadius.circular(12),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: NkColors.slate800,
            ),
            items: items,
            onChanged: onChanged,
          ),
        ),
      );

  Widget _tagChip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      );

  Widget _label(String text) => Padding(
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

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: NkColors.slate400),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NkColors.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NkColors.brand, width: 1.6),
        ),
      );
}
