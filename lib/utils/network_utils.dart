import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'dart:ui';

import 'package:flutter/material.dart';

/// 네트워크 에러 타입 분류
enum NetworkErrorType {
  noConnection, // 인터넷 연결 없음
  timeout, // 타임아웃
  serverError, // 서버 에러 (5xx)
  unauthorized, // 인증 에러 (401)
  notFound, // 리소스 없음 (404)
  badRequest, // 잘못된 요청 (400)
  unknown, // 기타 에러
}

class ConnectivityReloadCoordinator {
  static final ConnectivityReloadCoordinator _instance =
      ConnectivityReloadCoordinator._internal();
  factory ConnectivityReloadCoordinator() => _instance;
  ConnectivityReloadCoordinator._internal();

  StreamSubscription<dynamic>? _subscription;
  final Map<String, _Handler> _handlers = {};
  Timer? _debounce;

  void start() {
    _subscription ??= NetworkManager.onConnectivityChanged.listen((
      dynamic isOnlineDyn,
    ) {
      final bool isOnline = isOnlineDyn == true;
      if (!isOnline) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), _notifyHandlers);
    });
  }

  /// 핸들러 등록. 반환된 콜백을 호출하면 등록 해제됩니다.
  VoidCallback registerHandler({
    required String id,
    required Future<void> Function() onOnline,
  }) {
    _handlers[id] = _Handler(onOnline: onOnline);
    return () => _handlers.remove(id);
  }

  void _notifyHandlers() {
    for (final entry in _handlers.entries) {
      final handler = entry.value;
      if (handler.inProgress) continue;
      handler.inProgress = true;
      handler.onOnline().catchError((_) {}).whenComplete(() {
        handler.inProgress = false;
      });
    }
  }
}

class _Handler {
  final Future<void> Function() onOnline;
  bool inProgress;
  _Handler({required this.onOnline}) : inProgress = false;
}

/// 네트워크 에러 클래스
class NetworkError implements Exception {
  final NetworkErrorType type;
  final String message;
  final String userMessage;
  final int? statusCode;
  final bool isRetryable;

  const NetworkError({
    required this.type,
    required this.message,
    required this.userMessage,
    this.statusCode,
    this.isRetryable = false,
  });

  @override
  String toString() => 'NetworkError: $message (${statusCode ?? 'N/A'})';
}

/// 재시도 설정
class RetryConfig {
  final int maxRetries;
  final Duration initialDelay;
  final double backoffMultiplier;
  final List<NetworkErrorType> retryableErrors;

  const RetryConfig({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.retryableErrors = const [
      NetworkErrorType.timeout,
      NetworkErrorType.noConnection,
      NetworkErrorType.serverError,
    ],
  });
}

/// 간단한 네트워크 관리자
class NetworkManager {
  static bool _isOnline = true;
  static bool _hasRecentError = false;
  static final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();

  /// 네트워크 에러 발생 시 호출
  static void setNetworkError(bool hasError) {
    _hasRecentError = hasError;
    final newOnline = !hasError;
    if (_isOnline != newOnline) {
      _isOnline = newOnline;
      try {
        _connectivityController.add(_isOnline);
      } catch (_) {}
    }
  }

  /// 네트워크 연결 복구 시 호출
  static void setNetworkRecovered() {
    _hasRecentError = false;
    if (!_isOnline) {
      _isOnline = true;
      try {
        _connectivityController.add(true);
      } catch (_) {}
    }
  }

  /// 간단한 연결 상태 확인
  static Future<bool> checkConnection() async {
    // 최근 네트워크 에러가 있으면 오프라인으로 판단
    return !_hasRecentError;
  }

  /// 빈 스트림 (연결 상태 모니터링 안함)
  static Stream<bool> get onConnectivityChanged =>
      _connectivityController.stream;

  /// 현재 연결 상태
  static bool get isOnline => _isOnline;

  /// 🎯 connectivity_plus 제거로 인해 비활성화
  /// 네트워크 상태는 DioException을 통해서만 감지
  static void initConnectivityMonitor({
    String pingUrl = BaseApiService.baseUrl,
  }) {
    // connectivity_plus 패키지 제거로 인해 비활성화
    // 네트워크 상태는 DioException을 통해서만 감지됨
  }
}

