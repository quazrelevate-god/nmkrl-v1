// Port of frontend/lib/deptRouting.js — deterministic routing of a ticket
// through the Tamil-Nadu grievance-routing taxonomy:
//
//   Government Department → Grievance Type → Grievance Sub-Type
//                        → Sub-Department → Responsible Officer
//
// A ticket id is hashed to pick a leaf, so the SAME ticket always resolves
// to the SAME (dept, type, subtype, subDept, officer) tuple. The mobile
// coordinator's Dept Transfer sheet uses `resolveRouting()` to seed the
// dept dropdown and its "AI ROUTING → RESPONSIBLE OFFICER" panel.

/// Map the app's coarse Gemini department name → a formal Government
/// Department in the taxonomy. Unknown/absent departments fall back to a
/// deterministic pick from the tree.
const Map<String, String> _appToGov = {
  'Solid Waste Management Department':
      'Municipal Administration and Water Supply Department (MAWS)',
  'Electrical Department': 'Energy Department (ENERGY)',
  'Works & Roads Department': 'Highways and Minor Ports Department (HWY)',
  'Storm Water Drain Department':
      'Municipal Administration and Water Supply Department (MAWS)',
  'Public Health Department': 'Health and Family Welfare Department (HEALTH)',
  'Parks & Playfields Department':
      'Municipal Administration and Water Supply Department (MAWS)',
  'Allied Utilities':
      'Municipal Administration and Water Supply Department (MAWS)',
};

int _fnv1a(String s) {
  var h = 2166136261;
  for (final code in s.codeUnits) {
    h ^= code;
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h;
}

/// Every government department in the taxonomy, sorted.
List<String> govDepartments(Map<String, dynamic> tree) {
  final keys = tree.keys.toList()..sort();
  return keys;
}

/// Flatten one department's leaves →
///   [ { type, subtype, subDepts[], officers[] } ]
List<({String type, String subtype, List<String> subDepts, List<String> officers})>
    deptLeaves(Map<String, dynamic> tree, String deptName) {
  final d = tree[deptName] as Map<String, dynamic>?;
  if (d == null) return const [];
  final out = <({String type, String subtype, List<String> subDepts, List<String> officers})>[];
  for (final typeEntry in d.entries) {
    final subs = typeEntry.value as Map<String, dynamic>;
    for (final subEntry in subs.entries) {
      final node = subEntry.value as Map<String, dynamic>;
      out.add((
        type: typeEntry.key,
        subtype: subEntry.key,
        subDepts: (node['sd'] as List?)?.map((e) => '$e').toList() ?? const [],
        officers: (node['ro'] as List?)?.map((e) => '$e').toList() ?? const [],
      ));
    }
  }
  return out;
}

class RoutingResult {
  const RoutingResult({
    required this.govDept,
    required this.type,
    required this.subtype,
    required this.subDept,
    required this.officer,
    required this.officers,
  });

  final String govDept;
  final String type;
  final String subtype;
  final String subDept;
  final String officer;

  /// All officers under this leaf (useful if the UI wants to let the
  /// coordinator swap the suggested officer for another in the same subDept).
  final List<String> officers;
}

/// Deterministic routing for one ticket, given a loaded taxonomy tree.
/// Uses [issue.id] as the seed so a ticket always lands on the same leaf.
RoutingResult? resolveRouting({
  required Map<String, dynamic> tree,
  required String issueId,
  String? geminiDepartment,
}) {
  if (tree.isEmpty) return null;
  final keys = tree.keys.toList();
  // 1) Try the Gemini → gov-dept lookup.
  final mapped = _appToGov[geminiDepartment];
  final govDept = (mapped != null && tree.containsKey(mapped))
      ? mapped
      : keys[_fnv1a(issueId.isEmpty ? 'x' : issueId) % keys.length];

  final leaves = deptLeaves(tree, govDept);
  if (leaves.isEmpty) return null;

  final seed = issueId.isEmpty ? 'x' : issueId;
  final leaf = leaves[_fnv1a(seed) % leaves.length];
  final subDept = leaf.subDepts.isNotEmpty ? leaf.subDepts.first : 'General Administration';
  final officer = leaf.officers.isNotEmpty
      ? leaf.officers[_fnv1a('${seed}o') % leaf.officers.length]
      : 'Public Grievance Officer';

  return RoutingResult(
    govDept: govDept,
    type: leaf.type,
    subtype: leaf.subtype,
    subDept: subDept,
    officer: officer,
    officers: leaf.officers,
  );
}
