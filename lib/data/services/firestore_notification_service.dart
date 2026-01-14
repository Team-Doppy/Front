import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import 'auth_service.dart';

class FirestoreNotificationService {
  static final FirestoreNotificationService _instance =
      FirestoreNotificationService._internal();
  factory FirestoreNotificationService() => _instance;
  FirestoreNotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 현재 사용자 username 가져오기
  Future<String?> getCurrentUsername() async {
    try {
      final authService = AuthService();
      final username = await authService.getUsername();
      return username;
    } catch (e) {
      debugPrint('[FirestoreNotificationService] username 가져오기 실패: $e');
      return null;
    }
  }

  /// 초기 알림 데이터 로드 (스플래시에서 사용)
  Future<List<NotificationData>> loadInitialNotifications({
    int limit = 20,
  }) async {
    try {
      final username = await getCurrentUsername();
      if (username == null || username.isEmpty) {
        debugPrint(
          '[FirestoreNotificationService] username이 없어 알림을 불러올 수 없습니다',
        );
        return [];
      }

      debugPrint('[FirestoreNotificationService] 초기 알림 로드: username=$username');

      final querySnapshot =
          await _firestore
              .collection('notifications')
              .where('username', isEqualTo: username)
              .orderBy('createdAt', descending: true)
              .limit(limit)
              .get();

      final notifications =
          querySnapshot.docs.map((doc) {
            return NotificationData.fromFirestore(doc.id, doc.data());
          }).toList();

      debugPrint(
        '[FirestoreNotificationService] 알림 ${notifications.length}개 로드 완료',
      );
      return notifications;
    } catch (e) {
      debugPrint('[FirestoreNotificationService] 초기 알림 로드 실패: $e');
      // 권한 오류인 경우 빈 리스트 반환 (알림 컬렉션이 없거나 권한이 없을 수 있음)
      if (e.toString().contains('permission-denied')) {
        debugPrint('[FirestoreNotificationService] Firestore 권한 오류 - 빈 리스트 반환');
      }
      return [];
    }
  }

  /// 읽지 않은 알림 개수 조회
  Future<int> getUnreadCount() async {
    try {
      final username = await getCurrentUsername();
      if (username == null || username.isEmpty) {
        debugPrint(
          '[FirestoreNotificationService] username이 없어 읽지 않은 알림 개수를 조회할 수 없습니다',
        );
        return 0;
      }

      debugPrint(
        '[FirestoreNotificationService] 읽지 않은 알림 개수 조회: username=$username',
      );

      final querySnapshot =
          await _firestore
              .collection('notifications')
              .where('username', isEqualTo: username)
              .where('read', isEqualTo: false)
              .get();

      debugPrint(
        '[FirestoreNotificationService] 읽지 않은 알림 개수: ${querySnapshot.docs.length}',
      );
      return querySnapshot.docs.length;
    } catch (e) {
      debugPrint('[FirestoreNotificationService] 읽지 않은 알림 개수 조회 실패: $e');
      debugPrint('[FirestoreNotificationService] 에러 타입: ${e.runtimeType}');
      // 권한 오류인 경우 0 반환
      if (e.toString().contains('permission-denied')) {
        debugPrint('[FirestoreNotificationService] Firestore 권한 오류 - 0 반환');
        debugPrint(
          '[FirestoreNotificationService] 권한 오류 상세: notifications 컬렉션에 대한 읽기 권한이 없습니다. Firestore 보안 규칙을 확인하세요.',
        );
      }
      return 0;
    }
  }

  /// 알림 읽음 처리
  Future<void> markAsRead(String documentId) async {
    try {
      await _firestore.collection('notifications').doc(documentId).update({
        'read': true,
      });
      debugPrint('[FirestoreNotificationService] 알림 읽음 처리: $documentId');
    } catch (e) {
      debugPrint('[FirestoreNotificationService] 알림 읽음 처리 실패: $e');
      rethrow;
    }
  }

  /// 모든 알림 읽음 처리
  Future<void> markAllAsRead() async {
    try {
      final username = await getCurrentUsername();
      if (username == null || username.isEmpty) {
        return;
      }

      final querySnapshot =
          await _firestore
              .collection('notifications')
              .where('username', isEqualTo: username)
              .where('read', isEqualTo: false)
              .get();

      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();

      debugPrint('[FirestoreNotificationService] 모든 알림 읽음 처리 완료');
    } catch (e) {
      debugPrint('[FirestoreNotificationService] 모든 알림 읽음 처리 실패: $e');
      rethrow;
    }
  }

  /// 실시간 알림 구독 (알림 스크린이 열려있을 때만 사용)
  Stream<List<NotificationData>> subscribeNotifications({
    required String username,
    int limit = 50,
  }) {
    try {
      debugPrint('[FirestoreNotificationService] 알림 구독 시작: username=$username');
      final query = _firestore
          .collection('notifications')
          .where('username', isEqualTo: username)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      return query
          .snapshots()
          .map((snapshot) {
            return snapshot.docs.map((doc) {
              return NotificationData.fromFirestore(doc.id, doc.data());
            }).toList();
          })
          .handleError((error) {
            debugPrint('[FirestoreNotificationService] 알림 구독 오류: $error');
            // 권한 오류인 경우 빈 리스트 스트림 반환
            if (error.toString().contains('permission-denied')) {
              debugPrint(
                '[FirestoreNotificationService] Firestore 권한 오류 - 빈 리스트 반환',
              );
            }
            return <NotificationData>[];
          });
    } catch (e) {
      debugPrint('[FirestoreNotificationService] 알림 구독 실패: $e');
      return Stream.value(<NotificationData>[]);
    }
  }

  /// 읽지 않은 알림 개수 실시간 구독
  Stream<int> subscribeUnreadCount({required String username}) {
    try {
      debugPrint(
        '[FirestoreNotificationService] 읽지 않은 알림 개수 구독 시작: username=$username',
      );
      final query = _firestore
          .collection('notifications')
          .where('username', isEqualTo: username)
          .where('read', isEqualTo: false);

      return query
          .snapshots()
          .map((snapshot) => snapshot.docs.length)
          .handleError((error) {
            debugPrint(
              '[FirestoreNotificationService] 읽지 않은 알림 개수 구독 오류: $error',
            );
            // 권한 오류인 경우 0 반환
            if (error.toString().contains('permission-denied')) {
              debugPrint(
                '[FirestoreNotificationService] Firestore 권한 오류 - 0 반환',
              );
            }
            return 0;
          });
    } catch (e) {
      debugPrint('[FirestoreNotificationService] 읽지 않은 알림 개수 구독 실패: $e');
      return Stream.value(0);
    }
  }
}
