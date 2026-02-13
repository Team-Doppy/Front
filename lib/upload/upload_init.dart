import 'package:dio/dio.dart';

import '../../data/services/auth_interceptor.dart';
import 'core/upload_config.dart';
import 'service/upload_service.dart';
import 'backends/r2/r2_upload_backend.dart';

/// 업로드 모듈 초기화
///
/// [apiBaseUrl]을 문자열로 주입하여 R2 백엔드·Dio·UploadService를 생성합니다.
/// 호스트 앱의 설정(config, env 등)에서 URL을 가져와 넘기면 됩니다.
class UploadInit {
  UploadInit._();

  static UploadService? _instance;

  /// [apiBaseUrl] 문자열로 R2 백엔드 초기화 후 [UploadService] 반환.
  /// 이미 초기화된 경우 같은 인스턴스 반환.
  /// AuthInterceptor로 토큰 첨부 + 401 시 리프레시 후 재시도.
  ///
  /// 예: `await UploadInit.ensureInitialized(apiBaseUrl: 'https://your-api.com')`
  static Future<UploadService> ensureInitialized({
    required String apiBaseUrl,
  }) async {
    if (_instance != null) return _instance!;

    final baseUrl = apiBaseUrl.trim();

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
    ));
    dio.interceptors.add(AuthInterceptor.create(dio, debugLabel: 'Upload'));

    final backend = R2UploadBackend.fromDio(dio: dio, baseUrl: baseUrl);
    final service = UploadService();
    await service.initialize(UploadConfig(backend: backend));
    _instance = service;
    return service;
  }

  /// 이미 [ensureInitialized] 호출된 뒤에만 사용. 아니면 null.
  static UploadService? get instance => _instance;
}
