import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/image/simple_image_editor_screen.dart';
import 'package:doppy/image/group_image_layout_selector.dart';
import 'package:doppy/image/utils/image_bytes_resolver.dart';
import 'package:doppy/utils/image_size_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/l10n/app_localizations.dart';

/// 에디터 내 특수 노드(이미지/이미지행/링크/멘션 등)의 선택/하이라이트 상태를 관리하는 서비스
class NodeComponentService extends ChangeNotifier {
  static final NodeComponentService _instance =
      NodeComponentService._internal();
  factory NodeComponentService() => _instance;
  NodeComponentService._internal();

  void clearAll() {
    clearHighlightedSelection();
    selectImage(null);
    _spoilerByNodeId.clear();
  }

  /// 스포일러 상태만 초기화 (다른 상태는 유지)
  /// notify=false로 호출하면 리스너 알림 없이 내부 상태만 비웁니다.
  void clearSpoilers({bool notify = true}) {
    if (_spoilerByNodeId.isEmpty) return;
    _spoilerByNodeId.clear();

    if (!notify) return;

    // 위젯 트리가 잠긴 상태에서는 다음 프레임에 알림을 스케줄링
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      notifyListeners();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) notifyListeners();
      });
    }
  }

  // ===== 스포일러 헬퍼 =====
  bool shouldShowImageSpoiler(String nodeId, Map<String, dynamic>? metadata) {
    if (isSpoilerDisabled(nodeId)) return false; // 해제되면 숨기지 않음
    final metaFlag = (metadata != null && metadata['spoiler'] == true);
    return metaFlag || isSpoiler(nodeId);
  }

  bool shouldShowParagraphSpoiler(String nodeId, AttributedText text) {
    if (isSpoilerDisabled(nodeId)) return false;
    for (int i = 0; i < text.text.length; i++) {
      final attrs = text.getAllAttributionsAt(i);
      if (attrs.any((a) => a is NamedAttribution && a.id == 'spoiler')) {
        return true;
      }
    }
    return false;
  }

  // URL↔ID 매핑 로직 제거됨

  // 현재 선택된 노드 ID (과거 호환: 이미지 기준 네이밍 유지)
  String? _selectedImageId;
  // 편집된 이미지 바이트 저장소 (nodeId -> bytes)
  final Map<String, Uint8List> _editedBytesByNodeId = <String, Uint8List>{};
  // 텍스트 범위 선택에 포함된 이미지/이미지행 하이라이트 id 집합
  final Set<String> _selectionHighlightedImageIds = <String>{};
  // 스포일러 상태 (세션 범위 캐시)
  final Map<String, bool> _spoilerByNodeId = <String, bool>{};

  // Getters
  String? get selectedImageId => _selectedImageId;
  // 신규 API(의미 반영): 선택된 노드 ID
  String? get selectedNodeId => _selectedImageId;
  Uint8List? getEditedBytes(String nodeId) => _editedBytesByNodeId[nodeId];
  Set<String> get selectionHighlightedIds => _selectionHighlightedImageIds;
  bool get hasSelectedImage => _selectedImageId != null;
  bool isSpoiler(String nodeId) => _spoilerByNodeId[nodeId] == true;

  /// 스포일러가 명시적으로 비활성화되었는지 확인 (false로 설정된 경우)
  bool isSpoilerDisabled(String nodeId) {
    final hasKey = _spoilerByNodeId.containsKey(nodeId);
    final value = _spoilerByNodeId[nodeId];
    final result = hasKey && value == false;
    return result;
  }

  // ====== Transient video file storage (session-scoped, in-memory only) ======
  final Map<String, String> _tempVideoFilePathBySession =
      <String, String>{}; // 영상 파일 경로 저장
  final Map<String, String> _tempVideoThumbnailPathBySession =
      <String, String>{}; // 영상 로컬 썸네일 파일 경로 저장

  String? getTempVideoFilePath(String sessionKey) =>
      _tempVideoFilePathBySession[sessionKey];

  String? getTempVideoThumbnailPath(String sessionKey) =>
      _tempVideoThumbnailPathBySession[sessionKey];

  void setTempVideoFile(String sessionKey, String filePath) {
    _tempVideoFilePathBySession[sessionKey] = filePath;
    notifyListeners();
  }

  void setTempVideoThumbnail(String sessionKey, String thumbnailPath) {
    _tempVideoThumbnailPathBySession[sessionKey] = thumbnailPath;
    notifyListeners();
  }

  void clearTempVideoFile(String sessionKey) {
    _tempVideoFilePathBySession.remove(sessionKey);
    _tempVideoThumbnailPathBySession.remove(sessionKey);
    notifyListeners();
  }

  // notifyListeners() 없이 조용히 영상 정리 (dispose 시 사용)
  void clearTempVideoFileSilently(String sessionKey) {
    _tempVideoFilePathBySession.remove(sessionKey);
    _tempVideoThumbnailPathBySession.remove(sessionKey);
  }

  /// 노드 선택 (과거 호환: 이미지 선택)
  void selectImage(String? imageId) {
    if (imageId == _selectedImageId) {
      // 이미지 선택 취소
      _selectedImageId = null;
    } else {
      _selectedImageId = imageId;
    }

    notifyListeners();
  }

  /// 신규 API: 노드 선택
  void selectNode(String? nodeId) => selectImage(nodeId);

  /// 선택 상태 해제
  void clearSelection() {
    _selectedImageId = null;
    notifyListeners();
  }

  /// 신규 API: 선택 상태 해제 (별칭)
  void clearNodeSelection() => clearSelection();

  /// 선택 상태 해제 (notify 없이 조용히)
  void clearSelectionSilently() {
    _selectedImageId = null;
  }

  /// 신규 API: 선택 상태 해제 (notify 없이 조용히) 별칭
  void clearNodeSelectionSilently() => clearSelectionSilently();

  /// 편집 결과 반영: 해당 이미지 노드에 편집된 바이트를 저장한다
  void applyEditedBytes({required String nodeId, required Uint8List bytes}) {
    _editedBytesByNodeId[nodeId] = bytes;
    notifyListeners();
  }

  /// 편집 결과 제거(원본으로 복귀)
  void clearEditedBytes(String nodeId) {
    if (_editedBytesByNodeId.remove(nodeId) != null) {
      notifyListeners();
    }
  }

  /// 이미지/행 노드 스포일러 토글 및 설정
  void toggleSpoiler(String nodeId) {
    _spoilerByNodeId[nodeId] = !(_spoilerByNodeId[nodeId] == true);
    notifyListeners();
  }

  void setSpoiler(String nodeId, bool value) {
    final oldValue = _spoilerByNodeId[nodeId];
    if (oldValue == value) {
      if (kDebugMode) {
        debugPrint(
          '[NodeComponentService] setSpoiler: $nodeId = $value (변경 없음)',
        );
      }
      return;
    }
    _spoilerByNodeId[nodeId] = value;
    if (kDebugMode) {
      debugPrint(
        '[NodeComponentService] setSpoiler: $nodeId = $value (이전: $oldValue), notifyListeners 호출',
      );
    }
    notifyListeners();
  }

  /// 현재 텍스트 범위 선택에 포함된 특수 노드를 하이라이트한다
  void setHighlightedSelection(Set<String> ids) {
    if (_selectionHighlightedImageIds.length == ids.length &&
        _selectionHighlightedImageIds.containsAll(ids)) {
      return;
    }
    _selectionHighlightedImageIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  /// 신규 API: 하이라이트 설정 별칭
  void setHighlightedNodeSelection(Set<String> ids) =>
      setHighlightedSelection(ids);

  /// 특수 노드 하이라이트 해제
  void clearHighlightedSelection() {
    if (_selectionHighlightedImageIds.isEmpty) return;
    _selectionHighlightedImageIds.clear();
    notifyListeners();
  }

  /// 신규 API: 하이라이트 해제 별칭
  void clearHighlightedNodeSelection() => clearHighlightedSelection();

  /// 특수 노드 하이라이트 해제 (notify 없이 조용히)
  void clearHighlightedSelectionSilently() {
    if (_selectionHighlightedImageIds.isEmpty) return;
    _selectionHighlightedImageIds.clear();
  }

  /// 신규 API: 하이라이트 해제 (조용히) 별칭
  void clearHighlightedNodeSelectionSilently() =>
      clearHighlightedSelectionSilently();

  // ===== 이미지 편집 =====
  bool _isEditingImage = false;

  /// 이미지 편집 프로세스
  Future<void> editImage({
    required BuildContext context,
    required String imageId,
    required DocumentNode node,
    required EditorService editorService,
    required MutableDocument document,
  }) async {
    // 이미 편집 중이면 무시
    if (_isEditingImage) return;
    _isEditingImage = true;

    // 🎯 이미지 편집 전 현재 상태를 히스토리에 저장
    editorService.saveHistoryNow();
    debugPrint('[NodeComponentService] 📸 이미지 편집 전 히스토리 저장');

    // 🎯 로딩 다이얼로그 상태 추적 (함수 스코프)
    BuildContext? dialogContext;
    bool isDialogClosed = false; // 다이얼로그가 이미 닫혔는지 추적

    try {
      FocusScope.of(context).unfocus();

      // 로딩 다이얼로그 표시 (dialogContext 저장하여 명시적으로 닫기)
      //여기를 커스텀 스피너로 바꾸면 좋을 듯
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          dialogContext = dialogCtx;
          return PopScope(
            canPop: false,
            child: Center(
              child: SizedBox(
                width: 80,
                height: 80,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      );

      // ✅ 노드 타입별 이미지 소스(url/path/file://) 수집
      final sources = <String>[];
      if (node is ImageNode) {
        sources.add(node.imageUrl);
      } else if (node is ImageRowNode) {
        sources.addAll(node.imageUrls);
      } else if (node is PageViewImageNode) {
        sources.addAll(node.imageUrls);
      } else {
        // 지원하지 않는 노드 타입
        if (!isDialogClosed) {
          isDialogClosed = true;
          _closeLoadingDialogSafely(context, dialogContext);
        }
        if (context.mounted) {
          ErrorHandler.showError(context, context.tr('image_edit_failed'));
        }
        return;
      }

      // ✅ 네트워크/로컬 공통: bytes로 변환
      List<Uint8List> imageBytesList;
      try {
        imageBytesList = await ImageBytesResolver.resolveMany(
          sources,
          timeoutPerItem: const Duration(seconds: 10),
        );
      } on TimeoutException catch (e) {
        debugPrint('[NodeComponentService] 이미지 로드 타임아웃: $e');
        if (!isDialogClosed) {
          isDialogClosed = true;
          _closeLoadingDialogSafely(context, dialogContext);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ErrorHandler.showError(context, context.tr('image_download_failed'));
        }
        return;
      } catch (e) {
        debugPrint('[NodeComponentService] 이미지 로드 실패: $e');
        if (!isDialogClosed) {
          isDialogClosed = true;
          _closeLoadingDialogSafely(context, dialogContext);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ErrorHandler.showError(context, context.tr('image_load_failed'));
        }
        return;
      }

      // 🎯 이미지 다운로드 완료 후 다이얼로그 닫기 (편집기 열기 전)
      if (!isDialogClosed) {
        isDialogClosed = true;
        _closeLoadingDialogSafely(context, dialogContext);
      }

      // 3) SimpleImageEditorScreen 열기
      await Navigator.push<void>(
        context,
        PageRouteBuilder(
          fullscreenDialog: true,
          barrierColor: Theme.of(context).colorScheme.background,
          opaque: false,
          barrierDismissible: true,
          pageBuilder: (editorContext, _, __) {
            return imageBytesList.length <= 1
                ? SimpleImageEditorScreen(
                  imageBytes: imageBytesList.first,
                  isExistingNodeEdit: true,
                  enableLayoutSelectionForMultiImage: false,
                  onDone: (editorContext, result) async {
                    await _applyEditedImagesToNode(
                      context: context,
                      editorContext: editorContext,
                      imageId: imageId,
                      node: node,
                      editorService: editorService,
                      document: document,
                      result: result,
                    );
                  },
                )
                : SimpleImageEditorScreen(
                  imageBytesList: imageBytesList,
                  isExistingNodeEdit: true,
                  enableLayoutSelectionForMultiImage: false,
                  onDone: (editorContext, result) async {
                    await _applyEditedImagesToNode(
                      context: context,
                      editorContext: editorContext,
                      imageId: imageId,
                      node: node,
                      editorService: editorService,
                      document: document,
                      result: result,
                    );
                  },
                );
          },
        ),
      );
      // ✅ onDone에서 업로드/리플레이스까지 끝내고 editor를 닫는다.
      return;
    } catch (e) {
      debugPrint('[NodeComponentService] 이미지 편집 중 오류: $e');
      // 로딩 다이얼로그가 열려있을 수 있으므로 닫기 시도 (에디터는 유지)
      // 단, 이미 닫혔으면 다시 닫지 않음
      if (!isDialogClosed) {
        isDialogClosed = true;
        _closeLoadingDialogSafely(context, dialogContext);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ErrorHandler.showError(context, context.tr('image_edit_failed'));
      }
    } finally {
      // 🎯 finally에서도 로딩 다이얼로그가 열려있으면 닫기 (안전장치, 에디터는 유지)
      // 단, 이미 닫혔으면 다시 닫지 않음 (중복 pop 방지)
      if (!isDialogClosed && dialogContext != null) {
        isDialogClosed = true;
        _closeLoadingDialogSafely(context, dialogContext);
      }
      _isEditingImage = false;
    }
  }

  Future<void> _applyEditedImagesToNode({
    required BuildContext context,
    required BuildContext editorContext,
    required String imageId,
    required DocumentNode node,
    required EditorService editorService,
    required MutableDocument document,
    required dynamic result,
  }) async {
    if (!context.mounted) return;

    // ✅ 결과 파싱 (단일/다중 + layout)
    List<Uint8List> editedImages;
    GroupImageLayout? selectedLayout;
    if (result is Uint8List) {
      editedImages = [result];
    } else if (result is List<Uint8List>) {
      editedImages = result;
    } else if (result is Map) {
      final imgs = result['images'];
      final layout = result['layout'];
      if (imgs is List<Uint8List>) {
        editedImages = imgs;
      } else {
        editedImages = <Uint8List>[];
      }
      if (layout is GroupImageLayout) {
        selectedLayout = layout;
      }
    } else {
      return;
    }

    if (editedImages.isEmpty) return;

    // ✅ (닫히기 전에) 사이즈 미리 측정
    final sizes = await Future.wait(
      List.generate(editedImages.length, (i) async {
        try {
          return await ImageSizeUtils.extractSizeFromBytes(
            editedImages[i],
            'edited_$i.jpg',
          );
        } catch (_) {
          return null;
        }
      }),
    );

    // ✅ 업로드 진행: 임시 파일 생성 → 배치 업로드 → URL 수집
    final upload = context.read<UploadService>();
    final tempDir = await getTemporaryDirectory();
    final tempFiles = <File>[];
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < editedImages.length; i++) {
      final f = File('${tempDir.path}/edited_${ts}_$i.jpg');
      await f.writeAsBytes(editedImages[i]);
      tempFiles.add(f);
    }

    List<UploadTask> tasks = [];
    try {
      tasks = await upload
          .uploadFilesViaServerBatches(tempFiles, kind: UploadKind.editorImage)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              throw TimeoutException(
                '이미지 업로드 시간이 초과되었습니다.',
                const Duration(seconds: 45),
              );
            },
          );
    } on TimeoutException catch (e) {
      debugPrint('[NodeComponentService] 이미지 업로드 타임아웃: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ErrorHandler.showError(context, context.tr('image_upload_failed'));
      }
      return;
    } finally {
      for (final f in tempFiles) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    if (tasks.isEmpty || tasks.any((t) => t.state != UploadState.success)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ErrorHandler.showError(context, context.tr('image_upload_failed'));
      }
      return;
    }

    final urls =
        tasks
            .map((t) => t.url)
            .whereType<String>()
            .where((u) => u.isNotEmpty)
            .toList();
    if (urls.length != editedImages.length) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ErrorHandler.showError(context, context.tr('image_url_failed'));
      }
      return;
    }

    // ✅ 문서 노드 교체 (ImageNode / ImageRowNode / PageViewImageNode)
    final nodeIndex = document.getNodeIndexById(imageId);
    if (nodeIndex == -1) return;

    // 메타데이터 보존 + imageDimensions 업데이트
    Map<String, dynamic> meta = <String, dynamic>{};
    String altText = '';
    double rowSpacing = 0.0;
    if (node is ImageNode) {
      altText = node.altText;
      try {
        meta = Map<String, dynamic>.from(
          (node as dynamic).metadata as Map<String, dynamic>? ?? {},
        );
      } catch (_) {
        meta = Map<String, dynamic>.from(node.metadata);
      }
    } else if (node is ImageRowNode) {
      meta = Map<String, dynamic>.from(node.metadata);
      rowSpacing = node.spacing;
    } else if (node is PageViewImageNode) {
      meta = Map<String, dynamic>.from(node.metadata);
    }

    final imageDimensions = Map<String, dynamic>.from(
      (meta['imageDimensions'] as Map<String, dynamic>?) ?? {},
    );
    for (int i = 0; i < urls.length; i++) {
      final s = (i < sizes.length) ? sizes[i] : null;
      if (s == null) continue;
      imageDimensions[urls[i]] = {
        'width': s.width.toInt(),
        'height': s.height.toInt(),
      };
    }
    meta['imageDimensions'] = imageDimensions;

    // 레이아웃이 없으면 "원래 노드 타입 유지"가 기본
    final effectiveLayout =
        selectedLayout ??
        (node is PageViewImageNode
            ? GroupImageLayout.pageview
            : (node is ImageRowNode
                ? GroupImageLayout.grid2
                : GroupImageLayout.individual));

    // ✅ 기존 노드 편집에서는 구조 유지(기본)
    if (node is ImageNode) {
      final newNode = AppImageNode(
        id: imageId,
        imageUrl: urls.first,
        altText: altText,
        metadata: Map<String, dynamic>.from(meta),
      );
      editorService.editor.execute([
        ReplaceNodeRequest(existingNodeId: imageId, newNode: newNode),
      ]);
      editorService.saveHistoryNow();
      if (editorContext.mounted) Navigator.of(editorContext).pop();
      return;
    }

    if (node is ImageRowNode) {
      final newNode = ImageRowNode(
        id: imageId,
        imageUrls: urls,
        spacing: rowSpacing,
        metadata: Map<String, dynamic>.from(meta),
      );
      editorService.editor.execute([
        ReplaceNodeRequest(existingNodeId: imageId, newNode: newNode),
      ]);
      editorService.saveHistoryNow();
      if (editorContext.mounted) Navigator.of(editorContext).pop();
      return;
    }

    if (node is PageViewImageNode) {
      final newNode = PageViewImageNode(
        id: imageId,
        imageUrls: urls,
        metadata: Map<String, dynamic>.from(meta),
      );
      editorService.editor.execute([
        ReplaceNodeRequest(existingNodeId: imageId, newNode: newNode),
      ]);
      editorService.saveHistoryNow();
      if (editorContext.mounted) Navigator.of(editorContext).pop();
      return;
    }

    // (안전장치) 여기로 오면 일반적으로 도달하지 않음.
    if (effectiveLayout == GroupImageLayout.pageview ||
        effectiveLayout == GroupImageLayout.individual ||
        effectiveLayout == GroupImageLayout.grid2 ||
        effectiveLayout == GroupImageLayout.grid3) {
      // 기존 로직은 editImage 내부에 남아있으므로, 예상치 못한 타입은 스킵
      return;
    }
  }

  // 🎯 로딩 다이얼로그 안전하게 닫기 (에디터는 유지)
  void _closeLoadingDialogSafely(
    BuildContext context,
    BuildContext? dialogContext,
  ) {
    if (!context.mounted || dialogContext == null) {
      debugPrint('[NodeComponentService] 다이얼로그 닫기 스킵: context가 유효하지 않음');
      return;
    }

    try {
      // 다이얼로그 context가 여전히 유효한지 확인
      if (!dialogContext.mounted) {
        debugPrint(
          '[NodeComponentService] 다이얼로그 닫기 스킵: dialogContext가 이미 unmounted',
        );
        return;
      }

      // 다이얼로그 context에서 직접 pop (에디터는 절대 닫히지 않음)
      Navigator.pop(dialogContext);
      debugPrint('[NodeComponentService] ✅ 로딩 다이얼로그 닫기 성공');
    } catch (e) {
      debugPrint('[NodeComponentService] ⚠️ 로딩 다이얼로그 닫기 실패: $e');
      // fallback 시도하지 않음 (에디터를 닫을 위험이 있음)
      // 다이얼로그가 이미 닫혔거나 다른 문제가 있을 수 있음
    }
  }
}
