import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'base_api_service.dart';
import '../models/notification_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final Dio _dio = BaseApiService().dio;

  /// 알림 목록 조회
  /// [page] - 페이지 번호 (0부터 시작)
  /// [size] - 페이지 크기
  Future<List<NotificationData>> getNotifications({
    int page = 0,
    int size = 20,
  }) async {
    try {
      debugPrint('[NotificationService] 알림 목록 조회: page=$page, size=$size');
      final response = await _dio.get(
        '/api/notifications',
        queryParameters: {'page': page, 'size': size},
      );

      if (response.statusCode == 200) {
        final responseData = response.data;
        List<dynamic> notificationsData = [];

        // 응답 구조에 따라 파싱
        if (responseData is Map<String, dynamic>) {
          if (responseData.containsKey('content')) {
            notificationsData = responseData['content'] as List<dynamic>? ?? [];
          } else if (responseData.containsKey('data')) {
            notificationsData = responseData['data'] as List<dynamic>? ?? [];
          } else if (responseData.containsKey('notifications')) {
            notificationsData =
                responseData['notifications'] as List<dynamic>? ?? [];
          }
        } else if (responseData is List) {
          notificationsData = responseData;
        }

        final notifications =
            notificationsData
                .map(
                  (json) =>
                      NotificationData.fromJson(json as Map<String, dynamic>),
                )
                .toList();

        debugPrint('[NotificationService] 알림 ${notifications.length}개 조회 완료');
        return notifications;
      }

      throw Exception('알림 목록 조회 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 404) {
          // API가 아직 구현되지 않은 경우 빈 리스트 반환
          debugPrint('[NotificationService] 알림 API가 아직 구현되지 않음 (404)');
          return [];
        }
        debugPrint('[NotificationService] 알림 목록 조회 실패: $statusCode');
      } else {
        debugPrint('[NotificationService] 알림 목록 조회 실패: $e');
      }
      rethrow;
    }
  }

  /// 알림 읽음 처리
  Future<void> markAsRead(int notificationId) async {
    try {
      debugPrint('[NotificationService] 알림 읽음 처리: $notificationId');
      await _dio.put('/api/notifications/$notificationId/read');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 404) {
          debugPrint('[NotificationService] 알림 읽음 API가 아직 구현되지 않음 (404)');
          return;
        }
        debugPrint('[NotificationService] 알림 읽음 처리 실패: $statusCode');
      } else {
        debugPrint('[NotificationService] 알림 읽음 처리 실패: $e');
      }
      rethrow;
    }
  }

  /// 모든 알림 읽음 처리
  Future<void> markAllAsRead() async {
    try {
      debugPrint('[NotificationService] 모든 알림 읽음 처리');
      await _dio.put('/api/notifications/read-all');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 404) {
          debugPrint('[NotificationService] 모든 알림 읽음 API가 아직 구현되지 않음 (404)');
          return;
        }
        debugPrint('[NotificationService] 모든 알림 읽음 처리 실패: $statusCode');
      } else {
        debugPrint('[NotificationService] 모든 알림 읽음 처리 실패: $e');
      }
      rethrow;
    }
  }

  /// 읽지 않은 알림 개수 조회
  Future<int> getUnreadCount() async {
    try {
      debugPrint('[NotificationService] 읽지 않은 알림 개수 조회');
      final response = await _dio.get('/api/notifications/unread-count');

      if (response.statusCode == 200) {
        final responseData = response.data;
        final count =
            responseData is Map
                ? (responseData['count'] as int? ??
                    responseData['unreadCount'] as int? ??
                    0)
                : (responseData as int? ?? 0);
        return count;
      }

      throw Exception('읽지 않은 알림 개수 조회 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 404) {
          debugPrint('[NotificationService] 읽지 않은 알림 개수 API가 아직 구현되지 않음 (404)');
          return 0;
        }
        debugPrint('[NotificationService] 읽지 않은 알림 개수 조회 실패: $statusCode');
      } else {
        debugPrint('[NotificationService] 읽지 않은 알림 개수 조회 실패: $e');
      }
      return 0;
    }
  }
}
