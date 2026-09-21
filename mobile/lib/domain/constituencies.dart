/// Chennai Assembly Constituency ↔ GCC ward mapping (mirror of the backend
/// CHENNAI_AC_MAP). Reference data only: the app uses the LIVE corporation's
/// table from GET /api/corporation ([activeAcMap]), because the MLA office's
/// console switches the app between Tambaram and Chennai. Wards can clip/
/// overlap across AC lines, so a ward maps to a LIST of ACs.
const Map<String, List<String>> kChennaiAcMap = {
  '11 - Dr. Radhakrishnan Nagar': ['38', '39', '40', '41', '42', '43', '47'],
  '12 - Perambur': ['34', '35', '36', '37', '44', '45', '46', '64', '65', '66', '67', '68', '69', '70'],
  '13 - Kolathur': ['64', '65', '66', '67', '68', '69', '70'],
  '14 - Villivakkam': ['94', '95', '96', '97', '98', '102', '103', '104'],
  '15 - Thiru-Vi-Ka-Nagar': ['71', '72', '73', '74', '75', '76'],
  '16 - Egmore': ['58', '61', '77', '78', '104', '108'],
  '17 - Harbour': ['54', '55', '56', '57', '59', '60'],
  '18 - Chepauk-Thiruvallikeni': ['62', '63', '114', '115', '116', '119', '120'],
  '19 - Thousand Lights': ['109', '110', '111', '112', '113', '117', '118'],
  '20 - Anna Nagar': ['100', '101', '102', '103', '105', '106', '107'],
  '21 - Virugambakkam': ['127', '128', '129', '136', '137', '138'],
  '22 - Saidapet': ['126', '139', '140', '142', '168', '169', '170', '171', '172', '173', '174', '175', '176', '177', '178', '179', '180'],
  '23 - Thiyagarayanagar': ['130', '131', '132', '133', '134', '135', '141'],
  '24 - Mylapore': ['126', '170', '171', '172', '173', '174', '175', '176', '177', '178', '179', '180'],
  '25 - Velachery': ['139', '140', '142', '168', '169', '181', '182', '183', '184', '192', '193', '194'],
  '26 - Shozhinganallur': ['191', '195', '196', '197', '198', '199', '200'],
};

/// The live corporation's constituency -> wards table. Empty until the app
/// has heard from the server (see corporationProvider, which sets it and
/// remembers it for the next launch).
Map<String, List<String>> _activeAcMap = const {};

Map<String, List<String>> get activeAcMap => _activeAcMap;

/// Install the live corporation's table (corporationProvider calls this).
void setActiveAcMap(Map<String, List<String>> table) => _activeAcMap = table;

/// All AC names (keys) of the live corporation.
List<String> get kConstituencies => _activeAcMap.keys.toList();

/// The wards used by the "jump to Egmore" demo shortcut.
const List<String> kEgmoreWards = ['58', '61', '77', '78', '104', '108'];

/// Return the list of ACs a ward number belongs to, in the live corporation.
/// A grievance carries its own server-computed list (Issue.constituencies);
/// prefer that — an old report may be from the other corporation.
List<String> constituenciesForWard(Object? ward) {
  if (ward == null || '$ward'.trim().isEmpty) return [];
  final key = '$ward'.trim();
  return kConstituencies
      .where((ac) => _activeAcMap[ac]!.contains(key))
      .toList();
}

/// "20 - Anna Nagar" → "Anna Nagar". A group without a number (Tambaram's
/// "Tambaram Corporation") is returned as it is.
String shortAC(String? ac) =>
    (ac ?? '').replaceFirst(RegExp(r'^\d+\s*-\s*'), '');

/// The short form for tight spots (map pills, card pills): "20 - Anna Nagar"
/// → "Anna Nagar", and Tambaram's whole-corporation group "Tambaram
/// Corporation" → "Tambaram".
String compactAC(String? ac) =>
    shortAC(ac).replaceFirst(RegExp(r'\s+Corporation$'), '');

/// "ANNA NAGAR" → "Anna Nagar" for display.
String titleCase(String s) => s
    .toLowerCase()
    .replaceAllMapped(RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());

/// One Assembly Constituency and the wards under it, for grouped pickers.
class WardGroup {
  const WardGroup(this.key, this.label, this.wards);

  /// Stable id, unique across groups: the constituency number ("16"), the
  /// name of an unnumbered group, or [WardGroup.unmappedKey] for wards no
  /// constituency covers.
  final String key;

  /// "16 · Egmore", "Tambaram Corporation", or "No constituency yet".
  final String label;
  final List<String> wards;

  static const unmappedKey = 'none';

  bool get isUnmapped => key == unmappedKey;
}

/// [wards] grouped the way the admin dashboard groups them: by Assembly
/// Constituency, in constituency-number order, wards ascending within each.
///
/// A ward on a constituency boundary is listed under every constituency it
/// belongs to. Wards the constituency table does not cover come last, in their
/// own group, rather than being dropped: a grievance filed in one reaches no
/// coordinator and no MLA office, and a person choosing a ward needs to see
/// that before they choose it.
List<WardGroup> groupWardsByConstituency(
  Iterable<String> wards, {
  Map<String, List<String>>? table,
}) {
  final acMap = table ?? _activeAcMap;
  final available = wards.toSet();
  int byNumber(String a, String b) =>
      (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0);
  String numberOf(String ac) => ac.split(' - ').first.trim();

  final acs = [...acMap.keys]
    ..sort((a, b) => byNumber(numberOf(a), numberOf(b)));
  final out = <WardGroup>[];
  final placed = <String>{};
  for (final ac in acs) {
    final inAc = (acMap[ac] ?? const <String>[])
        .where(available.contains)
        .toList()
      ..sort(byNumber);
    if (inAc.isEmpty) continue;
    placed.addAll(inAc);
    final number = numberOf(ac);
    // A numbered assembly constituency reads "16 · Egmore"; an unnumbered
    // group (Tambaram's whole-corporation placeholder) reads as its name.
    final numbered = int.tryParse(number) != null;
    out.add(WardGroup(number, numbered ? '$number · ${shortAC(ac)}' : ac, inAc));
  }
  final unmapped = available.where((w) => !placed.contains(w)).toList()
    ..sort(byNumber);
  if (unmapped.isNotEmpty) {
    out.add(WardGroup(WardGroup.unmappedKey, 'No constituency yet', unmapped));
  }
  return out;
}
