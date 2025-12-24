import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/post_reader_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:super_editor/super_editor.dart';
import 'package:flutter/material.dart';

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
        forPublishing: true, // 🚀 임시저장도 네트워크 이미지로 변환 (로드 속도 향상)
        allowPartialUpload: false, // 🎯 임시저장 시에는 네트워크 URL만 저장 (업로드 중이면 스킵)
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

      return draftId;
    } catch (e, stackTrace) {
      debugPrint('[DraftService] ❌ 임시저장 실패: $e');
      debugPrint('[DraftService] 스택 트레이스: $stackTrace');
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
      debugPrint('[DraftService] Error getting drafts: $e');
      return [];
    }
  }

  /// 특정 임시저장 가져오기 (최적화: 파싱 중 조기 종료)
  Future<DraftData?> getDraft(String draftId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftsJson = prefs.getString(_draftsKey);

      if (draftsJson == null) return null;

      // 🚀 JSON 파싱 중 조기 종료 최적화
      final List<dynamic> draftsList = json.decode(draftsJson);

      // 필요한 드래프트만 찾아서 반환 (전체 리스트 생성하지 않음)
      for (final jsonData in draftsList) {
        if (jsonData is Map<String, dynamic> && jsonData['id'] == draftId) {
          return DraftData.fromJson(jsonData);
        }
      }

      return null;
    } catch (e) {
      debugPrint('[DraftService] Error getting draft: $e');
      return null;
    }
  }

  /// 임시저장 불러오기 (최적화)
  Future<bool> loadDraft({
    required String draftId,
    required EditorService editorService,
    required StickerService stickerService,
    NodeComponentService? nodeComponentService,
    dynamic dragService, // DragService 타입 (순환 참조 방지)
    BuildContext? context, // 🚀 이미지 프리로드용 컨텍스트
  }) async {
    try {
      // 🚀 1. 드래프트 데이터 로드 (최적화된 방식)
      final draft = await getDraft(draftId);
      if (draft == null) return false;

      // 🚀 2. 병렬 처리 가능한 작업들을 먼저 수행
      // JSON 디코딩은 한 번만 수행
      final exportedData = json.decode(draft.content) as Map<String, dynamic>;
      final postReaderService = PostReaderService();

      // 🚀 3. 초기화 작업들 (병렬 처리 가능)
      editorService.editor.composer.clearSelection();
      nodeComponentService?.clearSelection();
      nodeComponentService?.clearHighlightedSelection();

      // 🎯 히스토리 초기화 (임시저장 불러오기 시 필수)
      editorService.clearHistory();

      // 🎯 특수 노드 레지스트리 클리어 및 재등록 (임시저장 불러오기 시 필수)
      // 🎯 문서 교체 후 registerAllSpecialNodes()로 레지스트리에 재등록됨

      if (dragService != null) {
        (dragService as dynamic).invalidateNodeRectCache();
      }

      // 🚀 4. 문서 복원 및 교체 (특수 노드 등록 포함)
      final document = postReaderService.rebuildDocumentForRead(
        exportedData,
        includeTitleNode: true,
      );

      // 🚀 5. 문서 교체 (최적화: 특수 노드 등록 통합)
      await _replaceDocumentSafely(editorService, document);

      // 🎯 특수 노드 레지스트리 재등록 (문서 교체 후)
      editorService.registerAllSpecialNodes();

      // 🎯 새 문서의 초기 상태를 히스토리에 저장 (임시저장 불러온 상태를 기준으로)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        editorService.saveHistoryNow();
        editorService.markSavedSnapshot();
      });

      // 🚀 6. 스티커 복원
      postReaderService.restoreStickers(
        exported: exportedData,
        stickerService: stickerService,
      );

      // 🚀 7. 전체 네트워크 이미지를 순차적으로 배치 프리캐시
      if (context != null) {
        _precacheAllImagesInBatch(context, exportedData);
      }

      debugPrint('[DraftService] ✅ 임시저장 불러오기 완료');
      return true;
    } catch (e) {
      debugPrint('[DraftService] Error loading draft: $e');
      return false;
    }
  }

  /// 🚀 전체 네트워크 이미지를 순차적으로 배치 프리캐시
  void _precacheAllImagesInBatch(
    BuildContext context,
    Map<String, dynamic> exportedData,
  ) {
    try {
      final postReaderService = PostReaderService();
      final allImageUrls = postReaderService.extractImageUrls(exportedData);

      // 네트워크 URL만 필터링
      final networkUrls =
          allImageUrls.where((url) => EditorService.isNetworkUrl(url)).toList();

      if (networkUrls.isEmpty) return;

      // 🚀 배치로 병렬 프리캐시 (20개씩 동시 처리, 네트워크 부하 분산)
      Future.microtask(() async {
        const batchSize = 20; // 한 배치당 동시 처리 개수
        for (int i = 0; i < networkUrls.length; i += batchSize) {
          if (!context.mounted) break;

          // 현재 배치 추출
          final batch = networkUrls.skip(i).take(batchSize).toList();

          // 배치 내에서 병렬로 프리캐시 (await 없이 시작만)
          for (final url in batch) {
            if (!context.mounted) break;
            precacheImage(NetworkImage(url), context).catchError((_) {
              // 개별 실패는 무시
            });
          }

          // 배치 간 짧은 딜레이 (네트워크 부하 분산)
          if (i + batchSize < networkUrls.length) {
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
      });
    } catch (_) {
      // 프리캐시 실패는 무시 (나중에 위젯에서 로드됨)
    }
  }

  /// 안전한 문서 교체 (최적화: 불필요한 작업 제거)
  /// 🎯 히스토리 저장 방지: 문서 교체 중에는 히스토리에 저장하지 않음
  Future<void> _replaceDocumentSafely(
    EditorService editorService,
    MutableDocument newDocument,
  ) async {
    try {
      final currentDoc = editorService.document;

      // 🎯 문서 교체 중에는 EditorService의 _isExecutingHistory 플래그가
      // 🎯 true로 설정되어 있어서 히스토리 저장이 자동으로 방지됨
      // 🎯 리스너는 유지하되, 히스토리 저장만 스킵됨

      // 🚀 1. 현재 문서의 모든 노드를 삭제 (효율적으로)
      while (currentDoc.isNotEmpty) {
        final node = currentDoc.getNodeAt(0);
        if (node != null) {
          currentDoc.deleteNode(node.id);
        } else {
          break;
        }
      }

      // 🚀 2. 새 문서의 노드들을 추가하면서 특수 노드 정보 수집
      final specialNodes = <String, int>{}; // nodeId -> index

      for (int i = 0; i < newDocument.length; i++) {
        final node = newDocument.getNodeAt(i);
        if (node != null) {
          // 🚀 노드 복사 (새로 생성된 노드이므로 간단한 복사만 수행)
          final copiedNode = _copyNode(node);
          currentDoc.insertNodeAt(i, copiedNode);

          // 🚀 특수 노드 여부 확인 (EditorService의 isSpecialNode 로직 참고)
          if (_isSpecialNode(copiedNode)) {
            specialNodes[copiedNode.id] = i;
          }
        }
      }

      // 🚀 3. 선택 상태 확인 (한 번만)
      editorService.editor.composer.clearSelection();
    } catch (e) {
      debugPrint('[DraftService] Error replacing document: $e');
      _createDefaultDocument(editorService);
    }
  }

  /// 특수 노드 여부 확인 (EditorService 로직 참고)
  bool _isSpecialNode(dynamic node) {
    return node is ImageNode ||
        node is ClipNode ||
        node is LinkNode ||
        node is HorizontalRuleNode;
  }

  /// 노드 복사본 생성 (EditorService의 copyNode와 동일한 로직)
  /// ⚠️ EditorService.copyNode를 사용하는 것이 더 안전하지만,
  /// 순환 참조 방지를 위해 여기서 직접 구현
  dynamic _copyNode(dynamic node) {
    if (node is ParagraphNode) {
      // 🎯 AttributedText 전체 복사 (스타일 정보 유지: bold, italic, color 등)
      final copiedMetadata = Map<String, dynamic>.from(node.metadata);
      final isMention = copiedMetadata['mention'] == true;
      final AttributedText attributed = node.text.copyText(0, node.text.length);

      // 🎯 멘션 노드인데 볼드가 없으면 추가
      if (isMention && node.text.text.isNotEmpty) {
        final hasBold =
            attributed
                .getAttributionSpansInRange(
                  attributionFilter: (attr) => attr == boldAttribution,
                  range: SpanRange(0, node.text.text.length - 1),
                )
                .isNotEmpty;

        if (!hasBold) {
          attributed.addAttribution(
            boldAttribution,
            SpanRange(0, node.text.text.length - 1),
          );
        }
      }

      return ParagraphNode(
        id: node.id,
        text: attributed,
        metadata: copiedMetadata,
      );
    }
    if (node is ImageNode) {
      // 🎯 AppImageNode로 변환 (EditorService와 동일)
      return AppImageNode(
        id: node.id,
        imageUrl: node.imageUrl,
        altText: node.altText,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is ImageRowNode) {
      return ImageRowNode(
        id: node.id,
        imageUrls: List<String>.from(node.imageUrls),
        spacing: node.spacing,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is ClipNode) {
      return ClipNode(
        id: node.id,
        url: node.url,
        localPath: node.localPath,
        thumbnailPath: node.thumbnailPath,
        label: node.label,
        colorHex: node.colorHex,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is LinkNode) {
      return LinkNode(
        id: node.id,
        url: node.url,
        title: node.title,
        description: node.description,
        thumbnailUrl: node.thumbnailUrl,
      );
    }
    if (node is DividerNode) {
      return DividerNode(id: node.id);
    }
    if (node is PageViewImageNode) {
      return PageViewImageNode(
        id: node.id,
        imageUrls: List<String>.from(node.imageUrls),
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    // 알 수 없는 노드 타입은 그대로 반환 (fallback)
    return node;
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
      debugPrint('[DraftService] Error creating default document: $e');
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

      debugPrint('[DraftService] Draft deleted: $draftId');
      return true;
    } catch (e) {
      debugPrint('[DraftService] Error deleting draft: $e');
      return false;
    }
  }

  /// 모든 임시저장 삭제
  Future<bool> deleteAllDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftsKey);
      await prefs.remove(_currentDraftKey);

      debugPrint('[DraftService] All drafts deleted');
      return true;
    } catch (e) {
      debugPrint('[DraftService] Error deleting all drafts: $e');
      return false;
    }
  }

  /// 현재 임시저장 ID 가져오기
  Future<String?> getCurrentDraftId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_currentDraftKey);
    } catch (e) {
      debugPrint('[DraftService] Error getting current draft ID: $e');
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
      debugPrint('[DraftService] Error grouping drafts by title: $e');
      return {};
    }
  }
}
