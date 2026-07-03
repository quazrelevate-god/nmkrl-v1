/**
 * lib/communityData.js
 * --------------------
 * Rich mock data powering the Community section (profile, stories, feed, polls,
 * and threaded comments). PoC data only — deterministic image/avatar URLs via
 * picsum.photos and i.pravatar.cc so the feed looks alive without a backend.
 */

const img = (seed, w = 640, h = 440) => `https://picsum.photos/seed/${seed}/${w}/${h}`;
const avatar = (n) => `https://i.pravatar.cc/120?img=${n}`;

export const PROFILE = {
  name: "Raj Kumar",
  civicScore: 850,
  rating: 4.5,
  upvotes: 56,
  reports: 24,
  resolved: 18,
  streets: 20,
  rank: "Top 15%",
  level: "Gold",
  nextLevel: "Platinum",
  toNext: 150,          // civic points to the next tier
  levelSpan: 1000,      // points that make up the current tier band
  streak: 7,            // day streak
  achievements: [
    { icon: "🥇", label: "Gold Tier" },
    { icon: "🔥", label: "7-day Streak" },
    { icon: "🛠️", label: "24 Reports" },
    { icon: "✅", label: "18 Resolved" },
    { icon: "🏅", label: "Top 15%" },
  ],
};

export const NEWS = {
  title: "Today's NEWS highlights",
  body: "Tamil Nadu Chief Minister is actively modernizing public transport and seeking funding changes for school education from the Central Government",
  tagline: "Together, we build a better Tamil Nadu.",
};

export const STORIES = [
  { id: "s1", label: "Pothole Reported",    count: 12, ring: "from-amber-400 to-rose-500",
    slides: [ { image: img("pothole1"), caption: "12 potholes flagged in Ward 17 this week" },
              { image: img("pothole2"), caption: "Corporation crew begins patchwork on Anna Salai" } ] },
  { id: "s2", label: "Water Issue Updates", count: 8,  ring: "from-rose-400 to-brand",
    slides: [ { image: img("water1"), caption: "Leak on 5th Cross fixed within 24h" },
              { image: img("water2"), caption: "New pipeline testing underway" } ] },
  { id: "s3", label: "Street Light Repair", count: 5,  ring: "from-violet-400 to-fuchsia-600",
    slides: [ { image: img("light1"), caption: "5 street lights restored on OMR service road" } ] },
  { id: "s4", label: "CM Updates",           count: 0,  ring: "from-yellow-400 via-orange-500 to-red-500",
    slides: [ { image: img("cm1"), caption: "CM launches Clean Tamil Nadu 2.0 mission" },
              { image: img("cm2"), caption: "₹200 Cr allotted for urban roads" } ] },
  { id: "s5", label: "Clean Tamil Nadu",     count: 0,  ring: "from-emerald-400 to-green-600",
    slides: [ { image: img("green1"), caption: "Adyar eco-park restoration completed" } ] },
];

/* ── Shared comment pools (threaded) ── */
function thread(a) { return a; }

const COMMENTS_A = thread([
  { id: "c1", name: "Meena R", avatar: avatar(45), time: "1h", text: "Finally! This leak was wasting so much water. Thank you for reporting 🙏", likes: 12,
    replies: [
      { id: "c1r1", name: "Raj Kumar", avatar: avatar(12), time: "58m", text: "Glad it's fixed. Took 3 follow-ups with the ward office.", likes: 4 },
      { id: "c1r2", name: "Anitha Devi", avatar: avatar(32), time: "40m", text: "We should upvote these so they move faster next time.", likes: 6,
        replies: [ { id: "c1r2r1", name: "Meena R", avatar: avatar(45), time: "30m", text: "100%. Sharing with my street WhatsApp group.", likes: 2 } ] },
    ] },
  { id: "c2", name: "Karthik S", avatar: avatar(15), time: "45m", text: "The corporation response time has genuinely improved this year.", likes: 8, replies: [] },
]);

