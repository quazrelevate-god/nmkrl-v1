import 'models/issue.dart';

/// Port of lib/coordinators.js — the 4 seeded Egmore constituency
/// coordinators (illustrative PoC auth; plain-text by design for the demo).
class Coordinator {
  const Coordinator({
    required this.username,
    required this.password,
    required this.name,
    required this.initials,
    required this.role,
    required this.constituency,
    required this.homeWard,
    required this.civicScore,
    required this.reports,
    required this.resolved,
    required this.upvotes,
    required this.tenure,
  });

  final String username;
  final String password;
  final String name;
  final String initials;
  final String role;
  final String constituency;
  final String homeWard;
  final int civicScore;
  final int reports;
  final int resolved;
  final int upvotes;
  final String tenure;
}

const kCoordinators = [
  Coordinator(
    username: 'raja', password: 'raja123',
    name: 'V. Ramkumar Raja', initials: 'VR', role: 'Constituency Lead',
    constituency: '16 - Egmore', homeWard: '58',
    civicScore: 1560, reports: 112, resolved: 88, upvotes: 214, tenure: '4y 8m'),
  Coordinator(
    username: 'suresh', password: 'suresh123',
    name: 'Suresh Balan', initials: 'SB', role: 'Constituency PA',
    constituency: '16 - Egmore', homeWard: '77',
    civicScore: 1180, reports: 92, resolved: 71, upvotes: 168, tenure: '2y 6m'),
  Coordinator(
    username: 'karthik', password: 'karthik123',
    name: 'Karthik Sundaram', initials: 'KS', role: 'Ward Coordinator',
    constituency: '16 - Egmore', homeWard: '78',
    civicScore: 1240, reports: 87, resolved: 62, upvotes: 156, tenure: '3y 4m'),
  Coordinator(
    username: 'meena', password: 'meena123',
    name: 'Meena Lakshmi', initials: 'ML', role: 'Ward Coordinator',
    constituency: '16 - Egmore', homeWard: '104',
    civicScore: 1310, reports: 96, resolved: 79, upvotes: 190, tenure: '3y 1m'),
];

Coordinator? authenticateCoordinator(String username, String password) {
  for (final c in kCoordinators) {
    if (c.username == username.trim().toLowerCase() && c.password == password) {
      return c;
    }
  }
  return null;
}

Coordinator? coordinatorByUsername(String? username) {
  for (final c in kCoordinators) {
    if (c.username == username) return c;
  }
  return null;
}

/// The three coordinator tabs, partitioned exactly like the web page's
/// useMemos:
///   ward     = grievances I haven't taken ownership of yet
///   mine     = verified by me and still active (actions keep them here)
///   previous = terminal: CLOSED by citizen approval OR FALSE
({List<Issue> ward, List<Issue> mine, List<Issue> previous}) partitionWardIssues(
  List<Issue> issues,
  Set<String> verifiedIds,
) {
  final ward = <Issue>[];
  final mine = <Issue>[];
  final previous = <Issue>[];
  for (final i in issues) {
    if (!verifiedIds.contains(i.id)) {
      ward.add(i);
    } else if (i.status == 'CLOSED' || i.status == 'FALSE') {
      previous.add(i);
    } else {
      mine.add(i);
    }
  }
  return (ward: ward, mine: mine, previous: previous);
}
