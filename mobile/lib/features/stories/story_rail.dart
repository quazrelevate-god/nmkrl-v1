import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/media.dart';
import '../../domain/models/story.dart';
import 'story_viewer.dart';

/// Height of the whole rail strip, label included. Both home screens reserve
/// exactly this much under the app bar, and the sheet's expanded snap stops
/// below it, so a pulled-up sheet never covers the stories.
///
/// Trimmed from 110 to 100 by taking slack out of the padding and the
/// circle-to-label gap, then to 92 by bringing the circles themselves in from
/// 62 to [_kRingSize]. They are still circles with gradient rings and labels;
/// there is simply less air around them.
const double kStoryRailHeight = 92;

/// What the rail will actually occupy for this state — [kStoryRailHeight], or
/// zero when a citizen's ward has no stories and there is no composer tile to
/// draw. The home screens need this BEFORE building the rail, to place the
/// ward pill under it and to cap the sheet's expanded snap below it.
double storyRailHeight({
  required bool canPost,
  required bool hasRings,
  required bool loading,
}) =>
    (canPost || hasRings || loading) ? kStoryRailHeight : 0;

/// The circle's painted diameter (ring included).
const double _kRingSize = 56;

/// The horizontal story rail that opens both home screens.
///
/// Citizens see only the ward's rings and may open them. Coordinators get a
/// leading "Your Story" tile that posts into the ward they are viewing — the
/// single behavioural difference between the two apps, carried by [canPost].
class StoryRail extends StatelessWidget {
  const StoryRail({
    super.key,
    required this.rings,
    this.canPost = false,
    this.onAdd,
    this.onDelete,
    this.loading = false,
    this.ownerUsername,
  });

  final List<StoryRing> rings;

  /// Coordinator mode: show the "Your Story" composer tile.
  final bool canPost;
  final VoidCallback? onAdd;

  /// Remove one frame — offered in the viewer, and only on your own stories.
  final ValueChanged<Story>? onDelete;

  /// First load with nothing cached yet: show placeholder circles rather than
  /// an empty strip that pops into content a moment later.
  final bool loading;

  /// Signed-in coordinator's username, so the viewer knows which frames are
  /// theirs to delete.
  final String? ownerUsername;

  @override
  Widget build(BuildContext context) {
    final showPlaceholders = loading && rings.isEmpty;
    // Nothing to show and nothing to post: collapse the strip entirely rather
    // than leaving a band of empty white above the map.
    if (!canPost && rings.isEmpty && !showPlaceholders) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: kStoryRailHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 5, 14, 4),
        physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemCount: (canPost ? 1 : 0) + (showPlaceholders ? 4 : rings.length),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          if (canPost && i == 0) {
            return _AddTile(onTap: onAdd);
          }
          final index = canPost ? i - 1 : i;
          if (showPlaceholders) return const _SkeletonTile();
          final ring = rings[index];
          return _RingTile(
            ring: ring,
            onTap: () {
              HapticFeedback.selectionClick();
              StoryViewer.open(
                context,
                rings: rings,
                initialRing: index,
                onDelete: onDelete,
                ownerUsername: ownerUsername,
              );
            },
          );
        },
      ),
    );
  }
}

/// One ring: the newest frame inside a gold-to-brand gradient collar, with the
/// group title under it.
class _RingTile extends StatelessWidget {
  const _RingTile({required this.ring, required this.onTap});

  final StoryRing ring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = mediaImage(ring.cover);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _kRingSize + 12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: _kRingSize,
              width: _kRingSize,
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                // Unread-style collar, warm pink-to-orange. Every ring on
                // the rail is live (the server only returns unexpired ones),
                // so there is no read state to grey out yet.
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFC24B),
                    Color(0xFFF77737),
                    Color(0xFFE1306C),
                  ],
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(
                    color: NkColors.slate200,
                    shape: BoxShape.circle,
                  ),
                  child: cover == null
                      ? const Icon(Icons.photo_outlined,
                          size: 20, color: NkColors.slate500)
                      : Image(image: cover, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              context.tr(ring.title),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                height: 1.15,
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

/// Coordinator-only composer tile — the "+" that opens the story composer.
class _AddTile extends StatelessWidget {
  const _AddTile({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _kRingSize + 12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: _kRingSize,
              width: _kRingSize,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: NkColors.refBlueDeep,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 26, color: Colors.white),
            ),
            const SizedBox(height: 3),
            Text(
              context.tr('Your Story'),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: NkColors.slate800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grey circles held while the first fetch is in flight.
class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kRingSize + 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: _kRingSize,
            width: _kRingSize,
            decoration: const BoxDecoration(
              color: NkColors.slate100,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 7,
            width: _kRingSize * 0.7,
            decoration: BoxDecoration(
              color: NkColors.slate100,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
