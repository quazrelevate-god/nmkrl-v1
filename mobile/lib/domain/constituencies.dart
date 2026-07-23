/// Port of lib/constituencies.js — Chennai Assembly Constituency ↔ GCC ward
/// mapping (mirror of the backend CHENNAI_AC_MAP). Wards can clip/overlap
/// across AC lines, so a ward maps to a LIST of ACs.
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

/// All AC names (keys), in numeric order.
final List<String> kConstituencies = kChennaiAcMap.keys.toList();

/// The wards used by the "jump to Egmore" demo shortcut.
const List<String> kEgmoreWards = ['58', '61', '77', '78', '104', '108'];

/// Return the list of ACs a ward number belongs to.
List<String> constituenciesForWard(Object? ward) {
  if (ward == null || '$ward'.trim().isEmpty) return [];
  final key = '$ward'.trim();
  return kConstituencies
      .where((ac) => kChennaiAcMap[ac]!.contains(key))
      .toList();
}

/// "20 - Anna Nagar" → "Anna Nagar".
String shortAC(String? ac) =>
    (ac ?? '').replaceFirst(RegExp(r'^\d+\s*-\s*'), '');

/// "ANNA NAGAR" → "Anna Nagar" for display.
String titleCase(String s) => s
    .toLowerCase()
    .replaceAllMapped(RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());