const COMMENTS_B = thread([
  { id: "d1", name: "Prakash V", avatar: avatar(53), time: "2h", text: "Street lights near the school were off for weeks. Kids walk home in the dark.", likes: 19,
    replies: [
      { id: "d1r1", name: "Ward 12 Office", avatar: avatar(60), time: "1h", text: "Team dispatched. Should be resolved by tomorrow evening.", likes: 22,
        replies: [ { id: "d1r1r1", name: "Prakash V", avatar: avatar(53), time: "55m", text: "Appreciate the quick response 🙏", likes: 5 } ] },
    ] },
]);

const COMMENTS_C = thread([
  { id: "e1", name: "Divya L", avatar: avatar(24), time: "20m", text: "Voted for water supply — it's the biggest issue in our area.", likes: 3, replies: [] },
  { id: "e2", name: "Suresh N", avatar: avatar(8), time: "12m", text: "Road maintenance should be first honestly, the potholes are dangerous.", likes: 5,
    replies: [ { id: "e2r1", name: "Divya L", avatar: avatar(24), time: "8m", text: "Fair point, both are urgent.", likes: 1 } ] },
]);

/* ── Authored feed items ── */
const AUTHORED = [
  {
    id: "GRV-784512", type: "image", author: "Raj Kumar", verified: true, avatar: avatar(12),
    ward: "Ward 17", area: "Mylapore", time: "2h ago", status: "Resolved",
    title: "Water leakage on 5th Cross Street",
    body: "Water has been leaking continuously for the past 3 days. Requesting immediate action.",
    media: [img("leak1"), img("leak2"), img("leak3"), img("leak4"), img("leak5")],
    tag: "Water Supply", location: "5th Cross Street",
    likes: 56, shares: 8, saved: false, comments: COMMENTS_A,
  },
  {
    id: "POLL-1", type: "poll", author: "Ward 17 Council", verified: true, avatar: avatar(60),
    ward: "Ward 17", area: "Mylapore", time: "1d ago", status: null,
    question: "Which issue needs most urgent attention in our area?",
    options: [
      { label: "Water Supply", votes: 124 },
      { label: "Road Maintenance", votes: 85 },
      { label: "Garbage Collection", votes: 42 },
      { label: "Street Lighting", votes: 18 },
    ],
    totalVotes: 269, daysLeft: 2, likes: 34, shares: 5, saved: false, comments: COMMENTS_C,
  },
  {
    id: "GRV-901233", type: "text", author: "Anitha Devi", verified: true, avatar: avatar(32),
    ward: "Ward 12", area: "Adyar", time: "3h ago", status: "In Progress",
    title: "Broken footpath near School Zone",
    body: "Footpath tiles are broken and causing difficulty for students and senior citizens. Please prioritise this before the school reopens.",
    tag: "Works & Roads", location: "Adyar School Zone",
    likes: 41, shares: 3, saved: true, comments: COMMENTS_B,
  },
  {
    id: "GRV-555112", type: "video", author: "Karthik S", verified: false, avatar: avatar(15),
    ward: "Ward 22", area: "Velachery", time: "5h ago", status: "Assigned",
    title: "Overflowing storm water drain",
    body: "After last night's rain the drain is completely overflowing onto the main road. Recorded a short clip.",
    poster: img("drainvid"),
    video: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    tag: "Storm Water Drain", location: "Velachery Main Road",
    likes: 73, shares: 14, saved: false, comments: [] ,
  },
  {
    id: "GRV-337781", type: "image", author: "Fatima Begum", verified: true, avatar: avatar(20),
    ward: "Ward 9", area: "T. Nagar", time: "6h ago", status: "Resolved",
    title: "Garbage not cleared near market",
    body: "The garbage pile near Ranganathan Street market has finally been cleared after multiple reports. Thanks to the conservancy team!",
    media: [img("garb1"), img("garb2")],
    tag: "Solid Waste", location: "Ranganathan Street",
    likes: 88, shares: 11, saved: false, comments: [] ,
  },
  {
    id: "POLL-2", type: "poll", author: "Clean Tamil Nadu", verified: true, avatar: avatar(5),
    ward: "City-wide", area: "Chennai", time: "2d ago", status: null,
    question: "Should the city expand its cycle lane network?",
    options: [
      { label: "Yes, on all arterial roads", votes: 312 },
      { label: "Only in residential zones", votes: 96 },
      { label: "No, prioritise footpaths", votes: 141 },
    ],
    totalVotes: 549, daysLeft: 4, likes: 61, shares: 20, saved: true, comments: [] ,
  },
  {
    id: "GRV-118820", type: "text", author: "Vikram Anand", verified: false, avatar: avatar(11),
    ward: "Ward 30", area: "Porur", time: "8h ago", status: "In Progress",
    title: "Traffic signal not working at junction",
    body: "The signal at Porur junction has been blinking amber for two days, causing chaos during peak hours. Traffic police are managing manually.",
    tag: "Traffic", location: "Porur Junction",
    likes: 29, shares: 6, saved: false, comments: [] ,
  },
];

