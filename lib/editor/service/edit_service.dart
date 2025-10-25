import 'dart:convert';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:super_editor/super_editor.dart';

/// 편집 모드 전용 유틸리티 서비스
/// - 기존 Exported 데이터를 SuperEditor 문서로 복원
/// - 빈 문서 템플릿 제공
class EditService {
  /// Exported 데이터(Map)로부터 SuperEditor 문서를 복구한다.
  MutableDocument rebuildDocumentForEdit(Map<String, dynamic> exported) {
    dynamic content = exported['content'];
    if (content is String) {
      try {
        content = json.decode(content);
      } catch (_) {
        content = const {'nodes': []};
      }
    }
    if (content is! Map) content = const {'nodes': []};
    final nodes = (content['nodes'] as List?) ?? const [];
    final rebuilt = <DocumentNode>[];
    final String ts = DateTime.now().microsecondsSinceEpoch.toString();
    int seq = 0;
    String uid([String prefix = 'n']) => '${prefix}_${ts}_${seq++}';

    // 제목 우선 추가
    final String title = (exported['title'] ?? '').toString();
    rebuilt.add(
      ParagraphNode(
        id: uid('title'),
        text: AttributedText(title),
        metadata: {'isTitle': true, 'textAlign': 'center'},
      ),
    );

    for (final raw in nodes) {
      final m = (raw as Map).cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();
      switch (type) {
        case 'paragraph':
          rebuilt.add(
            ParagraphNode(
              id: uid('p'),
              text: AttributedText((m['text'] ?? '').toString()),
              metadata: {'textAlign': (m['align'] ?? 'center').toString()},
            ),
          );
          break;
        case 'image':
          rebuilt.add(
            ImageNode(
              id: uid('image'),
              imageUrl: (m['url'] ?? '').toString(),
              altText: (m['altText'] ?? '').toString(),
            ),
          );
          break;
        case 'imageRow':
          rebuilt.add(
            ImageRowNode(
              id: uid('imageRow'),
              imageUrls:
                  ((m['urls'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
              spacing: (m['spacing'] as num?)?.toDouble() ?? 4.0,
            ),
          );
          break;
        case 'link':
          rebuilt.add(
            LinkNode(
              id: uid('link'),
              url: (m['url'] ?? '').toString(),
              title: (m['title'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
              thumbnailUrl: (m['thumbnailUrl'] ?? '').toString(),
            ),
          );
          break;
        case 'mention':
          rebuilt.add(
            MentionNode(
              id: uid('mention'),
              usernames:
                  ((m['usernames'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
            ),
          );
          break;
        default:
          rebuilt.add(
            ParagraphNode(
              id: uid('p'),
              text: AttributedText(''),
              metadata: {'textAlign': 'center'},
            ),
          );
      }
    }
    return MutableDocument(nodes: rebuilt);
  }
}
