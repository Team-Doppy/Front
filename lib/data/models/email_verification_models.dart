/// 이메일 인증 코드 발송 결과
class EmailSendCodeResult {
  final bool success;
  final int? statusCode;
  final String? message;
  final DateTime? expiresAt;
  final int? expiresIn;

  const EmailSendCodeResult({
    required this.success,
    this.statusCode,
    this.message,
    this.expiresAt,
    this.expiresIn,
  });
}

/// 이메일 인증 코드 검증 결과
class EmailVerifyCodeResult {
  final bool success;
  final bool? verified;
  final int? statusCode;
  final String? message;
  final ApiError? error;

  const EmailVerifyCodeResult({
    required this.success,
    this.verified,
    this.statusCode,
    this.message,
    this.error,
  });
}

/// ID 찾기 결과
class FindUsernameResult {
  final bool success;
  final String? username;
  final String? message;

  const FindUsernameResult({
    required this.success,
    this.username,
    this.message,
  });
}

/// 비밀번호 재설정 결과
class ResetPasswordResult {
  final bool success;
  final String? message;

  const ResetPasswordResult({required this.success, this.message});
}

class ApiError {
  final String error;
  final String? message;

  const ApiError({required this.error, this.message});

  factory ApiError.fromJson(Map<String, dynamic> json) {
    // support nested: { "error": { "error": "CODE", "message": "..." } }
    final err = json['error'];
    if (err is Map<String, dynamic>) {
      return ApiError(
        error: (err['error'] ?? '').toString(),
        message: err['message']?.toString(),
      );
    }
    return ApiError(
      error: (json['error'] ?? '').toString(),
      message: json['message']?.toString(),
    );
  }
}
