/// Port of lib/ticket.js — deterministic, human-friendly tracking ticket
/// derived from an issue's UUID. Same id → same ticket, always.
String ticketNumber(String? id) {
  if (id == null || id.isEmpty) return 'FMS-UNKNOWN';
  final hex = id.replaceAll('-', '');
  final head = hex.length >= 8 ? hex.substring(0, 8) : hex;
  return 'FMS-${head.toUpperCase()}';
}
