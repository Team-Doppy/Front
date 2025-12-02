import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/image/custom_image_editor_screen.dart';
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
    required ImageNode node,
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

      // 🎯 이미지 다운로드에 타임아웃 추가 (10초)
      http.Response response;
      try {
        response = await http
            .get(Uri.parse(node.imageUrl))
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                debugPrint('[NodeComponentService] 이미지 다운로드 타임아웃');
                throw TimeoutException(
                  '이미지 다운로드 시간이 초과되었습니다.',
                  const Duration(seconds: 10),
                );
              },
            );
      } on TimeoutException catch (e) {
        debugPrint('[NodeComponentService] 이미지 다운로드 타임아웃: $e');
        // 로딩 다이얼로그 닫기 (에디터는 유지)
        if (!isDialogClosed) {
          isDialogClosed = true;
          _closeLoadingDialogSafely(context, dialogContext);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ErrorHandler.showError(context, context.tr('image_download_failed'));
        }
        return;
      } on Exception catch (e) {
        debugPrint('[NodeComponentService] 이미지 다운로드 실패: $e');
        // 로딩 다이얼로그 닫기 (에디터는 유지)
        if (!isDialogClosed) {
          isDialogClosed = true;
          _closeLoadingDialogSafely(context, dialogContext);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ErrorHandler.showError(context, context.tr('image_download_failed'));
        }
        return;
      }

      if (response.statusCode != 200) {
        // 로딩 다이얼로그 닫기
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

      final imageBytes = response.bodyBytes;

      // 🎯 이미지 다운로드 완료 후 다이얼로그 닫기 (편집기 열기 전)
      if (!isDialogClosed) {
        isDialogClosed = true;
        _closeLoadingDialogSafely(context, dialogContext);
      }

      // 3. 이미지 편집기 열기 (오버레이 스타일)
      // 🎯 업로드 및 노드 교체를 처리하는 콜백 전달
      final editedBytes = await Navigator.push<Uint8List?>(
        context,
        PageRouteBuilder(
          fullscreenDialog: true,
          barrierColor: Theme.of(context).colorScheme.background,
          opaque: false,
          barrierDismissible: true,
          pageBuilder:
              (context, _, __) => CustomImageEditorScreen(
                imageBytes: imageBytes,
                onApplyChanges: (Uint8List bytes) async {
                  // 업로드 및 노드 교체를 동기로 처리
                  try {
                    final upload = context.read<UploadService>();

                    // 임시 파일로 변환
                    final tempDir = await getTemporaryDirectory();
                    final tempFile = File(
                      '${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg',
                    );
                    await tempFile.writeAsBytes(bytes);

                    // 🎯 업로드 완료까지 대기
                    final tasks = await upload.uploadFilesViaServerBatches([
                      tempFile,
                    ], kind: UploadKind.editorImage);

                    // 임시 파일 삭제
                    try {
                      await tempFile.delete();
                    } catch (_) {}

                    if (tasks.isEmpty ||
                        tasks.first.state != UploadState.success) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ErrorHandler.showError(
                          context,
                          context.tr('image_upload_failed'),
                        );
                      }
                      return false;
                    }

                    final newUrl = tasks.first.url;
                    if (newUrl == null || newUrl.isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ErrorHandler.showError(
                          context,
                          context.tr('image_url_failed'),
                        );
                      }
                      return false;
                    }

                    // 🎯 문서에서 이미지 URL 교체
                    final nodeIndex = document.getNodeIndexById(imageId);
                    if (nodeIndex != -1) {
                      final newNode = AppImageNode(
                        id: imageId,
                        imageUrl: newUrl,
                        altText: node.altText,
                        metadata: Map<String, dynamic>.from(node.metadata),
                      );

                      document.deleteNode(imageId);
                      document.insertNodeAt(nodeIndex, newNode);

                      // 🎯 노드 교체 완료 확인 (이미지 URL이 실제로 변경되었는지)
                      await Future.delayed(const Duration(milliseconds: 100));
                      final replacedNode = document.getNodeById(imageId);
                      if (replacedNode is ImageNode &&
                          replacedNode.imageUrl == newUrl) {
                        debugPrint(
                          '[NodeComponentService] ✅ 이미지 노드 교체 완료: imageId=$imageId, newUrl=$newUrl',
                        );
                      }

                      // 🎯 이미지 편집 후 히스토리 저장
                      editorService.saveHistoryNow();
                      return true;
                    }
                    return false;
                  } catch (e) {
                    debugPrint('[NodeComponentService] 변경사항 반영 중 오류: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ErrorHandler.showError(
                        context,
                        context.tr('image_edit_failed'),
                      );
                    }
                    return false;
                  }
                },
              ),
        ),
      );

      // 편집 취소 또는 타임아웃 시 editedBytes는 null
      if (editedBytes == null || !context.mounted) {
        return;
      }
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
