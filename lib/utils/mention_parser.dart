/// 언급 파싱 유틸리티
/// 명세서의 언급 규칙을 모두 고려하여 구현
class MentionParser {
  // username token: 영문/숫자/_ + 점(.) 세그먼트 허용
  // - 연속 점/끝 점 방지: (?:\.[...]+)* 구조
  static final RegExp _mentionTokenRegex = RegExp(
    r'@([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*)',
  );

  static bool _isWordChar(String ch) {
    // username/email 등에 쓰이는 기본 word 범위만 차단하면 됨
    return RegExp(r'[A-Za-z0-9_]').hasMatch(ch);
  }

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

    final mentions = <String>[];
    int i = 0;

    while (i < message.length) {
      final at = message.indexOf('@', i);
      if (at == -1) break;

      // ✅ 경계 조건: 이메일(test@domain.com)처럼 단어/아이디 중간의 @는 멘션으로 보지 않음
      if (at > 0 && _isWordChar(message[at - 1])) {
        i = at + 1;
        continue;
      }

      // ✅ @ 위치에서 token을 prefix로 매칭
      final m = _mentionTokenRegex.matchAsPrefix(message, at);
      if (m == null) {
        i = at + 1;
        continue;
      }

      final username = m.group(1) ?? '';
      if (username.isEmpty) {
        i = at + 1;
        continue;
      }

      // ✅ 점이 깨진 케이스 방어: @jang. / @jang..xx 처럼 '.'이 바로 뒤에 오면 부분매칭(@jang)도 무효 처리
      if (m.end < message.length && message[m.end] == '.') {
        i = at + 1;
        continue;
      }

      mentions.add(username);
      i = m.end;
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
    int lastEnd = 0;
    int i = 0;

    while (i < message.length) {
      final at = message.indexOf('@', i);
      if (at == -1) break;

      // 이메일/단어 중간의 @는 멘션으로 처리하지 않음
      if (at > 0 && _isWordChar(message[at - 1])) {
        i = at + 1;
        continue;
      }

      final m = _mentionTokenRegex.matchAsPrefix(message, at);
      if (m == null) {
        i = at + 1;
        continue;
      }

      // 점 깨짐 방어: 부분매칭도 무효
      if (m.end < message.length && message[m.end] == '.') {
        i = at + 1;
        continue;
      }

      // 언급 전 일반 텍스트
      if (at > lastEnd) {
        final beforeText = message.substring(lastEnd, at);
        if (beforeText.isNotEmpty) {
          parts.add((text: beforeText, isMention: false));
        }
      }

      final mentionText = m.group(0) ?? '';
      if (mentionText.isNotEmpty) {
        parts.add((text: mentionText, isMention: true));
      }

      lastEnd = m.end;
      i = m.end;
    }

    // 마지막 이후 텍스트
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
