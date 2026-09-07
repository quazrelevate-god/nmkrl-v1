/// The authenticated citizen account, as returned by POST /api/auth/login.
/// Phase-1 identity: one account per phone number; every report / upvote /
/// verification is stamped with [id].
class CitizenUser {
  const CitizenUser({
    required this.id,
    required this.name,
    required this.phone,
    this.created = false,
    this.hasPin = false,
  });

  final String id;
  final String name;
  final String phone;

  /// True when this login auto-registered a brand-new profile.
  final bool created;

  /// Whether this account has an app-open PIN yet. False for a new account
  /// AND for every account created before PINs existed — both are taken
  /// through the same "create your PIN" screen.
  final bool hasPin;

  factory CitizenUser.fromJson(Map<String, dynamic> json) => CitizenUser(
        id: '${json['id']}',
        name: '${json['name']}',
        phone: '${json['phone']}',
        created: json['created'] == true,
        hasPin: json['has_pin'] == true,
      );
}
