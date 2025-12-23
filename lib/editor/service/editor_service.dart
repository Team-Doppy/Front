import 'dart:convert';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/history/editor_history_service.dart';
import 'package:doppy/editor/service/image/image_service.dart';
import 'package:doppy/editor/service/video/video_service.dart';
import 'package:doppy/editor/service/selection/selection_management_service.dart';
import 'package:doppy/editor/service/node/node_management_service.dart';
import 'package:doppy/editor/service/document/document_structure_service.dart';
import 'package:doppy/editor/service/mention/mention_service.dart';
import 'package:doppy/editor/service/change/document_change_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/utils/config.dart';
import 'package:doppy/image/group_image_layout_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';

class EditorService extends ChangeNotifier {
  late final Editor editor;
  late final MutableDocument document;
  GlobalKey? _documentLayoutKey;

  // 최근 저장 스냅샷 지문
  String? _lastSavedFingerprint;

  // 🎯 히스토리 서비스 (Undo/Redo 전담)
  late final EditorHistoryService _historyService;

  // 🎯 이미지 서비스
  late final ImageService _imageService;

  // 🎯 비디오 서비스
  late final VideoService _videoService;

  // 🎯 Selection 관리 서비스
  late final SelectionManagementService _selectionService;

  // 🎯 노드 관리 서비스
  late final NodeManagementService _nodeService;

  // 🎯 문서 구조 관리 서비스
  late final DocumentStructureService _documentService;

  // 🎯 멘션 관리 서비스
  late final MentionService _mentionService;

  // 🎯 문서 변경 이벤트 관리 서비스
  late final DocumentChangeService _changeService;

  // 🎯 NodeComponentService 참조 (노드 선택 해제용)
  BuildContext? _context;

