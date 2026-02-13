import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../editor/component/app_image_node.dart';
import '../../editor/component/pageview_image_component.dart';
import '../../editor/component/row_image_component.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/utils/editor_localization.dart';
import '../../editor/utils/snackbar_util.dart';
import '../../media/screens/group_image_layout_screen.dart';
import '../../media/screens/image_editor_screen.dart';
import '../../media/utils/image_bytes_resolver.dart';
import '../../media/utils/image_size_util.dart';
import '../../upload/core/upload_types.dart';
import '../../upload/service/upload_service.dart';
import '../../upload/core/upload_task.dart';
import 'package:super_editor/super_editor.dart';

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

  /// 특정 노드의 스포일러 세션 캐시만 제거한다.
  ///
  /// - 문서 metadata(`meta['spoiler']`)가 진짜 소스가 되어야 하는 편집(undo/redo 포함)에서는
  ///   세션 캐시가 metadata를 덮어쓰면 안 된다.
  /// - 읽기 모드에서 "한 번만 스포일러 보기" 같은 UX를 위해 세션 캐시를 쓰되,
  ///   편집/undo/redo에서는 필요 시 이 캐시를 제거하여 동기화를 맞춘다.
  void clearSpoilerForNode(String nodeId, {bool notify = true}) {
    if (!_spoilerByNodeId.containsKey(nodeId)) return;
    _spoilerByNodeId.remove(nodeId);

    if (!notify) return;

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

  /// ✅ 토글 없이 "선택 상태를 강제로 설정"한다.
  ///
  /// - `selectNode()`는 같은 id를 다시 전달하면 선택 해제로 토글된다.
  /// - ReplaceNodeRequest 등으로 문서가 갱신될 때 selection을 유지하려면
  ///   토글이 아닌 "set" 동작이 필요하다.
  void setSelectedNode(String? nodeId, {bool notify = true}) {
    if (_selectedImageId == nodeId) return;
    _selectedImageId = nodeId;
    if (notify) notifyListeners();
  }

  /// 별칭(호환): 이미지 선택을 토글 없이 강제 설정
  void setSelectedImage(String? imageId, {bool notify = true}) =>
      setSelectedNode(imageId, notify: notify);

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

    try {
      FocusScope.of(context).unfocus();

      // ✅ 노드 타입별 이미지 소스(url/path/file://) 수집
      final sources = <String>[];
      if (node is ImageNode) {
        sources.add(node.imageUrl);
        debugPrint('[NodeComponentService] 📸 이미지 편집 진입 - 단일 이미지 노드');
        debugPrint('   - 노드 ID: $imageId');
        debugPrint('   - 이미지 URL: ${node.imageUrl}');
      } else if (node is ImageRowNode) {
        sources.addAll(node.imageUrls);
        debugPrint('[NodeComponentService] 📸 이미지 편집 진입 - 이미지 로우 노드');
        debugPrint('   - 노드 ID: $imageId');
        debugPrint('   - 이미지 개수: ${node.imageUrls.length}');
        debugPrint('   - 이미지 URLs: ${node.imageUrls}');
      } else if (node is PageViewImageNode) {
        sources.addAll(node.imageUrls);
        debugPrint('[NodeComponentService] 📸 이미지 편집 진입 - 페이지뷰 이미지 노드');
        debugPrint('   - 노드 ID: $imageId');
        debugPrint('   - 이미지 개수: ${node.imageUrls.length}');
        debugPrint('   - 이미지 URLs: ${node.imageUrls}');
      } else {
        if (context.mounted) {
          SnackbarUtil.showError(context, context.tr('image_edit_failed'));
        }
        return;
      }

      // 🎯 편집 화면을 먼저 열고, 이미지 로딩은 편집 화면 내부에서 처리
      // (로딩 다이얼로그 없이 부드러운 전환 애니메이션 제공)
      await Navigator.push<void>(
        context,
        PageRouteBuilder(
          fullscreenDialog: true,
          barrierColor: Theme.of(context).colorScheme.background,
          opaque: false,
          barrierDismissible: true,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // 🎯 fade + scale 애니메이션으로 부드럽게 전환
            final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            final scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            return FadeTransition(
              opacity: fadeAnimation,
              child: ScaleTransition(scale: scaleAnimation, child: child),
            );
          },
          pageBuilder: (editorContext, _, __) {
            return _DelayedImageLoader(
              future: ImageBytesResolver.resolveMany(
                sources,
                timeoutPerItem: const Duration(seconds: 10),
              ),
              onBack: () {
                Navigator.of(editorContext).pop();
              },
              imageId: imageId,
              node: node,
              parentContext: context,
              editorService: editorService,
              document: document,
              onDone:
                  (editorContext, result, originalImages) async {
                        await _applyEditedImagesToNode(
                          context: context,
                          editorContext: editorContext,
                          imageId: imageId,
                          node: node,
                          editorService: editorService,
                          document: document,
                          result: result,
                          originalImages: originalImages,
                        );
                      }
                      as Future<void> Function(
                        BuildContext,
                        dynamic,
                        List<Uint8List>,
                      )?,
            );
          },
        ),
      );
    } catch (e) {
      debugPrint('[NodeComponentService] 이미지 편집 중 오류: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        SnackbarUtil.showError(context, context.tr('image_edit_failed'));
      }
    } finally {
      _isEditingImage = false;
    }
  }
}

