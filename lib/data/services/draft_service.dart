import 'dart:convert';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/location_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';

/// 임시저장 데이터 모델
class DraftData {
  final String id;
  final String title;
  final String content; // JSON 문자열
  final String thumbnailUrl;
  final String visibility; // 'public', 'private', 'groups'
  final List<int> selectedGroupIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  DraftData({
    required this.id,
    required this.title,
    required this.content,
    required this.thumbnailUrl,
    required this.visibility,
    required this.selectedGroupIds,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'thumbnailUrl': thumbnailUrl,
      'visibility': visibility,
      'selectedGroupIds': selectedGroupIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DraftData.fromJson(Map<String, dynamic> json) {
    return DraftData(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      thumbnailUrl: json['thumbnailUrl'] ?? '',
      visibility: json['visibility'] ?? 'public',
      selectedGroupIds: List<int>.from(json['selectedGroupIds'] ?? []),
      createdAt: DateTime.parse(
        json['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updatedAt'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

/// 임시저장 서비스
class DraftService {
  static const String _draftsKey = 'draft_posts';
  static const String _currentDraftKey = 'current_draft';

  /// 현재 에디터 상태를 임시저장
  Future<String> saveDraft({
    required EditorService editorService,
    required StickerService stickerService,
    required String title,
    required String thumbnailUrl,
    required String visibility,
    required List<int> selectedGroupIds,
    String? existingDraftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // PostExporter를 사용해서 에디터와 스티커 데이터를 JSON으로 변환
      final exportedData = PostExporter.exportToMap(
        editorService: editorService,
        stickerService: stickerService,
      );

      final draftId = existingDraftId ?? _generateDraftId(title);
      final now = DateTime.now();

      final draftData = DraftData(
        id: draftId,
        title: title,
        content: json.encode(exportedData), // PostExporter 결과를 그대로 저장
        thumbnailUrl: thumbnailUrl,
        visibility: visibility,
        selectedGroupIds: selectedGroupIds,
        createdAt:
            existingDraftId != null ? await _getDraftCreatedAt(draftId) : now,
        updatedAt: now,
      );

      // 기존 임시저장 목록 가져오기
      final drafts = await getAllDrafts();

      // 기존 임시저장이 있으면 업데이트, 없으면 새로 추가
      final existingIndex = drafts.indexWhere((draft) => draft.id == draftId);
      if (existingIndex != -1) {
        drafts[existingIndex] = draftData;
      } else {
        drafts.add(draftData);
      }

      // 저장
      final draftsJson = drafts.map((draft) => draft.toJson()).toList();
      await prefs.setString(_draftsKey, json.encode(draftsJson));

      // 현재 임시저장으로 설정
      await prefs.setString(_currentDraftKey, draftId);

      print('[DraftService] Draft saved: $draftId');
      return draftId;
    } catch (e) {
      print('[DraftService] Error saving draft: $e');
      throw Exception('임시저장에 실패했습니다: $e');
    }
  }

  /// 모든 임시저장 목록 가져오기
  Future<List<DraftData>> getAllDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftsJson = prefs.getString(_draftsKey);

      if (draftsJson == null) return [];

      final List<dynamic> draftsList = json.decode(draftsJson);
      return draftsList.map((json) => DraftData.fromJson(json)).toList();
    } catch (e) {
      print('[DraftService] Error getting drafts: $e');
      return [];
    }
  }

  /// 특정 임시저장 가져오기
  Future<DraftData?> getDraft(String draftId) async {
    try {
      final drafts = await getAllDrafts();
      return drafts.firstWhere((draft) => draft.id == draftId);
    } catch (e) {
      print('[DraftService] Error getting draft: $e');
      return null;
    }
  }

  /// 임시저장 불러오기
  Future<bool> loadDraft({
    required String draftId,
    required EditorService editorService,
    required StickerService stickerService,
  }) async {
    try {
      final draft = await getDraft(draftId);
      if (draft == null) return false;

      // PostReaderScreen의 복구 로직을 활용
      final exportedData = json.decode(draft.content) as Map<String, dynamic>;

      // 문서 복원
      final document = _rebuildDocument(exportedData);

      // 안전한 문서 교체 방식
      await _replaceDocumentSafely(editorService, document);

      // 스티커 복원
      stickerService.removeAll();
      final stickers = (exportedData['stickers'] as List?) ?? [];
      for (final stickerData in stickers) {
        if (stickerData is Map<String, dynamic>) {
          stickerService.addStickerFromData(stickerData);
        }
      }

      print('[DraftService] Draft loaded: $draftId');
      return true;
    } catch (e) {
      print('[DraftService] Error loading draft: $e');
      return false;
    }
  }

  /// 안전한 문서 교체
  Future<void> _replaceDocumentSafely(
    EditorService editorService,
    MutableDocument newDocument,
  ) async {
    try {
      // 1. 현재 문서의 모든 노드를 삭제 (뒤에서부터)
      final currentDoc = editorService.document;
      for (int i = currentDoc.length - 1; i >= 0; i--) {
        final node = currentDoc.getNodeAt(i);
        if (node != null) {
          currentDoc.deleteNode(node.id);
        }
      }

      // 2. 새 문서의 노드들을 추가
      for (int i = 0; i < newDocument.length; i++) {
        final node = newDocument.getNodeAt(i);
        if (node != null) {
          currentDoc.insertNodeAt(i, node);
        }
      }

      // 3. 선택 상태 초기화
      editorService.editor.composer.clearSelection();

      // 4. 첫 번째 문단으로 커서 이동
      if (newDocument.length > 0) {
        final firstNode = newDocument.getNodeAt(0);
        if (firstNode is ParagraphNode) {
          final position = DocumentPosition(
            nodeId: firstNode.id,
            nodePosition: TextNodePosition(offset: firstNode.text.text.length),
          );
          editorService.editor.composer.setSelectionWithReason(
            DocumentSelection.collapsed(position: position),
            SelectionReason.userInteraction,
          );
        }
      }
    } catch (e) {
      print('[DraftService] Error replacing document: $e');
      // 실패 시 기본 문서로 복구
      _createDefaultDocument(editorService);
    }
  }

  /// 기본 문서 생성 (복구용)
  void _createDefaultDocument(EditorService editorService) {
    try {
      final currentDoc = editorService.document;

      // 모든 노드 삭제
      for (int i = currentDoc.length - 1; i >= 0; i--) {
        final node = currentDoc.getNodeAt(i);
        if (node != null) {
          currentDoc.deleteNode(node.id);
        }
      }

      // 기본 노드 추가
      currentDoc.insertNodeAt(
        0,
        ParagraphNode(
          id: '1',
          text: AttributedText(''),
          metadata: {'isTitle': true, 'textAlign': 'center'},
        ),
      );

      currentDoc.insertNodeAt(
        1,
        ParagraphNode(
          id: '2',
          text: AttributedText(''),
          metadata: {'textAlign': 'center'},
        ),
      );
    } catch (e) {
      print('[DraftService] Error creating default document: $e');
    }
  }

  /// PostReaderScreen의 _rebuildDocument 로직을 활용
  MutableDocument _rebuildDocument(Map<String, dynamic> data) {
    // 저장 포맷(document | content 모두)과 과거 포맷까지 호환
    final List nodes =
        (data['document']?['nodes'] as List?) ??
        (data['content']?['nodes'] as List?) ??
        (data['content'] as List?) ??
        const [];
    final rebuilt = <DocumentNode>[];

    for (final raw in nodes) {
      final m = (raw as Map).cast<String, dynamic>();
      final id = (m['id'] ?? '').toString();
      final type = (m['type'] ?? '').toString();

      switch (type) {
        case 'paragraph':
          final text = (m['text'] ?? '').toString();
          final align = (m['align'] ?? 'center').toString();
          final isTitle = m['isTitle'] == true;
          final spans = (m['spans'] as List?) ?? const [];
          final attributed = _buildAttributedText(text, spans);
          final meta = <String, dynamic>{'textAlign': align};
          if (isTitle) meta['isTitle'] = true;
          rebuilt.add(ParagraphNode(id: id, text: attributed, metadata: meta));
          break;
        case 'image':
          rebuilt.add(
            ImageNode(
              id: id,
              imageUrl: (m['url'] ?? '').toString(),
              altText: (m['altText'] ?? '').toString(),
            ),
          );
          break;
        case 'imageRow':
          rebuilt.add(
            ImageRowNode(
              id: id,
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
              id: id,
              url: (m['url'] ?? '').toString(),
              title: (m['title'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
              thumbnailUrl: (m['thumbnailUrl'] ?? '').toString(),
            ),
          );
          break;
        case 'location':
          rebuilt.add(
            LocationNode(
              id: id,
              lat: (m['lat'] as num?)?.toDouble() ?? 0,
              lng: (m['lng'] as num?)?.toDouble() ?? 0,
              title: (m['title'] ?? '').toString(),
              address: (m['address'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
            ),
          );
          break;
        case 'mention':
          rebuilt.add(
            MentionNode(
              id: id,
              usernames:
                  ((m['usernames'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
            ),
          );
          break;
        default:
          // 알 수 없는 노드는 문단으로 폴백
          rebuilt.add(ParagraphNode(id: id, text: AttributedText('[${type}]')));
      }
    }
    return MutableDocument(nodes: rebuilt);
  }

  /// PostReaderScreen의 _buildAttributedText 로직을 활용
  AttributedText _buildAttributedText(String text, List spans) {
    final attributed = AttributedText(text);
    for (final s in spans) {
      final m = (s as Map).cast<String, dynamic>();
      final start = (m['start'] as num?)?.toInt() ?? 0;
      final end = (m['end'] as num?)?.toInt() ?? start;
      final ann = (m['attrs'] as Map?)?.cast<String, dynamic>() ?? {};
      final atts = <Attribution>{};
      if (ann['bold'] == true) atts.add(boldAttribution);
      if (ann['italic'] == true) atts.add(italicsAttribution);
      if (ann['underline'] == true) atts.add(underlineAttribution);
      if (ann['strikethrough'] == true) atts.add(strikethroughAttribution);
      final fs = (ann['font_size'] as num?)?.toDouble();
      if (fs != null) atts.add(FontSizeAttribution(fs));
      final colorHex = ann['color'] as String?;
      if (colorHex != null && colorHex.isNotEmpty) {
        atts.add(ColorAttribution(_parseHexColor(colorHex)));
      }
      for (final a in atts) {
        attributed.addAttribution(a, SpanRange(start, end - 1));
      }
    }
    return attributed;
  }

  /// PostReaderScreen의 _parseHexColor 로직을 활용
  ui.Color _parseHexColor(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    return ui.Color(int.parse(v, radix: 16));
  }

  /// 임시저장 삭제
  Future<bool> deleteDraft(String draftId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final drafts = await getAllDrafts();

      // 해당 임시저장 제거
      drafts.removeWhere((draft) => draft.id == draftId);

      // 저장
      final draftsJson = drafts.map((draft) => draft.toJson()).toList();
      await prefs.setString(_draftsKey, json.encode(draftsJson));

      // 현재 임시저장이 삭제된 것이라면 제거
      final currentDraftId = prefs.getString(_currentDraftKey);
      if (currentDraftId == draftId) {
        await prefs.remove(_currentDraftKey);
      }

      print('[DraftService] Draft deleted: $draftId');
      return true;
    } catch (e) {
      print('[DraftService] Error deleting draft: $e');
      return false;
    }
  }

  /// 모든 임시저장 삭제
  Future<bool> deleteAllDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftsKey);
      await prefs.remove(_currentDraftKey);

      print('[DraftService] All drafts deleted');
      return true;
    } catch (e) {
      print('[DraftService] Error deleting all drafts: $e');
      return false;
    }
  }

  /// 현재 임시저장 ID 가져오기
  Future<String?> getCurrentDraftId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_currentDraftKey);
    } catch (e) {
      print('[DraftService] Error getting current draft ID: $e');
      return null;
    }
  }

  /// 임시저장 생성 시간 가져오기
  Future<DateTime> _getDraftCreatedAt(String draftId) async {
    try {
      final draft = await getDraft(draftId);
      return draft?.createdAt ?? DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }

  /// 임시저장 ID 생성 (타이틀별 + 타임스탬프)
  String _generateDraftId(String title) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final titleHash = title.hashCode.abs(); // 제목 기반 해시
    return 'draft_${titleHash}_$timestamp';
  }

  /// 제목별 임시저장 그룹 가져오기
  Future<Map<String, List<DraftData>>> getDraftsByTitle() async {
    try {
      final allDrafts = await getAllDrafts();
      final Map<String, List<DraftData>> groupedDrafts = {};

      for (final draft in allDrafts) {
        final title = draft.title.isNotEmpty ? draft.title : '제목 없음';
        if (!groupedDrafts.containsKey(title)) {
          groupedDrafts[title] = [];
        }
        groupedDrafts[title]!.add(draft);
      }

      // 각 그룹을 시간순으로 정렬 (최신순)
      for (final title in groupedDrafts.keys) {
        groupedDrafts[title]!.sort(
          (a, b) => b.updatedAt.compareTo(a.updatedAt),
        );
      }

      return groupedDrafts;
    } catch (e) {
      print('[DraftService] Error grouping drafts by title: $e');
      return {};
    }
  }
}
