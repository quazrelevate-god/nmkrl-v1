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

/* Fictional MLA per constituency (mock — showcase only). */
export const MLA_BY_AC = {
  "11 - Dr. Radhakrishnan Nagar": "R. Senthil Vel",
  "12 - Perambur": "K. Arumugam",
  "13 - Kolathur": "M. Devanathan",
  "14 - Villivakkam": "S. Prabhu Rajan",
  "15 - Thiru-Vi-Ka-Nagar": "A. Jothi Murugan",
  "16 - Egmore": "V. Kalaiselvi",
  "17 - Harbour": "P. Dhanasekaran",
  "18 - Chepauk-Thiruvallikeni": "N. Karim Basha",
  "19 - Thousand Lights": "R. Ezhil Arasan",
  "20 - Anna Nagar": "S. Meenakshi Sundaram",
  "21 - Virugambakkam": "T. Bhuvaneswari",
  "22 - Saidapet": "G. Ramkumar",
  "23 - Thiyagarayanagar": "L. Chandrasekhar",
  "24 - Mylapore": "K. Vaidyanathan",
  "25 - Velachery": "D. Anitha Radhakrishnan",
  "26 - Shozhinganallur": "M. Suresh Babu",
};

const PLATFORMS = ["X (Twitter)", "Instagram", "Facebook", "YouTube"];

function hash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
  return Math.abs(h);
}

/** Deterministic mock social buzz for a constituency's MLA. */
export function socialMentions(ac) {
  const mla = MLA_BY_AC[ac] || "the Ward Councillor";
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

  const summary =
    `${mla}${ac ? ` (MLA, ${name})` : ""} is trending around the ${t1} and ${t2}. ` +
    `Citizens are largely ${pos >= 55 ? "appreciative" : pos >= 45 ? "mixed but hopeful" : "critical"}, ` +
    `with the ${platform} conversation driving most of the buzz this week.`;

  const hashtags = [
    `#${name.replace(/[^A-Za-z]/g, "")}`,
    "#ChennaiCorporation",
    "#FixMyStreet",
    trend >= 0 ? "#GoodGovernance" : "#WeWantAction",
  ];

  return { mla, name, mentions, pos, neu, neg, reach, trend, platform, summary, hashtags };
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
