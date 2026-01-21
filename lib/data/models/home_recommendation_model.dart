/// 추천 카드 타입
enum RecCardType { TIME_BASED, EVENT_EMOTION, SOCIAL }

/// 홈용 추천 카드 응답 모델
class RecCardForHomeResponse {
  final String recId;
  final RecCardType recType;
  final String title;
  final List<String> titleBoldSubstrings;
  final String narrative;
  final List<int> postIds;
  final int? anchorPostId;
  final List<Map<String, dynamic>> posts;

  RecCardForHomeResponse({
    required this.recId,
    required this.recType,
    required this.title,
    required this.titleBoldSubstrings,
    required this.narrative,
    required this.postIds,
    this.anchorPostId,
    required this.posts,
  });

  factory RecCardForHomeResponse.fromJson(Map<String, dynamic> json) {
    // recType 문자열을 enum으로 변환
    RecCardType recType;
    final recTypeStr = json['recType'] as String? ?? '';
    switch (recTypeStr) {
      case 'TIME_BASED':
        recType = RecCardType.TIME_BASED;
        break;
      case 'EVENT_EMOTION':
        recType = RecCardType.EVENT_EMOTION;
        break;
      case 'SOCIAL':
        recType = RecCardType.SOCIAL;
        break;
      default:
        recType = RecCardType.TIME_BASED; // 기본값
    }

    return RecCardForHomeResponse(
      recId: json['recId'] as String? ?? '',
      recType: recType,
      title: json['title'] as String? ?? '',
      titleBoldSubstrings:
          (json['titleBoldSubstrings'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      narrative: json['narrative'] as String? ?? '',
      postIds:
          (json['postIds'] as List<dynamic>?)?.map((e) => e as int).toList() ??
          [],
      anchorPostId: json['anchorPostId'] as int?,
      posts:
          (json['posts'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    String recTypeStr;
    switch (recType) {
      case RecCardType.TIME_BASED:
        recTypeStr = 'TIME_BASED';
        break;
      case RecCardType.EVENT_EMOTION:
        recTypeStr = 'EVENT_EMOTION';
        break;
      case RecCardType.SOCIAL:
        recTypeStr = 'SOCIAL';
        break;
    }

    return {
      'recId': recId,
      'recType': recTypeStr,
      'title': title,
      'titleBoldSubstrings': titleBoldSubstrings,
      'narrative': narrative,
      'postIds': postIds,
      'anchorPostId': anchorPostId,
      'posts': posts,
    };
  }
}
