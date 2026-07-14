/**
 * lib/communityInsights.js
 * ------------------------
 * Mock intelligence layer for the Performance page:
 *   • socialMentions(ac)  — trending social-media buzz about a constituency's MLA
 *   • communityKpis()     — engagement pulse computed from the citizen app's feed
 *   • FLAGGED_CONTENT     — community posts/comments flagged as abusive/violating
 *
 * The social + moderation data is illustrative mock data (fictional MLA names) —
 * clearly a showcase feature, not real records.
 */

import { FEED, STORIES } from "@/lib/communityData";
import { shortAC } from "@/lib/constituencies";

/**
 * Elected MLA per constituency (matched by constituency name).
 * The image is served from /public/mla/{N}.{ext} — the file is named after the
 * constituency number (e.g. 12.jpeg for Perambur / C. Joseph Vijay).
 */

export const MLA_BY_AC = {
  "11 - Dr. Radhakrishnan Nagar": { mla: "N. Marie Wilson", party: "TVK", image: "/mla/11.png" },
  "12 - Perambur": { mla: "C. Joseph Vijay", party: "TVK", image: "/mla/12.jpeg" },
  "13 - Kolathur": { mla: "V.S. Babu", party: "TVK", image: "/mla/13.png" },
  "14 - Villivakkam": { mla: "Aadhav Arjuna", party: "TVK", image: "/mla/14.png" },
  "15 - Thiru-Vi-Ka-Nagar": { mla: "M.R. Pallavi", party: "TVK", image: "/mla/15.png" },
  "16 - Egmore": { mla: "Rajmohan", party: "TVK", image: "/mla/16.jpg" },
  "17 - Harbour": { mla: "P.K. Sekarbabu", party: "DMK", image: "/mla/17.png" },
  "18 - Chepauk-Thiruvallikeni": { mla: "Udhayanidhi Stalin", party: "DMK", image: "/mla/18.png" },
  "19 - Thousand Lights": { mla: "J.C.D. Prabhakar", party: "TVK", image: "/mla/19.png" },
  "20 - Anna Nagar": { mla: "V.K. Ramkumar", party: "TVK", image: "/mla/20.png" },
  "21 - Virugambakkam": { mla: "R. Sabarinathan", party: "TVK", image: "/mla/21.png" },
  "22 - Saidapet": { mla: "M. Arul Prakasam", party: "TVK", image: "/mla/22.png" },
  "23 - Thiyagarayanagar": { mla: "Data Pending", party: "TVK", image: "/mla/23.png" },
  "24 - Mylapore": { mla: "Data Pending", party: "TVK", image: "/mla/24.png" },
  "25 - Velachery": { mla: "Data Pending", party: "TVK", image: "/mla/25.png" },
  "26 - Shozhinganallur": { mla: "Data Pending", party: "TVK", image: "/mla/26.png" },
};

/**
 * Tamil news carousel embedded in the Today's Pulse section. Illustrative
 * mocks pointing at real Tamil news portals; thumbnails are real civic photos
 * bundled under /public/community/ (no stock).
 */
export const TAMIL_NEWS = [
  {
    id: "n1",
    title: "சென்னையில் புதிய மெட்ரோ கட்டமைப்பு துவக்கம் — வேலைவாய்ப்பு உருவாகும்",
    source: "Thanthi TV",
    url: "https://www.thanthitv.com/",
    image: "/community/community-04.jpg",
  },
  {
    id: "n2",
    title: "மைலாப்பூரில் காவிரி நீர் திட்டம் மேம்பாட்டு பணிகள் தொடங்கின",
    source: "Puthiya Thalaimurai",
    url: "https://www.puthiyathalaimurai.com/",
    image: "/community/community-08.webp",
  },
  {
    id: "n3",
    title: "திமுக அரசு புதிய வேலைவாய்ப்பு அறிவிப்பு: 50,000 பணியிடங்கள்",
    source: "Sun News",
    url: "https://www.sunnews.co.in/",
    image: "/community/community-12.webp",
  },
  {
    id: "n4",
    title: "மழை பாதிப்பு களப்பணி: நகராட்சி அதிரடி நடவடிக்கை",
    source: "Dinakaran",
    url: "https://www.dinakaran.com/",
    image: "/community/community-14.jpg",
  },
  {
    id: "n5",
    title: "அண்ணா நகர் பூங்கா புத்துயிர் திட்டம் — மக்கள் வரவேற்பு",
    source: "Polimer News",
    url: "https://www.polimernews.com/",
    image: "/community/community-17.jpg",
  },
];

const PLATFORMS = ["X (Twitter)", "Instagram", "Facebook", "YouTube"];

function hash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
  return Math.abs(h);
}

