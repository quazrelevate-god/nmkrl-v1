/**
 * lib/communityData.js
 * --------------------
 * Rich mock data powering the Community section (profile, constituency
 * highlights, feed, polls, threaded comments). PoC data only — deterministic
 * image/avatar URLs via picsum.photos and i.pravatar.cc so the feed looks alive
 * without a backend. Content is city-wide / constituency-scale civic material:
 * public grievances, official updates, news, and polls.
 */

const img = (seed, w = 900, h = 620) => `https://picsum.photos/seed/${seed}/${w}/${h}`;
const avatar = (n) => `https://i.pravatar.cc/120?img=${n}`;

/** Deterministic avatar for a commenter name. */
function avatarFor(name) {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 70;
  return avatar(h + 1);
}

/** Map the provided [{commenterName, text}] into threaded comment nodes. */
function comments(list = []) {
  return list.map((c, i) => ({
    id: `cm-${i}-${c.commenterName}`,
    name: c.commenterName.replace(/_/g, " "),
    avatar: avatarFor(c.commenterName),
    time: `${i + 1}h`,
    text: c.text,
    likes: 3 + ((i * 7) % 20),
    replies: [],
  }));
}

/* ── The 16 Chennai (district) Assembly Constituencies ── */
export const CONSTITUENCIES = [
  "Dr. Radhakrishnan Nagar",
  "Perambur",
  "Kolathur",
  "Villivakkam",
  "Thiru-Vi-Ka-Nagar",
  "Egmore",
  "Harbour",
  "Chepauk-Thiruvallikeni",
  "Thousand Lights",
  "Anna Nagar",
  "Virugambakkam",
  "Saidapet",
  "Thiyagarayanagar",
  "Mylapore",
  "Velachery",
  "Shozhinganallur",
];

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
  toNext: 150,
  levelSpan: 1000,
  streak: 7,
  achievements: [
    { icon: "🥇", label: "Gold Tier" },
    { icon: "🔥", label: "7-day Streak" },
    { icon: "🛠️", label: "24 Reports" },
    { icon: "✅", label: "18 Resolved" },
    { icon: "🏅", label: "Top 15%" },
  ],
};

export const NEWS = {
  title: "Chennai NEWS highlights",
  body: "Tamil Nadu is modernizing public transport, expanding the metro network, and ramping up monsoon preparedness across Greater Chennai.",
  tagline: "Together, we build a better Tamil Nadu.",
};

/* ── Constituency highlights (city-wide stories) ── */
export const STORIES = [
  { id: "s1", label: "Metro Phase-2", count: 4, ring: "from-violet-500 to-fuchsia-600",
    slides: [
      { image: img("metro-phase2"), caption: "Metro Phase-2 tunnelling crosses the halfway mark across the city" },
      { image: img("metro-station"), caption: "9 new underground stations to open along the Poonamallee corridor" },
    ] },
  { id: "s2", label: "Marina Cleanup", count: 3, ring: "from-emerald-400 to-teal-600",
    slides: [
      { image: img("marina-clean"), caption: "3 tonnes of plastic cleared from Marina in a mega weekend drive" },
      { image: img("beach-volunteers"), caption: "1,200+ volunteers join the Greater Chennai Corporation cleanup" },
    ] },
  { id: "s3", label: "CM Breakfast Scheme", count: 0, ring: "from-amber-400 to-orange-600",
    slides: [
      { image: img("breakfast-scheme"), caption: "Free breakfast now reaches 1.5 lakh corporation-school children" },
    ] },
  { id: "s4", label: "Namma Chennai Budget", count: 0, ring: "from-brand to-brand-dark",
    slides: [
      { image: img("chennai-budget"), caption: "₹200 Cr allotted for urban roads and stormwater drains" },
      { image: img("city-works"), caption: "Ward-level participatory budgeting opens for public suggestions" },
    ] },
  { id: "s5", label: "Monsoon Prep", count: 6, ring: "from-sky-400 to-blue-600",
    slides: [
      { image: img("desilting"), caption: "Desilting of 240 km of macro-drains completed before the monsoon" },
    ] },
  { id: "s6", label: "New E-Buses", count: 0, ring: "from-lime-400 to-green-600",
    slides: [
      { image: img("electric-bus"), caption: "50 new low-floor electric MTC buses roll out on South Chennai routes" },
    ] },
  { id: "s7", label: "Jobs @ Guindy", count: 0, ring: "from-indigo-400 to-violet-600",
    slides: [
      { image: img("tech-park"), caption: "New Guindy tech incubator to generate 5,000+ jobs for youth" },
    ] },
];

