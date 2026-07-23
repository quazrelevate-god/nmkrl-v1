import 'dart:math' as math;

/// Port of lib/geo.js — great-circle distance in KM.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double toRad(double d) => d * math.pi / 180;
  final dLat = toRad(lat2 - lat1);
  final dLng = toRad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(toRad(lat1)) * math.cos(toRad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a.toDouble()), math.sqrt(1 - a.toDouble()));
}

/// "0.44 km" → "442 m", "1.4 km" — the issue-card distance format.
String formatDistanceKm(double km) =>
    km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

/// "23 Jul 2026" (en-IN short date, no intl dependency).
String formatShortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