/** Deterministic mock social buzz for a constituency's MLA. */
export function socialMentions(ac) {
  const info = MLA_BY_AC[ac] || { mla: "the Ward Councillor", party: "", image: null };
  const pending = info.mla === "Data Pending";
  const name = shortAC(ac);
  const h = hash(ac || "chennai");
  const mentions = 800 + (h % 3600);            // 0.8k – 4.4k
  const pos = 42 + (h % 34);                     // 42% – 75%
  const neg = 8 + (Math.floor(h / 7) % 20);      // 8% – 27%
  const neu = Math.max(0, 100 - pos - neg);
  const reach = 40 + (Math.floor(h / 11) % 260); // 40k – 300k
  const trend = (Math.floor(h / 13) % 47) - 12;  // -12% .. +34%
  const platform = PLATFORMS[h % PLATFORMS.length];

  const topics = [
    "monsoon desilting drive", "new stormwater drains", "road relaying works",
    "e-bus rollout", "park renovation", "breakfast scheme visit",
    "ward sanitation review", "metro feeder connectivity", "streetlight LED upgrade",
  ];
  const t1 = topics[h % topics.length];
  const t2 = topics[(h + 3) % topics.length];

  const summary = pending
    ? `The ${name} seat result is still being finalised. Meanwhile, civic chatter is ` +
      `trending around the ${t1} and ${t2}, with ${platform} driving most of the conversation this week.`
    : `${info.mla} (MLA, ${name}, ${info.party}) is trending around the ${t1} and ${t2}. ` +
      `Citizens are largely ${pos >= 55 ? "appreciative" : pos >= 45 ? "mixed but hopeful" : "critical"}, ` +
      `with the ${platform} conversation driving most of the buzz this week.`;

  const hashtags = [
    `#${name.replace(/[^A-Za-z]/g, "")}`,
    "#ChennaiCorporation",
    "#FixMyStreet",
    trend >= 0 ? "#GoodGovernance" : "#WeWantAction",
  ];

  return { mla: info.mla, party: info.party, image: info.image, pending, name, mentions, pos, neu, neg, reach, trend, platform, summary, hashtags };
}

function countComments(nodes = []) {
  return nodes.reduce((s, n) => s + 1 + countComments(n.replies || []), 0);
}

/** Engagement pulse from the citizen community feed (single-glance KPIs). */
export function communityKpis() {
  let likes = 0, shares = 0, comments = 0, pollVotes = 0, polls = 0;
  const authors = new Set();
  let top = null;
  for (const p of FEED) {
    likes += p.likes || 0;
    shares += p.shares || 0;
    comments += countComments(p.comments);
    if (p.type === "poll") { polls++; pollVotes += p.totalVotes || 0; }
    if (p.author) authors.add(p.author);
    const eng = (p.likes || 0) + (p.shares || 0) + countComments(p.comments);
    if (!top || eng > top.eng) top = { title: p.title || p.question, author: p.author, eng };
  }
  const engagement = likes + shares + comments;
  return {
    posts: FEED.length,
    stories: STORIES.length,
    likes, shares, comments, engagement,
    polls, pollVotes,
    voices: authors.size,
    avgEngagement: FEED.length ? Math.round(engagement / FEED.length) : 0,
    top,
  };
}

/* Community content flagged by the auto-moderation model as abusive/violating. */
export const FLAGGED_CONTENT = [
  {
    id: "mod-1", author: "angry_user_889", area: "Kodambakkam, Chennai",
    text: "These corporation officials are all useless *** and should be beaten up for ignoring our complaints!!",
    reason: "Threat / Incitement to violence", severity: "High", score: 0.94,
    context: "Comment on 'Garbage not cleared for several days'",
  },
  {
    id: "mod-2", author: "fake_news_reddy", area: "Velachery, Chennai",
    text: "BREAKING: the government is secretly poisoning the Velachery water supply — share before they delete this!",
    reason: "Health misinformation", severity: "High", score: 0.9,
    context: "Post in Velachery constituency feed",
  },
  {
    id: "mod-3", author: "casteslur_x", area: "Perambur, Chennai",
    text: "[redacted caste slur] people from that ward always create these problems, throw them out.",
    reason: "Hate speech / Casteist slur", severity: "High", score: 0.97,
    context: "Reply on 'Overflowing dustbin' post",
  },
  {
    id: "mod-4", author: "spam_loans_24x7", area: "T. Nagar, Chennai",
    text: "Get instant ₹5 lakh loan no documents!! WhatsApp +91-90000-00000 click bit.ly/xxxx now!!!",
    reason: "Spam / Scam link", severity: "Medium", score: 0.82,
    context: "Comment on Minister's Office update",
  },
  {
    id: "mod-5", author: "troll_master99", area: "Adyar, Chennai",
    text: "You are a stupid idiot if you actually believe this MLA will do anything, absolute clowns.",
    reason: "Abusive language / Harassment", severity: "Medium", score: 0.71,
    context: "Reply on Adyar stray-dogs post",
  },
];
