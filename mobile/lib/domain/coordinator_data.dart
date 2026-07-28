import 'models/issue.dart';

/// The authenticated constituency-staff account, as returned by
/// POST /api/auth/coordinator/login. Fields come from the admin-created
/// record in the backend `coordinators` table — there are no hardcoded
/// demo accounts on the mobile side anymore.
class Coordinator {
  const Coordinator({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    required this.constituency,
    required this.homeWard,
    this.mustChangePassword = false,
  });

  final String id;
  final String username;
  final String name;
  final String role;

  /// Fixed on sign-in — the coordinator can switch wards WITHIN this AC but
  /// not change the AC itself.
  final String constituency;

  /// The default ward the app opens on. The dropdown may switch to other
  /// wards inside [constituency] once loaded.
  final String homeWard;

  final bool mustChangePassword;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.map((w) => w[0]).take(2).join().toUpperCase();
  }

  factory Coordinator.fromJson(Map<String, dynamic> json) => Coordinator(
        id: '${json['id']}',
        username: '${json['username']}',
        name: '${json['name']}',
        role: '${json['role'] ?? ''}',
        constituency: '${json['constituency'] ?? ''}',
        homeWard: '${json['home_ward'] ?? json['homeWard'] ?? ''}',
        mustChangePassword:
            json['must_change_password'] == true || json['mustChangePassword'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'role': role,
        'constituency': constituency,
        'home_ward': homeWard,
        'must_change_password': mustChangePassword,
      };
}

/// The four tabs a coordinator navigates. Escalated is a first-class tab
/// (backed by `escalated_at` on the issue). Terminal statuses (CLOSED /
/// FALSE) go to Previous.
enum CoordinatorTab { ward, mine, escalated, previous }

/// Partition ward issues by tab, taking backend-persisted state as the
/// source of truth:
///   ward:      unassigned open grievances (any coord may verify)
///   mine:      assigned to me AND not-escalated AND not-terminal
///   escalated: assigned to me AND escalated_at is non-null AND not-terminal
///   previous:  assigned to me AND terminal (CLOSED or FALSE)
///
/// Grievances assigned to OTHER coordinators are not returned by the backend
/// for this coordinator, so they never show up in any tab.
({List<Issue> ward, List<Issue> mine, List<Issue> escalated, List<Issue> previous})
    partitionForCoordinator(List<Issue> issues, String myUsername) {
  final me = myUsername.toLowerCase();
  final ward = <Issue>[];
  final mine = <Issue>[];
  final escalated = <Issue>[];
  final previous = <Issue>[];
  for (final i in issues) {
    final owner = (i.assignedCoordinator ?? '').toLowerCase();
    final terminal = i.status == 'CLOSED' || i.status == 'FALSE';
    if (owner.isEmpty) {
      if (!terminal) ward.add(i);
      // (terminal + unassigned is a rare seed-only edge case; drop it.)
    } else if (owner == me) {
      if (terminal) {
        previous.add(i);
      } else if (i.escalatedAt != null) {
        escalated.add(i);
      } else {
        mine.add(i);
      }
    }
    // owner != me → hidden entirely
  }
  return (ward: ward, mine: mine, escalated: escalated, previous: previous);
}
