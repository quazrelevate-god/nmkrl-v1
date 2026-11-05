/// Ward stories — the Instagram-shaped rail that opens the home screen.
///
/// A [StoryRing] is one circle on the rail; a [Story] is one frame inside it.
/// Coordinators post them for their ward; citizens only read. The grouping is
/// done server-side by title (routers/stories.py), so the rail renders exactly
/// what the API hands it rather than re-deriving the rings on the phone.
class Story {
  const Story({
    required this.id,
    required this.imageUrl,
    this.caption = '',
    this.author = '',
    this.authorName = '',
    this.createdAt = '',
    this.expiresAt = '',
  });

  final String id;

  /// Stored path ('/uploads/images/x.jpg') — resolve with `mediaImage`.
  final String imageUrl;
  final String caption;

  /// Coordinator username who posted it, and their display name.
  final String author;
  final String authorName;

  final String createdAt;
  final String expiresAt;

  factory Story.fromJson(Map<String, dynamic> json) => Story(
        id: '${json['id']}',
        imageUrl: '${json['image_url'] ?? ''}',
        caption: '${json['caption'] ?? ''}',
        author: '${json['author'] ?? ''}',
        authorName: '${json['author_name'] ?? ''}',
        createdAt: '${json['created_at'] ?? ''}',
        expiresAt: '${json['expires_at'] ?? ''}',
      );

  /// "2h ago" / "Just now" — the stamp under the ring title in the viewer.
  String get age {
    final then = DateTime.tryParse(createdAt);
    if (then == null) return '';
    final d = DateTime.now().toUtc().difference(then.toUtc());
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// One circle on the rail: a titled group of frames, newest frame as cover.
class StoryRing {
  const StoryRing({
    required this.title,
    required this.items,
    this.cover = '',
    this.ward,
    this.author = '',
    this.authorName = '',
    this.updatedAt = '',
  });

  final String title;
  final List<Story> items;

  /// Stored path of the newest frame's photo — what the circle shows.
  final String cover;

  final int? ward;
  final String author;
  final String authorName;
  final String updatedAt;

  bool get isEmpty => items.isEmpty;

  factory StoryRing.fromJson(Map<String, dynamic> json) => StoryRing(
        title: '${json['title'] ?? ''}',
        cover: '${json['cover'] ?? ''}',
        ward: (json['ward'] as num?)?.toInt(),
        author: '${json['author'] ?? ''}',
        authorName: '${json['author_name'] ?? ''}',
        updatedAt: '${json['updated_at'] ?? ''}',
        items: [
          for (final raw in (json['items'] as List? ?? const []))
            Story.fromJson(Map<String, dynamic>.from(raw as Map)),
        ],
      );
}
