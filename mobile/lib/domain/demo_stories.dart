import 'models/story.dart';

/// DEMO DATA — three sample story rings for the pilot build.
///
/// The stories API is written and tested (backend/routers/stories.py) but not
/// deployed yet, so a build pointed at production gets an empty rail and there
/// is nothing to look at. These stand in until it ships.
///
/// They are a FALLBACK, never an override: the home screens use them only when
/// the server returns no rings at all. The moment one real story exists in the
/// ward, the real list wins and none of this is reachable. Flip
/// [kUseDemoStories] to false — or delete this file and its two call sites —
/// to take them out.
///
/// The photos are the community images already bundled with the app, so this
/// adds no assets. `/community/...` paths resolve to those bundled files
/// through `mediaRef` in data/media.dart.
const bool kUseDemoStories = true;

/// Three rings matching the pilot mock: the ward's own feed, the works under
/// way, and a drive the coordinator is running.
List<StoryRing> demoStoryRings(int? ward) {
  final wardLabel = ward == null ? 'Ward' : 'Ward $ward';
  return [
    StoryRing(
      title: '$wardLabel Updates',
      cover: '/community/community-03.jpg',
      ward: ward,
      authorName: 'Ward Office',
      updatedAt: '',
      items: [
        const Story(
          id: 'demo-ward-1',
          imageUrl: '/community/community-03.jpg',
          caption: 'Storm water drain work on Ritherdon Road starts today.',
          authorName: 'Ward Office',
        ),
        const Story(
          id: 'demo-ward-2',
          imageUrl: '/community/community-07.jpg',
          caption: 'Street lights restored along Vepery High Road.',
          authorName: 'Ward Office',
        ),
      ],
    ),
    StoryRing(
      title: 'Civic Work',
      cover: '/community/community-11.webp',
      ward: ward,
      authorName: 'Ward Office',
      updatedAt: '',
      items: [
        const Story(
          id: 'demo-civic-1',
          imageUrl: '/community/community-11.webp',
          caption: 'Road re-laying between Doveton and Purasawalkam.',
          authorName: 'Ward Office',
        ),
      ],
    ),
    StoryRing(
      title: 'Cleanup Drive',
      cover: '/community/community-15.jpg',
      ward: ward,
      authorName: 'Ward Office',
      updatedAt: '',
      items: [
        const Story(
          id: 'demo-clean-1',
          imageUrl: '/community/community-15.jpg',
          caption: 'Saturday cleanup at the Vepery market — everyone welcome.',
          authorName: 'Ward Office',
        ),
        const Story(
          id: 'demo-clean-2',
          imageUrl: '/community/community-18.jpg',
          caption: '"Thank you to the forty residents who turned up."',
          authorName: 'Ward Office',
        ),
      ],
    ),
    StoryRing(
      title: 'Park Revamp',
      cover: '/community/community-13.jpg',
      ward: ward,
      authorName: 'Ward Office',
      updatedAt: '',
      items: [
        const Story(
          id: 'demo-park-1',
          imageUrl: '/community/community-13.jpg',
          caption: 'New benches and lighting at the Vepery children\'s park.',
          authorName: 'Ward Office',
        ),
      ],
    ),
  ];
}
