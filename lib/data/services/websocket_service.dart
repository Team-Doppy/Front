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
      print('[WebSocketService] ⚠️ 이미 연결되어 있거나 연결 중입니다 - 중복 연결 방지');
      return;
    }

    try {
      wsState = WebSocketState.connecting;

      final token = await AuthService().getToken();
      final wsUrl = 'wss://nbillion.co.kr/ws?token=$token';
      webSocket = await WebSocket.connect(wsUrl);
      wsState = WebSocketState.connected;
      webSocket!.listen(_onMessageReceived);
    } catch (e) {
      wsState = WebSocketState.error;
      print('[WebSocketService] 연결 실패: $e');
    }
  }

  // 메시지 수신 처리
  void _onMessageReceived(dynamic data) {
    try {
      final message = json.decode(data);
      final messageType = message['type'] as String?;

      print('[WebSocketService] 📥 원본 데이터: $data');
      print('[WebSocketService] 📥 파싱된 메시지: $message');
      print('[WebSocketService] 📥 메시지 타입: $messageType');
      print('[WebSocketService] 📥 전체 키들: ${message.keys.toList()}');

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
          print('[WebSocketService] 연결 성공: ${message['message']}');
          break;
        case 'ERROR':
          print('[WebSocketService] 에러: ${message['message']}');
          break;
        case 'SUBSCRIBED':
          print('[WebSocketService] 구독 성공: ${message['postId']}');
          break;
        default:
          print('[WebSocketService] 알 수 없는 메시지 타입: $messageType');
          break;
      }
    } catch (e) {
      print('[WebSocketService] 메시지 파싱 오류: $e');
    }
  }

  // 포스트 댓글 구독
  void subscribeToPostComments(String postId) {
    final message = {'action': 'subscribe', 'postId': postId};
    _sendMessage(message);
  }

  // 메시지 전송
  void _sendMessage(Map<String, dynamic> message) {
    if (webSocket != null) {
      print('[WebSocketService] 전송할 메시지: ${json.encode(message)}');
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
    print('[WebSocketService] 연결 해제 완료');
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
