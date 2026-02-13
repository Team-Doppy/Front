/// ParagraphNode metadata 키/값으로 리스트(번호, 불릿, 체크리스트) 타입 관리
class ListParagraphMeta {
  static const String listType = 'listType';
  static const String listIndex = 'listIndex';
  static const String checked = 'checked';

  static const String typeNumbered = 'numbered';
  static const String typeBullet = 'bullet';
  static const String typeChecklist = 'checklist';
  static const String typeQuote = 'quote';

  static bool isListParagraph(Map<String, dynamic>? metadata) {
    if (metadata == null) return false;
    final t = metadata[listType];
    return t == typeNumbered ||
        t == typeBullet ||
        t == typeChecklist ||
        t == typeQuote;
  }

  static String? getListType(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    final t = metadata[listType];
    if (t == typeNumbered ||
        t == typeBullet ||
        t == typeChecklist ||
        t == typeQuote) {
      return t as String;
    }
    return null;
  }

  static int getListIndex(Map<String, dynamic>? metadata) {
    if (metadata == null) return 1;
    final v = metadata[listIndex];
    if (v is int && v >= 1) return v;
    return 1;
  }

  static bool isChecked(Map<String, dynamic>? metadata) {
    if (metadata == null) return false;
    return metadata[checked] == true;
  }

  static Map<String, dynamic> listMetadata({
    required String type,
    int listIndex = 1,
    bool checked = false,
  }) {
    final m = <String, dynamic>{listType: type};
    if (type == typeNumbered) m[ListParagraphMeta.listIndex] = listIndex;
    if (type == typeChecklist) m[ListParagraphMeta.checked] = checked;
    return m;
  }

  /// 리스트 문단에서 새 문단으로 상속할 메타데이터.
  /// - numbered: listIndex만 +1
  /// - checklist: checked는 항상 false (새로 이어지는 항목은 체크 해제)
  static Map<String, dynamic> copyWithIncrementedIndex(
    Map<String, dynamic>? source,
  ) {
    final base = Map<String, dynamic>.from(source ?? {});
    final t = base[listType];
    if (t == typeNumbered) {
      base[listIndex] = getListIndex(base) + 1;
    } else if (t == typeChecklist) {
      base[checked] = false;
    }
    return base;
  }
}
