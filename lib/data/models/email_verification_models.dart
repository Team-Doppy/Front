import 'api_error_model.dart';

class EmailSendCodeResult {
  final bool success;
  final String? message;
  final int? statusCode;
  final ApiErrorModel? error;
  final DateTime? expiresAt; // 서버에서 받은 만료 시간
  final int? expiresIn; // 서버에서 받은 만료 시간 (초 단위)

  const EmailSendCodeResult({
    required this.success,
    this.message,
    this.statusCode,
    this.error,
    this.expiresAt,
    this.expiresIn,
  });
}

class EmailVerifyCodeResult {
  final bool success;
  final bool? verified;
  final String? message;
  final int? statusCode;
  final ApiErrorModel? error;

  const EmailVerifyCodeResult({
    required this.success,
    this.verified,
    this.message,
    this.statusCode,
    this.error,
  });
}