/* ── Generators to reach 20 rich items ── */
const NAMES = ["Sundar M", "Lakshmi P", "Arjun R", "Deepa K", "Mohan Raj", "Kavya S", "Ganesh V", "Nithya B", "Ravi Shankar", "Priya D"];
const AREAS = [["Ward 5", "Egmore"], ["Ward 14", "Guindy"], ["Ward 40", "Ambattur"], ["Ward 8", "Kodambakkam"], ["Ward 25", "Perambur"]];
const STATUSES = ["Resolved", "In Progress", "Assigned", "Pending Verification"];
const TAGS = ["Solid Waste", "Electrical", "Works & Roads", "Public Health", "Parks & Playfields"];
const TITLES = [
  ["Fallen tree blocking the road", "A large tree fell during the storm and is blocking half the carriageway near the bus stop."],
  ["Mosquito breeding in stagnant water", "Stagnant water in the vacant plot is breeding mosquitoes. Requesting fogging urgently."],
  ["Street light flickering all night", "The street light keeps flickering and going off, making the lane unsafe after dark."],
  ["Damaged park benches", "Benches in the neighbourhood park are broken and unusable. Families have nowhere to sit."],
  ["Pothole causing two-wheeler skids", "A deep pothole has formed after the rains and several riders have already skidded."],
  ["Open manhole near footpath", "An uncovered manhole right next to the footpath is a serious danger for pedestrians at night."],
];

function generated(n) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const [ward, area] = AREAS[i % AREAS.length];
    const [title, body] = TITLES[i % TITLES.length];
    const type = i % 3 === 0 ? "image" : "text";
    out.push({
      id: `GRV-${700100 + i * 137}`,
      type,
      author: NAMES[i % NAMES.length],
      verified: i % 2 === 0,
      avatar: avatar((i * 7) % 70 + 1),
      ward, area,
      time: `${i + 1}h ago`,
      status: STATUSES[i % STATUSES.length],
      title, body,
      tag: TAGS[i % TAGS.length],
      location: `${area} area`,
      media: type === "image" ? [img(`gen${i}a`), img(`gen${i}b`)] : undefined,
      likes: 8 + ((i * 13) % 90),
      shares: (i * 3) % 15,
      saved: i % 5 === 0,
      comments: [],
    });
  }
  return out;
}

// 10 curated items (the authored set + a few generated) — trimmed from 20 to
// cut repetition while keeping one of each content type.
export const FEED = [...AUTHORED, ...generated(Math.max(0, 10 - AUTHORED.length))];

export const STATUS_STYLE = {
  "Resolved":              "bg-green-100 text-green-700",
  "In Progress":           "bg-orange-100 text-orange-700",
  "Assigned":              "bg-brand-100 text-brand-700",
  "Pending Verification":  "bg-amber-100 text-amber-700",
};