  EditorService({
    required this.editor,
    required this.document,
    BuildContext? context,
    bool enableInitialStateSave = true, // 🚀 PostReaderScreen에서는 false로 설정
  }) : _context = context {
    // 🎯 노드 관리 서비스 초기화 (히스토리보다 먼저 초기화 필요)
    _nodeService = NodeManagementService(
      document: document,
      isSpecialNode: isSpecialNode,
    );

    // 🎯 히스토리 서비스 초기화
    _historyService = EditorHistoryService(
      document: document,
      copyNode: _nodeService.copyNode,
    );

    // 🎯 문서 구조 관리 서비스 초기화
    _documentService = DocumentStructureService(
      document: document,
      editor: editor,
    );

    // 🎯 Selection 관리 서비스 초기화
    _selectionService = SelectionManagementService(
      editor: editor,
      document: document,
      context: context,
      isSpecialNode: isSpecialNode,
      hasNodeChanged: _historyService.hasNodeChanged,
      copyNode: _nodeService.copyNode,
    );

    // 🎯 멘션 서비스 초기화
    _mentionService = MentionService(
      editor: editor,
      document: document,
      setHistoryExecuting:
          (bool value) => _historyService.isExecutingHistory = value,
      saveHistory:
          (bool immediate, VoidCallback? onSaved) =>
              _historyService.saveCurrentState(
                immediate: immediate,
                onSaved: onSaved ?? notifyListeners,
              ),
      notifyListeners: notifyListeners,
      getCaretNodeIndexSafe: _getCaretNodeIndexSafe,
      getPreviousParagraphAlign: _documentService.getPreviousParagraphAlign,
    );

    // 🎯 이미지 서비스 초기화
    _imageService = ImageService(
      editor: editor,
      document: document,
      notifyListeners: notifyListeners,
      setHistoryExecuting:
          (bool value) => _historyService.isExecutingHistory = value,
      saveHistory:
          (bool immediate, VoidCallback? onSaved) =>
              _historyService.saveCurrentState(
                immediate: immediate,
                onSaved: onSaved ?? notifyListeners,
              ),
    );

    // 🎯 비디오 서비스 초기화
    _videoService = VideoService(
      editor: editor,
      document: document,
      notifyListeners: notifyListeners,
      setHistoryExecuting:
          (bool value) => _historyService.isExecutingHistory = value,
      saveHistory:
          (bool immediate, VoidCallback? onSaved) =>
              _historyService.saveCurrentState(
                immediate: immediate,
                onSaved: onSaved ?? notifyListeners,
              ),
      insertComponentNodeAtNextLine: _insertComponentNodeAtNextLine,
    );

    // 🎯 문서 변경 이벤트 서비스 초기화
    _changeService = DocumentChangeService(
      editor: editor,
      document: document,
      context: context,
      nodeService: _nodeService,
      selectionService: _selectionService,
      documentService: _documentService,
      notifyListeners: notifyListeners,
      trackChangeFromLog: _trackChangeFromLog,
      hasNodeChanged: _historyService.hasNodeChanged,
      copyNode: _nodeService.copyNode,
      isSpecialNode: isSpecialNode,
      getEditingIndex: getEditingIndex,
      setHistoryExecuting:
          (bool value) => _historyService.isExecutingHistory = value,
    );

    document.addListener(_onDocumentChanged);
    editor.composer.selectionNotifier.addListener(_onSelectionChanged);

    if (enableInitialStateSave) {
      // 초기 상태 저장 (여러 프레임 후 실행하여 UI 블로킹 방지)
      // 🎯 사용자가 실제로 편집을 시작할 때까지 충분히 지연
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 첫 프레임 후 추가 지연 (UI 렌더링 완료 보장)
        // 🚀 2초 후 저장 (UI 안정화를 위해 지연 증가)
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (!_historyService.initialStateSaved) {
            _historyService.saveInitialState();
          }
        });
      });
    }
  }

  // 🎯 BuildContext 설정 (initState 이후에 설정 가능)
  void setContext(BuildContext context) {
    _context = context;
  }

  // 🎯 ChangeLog에서 변경 추적
  /// 🎯 변경 추적: 실제 변경만 히스토리에 저장 (중복 체크로 필터링)
  void _trackChangeFromLog(DocumentChange change) {
    // 히스토리 실행 중이면 저장하지 않음
    if (_historyService.isExecutingHistory) return;

    try {
      // 텍스트 입력/삭제 - 디바운싱 (1초)
      if (change is TextInsertionEvent || change is TextDeletedEvent) {
        _historyService.saveCurrentState(
          immediate: false,
          onSaved: notifyListeners,
        );
        return;
      }

      // 구조 변경 - 즉시 저장 (중복은 자동 필터링됨)
      if (change is NodeInsertedEvent ||
          change is NodeRemovedEvent ||
          change is NodeChangeEvent ||
          change is NodeMovedEvent) {
        _historyService.saveCurrentState(
          immediate: true,
          onSaved: notifyListeners,
        );
        return;
      }
    } catch (e) {
      debugPrint('[EditorService] 변경 추적 실패: $e');
    }
  }

  void setDocumentLayoutKey(GlobalKey key) {
    _documentLayoutKey = key;
  }

  GlobalKey? get documentLayoutKey => _documentLayoutKey;

  // 🎯 Undo 가능 여부 (히스토리 서비스 위임)
  bool get canUndo => _historyService.canUndo;

  // 🎯 Redo 가능 여부 (히스토리 서비스 위임)
  bool get canRedo => _historyService.canRedo;

  // 🎯 히스토리 초기화 (임시저장 불러오기, 문서 교체 시 사용)
  void clearHistory() {
    _historyService.clearHistory();
    notifyListeners();
  }

  // 🎯 노드 복사 (임시저장 불러오기 시 사용)
  DocumentNode copyNode(DocumentNode node) {
    return _nodeService.copyNode(node);
  }

  // 🎯 특수 노드 복원 캐시 클리어 (임시저장 불러오기 시 사용)
  void clearSpecialNodeCache() {
    _changeService.clearSpecialNodeCache();
    debugPrint('[EditorService] 🧹 특수 노드 캐시 클리어');
  }

  // 🎯 히스토리 실행 플래그 설정 (문서 교체 시 사용)
  void setHistoryExecuting(bool value) {
    _historyService.isExecutingHistory = value;
  }

  // 🎯 document 리스너 일시 중단 (문서 교체 시 이벤트 발생 방지)
  void pauseDocumentListener() {
    try {
      document.removeListener(_onDocumentChanged);
      debugPrint('[EditorService] ⏸️ document 리스너 일시 중단');
    } catch (e) {
      debugPrint('[EditorService] ⚠️ 리스너 중단 실패 (무시): $e');
    }
  }

  // 🎯 document 리스너 재개
  void resumeDocumentListener() {
    try {
      document.addListener(_onDocumentChanged);
      debugPrint('[EditorService] ▶️ document 리스너 재개');
    } catch (e) {
      debugPrint('[EditorService] ⚠️ 리스너 재개 실패 (무시): $e');
    }
  }

  // 🎯 즉시 히스토리 저장 (외부에서 호출 가능)
  void saveHistoryNow() {
    _historyService.saveHistoryNow(onSaved: notifyListeners);
  }

  // 🎯 Undo 실행 (히스토리 서비스 위임)
  void undo() {
    _historyService.undo(
      onSuccess: notifyListeners,
      onRestoreSnapshot: () {
        final snapshot = _historyService.lastSnapshot;
        if (snapshot != null) {
          _historyService.restoreFromSnapshot(
            snapshot,
            editor: editor,
            isSpecialNode: isSpecialNode,
            copyNode: _nodeService.copyNode,
          );
        }
      },
    );
  }

  // 🎯 Redo 실행 (히스토리 서비스 위임)
  void redo() {
    _historyService.redo(
      onSuccess: notifyListeners,
      onRestoreSnapshot: () {
        final snapshot = _historyService.lastSnapshot;
        if (snapshot != null) {
          _historyService.restoreFromSnapshot(
            snapshot,
            editor: editor,
            isSpecialNode: isSpecialNode,
            copyNode: _nodeService.copyNode,
          );
        }
      },
    );
  }

  // 문서 변경 리스너: 구조가 변했을 때만 마진 재계산
  void _onDocumentChanged(DocumentChangeLog changeLog) {
    _changeService.handleDocumentChanged(changeLog);
  }

  @override
  void dispose() {
    // 🎯 각 서비스 dispose
    _historyService.dispose();
    _selectionService.dispose();
    _nodeService.dispose();

    try {
      document.removeListener(_onDocumentChanged);
      editor.composer.selectionNotifier.removeListener(_onSelectionChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onSelectionChanged() {
    _selectionService.handleSelectionChanged();
  }

  /// 🎯 마지막 유효 selection 가져오기 (SelectionManagementService에서 사용)
  DocumentSelection? get lastSelection => _selectionService.lastSelection;

  /// 🎯 하이라이트된 노드 ID 가져오기
  Set<String> get pendingHighlightedNodeIds =>
      _selectionService.pendingHighlightedNodeIds;

  /// 제목이 비어있지 않은지 판단
  bool hasNonEmptyTitle() {
    return _documentService.hasNonEmptyTitle();
  }

  /// 본문(제목 제외)에 유의미한 내용이 있는지 판단
  bool hasNonEmptyBody({BuildContext? context}) {
    // 🎯 스티커가 있으면 본문이 있다고 간주
    if (context != null) {
      final stickerService = context.read<StickerService>();
      if (stickerService.stickers.isNotEmpty) return true;
    }

    for (int i = 1; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      if (node is ParagraphNode) {
        if (node.text.text.trim().isNotEmpty) return true;
      } else if (isSpecialNode(node)) {
        return true;
      } else if (node is ParagraphNode && node.metadata['mention'] == true) {
        return true;
      } else {
        // 기타 노드가 존재하면 본문이 있다고 간주
        return true;
      }
    }
    return false;
  }

  /// 🎯 업로드되지 않은 이미지가 있는지 확인 (UploadService의 task 기반 실제 업로드 상태만 확인)
  /// 🚀 플레이스홀더 개념 제거 - UploadService의 활성 업로드만 체크하여 가볍고 정확하게 판단
  bool hasUnuploadedImages() {
    if (_context == null) return false;

    try {
      final uploadService = _context!.read<UploadService>();
      // 🚀 에디터 관련 활성 업로드(pending, uploading)가 있는지만 확인
      return uploadService.hasActiveUploads();
    } catch (e) {
      // UploadService 접근 실패 시 false 반환 (업로드 없음으로 간주)
      debugPrint(
        '[EditorService] hasUnuploadedImages: UploadService 접근 실패: $e',
      );
      return false;
    }
  }

  /// 문서에서 첫 번째 이미지 URL 찾기
  String? findFirstImageUrl() {
    try {
      for (int i = 0; i < document.nodeCount; i++) {
        final node = document.getNodeAt(i);

        // ImageNode인 경우
        if (node is ImageNode) {
          final url = node.imageUrl;
          if (url.isNotEmpty &&
              (url.startsWith('http://') || url.startsWith('https://'))) {
            return url;
          }
        }

        // ImageRowNode인 경우 (첫 번째 이미지 사용)
        if (node is ImageRowNode) {
          if (node.imageUrls.isNotEmpty) {
            final url = node.imageUrls.first;
            if (url.isNotEmpty &&
                (url.startsWith('http://') || url.startsWith('https://'))) {
              return url;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[EditorService] 이미지 찾기 실패: $e');
    }
    return null;
  }

  /// 제목 노드 업데이트
  void updateTitleNode(String newTitle) {
    try {
      // 첫 번째 노드가 제목 노드인지 확인
      final firstNode = document.getNodeAt(0);
      if (firstNode is! ParagraphNode ||
          firstNode.metadata['isTitle'] != true) {
        debugPrint('[EditorService] 제목 노드를 찾을 수 없습니다');
        return;
      }

      // 새 제목 노드 생성
      final newTitleNode = ParagraphNode(
        id: firstNode.id,
        text: AttributedText(newTitle),
        metadata: firstNode.metadata,
      );

      // 노드 교체
      document.replaceNodeById(firstNode.id, newTitleNode);

      debugPrint('[EditorService] 제목 노드 업데이트 완료: "$newTitle"');
    } catch (e) {
      debugPrint('[EditorService] 제목 노드 업데이트 실패: $e');
    }
  }

  /// 미디어(이미지/영상) 정렬 변경 (패딩 토글)
  void changeMediaAlignment(String nodeId) {
    try {
      final node = document.getNodeById(nodeId);
      if (node == null) return;

      // 메타데이터에서 현재 패딩 정보 가져오기
      final currentPadding = node.metadata['padding'] as String? ?? 'center';

      // 다음 패딩 모드로 전환
      final nextPadding = currentPadding == 'full' ? 'center' : 'full';

      // 메타데이터 업데이트
      final updatedMetadata = Map<String, dynamic>.from(node.metadata);
      updatedMetadata['padding'] = nextPadding;

      DocumentNode newNode;

      if (node is ImageNode) {
        newNode = AppImageNode(
          id: node.id,
          imageUrl: node.imageUrl,
          altText: node.altText,
          metadata: updatedMetadata,
        );
      } else if (node is ClipNode) {
        newNode = ClipNode(
          id: node.id,
          label: node.label,
          colorHex: node.colorHex,
          url: node.url,
          localPath: node.localPath,
          thumbnailPath: node.thumbnailPath,
          metadata: updatedMetadata,
        );
      } else {
        return; // 지원하지 않는 노드 타입
      }

      // 노드 교체
      editor.execute([
        ReplaceNodeRequest(existingNodeId: nodeId, newNode: newNode),
      ]);

      debugPrint('[EditorService] 미디어 정렬 변경: $currentPadding → $nextPadding');
    } catch (e) {
      debugPrint('[EditorService] 미디어 정렬 변경 실패: $e');
    }
  }

  /// 문서 내용을 간단 스냅샷으로 직렬화하여 지문(fingerprint)을 생성
  String computeDocumentFingerprint() {
    final nodes = <Map<String, dynamic>>[];
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      if (node is ParagraphNode) {
        nodes.add({
          't': 'p',
          'title': node.metadata['isTitle'] == true,
          'align': node.metadata['textAlign'],
          'fontFamily': node.metadata['fontFamily'], // 폰트 정보 포함
          'text': node.text.text,
        });
      } else if (node is AppImageNode) {
        nodes.add({'t': 'img', 'url': node.imageUrl});
      } else if (node is ImageNode) {
        nodes.add({'t': 'img', 'url': node.imageUrl});
      } else if (node is ImageRowNode) {
        nodes.add({'t': 'row', 'urls': List<String>.from(node.imageUrls)});
      } else if (node is LinkNode) {
        nodes.add({'t': 'link', 'url': node.url, 'title': node.title});
      } else if (node is ParagraphNode && node.metadata['mention'] == true) {
        final List<dynamic> namesDyn =
            (node.metadata['usernames'] as List?) ?? const [];
        nodes.add({
          't': 'mention',
          'users': namesDyn.map((e) => e.toString()).toList(),
        });
      } else {
        nodes.add({'t': node.runtimeType.toString(), 'id': node.id});
      }
    }
    return jsonEncode({'nodes': nodes});
  }

  /// 현재 문서 상태를 저장 스냅샷으로 마크
  void markSavedSnapshot() {
    _lastSavedFingerprint = computeDocumentFingerprint();
  }

  /// 종료 시 임시저장 다이얼로그 노출 필요 여부
  bool shouldPromptSaveOnExit(BuildContext context) {
    final hasStickerChanges = context.read<StickerService>().hasChanges;
    // 제목 또는 본문 중 하나라도 유효한 입력이 있어야 함
    final bool anyContent =
        hasNonEmptyTitle() || hasNonEmptyBody(context: context);
    if (!anyContent) return false;
    final now = computeDocumentFingerprint();
    if (_lastSavedFingerprint == null || hasStickerChanges) {
      // 저장 이력이 없다면 변경이 있는 상태로 간주
      return true;
    }
    return now != _lastSavedFingerprint;
  }

  void reorderNode(String nodeId, int targetIndex) {
    final node = document.getNodeById(nodeId);
    if (node == null) return;

    // 🎯 최적화: getNodeIndexById 직접 사용 (O(1) vs O(n))
    final currentIndex = document.getNodeIndexById(nodeId);
    if (currentIndex == -1) return;

    // 🛡️ 제목 노드 보호: 제목 노드는 항상 index 0에 유지
    if (node is ParagraphNode && node.metadata['isTitle'] == true) {
      return;
    }

    // 🛡️ 제목 노드 위치 보호: 다른 노드를 index 0으로 이동하는 것 방지
    if (targetIndex == 0) {
      final titleNode = document.getNodeAt(0);
      if (titleNode is ParagraphNode && titleNode.metadata['isTitle'] == true) {
        return;
      }
    }

    // 같은 위치면 이동하지 않음
    if (currentIndex == targetIndex) return;

    // 🎯 reorder 작업 중에는 히스토리 추적 일시 중단
    _historyService.isExecutingHistory = true;

    try {
      // 문서 끝에 삽입하는 경우 처리
      if (targetIndex >= document.length) {
        document.deleteNode(nodeId);
        document.insertNodeAt(document.length, node);
      } else {
        // 노드 삭제 후 새 위치에 삽입
        document.deleteNode(nodeId);
        final insertIndex =
            targetIndex > currentIndex ? targetIndex - 1 : targetIndex;
        document.insertNodeAt(insertIndex, node);
      }
      // 🎯 notifyListeners는 finally 이후에 한 번만
    } finally {
      _historyService.isExecutingHistory = false;
      _historyService.saveCurrentState(
        immediate: true,
        onSaved: notifyListeners,
      );
      debugPrint(
        '[EditorService] 🔄 노드 순서 변경 완료 (${currentIndex} → ${targetIndex})',
      );
      notifyListeners(); // 🎯 최종: 한 번만 호출
    }
  }

  /// 두 이미지를 가로 배치로 합치는 함수
  void mergeImagesIntoRow(
    String draggingImageId,
    String targetImageId, {
    bool isFromLeft = true,
  }) {
    _imageService.mergeImagesIntoRow(
      draggingImageId,
      targetImageId,
      isFromLeft: isFromLeft,
    );
  }

  NodeType getNodeType(String nodeId) {
    final node = document.getNodeById(nodeId);
    switch (node) {
      case ParagraphNode():
        return NodeType.paragraph;
      case ImageNode():
        return NodeType.image;
      case ImageRowNode():
        return NodeType.imageRow;
      default:
        return NodeType.unknown;
    }
  }

  int getEditingIndex() {
    final selection = editor.composer.selectionNotifier.value;
    if (selection == null) return -1;
    final nodeId = selection.extent.nodeId;
    return document.getNodeIndexById(nodeId);
  }

  /// 링크 노드를 현재 커서 다음 슬롯에 삽입
  void addLinkNode({
    required String url,
    String? title,
    String? description,
    String? thumbnailUrl,
  }) {
    final node = LinkNode(
      id: 'link_${DateTime.now().millisecondsSinceEpoch}',
      url: url,
      title: title ?? '',
      description: description ?? '',
      thumbnailUrl: thumbnailUrl ?? '',
    );
    _insertComponentNodeAtNextLine(node);
  }

  /// 지정 인덱스에 빈 문단을 삽입하고 캐럿을 그 문단 앞으로 이동
  /// 🎯 정렬을 이전 문단에서 상속받아 항상 유지
  void insertEmptyParagraphAtIndex(int index) {
    try {
      final doc = editor.document;
      int insertIndex = index;
      if (insertIndex < 0) insertIndex = 0;
      if (insertIndex > doc.nodeCount) insertIndex = doc.nodeCount;

      // 🎯 이전 문단의 정렬을 가져와서 상속
      final String align = _getPreviousParagraphAlign(insertIndex);
      final String paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';

      final ParagraphNode newParagraph = ParagraphNode(
        id: paragraphId,
        text: AttributedText(''),
        metadata: {'textAlign': align},
      );

      editor.execute([
        InsertNodeAtIndexRequest(nodeIndex: insertIndex, newNode: newParagraph),
      ]);

      // 🎯 정렬 보정 (삽입 후 정렬이 제대로 적용되었는지 확인)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          // 정렬이 제대로 적용되었는지 확인하고 보정
          _documentService.ensureParagraphAlignmentForIndex(insertIndex);

          editor.execute([
            ChangeSelectionRequest(
              DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: paragraphId,
                  nodePosition: const TextNodePosition(offset: 0),
                ),
              ),
              SelectionChangeType.placeCaret,
              SelectionReason.userInteraction,
            ),
          ]);
        } catch (_) {}
      });
      // 🎯 editor.execute()가 자동으로 document 리스너를 호출하므로 notifyListeners() 불필요
    } catch (_) {}
  }

  /// 언급 노드를 문단(Paragraph) 기반으로 삽입한다.
  /// - 전체 텍스트는 굵게(bold)
  /// - 메타데이터로 mention 플래그와 usernames를 보관
  /// - 컴포넌트처럼 현재 라인 다음 슬롯에 삽입(필요 시 끝에 빈 문단 생성)
  /// - 각 멘션은 개별 노드로 생성되어 세로로 표시됨
  /// 멘션 노드 추가
  void addMentionNode(List<String> usernames) {
    _mentionService.addMentionNode(usernames);
  }

  ///  노드 추가: 현재 캐럿 다음 슬롯에  삽입
  void addClipNode({
    String label = '',
    String colorHex = '#FF5252',
    required String url,
  }) {
    _videoService.addClipNode(label: label, colorHex: colorHex, url: url);
  }

  DocumentNode? findNodeAtPosition(Offset position) {
    final documentLayout = _documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) {
      return null;
    }

    try {
      // 글로벌 좌표를 DocumentLayout의 로컬 좌표로 변환
      final renderObject =
          _documentLayoutKey?.currentContext?.findRenderObject();
      RenderBox? renderBox;
      if (renderObject is RenderSliverToBoxAdapter) {
        renderBox = renderObject.child;
      } else if (renderObject is RenderBox) {
        renderBox = renderObject;
      }

      if (renderBox == null) {
        return null;
      }

      // 글로벌 좌표를 DocumentLayout의 로컬 좌표로 변환
      final localPosition = renderBox.globalToLocal(position);

      // SuperEditor 내장 함수 사용 (안전한 처리)
      DocumentPosition? documentPosition;
      try {
        documentPosition = documentLayout.getDocumentPositionNearestToOffset(
          localPosition,
        );
      } catch (e) {
        return null;
      }

      if (documentPosition == null) {
        return null;
      }

      final node = document.getNodeById(documentPosition.nodeId);

      return node;
    } catch (e) {
      debugPrint("Error finding node at position: $e");
      return null;
    }
  }

  /// 🎯 직접 hit test 방식: 모든 노드의 실제 렌더링 영역을 확인하여 탭 위치가 어느 노드에 있는지 정확히 판단
  /// findNodeAtPosition과 달리 실제 렌더링된 컴포넌트의 글로벌 좌표를 사용하므로 더 정확함
  ///
  /// 반환값: (탭된 노드, 노드의 실제 렌더링 영역)
  /// 텍스트 노드가 최우선순위를 가지며, 텍스트 노드가 없을 때만 특수 노드를 확인
  MapEntry<DocumentNode?, Rect?>? findNodeByHitTest(
    Offset globalPosition,
    DragService dragService,
  ) {
    try {
      // 🎯 텍스트 노드를 먼저 확인하여 최우선순위 보장
      // 텍스트 노드가 감지되면 즉시 반환하여 특수 노드 선택 방지
      for (int i = 0; i < document.nodeCount; i++) {
        final node = document.getNodeAt(i);
        if (node == null) continue;

        // 🎯 텍스트 노드를 먼저 확인
        if (node is ParagraphNode &&
            node.metadata['mention'] != true &&
            node.metadata['isTitle'] != true) {
          final rect = dragService.getNodeGlobalRect(node.id);
          if (rect != null && rect.contains(globalPosition)) {
            // 텍스트 노드가 감지되면 즉시 반환 (특수 노드보다 우선)
            return MapEntry(node, rect);
          }
        }
      }

      // 텍스트 노드가 없을 때만 특수 노드 확인
      // 🎯 멘션 노드는 일반 텍스트로 처리하므로 특수 노드에서 제외
      final specialNodes = <MapEntry<DocumentNode, Rect>>[];
      for (int i = 0; i < document.nodeCount; i++) {
        final node = document.getNodeAt(i);
        if (node == null) continue;

        final bool isSpecial = isSpecialNode(node);

        if (isSpecial) {
          final rect = dragService.getNodeGlobalRect(node.id);
          if (rect != null && rect.contains(globalPosition)) {
            specialNodes.add(MapEntry(node, rect));
          }
        }
      }

      // 특수 노드가 있으면 위에서부터 반환
      if (specialNodes.isNotEmpty) {
        // 위에서부터 확인 (인덱스 순서대로)
        specialNodes.sort((a, b) {
          final indexA = document.getNodeIndexById(a.key.id);
          final indexB = document.getNodeIndexById(b.key.id);
          return indexA.compareTo(indexB);
        });
        return MapEntry(specialNodes.first.key, specialNodes.first.value);
      }

      return null;
    } catch (e) {
      debugPrint("Error in findNodeByHitTest: $e");
      return null;
    }
  }

  /// 이미지 행에서 특정 이미지를 분리하고 분리된 이미지 ID 반환
  /// insertIndex가 주어지면 해당 위치에 바로 삽입한다. 주어지지 않으면 행의 위치(rowIndex)에 삽입.
  String? splitImageFromRow(String rowId, int imageIndex, {int? insertIndex}) {
    return _imageService.splitImageFromRow(
      rowId,
      imageIndex,
      insertIndex: insertIndex,
    );
  }

  /// 이미지 추가: 현재 커서 다음 줄에 로컬 경로 기반 이미지 노드 삽입
  String addImageNode(String localPath) {
    return _imageService.addImageNode(
      localPath,
      _insertComponentNodeAtNextLine,
    );
  }

  /// 그룹 이미지 노드 추가 (로컬 경로 기반)
  String addGroupImageNode({
    required List<String> localPaths,
    required GroupImageLayout layout,
  }) {
    return _imageService.addGroupImageNode(
      localPaths: localPaths,
      layout: layout,
      insertComponentNodeAtNextLine: _insertComponentNodeAtNextLine,
    );
  }

  /// 단일 이미지의 URL을 메타데이터에 저장
  Future<void> replaceImageUrlByPath({
    required String nodeId,
    required String localPath,
    required String url,
  }) async {
    await _imageService.replaceImageUrlByPath(
      nodeId: nodeId,
      localPath: localPath,
      url: url,
      setHistoryExecuting:
          (bool value) => _historyService.isExecutingHistory = value,
      notifyListeners: notifyListeners,
    );
  }

  /// 비디오 클립 노드 추가 (로컬 경로 기반)
  String addVideoClipNode({
    required String localPath,
    String label = '',
    String? thumbnailPath,
    double? aspectRatio,
  }) {
    return _videoService.addVideoClipNode(
      localPath: localPath,
      label: label,
      thumbnailPath: thumbnailPath,
      aspectRatio: aspectRatio,
    );
  }

  /// 비디오 썸네일 업데이트
  void updateVideoThumbnail(String nodeId, String thumbnailPath) {
    _videoService.updateVideoPlaceholderThumbnail(nodeId, thumbnailPath);
  }

  /// 비디오 URL을 메타데이터에 저장
  Future<void> replaceVideoUrlByPath({
    required String nodeId,
    required String url,
    String? fallbackLocalPath,
  }) async {
    await _videoService.replaceVideoPlaceholderWithUrl(
      nodeId,
      url,
      fallbackLocalPath: fallbackLocalPath,
      isNetworkUrl: isNetworkUrl,
    );
  }

  /// 🎯 그룹 이미지의 특정 로컬 경로를 URL로 교체
  Future<void> replaceGroupImageUrlByPath({
    required String groupNodeId,
    required String localPath,
    required String url,
  }) async {
    await _imageService.replaceGroupImageUrlByPath(
      groupNodeId: groupNodeId,
      localPath: localPath,
      url: url,
      setHistoryExecuting:
          (bool value) => _historyService.isExecutingHistory = value,
      notifyListeners: notifyListeners,
    );
  }

  // selection이 null이거나 nodeId를 찾지 못해도 문서 끝을 반환하여 안전
  int _getCaretNodeIndexSafe() {
    final doc = editor.document;
    final sel =
        editor.composer.selectionNotifier.value ??
        _selectionService.lastSelection;
    if (sel == null) return doc.nodeCount;
    final idx = doc.getNodeIndexById(sel.extent.nodeId);
    return idx == -1 ? doc.nodeCount : idx;
  }

  /// 공통 삽입 유틸: 현재 커서 위치에 컴포넌트 노드를 삽입한다.
  /// 만약 삽입 지점이 문서의 마지막(끝)이면, 그 아래에 빈 문단을 추가하고
  /// 커서를 그 빈 문단 앞으로 이동한다.
  void _insertComponentNodeAtNextLine(DocumentNode componentNode) {
    debugPrint('DEBUG: _insertComponentNodeAtNextLine: $componentNode');
    final doc = editor.document;
    final safeIndex = _getCaretNodeIndexSafe();
    int insertIndex = safeIndex;

    // 제목 노드(index 0)에 커서가 있으면 강제로 다음 라인에 삽입
    if (insertIndex == 0) {
      insertIndex = 1;
      debugPrint('🎯 제목 노드에 커서가 있음, 다음 라인(index 1)에 삽입');

      // 제목 다음에 빈 문단이 없으면 먼저 생성
      if (doc.nodeCount < 2) {
        final paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';
        final ParagraphNode newParagraph = ParagraphNode(
          id: paragraphId,
          text: AttributedText(''),
          metadata: {'textAlign': 'center'},
        );
        doc.insertNodeAt(1, newParagraph);
        debugPrint('📝 제목 다음에 빈 문단 생성');
      }
    } else {
      // 현재 커서가 있는 문단에 텍스트가 있으면 다음 줄에 삽입
      if (insertIndex < doc.nodeCount) {
        final currentNode = doc.getNodeAt(insertIndex);
        if (currentNode is ParagraphNode) {
          final hasText = currentNode.text.text.trim().isNotEmpty;
          if (hasText) {
            insertIndex = insertIndex + 1;
            debugPrint('🎯 현재 문단에 텍스트가 있음, 다음 줄(index $insertIndex)에 삽입');
          }
        }
      }
    }

    if (insertIndex > doc.nodeCount) insertIndex = doc.nodeCount;

    final bool insertingAtEnd = insertIndex == doc.nodeCount;

    final edits = <EditRequest>[
      InsertNodeAtIndexRequest(nodeIndex: insertIndex, newNode: componentNode),
    ];

    if (insertingAtEnd) {
      final String paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';
      // 🎯 직전 문단의 정렬을 승계 (항상 정렬 유지)
      final String inheritedAlign = _getPreviousParagraphAlign(insertIndex);
      final ParagraphNode trailingParagraph = ParagraphNode(
        id: paragraphId,
        text: AttributedText(''),
        metadata: {'textAlign': inheritedAlign},
      );
      edits.add(
        InsertNodeAtIndexRequest(
          nodeIndex: insertIndex + 1,
          newNode: trailingParagraph,
        ),
      );
      // selection 이동은 프레임 이후로 지연하여 iOS 핸들 레이어의 NPE 방지
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          // 🎯 정렬 보정 (삽입 후 정렬이 제대로 적용되었는지 확인)
          _documentService.ensureParagraphAlignmentForIndex(insertIndex + 1);

          editor.execute([
            ChangeSelectionRequest(
              DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: paragraphId,
                  nodePosition: const TextNodePosition(offset: 0),
                ),
              ),
              SelectionChangeType.placeCaret,
              SelectionReason.userInteraction,
            ),
          ]);
        } catch (_) {}
      });
    }

    editor.execute(edits);
  }

  String _getPreviousParagraphAlign(int beforeIndex) {
    return _documentService.getPreviousParagraphAlign(beforeIndex);
  }

  static bool isNetworkUrl(String imageUrl) {
    return imageUrl.startsWith('http') || imageUrl.startsWith('https');
  }
}