/* ── City-wide feed (public grievances, official updates, news, polls) ── */
export const FEED = [
  {
    id: "GRV-VLCY-4415", type: "image",
    author: "Ramesh K.", handle: "@Ramesh_K_Velachery", verified: false, avatar: avatar(12),
    area: "Velachery, Chennai", time: "2h ago", status: "Reported",
    title: "AGS Colony interior streets waterlogged again",
    body: "Heavy rain for just 30 minutes and the interior streets of AGS Colony are completely waterlogged. The stormwater drain project here seems incomplete. Requesting GCC to look into this urgently before the monsoon worsens.",
    media: [img("velachery-flood-1"), img("velachery-flood-2"), img("velachery-flood-3")],
    tag: "Storm Water Drain", location: "AGS Colony, Velachery",
    likes: 342, shares: 58, saved: false,
    comments: comments([
      { commenterName: "SureshKumar_Anand", text: "Every year it is the same story in AGS colony. Hope the officials act fast this time." },
      { commenterName: "GCC_Grievance_Cell", text: "Thank you for bringing this to our notice. We have forwarded this to the zonal engineer for immediate action." },
      { commenterName: "Preethi_M", text: "The main roads are fine, but interior streets really need attention." },
    ]),
  },
  {
    id: "UPD-TNGR-2201", type: "image",
    author: "Minister's Office, TN", handle: "@Minister_Office_TN", verified: true, avatar: avatar(51),
    area: "T. Nagar, Chennai", time: "4h ago", status: "Official Update",
    title: "Inspection of multi-level car parking in T. Nagar",
    body: "Today, inspected the ongoing multi-level car parking facilities and met with local shop owners in T. Nagar. Discussed ways to further reduce traffic congestion and ensured that the ward's daily sanitation drives are being monitored properly.",
    media: [img("tnagar-inspection-1"), img("tnagar-inspection-2")],
    tag: "Traffic & Parking", location: "Ranganathan Street, T. Nagar",
    likes: 1284, shares: 210, saved: false,
    comments: comments([
      { commenterName: "Selvam_Trader", text: "Thank you minister for listening to our grievances regarding parking space. Highly appreciated." },
      { commenterName: "Deepak_Rao", text: "Sir, please also look into the pedestrian platform encroachment near the metro station." },
    ]),
  },
  {
    id: "NEWS-GNDY-8890", type: "video",
    author: "Thanthi TV Digital", handle: "@Thanthi_TV_Digital", verified: true, avatar: avatar(33),
    area: "Guindy, Chennai", time: "6h ago", status: "LIVE",
    title: "CM inaugurates new tech incubator at Guindy Industrial Estate",
    body: "Live Updates: Chief Minister inaugurates the new state-of-the-art tech incubator facility at Guindy Industrial Estate today. This move is expected to generate over 5,000 jobs for youth in and around Chennai.",
    poster: img("guindy-tech-live"),
    video: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
    tag: "Jobs & Economy", location: "Guindy Industrial Estate",
    likes: 2143, shares: 512, saved: true,
    comments: comments([
      { commenterName: "Karthik_Techie", text: "Great news for freshers! Guindy is becoming a massive hub again." },
      { commenterName: "Vidhya_S", text: "Hope there is a focus on core engineering jobs alongside IT." },
    ]),
  },
  {
    id: "POLL-MYLP-3312", type: "poll",
    author: "Mylapore Residents' Assoc.", handle: "@Mylapore_Resident_Assoc", verified: true, avatar: avatar(5),
    area: "Mylapore, Chennai", time: "8h ago", status: null,
    question: "How do you find the new Mylapore traffic diversions?",
    body: "With the new Metro Rail phase construction speeding up, several traffic diversions have been introduced around the Luz Church Road area. How is this affecting your daily commute?",
    options: [
      { label: "Highly confusing — adds 20 mins to my travel", votes: 486 },
      { label: "Manageable, traffic moves slowly but steadily", votes: 731 },
      { label: "Well-planned routing by the traffic police", votes: 254 },
    ],
    totalVotes: 1471, daysLeft: 3, likes: 173, shares: 44, saved: false,
    comments: comments([
      { commenterName: "Anantha_Srinivasan", text: "Voted for manageable. It's a temporary pain for a fantastic permanent gain (Metro)." },
      { commenterName: "Sasi_Rider", text: "Peak hours are literal nightmares near Luz corner right now. Need more traffic police personnel." },
    ]),
  },
  {
    id: "UPD-THLT-7745", type: "video",
    author: "MLA Ezhilan Office", handle: "@MLA_Ezhilan_Office", verified: true, avatar: avatar(60),
    area: "Thousand Lights, Chennai", time: "10h ago", status: "Official Update",
    title: "School visit & Chief Minister's Breakfast Scheme review",
    body: "Happy to interact with the bright young minds of the Chennai Corporation Higher Secondary School in our constituency today. Distributed free nutritional kits and checked on the quality of the Chief Minister's Breakfast Scheme. Smiling faces are our biggest reward!",
    poster: img("school-breakfast"),
    video: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4",
    tag: "Education", location: "Thousand Lights",
    likes: 986, shares: 121, saved: false,
    comments: comments([
      { commenterName: "Meenakshi_Amma", text: "The breakfast scheme has been a boon for working mothers. Kids don't skip meals anymore." },
      { commenterName: "Janani_R", text: "Please ensure the food menu variety is maintained well throughout the month, sir." },
    ]),
  },
  {
    id: "NEWS-MRNA-5521", type: "image",
    author: "Puthiya Thalaimurai News", handle: "@PuthiyaThalaimurai_News", verified: true, avatar: avatar(24),
    area: "Marina Beach, Chennai", time: "12h ago", status: null,
    title: "Mega beach cleanup: 3 tonnes of plastic cleared",
    body: "Visuals from the mega beach cleanup drive organized by environmental NGOs along with the Greater Chennai Corporation. Over 3 tonnes of plastic waste collected within 4 hours this morning.",
    media: [img("marina-cleanup-1"), img("marina-cleanup-2"), img("marina-cleanup-3"), img("marina-cleanup-4")],
    tag: "Environment", location: "Marina Beach",
    likes: 1567, shares: 389, saved: false,
    comments: comments([
      { commenterName: "Eco_Warrior_TN", text: "Kudos to the volunteers, but we need stricter fines for littering on the beach." },
      { commenterName: "Raj_Kumar", text: "People who visit should take responsibility for their own trash." },
    ]),
  },
  {
    id: "GRV-KYBD-9014", type: "video",
    author: "Koyambedu Wholesale Voice", handle: "@Koyambedu_Wholesale_Voice", verified: false, avatar: avatar(15),
    area: "Koyambedu, Chennai", time: "14h ago", status: "Escalated",
    title: "Garbage dumping behind the wholesale market complex",
    body: "Shocking state of garbage dumping right behind the vegetable market complex. The smell is unbearable and it is creating an incredibly unhygienic environment for both vendors and customers. CMDA needs to intervene immediately.",
    poster: img("koyambedu-garbage"),
    video: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
    tag: "Solid Waste", location: "Koyambedu Market",
    likes: 731, shares: 143, saved: false,
    comments: comments([
      { commenterName: "Ganesh_Fruits", text: "We pay maintenance taxes regularly, yet waste clearance happens only once a week here." },
      { commenterName: "HealthFirst_Chennai", text: "This is a serious health hazard. Monsoon rains will turn this into a breeding ground for mosquitoes." },
    ]),
  },
  {
    id: "POLL-ANGR-1102", type: "poll",
    author: "Councillor · Ward 102", handle: "@Councillor_Ward_102", verified: true, avatar: avatar(48),
    area: "Anna Nagar, Chennai", time: "16h ago", status: null,
    question: "Should Anna Nagar Tower Park hours be extended until 10:00 PM?",
    body: "We have received representations from several senior citizens and working professionals requesting an extension of park timings at the local Tower Park for late-night walks.",
    options: [
      { label: "Yes, highly beneficial for working professionals", votes: 642 },
      { label: "No, it might raise safety and security concerns", votes: 198 },
      { label: "Keep current timings but improve lighting inside", votes: 377 },
    ],
    totalVotes: 1217, daysLeft: 5, likes: 209, shares: 33, saved: true,
    comments: comments([
      { commenterName: "Nirmala_Rangarajan", text: "As long as there is adequate CCTV coverage and police patrolling, extending timings is a great idea." },
      { commenterName: "Vignesh_Walks", text: "Voted for option 1. It gets too crowded in the evenings; splitting the crowd with longer hours helps." },
    ]),
  },
  {
    id: "POLL-TMBM-6650", type: "poll",
    author: "Sun News", handle: "@SunNews_Tweets", verified: true, avatar: avatar(9),
    area: "Tambaram, Chennai", time: "18h ago", status: null,
    question: "Rate the frequency & comfort of the new Tambaram Electric MTC buses:",
    body: "The transport department recently rolled out 50 new low-floor electric MTC buses across South Chennai routes connecting Tambaram. Tell us about your experience so far.",
    options: [
      { label: "Excellent — comfortable and timely", votes: 903 },
      { label: "Good comfort, but frequency needs improvement", votes: 1122 },
      { label: "Haven't been able to board one yet due to rush", votes: 418 },
    ],
    totalVotes: 2443, daysLeft: 2, likes: 512, shares: 96, saved: false,
    comments: comments([
      { commenterName: "Commuter_Balu", text: "Buses are super quiet and AC works great, but we need more during the 8 AM to 10 AM window." },
      { commenterName: "Divya_Nathan", text: "A massive upgrade from the old green buses. Proud to see Chennai upgrading!" },
    ]),
  },
  {
    id: "GRV-ADYR-2278", type: "image",
    author: "Adyar Civic Forum", handle: "@Adyar_Civic_Forum", verified: true, avatar: avatar(20),
    area: "Adyar, Chennai", time: "20h ago", status: "In Progress",
    title: "Surge in stray dog population near Shastri Nagar",
    body: "Stray dog population has surged drastically around Shastri Nagar 3rd Main Road. Many school children and delivery executives are hesitant to travel via this route after dark. Requesting animal welfare and GCC teams to schedule a vaccination and birth control drive.",
    media: [img("adyar-strays-1"), img("adyar-strays-2")],
    tag: "Public Health", location: "Shastri Nagar, Adyar",
    likes: 604, shares: 88, saved: false,
    comments: comments([
      { commenterName: "AnimalLover_Priya", text: "Please opt for humane ABC (Animal Birth Control) programs. Relocation is illegal and ineffective." },
      { commenterName: "Balaji_Srinivas", text: "I was chased by three dogs last midnight on my two-wheeler here. Truly scary situation." },
      { commenterName: "GCC_Health_Official", text: "Noted. The veterinary public health department will schedule an inspection in this zone by Monday." },
    ]),
  },
];

export const STATUS_STYLE = {
  "Resolved":              "bg-green-100 text-green-700",
  "In Progress":           "bg-orange-100 text-orange-700",
  "Assigned":              "bg-brand-100 text-brand-700",
  "Reported":              "bg-sky-100 text-sky-700",
  "Escalated":             "bg-red-100 text-red-700",
  "Official Update":       "bg-brand-100 text-brand-700",
  "LIVE":                  "bg-red-600 text-white",
  "Pending Verification":  "bg-amber-100 text-amber-700",
};
