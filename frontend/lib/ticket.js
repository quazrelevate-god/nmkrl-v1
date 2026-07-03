/**
 * lib/ticket.js
 * -------------
 * Deterministic, human-friendly tracking ticket derived from an issue's UUID.
 * The same issue id always yields the same ticket, so it can be shown on the
 * success popup AND later in My History for future reference.
 */

export function ticketNumber(id) {
  if (!id) return "FMS-UNKNOWN";
  const hex = id.replace(/-/g, "").slice(0, 8).toUpperCase();
  return `FMS-${hex}`;
}
