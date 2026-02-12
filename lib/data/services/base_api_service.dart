import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class BaseApiService {
  static final BaseApiService _instance = BaseApiService._internal();
  factory BaseApiService() => _instance;
  BaseApiService._internal() {
    _setupInterceptors();
  }

  static const String baseUrl = 'https://api.doppy.app';
  final AuthService _auth = AuthService();

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json; charset=UTF-8'},
  ));

  Dio get dio => _dio;

  void _setupInterceptors() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (opt, h) async {
        final path = opt.path;
        final isAuth = path.contains('/api/auth/login') || path.contains('/api/auth/refresh');
        if (!isAuth) {
          final token = await _auth.getToken();
          if (token != null && token.isNotEmpty) {
            opt.headers['Authorization'] = 'Bearer $token';
          } else if (kDebugMode) {
            debugPrint('[BaseApi] no token for ${opt.method} ${opt.path}');
          }
        }
        if (kDebugMode) {
          debugPrint('[BaseApi] ${opt.method} ${opt.path}');
        }
        h.next(opt);
      },
      onError: (e, h) async {
        // 401이면 재시도하지 않고 에러 전파 → SplashScreen 등에서 온보딩(로그인)으로 보냄
        h.next(e);
      },
    ));
  }
}
