class User {
  final String id;
  final String email;
  final String role;
  final String name;
  final String token;

  User({
    required this.id,
    required this.email,
    required this.role,
    required this.name,
    required this.token,
  });

  /// Parses the flat `POST /auth/login` response:
  /// `{ access_token, token_type, role, user_id }`
  ///
  /// [email] and [name] are passed in from the request since the login
  /// response does not echo them back.
  factory User.fromLoginResponse(
    Map<String, dynamic> json, {
    required String email,
    required String name,
  }) {
    return User(
      id: (json['user_id'] as String?) ?? '',
      email: email,
      role: (json['role'] as String?) ?? 'shipper',
      name: name,
      token: (json['access_token'] as String?) ?? '',
    );
  }

  /// Parses the `GET /auth/me` response:
  /// `{ id, email, role, name, created_at }`
  ///
  /// [token] is injected from secure storage since /auth/me does not
  /// return the token.
  factory User.fromMeResponse(
    Map<String, dynamic> json, {
    required String token,
  }) {
    return User(
      id: (json['id'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      role: (json['role'] as String?) ?? 'shipper',
      name: (json['name'] as String?) ?? '',
      token: token,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role,
      'name': name,
      'token': token,
    };
  }
}
