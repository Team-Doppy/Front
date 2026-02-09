import 'package:doppy/data/models/user_model.dart';

/// 곰신 요청 상태
enum GirlfriendRequestStatus {
  pending, // 대기 중 (수락/거절 대기)
  accepted, // 수락됨 (연결 완료)
  rejected, // 거절됨
  expired, // 만료됨 (선택적)
}

/// 곰신 요청 모델
class GirlfriendRequest {
  final String requestId; // 요청 ID
  final User requester; // 요청을 보낸 곰신 사용자 정보
  final GirlfriendRequestStatus status; // 요청 상태
  final DateTime requestedAt; // 요청 시간
  final DateTime? respondedAt; // 응답 시간 (수락/거절 시)

  GirlfriendRequest({
    required this.requestId,
    required this.requester,
    required this.status,
    required this.requestedAt,
    this.respondedAt,
  });

  factory GirlfriendRequest.fromJson(Map<String, dynamic> json) {
    return GirlfriendRequest(
      requestId: json['requestId'] as String,
      requester: User.fromJson(json['requester'] as Map<String, dynamic>),
      status: GirlfriendRequestStatus.values.firstWhere(
        (e) => e.name == json['status'] as String,
        orElse: () => GirlfriendRequestStatus.pending,
      ),
      requestedAt: DateTime.parse(json['requestedAt'] as String),
      respondedAt:
          json['respondedAt'] != null
              ? DateTime.parse(json['respondedAt'] as String)
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'requester': requester,
      'status': status.name,
      'requestedAt': requestedAt.toIso8601String(),
      'respondedAt': respondedAt?.toIso8601String(),
    };
  }

  GirlfriendRequest copyWith({
    String? requestId,
    User? requester,
    GirlfriendRequestStatus? status,
    DateTime? requestedAt,
    DateTime? respondedAt,
  }) {
    return GirlfriendRequest(
      requestId: requestId ?? this.requestId,
      requester: requester ?? this.requester,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }
}
