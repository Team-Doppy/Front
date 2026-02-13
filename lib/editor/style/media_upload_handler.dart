import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../component/clip_component.dart';
import '../service/editor_service.dart';
import '../utils/dialog_util.dart';
import '../utils/editor_localization.dart';
import '../../media/editor/video_specs.dart';
import '../../media/screens/group_image_layout_screen.dart';
import '../../media/screens/media_picker_screen.dart';
import '../../upload/core/upload_types.dart';
import '../../upload/service/upload_service.dart';
import '../../upload/utils/video_upload_utils.dart';

/// 에디터의 미디어(이미지/영상) 업로드를 담당하는 핸들러
class MediaUploadHandler {
  final BuildContext context;
  final EditorService editorService;
  final VoidCallback? onUploadComplete;
  // ✅ 미디어 추가 시 빈 상태 오버레이를 숨기기 위한 콜백
  final VoidCallback? onMediaAdded;

  MediaUploadHandler({
    required this.context,
    required this.editorService,
    this.onUploadComplete,
    this.onMediaAdded,
  });

  /// 이미지 업로드 처리
  Future<void> handleImageUpload() async {
    if (!context.mounted) return;

    // 🎯 미디어피커로 들어가기 전에 모든 비디오 재생 중지
    try {
      await pauseAllVideoPlayers(seekToStart: true, mute: true);
    } catch (e) {
      debugPrint('[MediaUploadHandler] 비디오 정리 실패: $e');
    }

    final result = await Navigator.of(context).push<MediaPickerResult>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MediaPickerScreen(
              initialMediaType: MediaType.image,
              maxSelectionCount: 6,
              enableToggle: true,
              onMediaSelected: (file) {},
              onCancel: () {},
              popImmediately: true,
            ),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        fullscreenDialog: true,
      ),
    );
    if (result == null || !context.mounted) return;
    if (editorService.networkMode) {
      final upload = context.read<UploadService>();
      if (result.selectedMediaType == MediaType.video) {
        await _handleVideoFromImagePicker(result, upload);
      } else {
        await _handleImageFiles(result, upload);
      }
    } else {
      if (result.selectedMediaType == MediaType.video) {
        await _insertLocalVideo(result);
      } else {
        await _insertLocalImages(result);
      }
    }
    onMediaAdded?.call();
    onUploadComplete?.call();
  }

  /// 영상 업로드 처리
  Future<void> handleVideoUpload() async {
    if (!context.mounted) return;

    // 🎯 미디어피커로 들어가기 전에 모든 비디오 재생 중지
    try {
      await pauseAllVideoPlayers(seekToStart: true, mute: true);
    } catch (e) {
      debugPrint('[MediaUploadHandler] 비디오 정리 실패: $e');
    }

    final result = await Navigator.of(context).push<MediaPickerResult>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MediaPickerScreen(
              initialMediaType: MediaType.video,
              maxSelectionCount: 1,
              enableToggle: true,
              onMediaSelected: (file) {},
              onCancel: () {},
              popImmediately: true,
            ),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        fullscreenDialog: true,
      ),
    );
    if (result == null || !context.mounted) return;
    if (editorService.networkMode) {
      final upload = context.read<UploadService>();
      if (result.selectedMediaType == MediaType.image) {
        await _handleImageFromVideoPicker(result, upload);
      } else {
        await _uploadVideo(
          result.files.first,
          result.thumbnailPath,
          upload,
          trimSpec: result.trimSpec,
          editSpec: result.editSpec,
        );
      }
    } else {
      if (result.selectedMediaType == MediaType.image) {
        await _insertLocalImages(result);
      } else {
        await _insertLocalVideo(result);
      }
    }
    onMediaAdded?.call();
    onUploadComplete?.call();
  }

  /// 이미지 파일 처리 (그룹 레이아웃 포함)
  Future<void> _handleImageFiles(
    MediaPickerResult result,
    UploadService upload,
  ) async {
    // 🎯 그룹 레이아웃이 선택된 경우
    if (result.groupLayout != null) {
      await _handleGroupImageLayout(result, upload);
    } else {
      // 일반 이미지 업로드
      await _uploadImages(result.files, upload);
    }
  }

  /// 그룹 이미지 레이아웃 처리
  Future<void> _handleGroupImageLayout(
    MediaPickerResult result,
    UploadService upload,
  ) async {
    final layout = result.groupLayout!;
    // ✅ 안전장치: 동일 경로가 중복으로 들어오면(플러그인/편집 플로우/임시파일 재사용 등)
    // row/grid에서 같은 이미지가 2번씩 보이거나 업로드 매핑이 꼬일 수 있어 dedupe 한다.
    final files = <File>[];
    final seen = <String>{};
    for (final f in result.files) {
      final p = f.path;
      if (p.isEmpty) continue;
      if (seen.add(p)) files.add(f);
    }
    final preDimensions = result.imageDimensions;

    // 🎯 개별 이미지: 그룹 노드 생성 없이 일반 이미지로 업로드
    if (layout == GroupImageLayout.individual) {
      await _uploadImages(files, upload);
      return;
    }

    if (layout == GroupImageLayout.pageview) {
      // 🎯 페이지뷰: 모든 이미지를 하나의 노드로
      await _uploadPageViewGroup(files, layout, upload, preDimensions);
    } else {
      // 🎯 2열 또는 3열: 이미지를 그룹으로 나눔
      await _uploadGridLayout(files, layout, upload, preDimensions);
    }
  }

  /// 페이지뷰 그룹 업로드
  Future<void> _uploadPageViewGroup(
    List<File> files,
    GroupImageLayout layout,
    UploadService upload,
    Map<String, dynamic>? preDimensions,
  ) async {
    final localPaths = files.map((f) => f.path).toList();
    // 🎯 성능 최적화: Set 사용으로 O(1) 조회
    final uploadedPathsSet = <String>{};
    final Map<String, String> pendingUrls = {}; // 배치 업데이트용

    debugPrint(
      '[MediaUploadHandler] 🎯 PageView 그룹 업로드 시작: ${files.length}개, localPaths=${localPaths.length}개',
    );

    // 🎯 업로드 시작 전에 그룹 플레이스홀더 먼저 생성 (확실한 그룹 노드 생성 보장)
    debugPrint(
      '[MediaUploadHandler] 🔨 PageView 그룹 노드 생성 시도: layout=$layout, paths=${localPaths.length}개',
    );
    final meta = (preDimensions != null && preDimensions.isNotEmpty)
        ? <String, dynamic>{'imageDimensions': preDimensions}
        : null;
    final groupPlaceholderId = editorService.addGroupImageNode(
      localPaths: localPaths,
      layout: layout,
      metadata: meta,
    );
    debugPrint(
      '[MediaUploadHandler] ✅ PageView 그룹 노드 생성 완료: $groupPlaceholderId (layout=$layout)',
    );

    // 🎯 배치 업데이트 함수
    Future<void> flushBatch() async {
      if (pendingUrls.isEmpty) return;

      final urlsToUpdate = Map<String, String>.from(pendingUrls);
      pendingUrls.clear();

      await editorService.replaceGroupImageUrlsByPath(
        groupNodeId: groupPlaceholderId,
        urlMap: urlsToUpdate,
      );
    }

    await _uploadEditorImages(
      upload: upload,
      files: files,
      onCreateNode: (localPath) {
        debugPrint(
          '[MediaUploadHandler] 📝 onCreateNode: 기존 그룹 ID 재사용 $groupPlaceholderId',
        );
        // 이미 생성된 그룹 노드 ID 반환
        return groupPlaceholderId;
      },
      onUploadComplete: (nodeId, localPath, url) async {
        // ✅ 순서 보장: 업로드 완료된 "그 파일의 localPath"에 정확히 매핑한다.
        if (!localPaths.contains(localPath)) {
          assert(() {
            debugPrint(
              '[MediaUploadHandler] ⚠️ PageView URL 매핑 스킵: localPath가 그룹에 없음 (nodeId=$nodeId, localPath=$localPath)',
            );
            return true;
          }());
          return;
        }

        uploadedPathsSet.add(localPath);
        pendingUrls[localPath] = url;

        assert(() {
          debugPrint(
            '[MediaUploadHandler] 📦 PageView URL 배치 대기 (${pendingUrls.length}/${files.length}): $localPath → $url',
          );
          return true;
        }());

        // 1-6개라는 작은 수이므로, 모두 모이면 즉시 배치 처리
        if (pendingUrls.length == files.length) {
          await flushBatch();
        }
      },
      onDeleteNode: (nodeId) {
        debugPrint('[MediaUploadHandler] ❌ PageView 그룹 노드 삭제: $nodeId');
        editorService.purgeNodeIdsFromHistory({groupPlaceholderId});
        editorService.deleteNode(groupPlaceholderId);
      },
      isMounted: () => context.mounted,
      showErrorDialog: _showErrorDialog,
    );

    // 🎯 남은 배치 처리 (모든 업로드 완료 후)
    await flushBatch();

    debugPrint(
      '[MediaUploadHandler] ✅ PageView 그룹 업로드 완료: groupId=$groupPlaceholderId',
    );
  }

  /// 그리드 레이아웃 업로드
  Future<void> _uploadGridLayout(
    List<File> files,
    GroupImageLayout layout,
    UploadService upload,
    Map<String, dynamic>? preDimensions,
  ) async {
    final imagesPerRow = layout == GroupImageLayout.grid2 ? 2 : 3;
    int groupIndex = 0;

    debugPrint(
      '[MediaUploadHandler] 🎯 Grid 레이아웃 업로드 시작: 총 ${files.length}개, $imagesPerRow개씩 그룹화',
    );

    for (int i = 0; i < files.length; i += imagesPerRow) {
      final endIndex = (i + imagesPerRow).clamp(0, files.length);
      final groupFiles = files.sublist(i, endIndex);
      groupIndex++;

      debugPrint(
        '[MediaUploadHandler] 📦 그룹 #$groupIndex: ${groupFiles.length}개 이미지 (index $i-${endIndex - 1})',
      );

      if (groupFiles.length >= 2) {
        // 2개 이상이면 ImageRowNode 생성
        debugPrint('[MediaUploadHandler] ✅ 그룹 #$groupIndex를 ImageRow로 업로드');
        await _uploadImageRow(groupFiles, upload, preDimensions);
      } else {
        // 1개만 남으면 단일 이미지로
        debugPrint(
          '[MediaUploadHandler] ⚠️ 그룹 #$groupIndex는 1개뿐이므로 단일 이미지로 업로드',
        );
        await _uploadImages(groupFiles, upload);
      }
    }

    debugPrint('[MediaUploadHandler] ✅ Grid 레이아웃 업로드 완료: 총 $groupIndex개 그룹 처리');
  }

  /// ImageRow 그룹 업로드
  Future<void> _uploadImageRow(
    List<File> groupFiles,
    UploadService upload,
    Map<String, dynamic>? preDimensions,
  ) async {
    final localPaths = groupFiles.map((f) => f.path).toList();
    // 🎯 성능 최적화: Set 사용으로 O(1) 조회
    final uploadedPathsSet = <String>{};
    final Map<String, String> pendingUrls = {}; // 배치 업데이트용

    debugPrint(
      '[MediaUploadHandler] 🎯 ImageRow 그룹 업로드 시작: ${groupFiles.length}개, localPaths=${localPaths.length}개',
    );

    // 🎯 업로드 시작 전에 그룹 플레이스홀더 먼저 생성 (확실한 그룹 노드 생성 보장)
    debugPrint(
      '[MediaUploadHandler] 🔨 ImageRow 그룹 노드 생성 시도: layout=grid2, paths=${localPaths.length}개',
    );
    Map<String, dynamic>? filtered;
    if (preDimensions != null && preDimensions.isNotEmpty) {
      final out = <String, dynamic>{};
      for (final p in localPaths) {
        final v1 = preDimensions[p];
        if (v1 != null) out[p] = v1;
        final v2 = preDimensions['file://$p'];
        if (v2 != null) out['file://$p'] = v2;
      }
      filtered = out.isNotEmpty ? out : null;
    }
    final meta = filtered != null
        ? <String, dynamic>{'imageDimensions': filtered}
        : null;
    final groupPlaceholderId = editorService.addGroupImageNode(
      localPaths: localPaths,
      layout: GroupImageLayout.grid2,
      metadata: meta,
    );
    debugPrint(
      '[MediaUploadHandler] ✅ ImageRow 그룹 노드 생성 완료: $groupPlaceholderId (layout=grid2)',
    );

    // 🎯 배치 업데이트 함수
    Future<void> flushBatch() async {
      if (pendingUrls.isEmpty) return;

      final urlsToUpdate = Map<String, String>.from(pendingUrls);
      pendingUrls.clear();

      await editorService.replaceGroupImageUrlsByPath(
        groupNodeId: groupPlaceholderId,
        urlMap: urlsToUpdate,
      );
    }

    await _uploadEditorImages(
      upload: upload,
      files: groupFiles,
      onCreateNode: (localPath) {
        debugPrint(
          '[MediaUploadHandler] 📝 onCreateNode: 기존 그룹 ID 재사용 $groupPlaceholderId',
        );
        // 이미 생성된 그룹 노드 ID 반환
        return groupPlaceholderId;
      },
      onUploadComplete: (nodeId, localPath, url) async {
        // ✅ 순서 보장: 업로드 완료된 "그 파일의 localPath"에 정확히 매핑한다.
        if (!localPaths.contains(localPath)) {
          assert(() {
            debugPrint(
              '[MediaUploadHandler] ⚠️ ImageRow URL 매핑 스킵: localPath가 그룹에 없음 (nodeId=$nodeId, localPath=$localPath)',
            );
            return true;
          }());
          return;
        }

        uploadedPathsSet.add(localPath);
        pendingUrls[localPath] = url;

        assert(() {
          debugPrint(
            '[MediaUploadHandler] 📦 ImageRow URL 배치 대기 (${pendingUrls.length}/${groupFiles.length}): $localPath → $url',
          );
          return true;
        }());

        if (pendingUrls.length == groupFiles.length) {
          await flushBatch();
        }
      },
      onDeleteNode: (nodeId) {
        debugPrint('[MediaUploadHandler] ❌ ImageRow 그룹 노드 삭제: $nodeId');
        editorService.purgeNodeIdsFromHistory({groupPlaceholderId});
        editorService.deleteNode(groupPlaceholderId);
      },
      isMounted: () => context.mounted,
      showErrorDialog: _showErrorDialog,
    );

    // 🎯 남은 배치 처리 (모든 업로드 완료 후)
    await flushBatch();

    debugPrint(
      '[MediaUploadHandler] ✅ ImageRow 그룹 업로드 완료: groupId=$groupPlaceholderId',
    );
  }

  /// 일반 이미지 업로드
  Future<void> _uploadImages(List<File> files, UploadService upload) async {
    // 🎯 nodeId와 localPath 매핑 (여러 파일 업로드 시 각각의 localPath 추적)
    final nodeIdToLocalPath = <String, String>{};

    await _uploadEditorImages(
      upload: upload,
      files: files,
      onCreateNode: (localPath) {
        final nodeId = editorService.addImageNode(localPath);
        nodeIdToLocalPath[nodeId] = localPath; // 매핑 저장
        return nodeId;
      },
      onUploadComplete: (nodeId, localPath, url) async {
        // 🎯 매핑에서 정확한 localPath 가져오기
        final mappedLocalPath = nodeIdToLocalPath[nodeId];
        if (mappedLocalPath != null) {
          await editorService.replaceImageUrlByPath(
            nodeId: nodeId,
            localPath: mappedLocalPath,
            url: url,
          );
        } else {
          assert(() {
            debugPrint(
              '[MediaUploadHandler] ⚠️ 일반 이미지 URL 교체 실패: nodeId=$nodeId에 대한 localPath를 찾을 수 없음',
            );
            return true;
          }());
        }
      },
      onDeleteNode: (nodeId) {
        editorService.purgeNodeIdsFromHistory({nodeId});
        editorService.deleteNode(nodeId);
      },
      isMounted: () => context.mounted,
      showErrorDialog: _showErrorDialog,
    );
  }

  /// 영상 업로드
  Future<void> _uploadVideo(
    File file,
    String? thumbnailPath,
    UploadService upload, {
    VideoTrimSpec? trimSpec,
    VideoEditSpec? editSpec,
  }) async {
    await _uploadEditorVideo(
      upload: upload,
      file: file,
      initialThumbnailPath: thumbnailPath,
      trimSpec: trimSpec,
      editSpec: editSpec,
      onCreateNode: (localPath, fileName, {thumbnailPath, aspectRatio}) {
        return editorService.addVideoClipNode(
          localPath: localPath,
          label: fileName,
          thumbnailPath: thumbnailPath,
          aspectRatio: aspectRatio,
        );
      },
      onUpdateThumbnail: (nodeId, thumbnailPath) {
        editorService.updateVideoThumbnail(nodeId, thumbnailPath);
      },
      onCompressionComplete: (nodeId, processedLocalPath) {
        // ✅ 압축 완료 즉시 노드 localPath를 교체하여 검정 화면 방지
        editorService.updateVideoLocalPath(nodeId, processedLocalPath);
      },
      onUploadComplete:
          (nodeId, url, {fallbackLocalPath, processedLocalPath}) async {
            await editorService.replaceVideoUrlByPath(
              nodeId: nodeId,
              url: url,
              fallbackLocalPath: fallbackLocalPath,
              processedLocalPath: processedLocalPath, // 🎯 ffmpeg 처리된 경로 전달
            );
            onUploadComplete?.call();
            // 🎯 키보드 유지 (이미지와 동일하게)
          },
      onDeleteNode: (nodeId) {
        editorService.purgeNodeIdsFromHistory({nodeId});
        editorService.deleteNode(nodeId);
      },
      isMounted: () => context.mounted,
      showErrorDialog: _showErrorDialog,
    );
  }

  /// 이미지 피커에서 영상으로 전환된 경우
  Future<void> _handleVideoFromImagePicker(
    MediaPickerResult result,
    UploadService upload,
  ) async {
    if (result.files.length > 1) {
      if (context.mounted) {
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('editor_notification'),
          message: context.tr('editor_selection_limit'),
        );
      }
      return;
    }

    // 🎯 이미지 피커에서 영상으로 전환된 경우에도 trim/edit spec을 반드시 전달
    await _uploadVideo(
      result.files.first,
      result.thumbnailPath,
      upload,
      trimSpec: result.trimSpec,
      editSpec: result.editSpec,
    );
  }

  /// 영상 피커에서 이미지로 전환된 경우
  Future<void> _handleImageFromVideoPicker(
    MediaPickerResult result,
    UploadService upload,
  ) async {
    if (result.files.length > 5) {
      if (context.mounted) {
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('editor_notification'),
          message: context.tr('editor_selection_limit'),
        );
      }
      return;
    }

    await _uploadImages(result.files, upload);
  }

  /// 에러 다이얼로그 표시
  Future<void> _showErrorDialog(String title, String message) async {
    await DialogUtils.showInfoDialog(context, title: title, message: message);
  }

  /// 이미지 업로드 헬퍼 (enqueueFiles 사용)
  Future<void> _uploadEditorImages({
    required UploadService upload,
    required List<File> files,
    required String Function(String localPath) onCreateNode,
    required Future<void> Function(String nodeId, String localPath, String url)
    onUploadComplete,
    required void Function(String nodeId) onDeleteNode,
    required bool Function() isMounted,
    required Future<void> Function(String title, String message)
    showErrorDialog,
  }) async {
    if (files.isEmpty) return;

    final nodeIdToLocalPath = <String, String>{};
    final fileToNodeId = <File, String>{};

    try {
      // 각 파일에 대해 노드 생성 및 매핑
      for (final file in files) {
        final localPath = file.path;
        final nodeId = onCreateNode(localPath);
        nodeIdToLocalPath[nodeId] = localPath;
        fileToNodeId[file] = nodeId;
      }

      // 배치 업로드 (각 파일마다 개별 refId 사용)
      final successfulTasks = await upload.enqueueFiles(
        files,
        kind: UploadKind.image,
        refIdMapper: (file) => fileToNodeId[file],
        timeout: const Duration(seconds: 60),
      );

      // 성공한 업로드 처리
      // 🎯 그룹 이미지: nodeIdToLocalPath는 동일 nodeId로 덮어써지므로, task.file.path로 정확한 localPath 사용
      for (final task in successfulTasks) {
        final nodeId = task.refId;
        if (nodeId != null && task.url != null) {
          final localPath =
              task.file?.path ?? nodeIdToLocalPath[nodeId];
          if (localPath != null && localPath.isNotEmpty) {
            await onUploadComplete(nodeId, localPath, task.url!);
          }
        }
      }

      // 실패한 업로드 처리 (모든 태스크 확인)
      // 🎯 그룹 이미지: 동일 nodeId에 여러 파일이 매핑됨 → 하나라도 실패하면 전체 삭제
      final allNodeIds = fileToNodeId.values.toSet();
      final failedNodeIds = <String>{};
      for (final nodeId in allNodeIds) {
        final expectedCount =
            fileToNodeId.values.where((id) => id == nodeId).length;
        final successCount =
            successfulTasks.where((t) => t.refId == nodeId).length;
        if (successCount < expectedCount) {
          failedNodeIds.add(nodeId);
        }
      }

      // 실패한 노드 삭제 (그룹은 전체, 단일은 해당 노드만)
      for (final nodeId in failedNodeIds) {
        onDeleteNode(nodeId);
      }

      // 모든 업로드가 실패한 경우
      if (successfulTasks.isEmpty && files.isNotEmpty) {
        debugPrint(
          '[MediaUploadHandler] 모든 이미지 업로드 실패: files=${files.length}, '
          'successfulTasks=${successfulTasks.length}',
        );
        if (kDebugMode) {
          for (final nodeId in nodeIdToLocalPath.keys) {
            final task = upload.getTaskForRef(nodeId);
            if (task != null && task.error != null) {
              debugPrint(
                '[MediaUploadHandler] 실패 노드 refId=$nodeId: error=${task.error}',
              );
            }
          }
        }
        throw Exception(context.tr('editor_upload_failed'));
      }
    } on TimeoutException catch (e) {
      debugPrint('[MediaUploadHandler] 이미지 업로드 타임아웃: $e');
      if (isMounted()) {
        await showErrorDialog(
          context.tr('editor_error'),
          context.tr('editor_upload_failed'),
        );
      }
      // 실패한 노드 삭제
      for (final nodeId in nodeIdToLocalPath.keys) {
        onDeleteNode(nodeId);
      }
    } catch (e, stackTrace) {
      debugPrint('[MediaUploadHandler] 이미지 업로드 실패: $e');
      debugPrint('[MediaUploadHandler] stackTrace: $stackTrace');
      if (isMounted()) {
        await showErrorDialog(
          context.tr('editor_error'),
          context.tr('editor_upload_failed'),
        );
      }
      // 실패한 노드 삭제
      for (final nodeId in nodeIdToLocalPath.keys) {
        onDeleteNode(nodeId);
      }
    }
  }

  /// 로컬 모드: 이미지(단일/그룹) 노드를 로컬 경로로만 추가한다.
  Future<void> _insertLocalImages(MediaPickerResult result) async {
    // ✅ 안전장치: 동일 경로 dedupe
    final files = <File>[];
    final seen = <String>{};
    for (final f in result.files) {
      final p = f.path;
      if (p.isEmpty) continue;
      if (seen.add(p)) files.add(f);
    }
    if (files.isEmpty) return;

    final layout = result.groupLayout;
    final preDimensions = result.imageDimensions;
    final meta = (preDimensions != null && preDimensions.isNotEmpty)
        ? <String, dynamic>{'imageDimensions': preDimensions}
        : null;

    if (layout == null || layout == GroupImageLayout.individual) {
      for (final f in files) {
        editorService.addImageNode(f.path);
      }
      return;
    }

    if (layout == GroupImageLayout.pageview) {
      editorService.addGroupImageNode(
        localPaths: files.map((f) => f.path).toList(),
        layout: GroupImageLayout.pageview,
        metadata: meta,
      );
      return;
    }

    // grid2/grid3는 기존 UX와 동일하게 "한 행에 N장" 단위로 쪼개서 Row 노드를 만든다.
    final imagesPerRow = layout == GroupImageLayout.grid2 ? 2 : 3;
    for (int i = 0; i < files.length; i += imagesPerRow) {
      final end = (i + imagesPerRow).clamp(0, files.length);
      final groupFiles = files.sublist(i, end);
      if (groupFiles.length >= 2) {
        editorService.addGroupImageNode(
          localPaths: groupFiles.map((f) => f.path).toList(),
          layout: layout,
          metadata: meta,
        );
      } else {
        editorService.addImageNode(groupFiles.first.path);
      }
    }
  }

  /// 로컬 모드: 비디오 노드를 로컬 경로로만 추가한다.
  Future<void> _insertLocalVideo(MediaPickerResult result) async {
    if (result.files.isEmpty) return;
    if (result.files.length > 1) {
      if (context.mounted) {
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('editor_notification'),
          message: context.tr('editor_selection_limit'),
        );
      }
      return;
    }

    final file = result.files.first;
    if (file.path.isEmpty) return;

    editorService.addVideoClipNode(
      localPath: file.path,
      label: file.path.split('/').last,
      thumbnailPath: result.thumbnailPath,
    );
  }

  /// 비디오 업로드 헬퍼 (enqueueFile 사용)
  Future<void> _uploadEditorVideo({
    required UploadService upload,
    required File file,
    String? initialThumbnailPath,
    VideoTrimSpec? trimSpec,
    VideoEditSpec? editSpec,
    required String Function(
      String localPath,
      String fileName, {
      String? thumbnailPath,
      double? aspectRatio,
    })
    onCreateNode,
    required void Function(String nodeId, String thumbnailPath)
    onUpdateThumbnail,
    required void Function(String nodeId, String processedLocalPath)
    onCompressionComplete,
    required Future<void> Function(
      String nodeId,
      String url, {
      String? fallbackLocalPath,
      String? processedLocalPath,
    })
    onUploadComplete,
    required void Function(String nodeId) onDeleteNode,
    required bool Function() isMounted,
    required Future<void> Function(String title, String message)
    showErrorDialog,
  }) async {
    String? nodeId;
    String? processedLocalPath;
    String? fallbackLocalPath;

    try {
      // 파일 검증
      if (!VideoUploadUtils.validateExtension(file.path)) {
        if (isMounted()) {
          await showErrorDialog(
            context.tr('editor_error'),
            context.tr('editor_unsupported_file_format'),
          );
        }
        return;
      }

      if (!await VideoUploadUtils.validateFileSize(file.path)) {
        if (isMounted()) {
          await showErrorDialog(
            context.tr('editor_error'),
            context.tr(
              'editor_file_too_large',
              placeholders: {
                'maxSize': VideoUploadUtils.maxVideoSizeMB.toString(),
              },
            ),
          );
        }
        return;
      }

      // 노드 생성
      final fileName = file.path.split('/').last;
      nodeId = onCreateNode(
        file.path,
        fileName,
        thumbnailPath: initialThumbnailPath,
      );

      // 비디오 압축 (trim/edit spec이 있는 경우)
      if (trimSpec != null || editSpec != null) {
        // TODO: FFmpeg 압축 구현 필요 (VideoUploadUtils.compressVideo 사용)
        // 현재는 원본 파일 사용
        processedLocalPath = file.path;
        fallbackLocalPath = file.path;
      } else {
        processedLocalPath = file.path;
        fallbackLocalPath = file.path;
      }

      // 압축 완료 콜백
      onCompressionComplete(nodeId, processedLocalPath);

      // 업로드
      final task = upload.enqueueFile(
        File(processedLocalPath),
        kind: UploadKind.video,
        refId: nodeId,
      );

      // 업로드 완료 대기 (UploadService의 waitForTask 사용)
      final success = await upload.waitForTask(
        task,
        timeout: const Duration(seconds: 60),
      );

      if (!success) {
        onDeleteNode(nodeId);
        if (isMounted()) {
          final errorMessage = VideoUploadUtils.buildErrorMessage(task.error);
          await showErrorDialog(context.tr('editor_error'), errorMessage);
        }
        return;
      }

      if (task.url != null) {
        await onUploadComplete(
          nodeId,
          task.url!,
          fallbackLocalPath: fallbackLocalPath,
          processedLocalPath: processedLocalPath,
        );
      }
    } catch (e) {
      debugPrint('[MediaUploadHandler] 비디오 업로드 실패: $e');
      if (nodeId != null) {
        onDeleteNode(nodeId);
      }
      if (isMounted()) {
        final errorMessage = VideoUploadUtils.buildErrorMessage(e);
        await showErrorDialog(context.tr('editor_error'), errorMessage);
      }
    }
  }
}
