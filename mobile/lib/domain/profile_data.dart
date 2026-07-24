/// Port of the PROFILE mock data from lib/communityData.js — the citizen
/// profile shown in the expandable home header and on Edit Profile.
class ProfileData {
  ProfileData._();

  // TODO: replace these mock stats with API-backed values (the user's own
  // report list from /api/issues/history) once the data layer supports it.
  static const name = 'Raj Kumar';
  static const upvotes = 56;
  static const reports = 24;
  static const resolved = 18;

  /// Grievances not yet resolved (Assigned / In Progress / Verification
  /// Pending). Derived so it stays correct when reports/resolved go live.
  static int get open => reports - resolved;

  static String get initials =>
      name.split(' ').map((w) => w[0]).join().toUpperCase();
}
