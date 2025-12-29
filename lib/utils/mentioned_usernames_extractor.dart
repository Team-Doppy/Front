/// 게시글 content(JSON)에서 mentionedUsernames를 추출한다.
///
/// 우선순위(중요):
/// 1) 에디터가 export한 멘션 메타 노드(`type: "mention"`, `usernames: [...]`)를 1순위로 사용
///
/// - 최대 30개까지만 반환 (서버도 앞 30명만 처리)
/// - 중복 제거는 서버에서 한다고 되어 있으나, 클라이언트에서도 제거해도 무방하므로 안정성 위해 제거
class MentionedUsernamesExtractor {
  MentionedUsernamesExtractor._();

  static List<String> extractFromContent(Map<String, dynamic>? content) {
    if (content == null) return const [];

    final List<dynamic> nodes =
        (content['nodes'] is List) ? List<dynamic>.from(content['nodes']) : [];

    final List<String> out = <String>[];
    final Set<String> seen = <String>{};

    void add(String u) {
      final v = u.trim();
      if (v.isEmpty) return;
      if (seen.add(v)) out.add(v);
    }

    for (final n in nodes) {
      if (n is! Map) continue;
      final String type = (n['type'] ?? '').toString();

      // ✅ 1순위: PostExporter가 내보내는 멘션 노드
      if (type == 'mention') {
        final List<dynamic> usernamesDyn =
            (n['usernames'] is List) ? List<dynamic>.from(n['usernames']) : [];
        for (final u in usernamesDyn) {
          add(u.toString());
        }
      }

      // ✅ 레거시 방어: type이 mention이 아니어도 usernames 필드가 있으면 수집
      // (과거 포맷/변형 포맷에서 usernames가 남아있는 경우를 대비)
      if (type != 'mention' && n['usernames'] is List) {
        final List<dynamic> usernamesDyn = List<dynamic>.from(n['usernames']);
        for (final u in usernamesDyn) {
          add(u.toString());
        }
      }
    }

    // 최대 30명 제한
    if (out.length > 30) {
      return out.take(30).toList();
    }
    return out;
  }
}
