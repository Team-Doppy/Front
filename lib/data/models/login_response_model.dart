class LoginResponse {
  final String token;
  final String refreshToken;
  final String type;
  final String username;

  LoginResponse({
    required this.token,
    required this.refreshToken,
    required this.type,
    required this.username,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token'],
      refreshToken: json['refreshToken'],
      type: json['type'],
      username: json['username'],
    );
  }
}
