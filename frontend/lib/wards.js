/**
 * lib/wards.js
 * ------------
 * Client-side helpers over the canonical ward grid fetched from /api/wards.
 * The grid is the backend's source of truth; here we only read it (draw +
 * "which ward am I in"), so no PRNG/generation logic lives on the client.
 */

/** Return the ward number whose rectangle contains (lat, lng), or null. */
export function wardForCoords(wards, lat, lng) {
  if (!wards || lat == null || lng == null) return null;
  for (const w of wards) {
    if (lat >= w.lat_min && lat <= w.lat_max && lng >= w.lng_min && lng <= w.lng_max) {
      return w.number;
    }
  }
  return null;
}
