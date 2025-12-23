import 'package:super_editor/super_editor.dart';

/// 🎯 문서 구조 관리 전담 서비스
/// - 제목 문단 보정
/// - 정렬 승계
/// - 문서 구조 검증
class DocumentStructureService {
  final MutableDocument document;
  final Editor editor;

  DocumentStructureService({required this.document, required this.editor});

  /// 🎯 제목이 항상 맨 위(index 0)에 있도록 보정
  void ensureTitleAtTop() {
    int titleIndex = -1;
    ParagraphNode? titleNode;

    // 0,1번까지만 체크
    for (int i = 0; i < document.length && i < 2; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode && node.metadata['isTitle'] == true) {
        titleIndex = i;
        titleNode = node;
        break;
      }
    }

    if (titleIndex == -1) {
      // 제목 없으면 새로 추가
      document.insertNodeAt(
        0,
        ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(),
          metadata: {'isTitle': true, 'textAlign': 'center'},
        ),
      );
    } else if (titleIndex > 0) {
      // 이미 맨 위에 있지 않으면 위치만 교체
      final node = titleNode!;
      document
        ..deleteNode(titleNode.id)
        ..insertNodeAt(0, node);
    }

    // 제목 정렬 보정 (다른 텍스트 문단의 정렬과 맞춤)
    _alignTitleWithBody();
  }

  /// 제목을 본문의 정렬과 맞춤
  void _alignTitleWithBody() {
    final title = document.getNodeAt(0);
    if (title is! ParagraphNode || title.metadata['isTitle'] != true) {
      return;
    }

    // 다른 텍스트 문단의 정렬 찾기
    String targetAlignment = 'center';
    for (int i = 1; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode) {
        final String? align = node.metadata['textAlign'] as String?;
        if (align != null) {
          targetAlignment = align;
          break;
        }
      }
    }

    final meta = Map<String, dynamic>.from(title.metadata);
    meta['textAlign'] = targetAlignment;
    final updated = ParagraphNode(
      id: title.id,
      text: title.text,
      metadata: meta,
    );
    document.replaceNodeById(title.id, updated);
  }

  /// 🎯 0번째만 제목이고, 나머지는 제목이 아니도록 보정
  void ensureOnlyFirstIsTitle() {
    try {
      // 0번째는 제목 유지
      if (document.isNotEmpty) {
        final node0 = document.getNodeAt(0);

        if (node0 is ParagraphNode) {
          final meta0 = Map<String, dynamic>.from(node0.metadata);
          if (meta0['isTitle'] != true) {
            meta0['isTitle'] = true;
            document.replaceNodeById(
              node0.id,
              ParagraphNode(id: node0.id, text: node0.text, metadata: meta0),
            );
          }
        }
      }

      // 1번째부터는 제목 금지
      if (document.length > 1) {
        final node1 = document.getNodeAt(1);
        if (node1 is ParagraphNode) {
          final meta1 = Map<String, dynamic>.from(node1.metadata);
          if (meta1['isTitle'] == true) {
            meta1.remove('isTitle');
            document.replaceNodeById(
              node1.id,
              ParagraphNode(id: node1.id, text: node1.text, metadata: meta1),
            );
          }
        }
      }
    } catch (_) {}
  }

  /// 🎯 삽입된 문단의 정렬을 이전 문단과 맞춤
  void ensureParagraphAlignmentForIndex(int index) {
    if (index < 0 || index >= document.length) return;

    final node = document.getNodeAt(index);
    if (node is! ParagraphNode) return;

    final Map<String, dynamic> meta = Map<String, dynamic>.from(node.metadata);
    final String? align = meta['textAlign'] as String?;
    if (align != null) return;

    String previousAlign = 'center';
    for (int i = index - 1; i >= 0; i--) {
      final prev = document.getNodeAt(i);
      if (prev is ParagraphNode) {
        final String? prevAlign = prev.metadata['textAlign'] as String?;
        if (prevAlign != null) {
          previousAlign = prevAlign;
        }
        break;
      }
    }

    meta['textAlign'] = previousAlign;
    final replaced = ParagraphNode(
      id: node.id,
      text: node.text,
      metadata: meta,
    );
    document.replaceNodeById(node.id, replaced);
  }

  /// 🎯 이전 문단의 정렬 가져오기
  String getPreviousParagraphAlign(int beforeIndex) {
    for (int i = beforeIndex - 1; i >= 0; i--) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode) {
        final String? align = node.metadata['textAlign'] as String?;
        if (align != null) return align;
      }
    }
    return 'center';
  }

  /// 🎯 제목이 비어있지 않은지 확인
  bool hasNonEmptyTitle() {
    final node = document.getNodeAt(0);
    if (node is ParagraphNode && node.metadata['isTitle'] == true) {
      final text = node.text.text.trim();
      return text.isNotEmpty;
    }
    return false;
  }
}
