import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/post_reader_service.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:super_editor/super_editor.dart';

/// 임시저장 데이터 모델
class DraftData {
  final String id;
  final String title;
  final String summary; // 🎯 요약/본문 미리보기
  final String content; // JSON 문자열
  final String thumbnailUrl;
  final String? videoFilePath; // 영상 원본 파일 경로
  final String? videoThumbnailPath; // 영상 로컬 썸네일 파일 경로
  final String visibility; // 'public', 'private', 'groups'
  final List<int> selectedGroupIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  DraftData({
    required this.id,
    required this.title,
    this.summary = '', // 🎯 기본값 빈 문자열
    required this.content,
    required this.thumbnailUrl,
    this.videoFilePath,
    this.videoThumbnailPath,
    required this.visibility,
    required this.selectedGroupIds,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary, // 🎯 요약 추가
      'content': content,
      'thumbnailUrl': thumbnailUrl,
      if (videoFilePath != null) 'videoFilePath': videoFilePath,
      if (videoThumbnailPath != null) 'videoThumbnailPath': videoThumbnailPath,
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
      summary: json['summary'] ?? '', // 🎯 요약 추가 (기본값 빈 문자열)
      content: json['content'] ?? '',
      thumbnailUrl: json['thumbnailUrl'] ?? '',
      videoFilePath: json['videoFilePath'] as String?,
      videoThumbnailPath: json['videoThumbnailPath'] as String?,
      visibility: json['visibility'] ?? 'public',
      selectedGroupIds: List<int>.from(json['selectedGroupIds'] ?? []),
      createdAt: TimeUtils.toLocalTime(
        json['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: TimeUtils.toLocalTime(
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
    String summary = '', // 🎯 요약 추가
    required String thumbnailUrl,
    String? videoFilePath,
    String? videoThumbnailPath,
    required String visibility,
    required List<int> selectedGroupIds,
    String? existingDraftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // base 수집 후 composeFinalPayload로 최종 페이로드 구성하여 저장
      final base = PostExporter.exportToMap(
        editorService: editorService,
        stickerService: stickerService,
      );
      final String v = visibility.toLowerCase();
      final bool privateOnly = v == 'private';
      final bool publicOnly = v == 'public';
      final Map<String, dynamic> finalPayload =
          PostExporter.composeFinalPayload(
            thumbnailImageUrl: thumbnailUrl,
            base: Map<String, dynamic>.from(base),
            privateOnly: privateOnly,
            publicOnly: publicOnly,
            selectedGroupIds: selectedGroupIds,
            createdAt: DateTime.now(),
            skipValidation: true, // 임시저장은 제목 검증 생략
          );

      // 제목이 비어있으면 기본값 사용
      final effectiveTitle = title.trim().isEmpty ? '제목 없음' : title;

      final draftId = existingDraftId ?? _generateDraftId(effectiveTitle);
      final now = DateTime.now();

      final draftData = DraftData(
        id: draftId,
        title: effectiveTitle,
        summary: summary, // 🎯 요약 저장
        content: json.encode(finalPayload), // 최종 페이로드 기준 저장
        thumbnailUrl: thumbnailUrl,
        videoFilePath: videoFilePath,
        videoThumbnailPath: videoThumbnailPath,
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
      throw Exception('임시저장에 실패했습니다');
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

      // PostReaderService를 사용하여 문서 복원
      final exportedData = json.decode(draft.content) as Map<String, dynamic>;
      final postReaderService = PostReaderService();
      // 드래프트 복구시에는 제목 노드도 포함 (includeTitleNode: true)
      final document = postReaderService.rebuildDocumentForRead(
        exportedData,
        includeTitleNode: true,
      );

      // 안전한 문서 교체 방식
      await _replaceDocumentSafely(editorService, document);

      // 스티커 복원
      postReaderService.restoreStickers(
        exported: exportedData,
        stickerService: stickerService,
      );

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
    final titleHash = title.hashCode.abs(); // 제목 기반 해시만 사용 (timestamp 제거)
    return 'draft_$titleHash';
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
