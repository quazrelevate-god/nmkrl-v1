/// The authenticated citizen account, as returned by POST /api/auth/login.
/// Phase-1 identity: one account per phone number; every report / upvote /
/// verification is stamped with [id].
class CitizenUser {
  const CitizenUser({
    required this.id,
    required this.name,
    required this.phone,
    this.created = false,
  });

  final String id;
  final String name;
  final String phone;

  /// True when this login auto-registered a brand-new profile.
  final bool created;

  factory CitizenUser.fromJson(Map<String, dynamic> json) => CitizenUser(
        id: '${json['id']}',
        name: '${json['name']}',
        phone: '${json['phone']}',
        created: json['created'] == true,
      );
}
