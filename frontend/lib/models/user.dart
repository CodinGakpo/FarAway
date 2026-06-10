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

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      name: json['name'] as String,
      token: json['token'] as String,
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
