import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Port of the PROFILE + STORIES mock data from lib/communityData.js.
/// Images are the same real civic photos, bundled as app assets (the one AVIF
/// was converted to JPG — Flutter's codecs don't decode AVIF).
class ProfileData {
  ProfileData._();

  static const name = 'Raj Kumar';
  static const civicScore = 850;
  static const rating = 4.5;
  static const upvotes = 56;
  static const reports = 24;
  static const resolved = 18;
  static const streets = 20;
  static const rank = 'Top 15%';
  static const level = 'Gold';
  static const nextLevel = 'Platinum';
  static const toNext = 150;
  static const levelSpan = 1000;
  static const streak = 7;

  static String get initials =>
      name.split(' ').map((w) => w[0]).join().toUpperCase();
}

class StorySlide {
  const StorySlide({required this.asset, required this.caption});

  final String asset;
  final String caption;
}

class Story {
  const Story({
    required this.id,
    required this.label,
    required this.count,
    required this.ring,
    required this.slides,
  });

  final String id;
  final String label;
  final int count;
  final List<Color> ring;
  final List<StorySlide> slides;
}

/// Constituency-highlights stories. Image choices reproduce the web's
/// deterministic seed → photo mapping exactly (precomputed).
const kStories = [
  Story(
    id: 's1',
    label: 'Metro Phase-2',
    count: 4,
    ring: [Color(0xFF818CF8), Color(0xFF8B5CF6)], // indigo-400 → violet-500
    slides: [
      StorySlide(
        asset: 'assets/community/community-08.webp',
        caption: 'Metro Phase-2 tunnelling crosses the halfway mark across the city',
      ),
      StorySlide(
        asset: 'assets/community/community-13.jpg',
        caption: '9 new underground stations to open along the Poonamallee corridor',
      ),
    ],
  ),
  Story(
    id: 's2',
    label: 'Marina Cleanup',
    count: 3,
    ring: [Color(0xFF34D399), Color(0xFF0D9488)], // emerald-400 → teal-600
    slides: [
      StorySlide(
        asset: 'assets/community/community-04.jpg',
        caption: '3 tonnes of plastic cleared from Marina in a mega weekend drive',
      ),
      StorySlide(
        asset: 'assets/community/community-04.jpg',
        caption: '1,200+ volunteers join the Greater Chennai Corporation cleanup',
      ),
    ],
  ),
  Story(
    id: 's3',
    label: 'CM Breakfast Scheme',
    count: 0,
    ring: [Color(0xFF2DD4BF), Color(0xFF0891B2)], // teal-400 → cyan-600
    slides: [
      StorySlide(
        asset: 'assets/community/community-08.webp',
        caption: 'Free breakfast now reaches 1.5 lakh corporation-school children',
      ),
    ],
  ),
  Story(
    id: 's4',
    label: 'Namma Chennai Budget',
    count: 0,
    ring: [NkColors.brand, NkColors.brandDark],
    slides: [
      StorySlide(
        asset: 'assets/community/community-08.webp',
        caption: '₹200 Cr allotted for urban roads and stormwater drains',
      ),
      StorySlide(
        asset: 'assets/community/community-17.jpg',
        caption: 'Ward-level participatory budgeting opens for public suggestions',
      ),
    ],
  ),
  Story(
    id: 's5',
    label: 'Monsoon Prep',
    count: 6,
    ring: [Color(0xFF38BDF8), Color(0xFF2563EB)], // sky-400 → blue-600
    slides: [
      StorySlide(
        asset: 'assets/community/community-01.jpg',
        caption: 'Desilting of 240 km of macro-drains completed before the monsoon',
      ),
    ],
  ),
  Story(
    id: 's6',
    label: 'New E-Buses',
    count: 0,
    ring: [Color(0xFF2DD4BF), Color(0xFF059669)], // teal-400 → emerald-600
    slides: [
      StorySlide(
        asset: 'assets/community/community-18.jpg',
        caption: '50 new low-floor electric MTC buses roll out on South Chennai routes',
      ),
    ],
  ),
  Story(
    id: 's7',
    label: 'Jobs @ Guindy',
    count: 0,
    ring: [Color(0xFF818CF8), Color(0xFF7C3AED)], // indigo-400 → violet-600
    slides: [
      StorySlide(
        asset: 'assets/community/community-12.webp',
        caption: 'New Guindy tech incubator to generate 5,000+ jobs for youth',
      ),
    ],
  ),
];
