/// 언급 파싱 유틸리티
/// 명세서의 언급 규칙을 모두 고려하여 구현
class MentionParser {
  /// 메시지에서 언급된 사용자명 추출
  ///
  /// 규칙:
  /// - ✅ @john - 유효
  /// - ✅ @user123 - 유효
  /// - ✅ @user_name - 유효 (언더스코어 포함)
  /// - ✅ "안녕하세요 @john 님!" - 유효 (메시지 중간에 포함 가능)
  /// - ✅ "@john @jane 모두 확인해주세요" - 여러 명 언급 가능
  /// - ❌ @john doe - 공백 포함 (유효하지 않음, 별도로 @john과 @doe로 인식)
  /// - ❌ @john-doe - 하이픈 포함 (유효하지 않음)
  /// - ❌ @john@jane - 연속 언급 (각각 별도로 인식)
  ///
  /// 반환: 중복 제거된 username 목록
  static List<String> extractMentions(String message) {
    if (message.isEmpty) return [];

    // @로 시작하고, 영문자/숫자/언더스코어로만 구성된 패턴 매칭
    // \w+ 는 [a-zA-Z0-9_] 와 동일
    final mentionRegex = RegExp(r'@(\w+)');

    final mentions = <String>[];
    final matches = mentionRegex.allMatches(message);

    for (final match in matches) {
      if (match.groupCount >= 1) {
        final username = match.group(1);
        if (username != null && username.isNotEmpty) {
          mentions.add(username);
        }
      }
    }

    // 중복 제거 (Set 사용)
    return mentions.toSet().toList();
  }

  /// 메시지에 언급이 포함되어 있는지 확인
  static bool hasMentions(String message) {
    return extractMentions(message).isNotEmpty;
  }

  /// 특정 사용자가 언급되었는지 확인
  static bool isMentioned(String message, String username) {
    return extractMentions(message).contains(username);
  }

  /// 메시지에서 언급 부분을 하이라이트할 수 있도록 파싱
  /// 반환: (텍스트, 언급 여부) 튜플 리스트
  static List<({String text, bool isMention})> parseMessageWithMentions(
    String message,
  ) {
    if (message.isEmpty) return [];

    final parts = <({String text, bool isMention})>[];
    final mentionRegex = RegExp(r'@(\w+)');

    int lastEnd = 0;
    final matches = mentionRegex.allMatches(message);

    for (final match in matches) {
      // 언급 전의 일반 텍스트
      if (match.start > lastEnd) {
        final beforeText = message.substring(lastEnd, match.start);
        if (beforeText.isNotEmpty) {
          parts.add((text: beforeText, isMention: false));
        }
      }

      // 언급 부분
      final mentionText = match.group(0) ?? '';
      if (mentionText.isNotEmpty) {
        parts.add((text: mentionText, isMention: true));
      }

      lastEnd = match.end;
    }

    // 마지막 언급 이후의 일반 텍스트
    if (lastEnd < message.length) {
      final afterText = message.substring(lastEnd);
      if (afterText.isNotEmpty) {
        parts.add((text: afterText, isMention: false));
      }
    }

    // 매칭이 없으면 전체를 일반 텍스트로
    if (parts.isEmpty) {
      parts.add((text: message, isMention: false));
    }

    return parts;
  }
}
