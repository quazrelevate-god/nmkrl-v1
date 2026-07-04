/**
 * lib/constituencies.js
 * ---------------------
 * Frontend mirror of the backend CHENNAI_AC_MAP (utils.py). Lets the admin
 * portal filter tickets by Assembly Constituency purely client-side (the queue
 * already loads the full set for the heatmap), and populate the AC dropdown.
 * Wards can clip/overlap across AC lines, so a ward maps to a list of ACs.
 */

export const CHENNAI_AC_MAP = {
  "11 - Dr. Radhakrishnan Nagar": ["38", "39", "40", "41", "42", "43", "47"],
  "12 - Perambur": ["34", "35", "36", "37", "44", "45", "46", "64", "65", "66", "67", "68", "69", "70"],
  "13 - Kolathur": ["64", "65", "66", "67", "68", "69", "70"],
  "14 - Villivakkam": ["94", "95", "96", "97", "98", "102", "103", "104"],
  "15 - Thiru-Vi-Ka-Nagar": ["71", "72", "73", "74", "75", "76"],
  "16 - Egmore": ["58", "61", "77", "78", "104", "108"],
  "17 - Harbour": ["54", "55", "56", "57", "59", "60"],
  "18 - Chepauk-Thiruvallikeni": ["62", "63", "114", "115", "116", "119", "120"],
  "19 - Thousand Lights": ["109", "110", "111", "112", "113", "117", "118"],
  "20 - Anna Nagar": ["100", "101", "102", "103", "105", "106", "107"],
  "21 - Virugambakkam": ["127", "128", "129", "136", "137", "138"],
  "22 - Saidapet": ["126", "139", "140", "142", "168", "169", "170", "171", "172", "173", "174", "175", "176", "177", "178", "179", "180"],
  "23 - Thiyagarayanagar": ["130", "131", "132", "133", "134", "135", "141"],
  "24 - Mylapore": ["126", "170", "171", "172", "173", "174", "175", "176", "177", "178", "179", "180"],
  "25 - Velachery": ["139", "140", "142", "168", "169", "181", "182", "183", "184", "192", "193", "194"],
  "26 - Shozhinganallur": ["191", "195", "196", "197", "198", "199", "200"],
};

/** All AC names (keys), in numeric order. */
export const CONSTITUENCIES = Object.keys(CHENNAI_AC_MAP);

/** Return the list of ACs a ward number belongs to. */
export function constituenciesForWard(ward) {
  if (ward == null || ward === "") return [];
  const key = String(ward).trim();
  return CONSTITUENCIES.filter((ac) => CHENNAI_AC_MAP[ac].includes(key));
}

/** Does an issue's ward fall within the given AC? */
export function issueInConstituency(issue, ac) {
  if (!ac) return true;
  return CHENNAI_AC_MAP[ac]?.includes(String(issue.ward_no)) || false;
}

/** "20 - Anna Nagar" → "Anna Nagar". */
export function shortAC(ac) {
  return String(ac || "").replace(/^\d+\s*-\s*/, "");
}
