import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';

/// Coordinator-only: post a story to the ward currently on screen.
///
/// Citizens never reach this — the "Your Story" tile that opens it is drawn
/// only when [StoryRail.canPost] is set, and the endpoint behind it takes a
/// coordinator session. Three fields and nothing else: a photo (camera or
/// gallery), the ring it belongs to, and an optional caption.
class StoryComposer extends StatefulWidget {
  const StoryComposer({
    super.key,
    required this.api,
    required this.ward,
    this.existingTitles = const [],
  });

  final ApiClient api;

  /// The ward the story is filed against — whatever the coordinator is
  /// viewing. The server re-checks it is inside their constituency.
  final int? ward;

  /// Ring names already live in this ward, offered as chips so a second post
  /// lands in the same circle rather than opening a near-duplicate one.
  final List<String> existingTitles;

  /// Returns true when a story was posted, so the caller can refetch.
  static Future<bool> open(
    BuildContext context, {
    required ApiClient api,
    required int? ward,
    List<String> existingTitles = const [],
  }) async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StoryComposer(
        api: api,
        ward: ward,
        existingTitles: existingTitles,
      ),
    );
    return posted ?? false;
  }

  @override
  State<StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends State<StoryComposer> {
  final _title = TextEditingController();
  final _caption = TextEditingController();
  File? _photo;
  bool _posting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.text = widget.existingTitles.isNotEmpty
        ? widget.existingTitles.first
        : 'Ward ${widget.ward ?? ''} Updates'.trim();
  }

  @override
  void dispose() {
    _title.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      // A story is a full-screen photo, not an archive copy: cap it so the
      // upload survives a field connection and stays inside the server's limit.
      maxWidth: 1440,
      imageQuality: 82,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _photo = File(picked.path);
      _error = null;
    });
  }

  Future<void> _post() async {
    final photo = _photo;
    if (photo == null) {
      setState(() => _error = 'Pick a photo first.');
      return;
    }
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await widget.api.postStory(
        image: photo,
        title: _title.text.trim().isEmpty ? 'Ward Update' : _title.text.trim(),
        caption: _caption.text.trim(),
        ward: widget.ward,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _error = 'Could not post that story. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: EdgeInsets.fromLTRB(
            18, 10, 18, 18 + MediaQuery.paddingOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 38,
                  decoration: BoxDecoration(
                    color: NkColors.slate300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('New ward story'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: NkColors.slate900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.ward == null
                    ? context
                        .tr('Visible to everyone in your ward for 24 hours.')
                    : '${context.tr('Visible to everyone in Ward')} ${widget.ward} '
                        '${context.tr('for 24 hours.')}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: NkColors.slate500,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),

              // ── Photo ──
              _PhotoWell(
                photo: _photo,
                onCamera: () => _pick(ImageSource.camera),
                onGallery: () => _pick(ImageSource.gallery),
              ),
              const SizedBox(height: 14),

              _Label(context.tr('Story circle')),
              const SizedBox(height: 6),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.words,
                decoration: _dec(context.tr('e.g. Cleanup Drive')),
                style: const TextStyle(fontSize: 13),
              ),
              if (widget.existingTitles.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in widget.existingTitles)
                      GestureDetector(
                        onTap: () => setState(() => _title.text = t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _title.text == t
                                ? NkColors.brand50
                                : NkColors.slate100,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _title.text == t
                                  ? NkColors.brand200
                                  : NkColors.slate200,
                            ),
                          ),
                          child: Text(
                            t,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: NkColors.slate700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              _Label(context.tr('Caption (optional)')),
              const SizedBox(height: 6),
              TextField(
                controller: _caption,
                maxLines: 3,
                minLines: 2,
                maxLength: 220,
                textCapitalization: TextCapitalization.sentences,
                decoration: _dec(context.tr('What is happening in the ward?')),
                style: const TextStyle(fontSize: 13),
              ),

              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  context.tr(_error!),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: NkColors.rose600,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: _posting ? null : _post,
                  style: FilledButton.styleFrom(
                    backgroundColor: NkColors.refBlueDeep,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: _posting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          context.tr('Post story'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
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

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: NkColors.slate50,
        hintStyle: const TextStyle(fontSize: 12.5, color: NkColors.slate400),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NkColors.slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NkColors.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NkColors.brand200, width: 1.4),
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: NkColors.slate600,
        ),
      );
}

/// The photo slot: an empty dashed well with camera/gallery buttons, replaced
/// by the chosen shot (with a change affordance) once one is picked.
class _PhotoWell extends StatelessWidget {
  const _PhotoWell({
    required this.photo,
    required this.onCamera,
    required this.onGallery,
  });

  final File? photo;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    if (photo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Image.file(photo!, fit: BoxFit.cover),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Row(
                children: [
                  _MiniButton(icon: Icons.photo_camera, onTap: onCamera),
                  const SizedBox(width: 6),
                  _MiniButton(icon: Icons.photo_library, onTap: onGallery),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: NkColors.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NkColors.slate200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PickButton(
            icon: Icons.photo_camera_outlined,
            label: context.tr('Camera'),
            onTap: onCamera,
          ),
          const SizedBox(width: 10),
          _PickButton(
            icon: Icons.photo_library_outlined,
            label: context.tr('Gallery'),
            onTap: onGallery,
          ),
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NkColors.slate200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: NkColors.refBlueDeep),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: NkColors.slate700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        width: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}
