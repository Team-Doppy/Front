class LoginResponse {
  final String token;
  final String type;
  final String username;

  LoginResponse({
    required this.token,
    required this.type,
    required this.username,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token'],
      type: json['type'],
      username: json['username'],
    );
  }
}