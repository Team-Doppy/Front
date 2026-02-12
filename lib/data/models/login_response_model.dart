class LoginResponse {
  final String token;
  final String refreshToken;
  final String type;
  final String username;

  LoginResponse({
    required this.token,
    required this.refreshToken,
    this.type = 'Bearer',
    required this.username,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    final token = (data['token'] ?? data['accessToken'] ?? data['access_token'] ?? '').toString();
    return LoginResponse(
      token: token,
      refreshToken: (data['refreshToken'] ?? data['refresh_token'] ?? '').toString(),
      type: (data['type'] ?? 'Bearer').toString(),
      username: (data['username'] ?? '').toString(),
    );
  }
}
