import 'package:dio/dio.dart';

import 'auth_interceptor.dart';

class BaseApiService {
  static final BaseApiService _instance = BaseApiService._internal();
  factory BaseApiService() => _instance;
  BaseApiService._internal() {
    _dio.interceptors.add(AuthInterceptor.create(_dio, debugLabel: 'BaseApi'));
  }

  static const String baseUrl = 'https://api.doppy.app';

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json; charset=UTF-8'},
  ));

  Dio get dio => _dio;
}
