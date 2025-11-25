import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:doppy/data/services/auth_service.dart';

enum WebSocketState { disconnected, connecting, connected, error }

class WebSocketService extends ChangeNotifier {
  WebSocket? webSocket;
  WebSocketState wsState = WebSocketState.disconnected;

  // 콜백 함수들
  Function(Map<String, dynamic>)? onCommentCreated;
  Function(Map<String, dynamic>)? onCommentUpdated;
  Function(Map<String, dynamic>)? onCommentDeleted;
  Function(Map<String, dynamic>)? onCommentLiked;
  Function(Map<String, dynamic>)? onCommentUnliked;

  // WebSocket 연결
  Future<void> connect() async {
    // 이미 연결되어 있으면 중복 연결 방지
    if (wsState == WebSocketState.connected ||
        wsState == WebSocketState.connecting) {
      debugPrint('[WebSocketService] ⚠️ 이미 연결되어 있거나 연결 중입니다 - 중복 연결 방지');
      return;
    }

    try {
      wsState = WebSocketState.connecting;

      final token = await AuthService().getToken();
      final wsUrl = 'wss://api.doppy.app/ws?token=$token';
      webSocket = await WebSocket.connect(wsUrl);
      wsState = WebSocketState.connected;
      webSocket!.listen(_onMessageReceived);
    } catch (e) {
      wsState = WebSocketState.error;
      debugPrint('[WebSocketService] 연결 실패: $e');
    }
  }

  // 메시지 수신 처리 (비동기로 처리하여 Hang 방지)
  void _onMessageReceived(dynamic data) {
    // 🎯 비동기로 처리하여 UI 스레드 블로킹 방지
    Future.microtask(() async {
      try {
        final message = json.decode(data);
        final messageType = message['type'] as String?;

        debugPrint('[WebSocketService] 📥 원본 데이터: $data');
        debugPrint('[WebSocketService] 📥 파싱된 메시지: $message');
        debugPrint('[WebSocketService] 📥 메시지 타입: $messageType');
        debugPrint('[WebSocketService] 📥 전체 키들: ${message.keys.toList()}');

        // 🎯 성능 최적화: 콜백 호출 전에 UI 업데이트 기회 제공
        await Future.delayed(Duration.zero);

        switch (messageType) {
          case 'COMMENT_CREATED':
            onCommentCreated?.call(message);
            break;
          case 'COMMENT_UPDATED':
            onCommentUpdated?.call(message);
            break;
          case 'COMMENT_DELETED':
            onCommentDeleted?.call(message);
            break;
          case 'COMMENT_LIKED':
            onCommentLiked?.call(message);
            break;
          case 'COMMENT_UNLIKED':
            onCommentUnliked?.call(message);
            break;
          case 'SUCCESS':
            debugPrint('[WebSocketService] 연결 성공: ${message['message']}');
            break;
          case 'ERROR':
            debugPrint('[WebSocketService] 에러: ${message['message']}');
            break;
          case 'SUBSCRIBED':
            debugPrint('[WebSocketService] 구독 성공: ${message['postId']}');
            break;
          default:
            debugPrint('[WebSocketService] 알 수 없는 메시지 타입: $messageType');
            break;
        }
      } catch (e) {
        debugPrint('[WebSocketService] 메시지 파싱 오류: $e');
      }
    });
  }

  // 포스트 댓글 구독
  void subscribeToPostComments(String postId) {
    final message = {'action': 'subscribe', 'postId': postId};
    _sendMessage(message);
  }

  // 메시지 전송
  void _sendMessage(Map<String, dynamic> message) {
    if (webSocket != null) {
      debugPrint('[WebSocketService] 전송할 메시지: ${json.encode(message)}');
      webSocket!.add(json.encode(message));
    }
  }

  // 콜백 설정
  void setCallbacks({
    Function(Map<String, dynamic>)? onCommentCreated,
    Function(Map<String, dynamic>)? onCommentUpdated,
    Function(Map<String, dynamic>)? onCommentDeleted,
    Function(Map<String, dynamic>)? onCommentLiked,
    Function(Map<String, dynamic>)? onCommentUnliked,
  }) {
    this.onCommentCreated = onCommentCreated;
    this.onCommentUpdated = onCommentUpdated;
    this.onCommentDeleted = onCommentDeleted;
    this.onCommentLiked = onCommentLiked;
    this.onCommentUnliked = onCommentUnliked;
  }

  // 연결 해제
  void disconnect() {
    webSocket?.close();
    wsState = WebSocketState.disconnected;
    debugPrint('[WebSocketService] 연결 해제 완료');
  }

  // 연결 상태 getter
  bool get isConnected => wsState == WebSocketState.connected;
  bool get isStompConnected => wsState == WebSocketState.connected;

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