/// 🎯 1초 이상 걸릴 때만 로딩 로고를 표시하는 이미지 로더
class _DelayedImageLoader extends StatefulWidget {
  final Future<List<Uint8List>> future;
  final VoidCallback onBack;
  final String imageId;
  final DocumentNode node;
  final BuildContext parentContext;
  final EditorService editorService;
  final MutableDocument document;
  final Future<void> Function(
    BuildContext editorContext,
    dynamic result,
    List<Uint8List> originalImages,
  )?
  onDone;

  const _DelayedImageLoader({
    required this.future,
    required this.onBack,
    required this.imageId,
    required this.node,
    required this.parentContext,
    required this.editorService,
    required this.document,
    required this.onDone,
  });

  @override
  State<_DelayedImageLoader> createState() => _DelayedImageLoaderState();
}

class _DelayedImageLoaderState extends State<_DelayedImageLoader> {
  bool _showLoading = false;
  Timer? _loadingTimer;

  @override
  void initState() {
    super.initState();
    // 🎯 1초 후에 로딩 로고 표시
    _loadingTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showLoading = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Uint8List>>(
      future: widget.future,
      builder: (context, snapshot) {
        // 🎯 로딩 완료되면 타이머 취소하고 로딩 숨김
        if (snapshot.connectionState != ConnectionState.waiting) {
          _loadingTimer?.cancel();
          if (_showLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _showLoading = false;
                });
              }
            });
          }
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          // 🎯 1초 이상 걸릴 때만 로딩 로고 표시
          if (!_showLoading) {
            return Scaffold(
              backgroundColor: Theme.of(context).colorScheme.background,
              body: const SizedBox.shrink(),
            );
          }
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          // 🎯 에러 발생 시 편집 화면 닫고 에러 표시
          final error = snapshot.error;
          if (error != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Navigator.pop(context);
                SnackbarUtil.showError(
                  widget.parentContext,
                  widget.parentContext.tr('image_load_failed'),
                );
              }
            });
            return Scaffold(
              backgroundColor: Theme.of(context).colorScheme.background,
              body: const Center(child: SizedBox.shrink()),
            );
          }
          final imageBytesList = snapshot.data!;
          return imageBytesList.length <= 1
              ? SimpleImageEditorScreen(
                  imageBytes: imageBytesList.first,
                  isExistingNodeEdit: true,
                  enableLayoutSelectionForMultiImage: false,
                  onDone: widget.onDone != null
                      ? (editorContext, result) async {
                          await widget.onDone!(
                            editorContext,
                            result,
                            imageBytesList,
                          );
                        }
                      : null,
                )
              : SimpleImageEditorScreen(
                  imageBytesList: imageBytesList,
                  isExistingNodeEdit: true,
                  enableLayoutSelectionForMultiImage: false,
                  onDone: widget.onDone != null
                      ? (editorContext, result) async {
                          await widget.onDone!(
                            editorContext,
                            result,
                            imageBytesList,
                          );
                        }
                      : null,
                );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }
}