/// 네트워크 유틸리티 클래스
class NetworkUtils {
  /// DioException을 NetworkError로 변환
  static NetworkError parseError(dynamic error) {
    if (error is NetworkError) return error;

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          // 네트워크 에러 상태 설정
          NetworkManager.setNetworkError(true);
          return NetworkError(
            type: NetworkErrorType.timeout,
            message: 'Request timeout: ${error.message}',
            userMessage: '오프라인 상태입니다',
            isRetryable: true,
          );

        case DioExceptionType.connectionError:
          // 네트워크 에러 상태 설정
          NetworkManager.setNetworkError(true);
          return NetworkError(
            type: NetworkErrorType.noConnection,
            message: 'Connection error: ${error.message}',
            userMessage: '오프라인 상태입니다',
            isRetryable: true,
          );

        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          switch (statusCode) {
            case 400:
              return NetworkError(
                type: NetworkErrorType.badRequest,
                message: 'Bad request: ${error.response?.data}',
                userMessage: '잘못된 요청입니다.',
                statusCode: statusCode,
                isRetryable: false,
              );
            case 401:
              return NetworkError(
                type: NetworkErrorType.unauthorized,
                message: 'Unauthorized: ${error.response?.data}',
                userMessage: '인증이 필요합니다. 다시 로그인해주세요.',
                statusCode: statusCode,
                isRetryable: false,
              );
            case 404:
              return NetworkError(
                type: NetworkErrorType.notFound,
                message: 'Not found: ${error.response?.data}',
                userMessage: '요청한 데이터를 찾을 수 없습니다.',
                statusCode: statusCode,
                isRetryable: false,
              );
            case 500:
            case 502:
            case 503:
            case 504:
              // ✅ 서버 에러(5xx)는 "오프라인"으로 간주하지 않는다.
              // (오프라인 배너는 noConnection/timeout 같은 실제 연결 문제일 때만 떠야 함)
              return NetworkError(
                type: NetworkErrorType.serverError,
                message: 'Server error: ${error.response?.data}',
                userMessage: '서버 오류가 발생했습니다.',
                statusCode: statusCode,
                isRetryable: true,
              );
            default:
              return NetworkError(
                type: NetworkErrorType.unknown,
                message: 'HTTP error: ${error.response?.data}',
                userMessage: '알 수 없는 오류가 발생했습니다.',
                statusCode: statusCode,
                isRetryable: false,
              );
          }

        default:
          return NetworkError(
            type: NetworkErrorType.unknown,
            message: 'Dio error: ${error.message}',
            userMessage: '네트워크 오류가 발생했습니다.',
            isRetryable: false,
          );
      }
    }

    if (error is SocketException) {
      // 소켓 에러도 네트워크 문제로 간주
      NetworkManager.setNetworkError(true);
      return NetworkError(
        type: NetworkErrorType.noConnection,
        message: 'Socket error: ${error.message}',
        userMessage: '오프라인 상태입니다',
        isRetryable: true,
      );
    }

    return NetworkError(
      type: NetworkErrorType.unknown,
      message: 'Unknown error: $error',
      userMessage: '알 수 없는 오류가 발생했습니다.',
      isRetryable: false,
    );
  }

  /// 재시도 로직이 포함된 네트워크 요청 실행
  static Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    RetryConfig config = const RetryConfig(),
    String? operationName,
  }) async {
    int attempts = 0;
    NetworkError? lastError;

    while (attempts < config.maxRetries) {
      attempts++;

      try {
        // 연결 상태 확인 (첫 번째 시도가 아닌 경우)
        if (attempts > 1) {
          final isConnected = await NetworkManager.checkConnection();
          if (!isConnected) {
            throw NetworkError(
              type: NetworkErrorType.noConnection,
              message: 'No internet connection',
              userMessage: '오프라인 상태입니다',
              isRetryable: true,
            );
          }
        }

        debugPrint(
          '[NetworkUtils] ${operationName ?? 'Operation'} 시도 $attempts/${config.maxRetries}',
        );
        final result = await operation();

        if (attempts > 1) {
          debugPrint('[NetworkUtils] ${operationName ?? 'Operation'} 재시도 성공!');
        }

        return result;
      } catch (e) {
        lastError = parseError(e);

        debugPrint(
          '[NetworkUtils] ${operationName ?? 'Operation'} 실패 (시도 $attempts): ${lastError.message}',
        );

        // 재시도 불가능한 에러이거나 최대 시도 횟수에 도달한 경우
        if (!config.retryableErrors.contains(lastError.type) ||
            attempts >= config.maxRetries) {
          break;
        }

        // 백오프 지연
        final delay = Duration(
          milliseconds:
              (config.initialDelay.inMilliseconds *
                      pow(config.backoffMultiplier, attempts - 1))
                  .round(),
        );

        debugPrint('[NetworkUtils] ${delay.inMilliseconds}ms 후 재시도...');
        await Future.delayed(delay);
      }
    }

    debugPrint(
      '[NetworkUtils] ${operationName ?? 'Operation'} 최종 실패: ${lastError?.message}',
    );
    throw lastError ??
        NetworkError(
          type: NetworkErrorType.unknown,
          message: 'Operation failed after $attempts attempts',
          userMessage: '요청 처리에 실패했습니다.',
        );
  }

  /// 에러 타입에 따른 아이콘 반환
  static String getErrorIcon(NetworkErrorType type) {
    switch (type) {
      case NetworkErrorType.noConnection:
        return '📡';
      case NetworkErrorType.timeout:
        return '⏱️';
      case NetworkErrorType.serverError:
        return '🔧';
      case NetworkErrorType.unauthorized:
        return '🔒';
      case NetworkErrorType.notFound:
        return '🔍';
      case NetworkErrorType.badRequest:
        return '⚠️';
      case NetworkErrorType.unknown:
        return '❓';
    }
  }

  /// 에러 타입에 따른 제목 반환
  static String getErrorTitle(NetworkErrorType type) {
    switch (type) {
      case NetworkErrorType.noConnection:
        return '인터넷 연결 없음';
      case NetworkErrorType.timeout:
        return '요청 시간 초과';
      case NetworkErrorType.serverError:
        return '서버 오류';
      case NetworkErrorType.unauthorized:
        return '인증 필요';
      case NetworkErrorType.notFound:
        return '데이터 없음';
      case NetworkErrorType.badRequest:
        return '잘못된 요청';
      case NetworkErrorType.unknown:
        return '알 수 없는 오류';
    }
  }
}