extension NodeComponentServiceExtension on NodeComponentService {
  Future<void> _applyEditedImagesToNode({
    required BuildContext context,
    required BuildContext editorContext,
    required String imageId,
    required DocumentNode node,
    required EditorService editorService,
    required MutableDocument document,
    required dynamic result,
    required List<Uint8List> originalImages,
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

    // ✅ 기존 노드 편집: 변경이 없으면 업로드/교체 없이 바로 닫기
    // - 에디터는 "변화 없음"이면 원본 bytes를 그대로 반환할 수 있다.
    // - 이 경우 서버 업로드를 하면 불필요한 네트워크/노드 교체가 발생한다.
    final isUnchanged =
        editedImages.length == originalImages.length &&
        List.generate(
          editedImages.length,
          (i) => i,
        ).every((i) => listEquals(editedImages[i], originalImages[i]));
    if (isUnchanged) {
      return;
    }

    // ✅ (업로드 전에) 사이즈 미리 측정
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

    // ✅ 로컬/네트워크 모드 공통: 임시 파일 생성
    final tempDir = await getTemporaryDirectory();
    final tempFiles = <File>[];
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < editedImages.length; i++) {
      final f = File('${tempDir.path}/edited_${ts}_$i.jpg');
      await f.writeAsBytes(editedImages[i]);
      tempFiles.add(f);
    }

    // ✅ 네트워크 모드: 업로드 진행 → URL 수집
    // ✅ 로컬 모드: 업로드 없이 로컬 경로를 그대로 사용 (payload에 로컬 경로 포함)
    List<String> urls = [];
    if (editorService.networkMode) {
      final upload = context.read<UploadService>();

      // ✅ 배치 업로드 (UploadService의 enqueueFiles 사용)
      List<UploadTask> tasks = [];
      try {
        tasks = await upload.enqueueFiles(
          tempFiles,
          kind: UploadKind.image,
          refId: imageId,
          timeout: const Duration(seconds: 45),
        );
      } catch (e) {
        debugPrint('[NodeComponentService] 이미지 업로드 실패: $e');
        upload.cancelUploadForRef(imageId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          SnackbarUtil.showError(context, context.tr('editor_upload_failed'));
        }
        return;
      } finally {
        // 네트워크 모드에서는 업로드 후 임시 파일 정리
        for (final f in tempFiles) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }

      // ✅ 업로드 결과 확인 (enqueueFiles는 성공한 태스크만 반환)
      if (tasks.isEmpty || tasks.length != tempFiles.length) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          SnackbarUtil.showError(context, context.tr('editor_upload_failed'));
        }
        return;
      }

      // ✅ URL 추출 및 검증
      urls = tasks
          .map((t) => t.url)
          .whereType<String>()
          .where((u) => u.isNotEmpty)
          .toList();
      if (urls.length != editedImages.length) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          SnackbarUtil.showError(context, context.tr('editor_load_failed'));
        }
        return;
      }
    } else {
      // 로컬 모드에서는 임시 파일을 유지해야 경로가 유효하다.
      urls = tempFiles.map((f) => f.path).toList();
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

    if (node is ImageNode) {
      final newNode = AppImageNode(
        id: imageId,
        imageUrl: urls.first,
        altText: altText,
        metadata: Map<String, dynamic>.from(meta),
      );
      editorService.document.replaceNodeById(imageId, newNode);
      editorService.saveHistoryNow();
      return;
    }

    if (node is ImageRowNode) {
      final newNode = ImageRowNode(
        id: imageId,
        imageUrls: urls,
        spacing: rowSpacing,
        metadata: Map<String, dynamic>.from(meta),
      );
      editorService.document.replaceNodeById(imageId, newNode);
      editorService.saveHistoryNow();
      return;
    }

    if (node is PageViewImageNode) {
      final newNode = PageViewImageNode(
        id: imageId,
        imageUrls: urls,
        metadata: Map<String, dynamic>.from(meta),
      );
      editorService.document.replaceNodeById(imageId, newNode);
      editorService.saveHistoryNow();
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
}
