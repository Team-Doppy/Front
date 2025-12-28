import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/image/group_image_layout_selector.dart';
import 'package:doppy/image/media_picker_screen.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 에디터의 미디어(이미지/영상) 업로드를 담당하는 핸들러
class MediaUploadHandler {
  final BuildContext context;
  final EditorService editorService;
  final VoidCallback? onUploadComplete;

  MediaUploadHandler({
    required this.context,
    required this.editorService,
    this.onUploadComplete,
  });

  /// 미디어 타입 선택 다이얼로그 표시
  Future<String?> showMediaTypeSelector() async {
    return await showModalBottomSheet<String>(
      backgroundColor: Colors.transparent,
      context: context,
      builder:
          (context) => ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                height: 180,
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      onTap: () => Navigator.of(context).pop('image'),
                      title: Text(context.tr('upload_image')),
                    ),
                    ListTile(
                      onTap: () => Navigator.of(context).pop('short clip'),
                      title: Text(context.tr('upload_short_clip')),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  /// 이미지 업로드 처리
  Future<void> handleImageUpload() async {
    if (!context.mounted) return;

    final result = await Navigator.of(context).push<MediaPickerResult>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder:
            (context) => MediaPickerScreen(
              initialMediaType: MediaType.image,
              maxSelectionCount: 6,
              enableToggle: true,
              onMediaSelected: (file) {},
              onCancel: () {},
            ),
      ),
    );

    if (!context.mounted || result == null || result.files.isEmpty) return;

    final upload = context.read<UploadService>();

    // 🎯 영상으로 전환된 경우
    if (result.selectedMediaType == MediaType.video) {
      await _handleVideoFromImagePicker(result, upload);
      return;
    }

    // 🎯 이미지 업로드
    await _handleImageFiles(result, upload);
  }

  /// 영상 업로드 처리
  Future<void> handleVideoUpload() async {
    if (!context.mounted) return;

    final result = await Navigator.of(context).push<MediaPickerResult>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder:
            (context) => MediaPickerScreen(
              initialMediaType: MediaType.video,
              maxSelectionCount: 1,
              enableToggle: true,
              onMediaSelected: (file) {},
              onCancel: () {},
            ),
      ),
    );

    if (!context.mounted || result == null || result.files.isEmpty) return;

    final upload = context.read<UploadService>();

    // 🎯 이미지로 전환된 경우
    if (result.selectedMediaType == MediaType.image) {
      await _handleImageFromVideoPicker(result, upload);
      return;
    }

    // 🎯 영상 업로드
    await _uploadVideo(result.files.first, result.thumbnailPath, upload);
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
    final files = result.files;

    // 🎯 개별 이미지: 그룹 노드 생성 없이 일반 이미지로 업로드
    if (layout == GroupImageLayout.individual) {
      await _uploadImages(files, upload);
      return;
    }

    if (layout == GroupImageLayout.pageview) {
      // 🎯 페이지뷰: 모든 이미지를 하나의 노드로
      await _uploadPageViewGroup(files, layout, upload);
    } else {
      // 🎯 2열 또는 3열: 이미지를 그룹으로 나눔
      await _uploadGridLayout(files, layout, upload);
    }
  }

  /// 페이지뷰 그룹 업로드
  Future<void> _uploadPageViewGroup(
    List<File> files,
    GroupImageLayout layout,
    UploadService upload,
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
    final groupPlaceholderId = editorService.addGroupImageNode(
      localPaths: localPaths,
      layout: layout,
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

    await upload.uploadEditorImages(
      files: files,
      onCreateNode: (localPath) {
        debugPrint(
          '[MediaUploadHandler] 📝 onCreateNode: 기존 그룹 ID 재사용 $groupPlaceholderId',
        );
        // 이미 생성된 그룹 노드 ID 반환
        return groupPlaceholderId;
      },
      onUploadComplete: (nodeId, url) async {
        // 🎯 성능 최적화: Set 사용으로 O(1) 조회
        String? targetLocalPath;
        for (final path in localPaths) {
          if (!uploadedPathsSet.contains(path)) {
            targetLocalPath = path;
            break;
          }
        }

        if (targetLocalPath != null) {
          uploadedPathsSet.add(targetLocalPath);
          pendingUrls[targetLocalPath] = url;

          assert(() {
            debugPrint(
              '[MediaUploadHandler] 📦 PageView URL 배치 대기 (${pendingUrls.length}/${files.length}): $targetLocalPath → $url',
            );
            return true;
          }());

          // 🎯 모든 이미지가 완료되면 즉시 배치 처리
          // 1-6개라는 작은 수이므로 타이머 없이 즉시 처리
          if (pendingUrls.length == files.length) {
            await flushBatch();
          }
          // 일부만 완료된 경우는 다음 완료 시점에 처리 (타이머 불필요)
        } else {
          assert(() {
            debugPrint(
              '[MediaUploadHandler] ⚠️ PageView URL 교체 실패: targetLocalPath를 찾을 수 없음 (nodeId=$nodeId)',
            );
            return true;
          }());
        }
      },
      onDeleteNode: (nodeId) {
        debugPrint('[MediaUploadHandler] ❌ PageView 그룹 노드 삭제: $nodeId');
        final doc = editorService.document;
        if (doc.getNodeById(groupPlaceholderId) != null) {
          doc.deleteNode(groupPlaceholderId);
        }
      },
      isMounted: () => context.mounted,
      context: context,
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
        await _uploadImageRow(groupFiles, upload);
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
    final groupPlaceholderId = editorService.addGroupImageNode(
      localPaths: localPaths,
      layout: GroupImageLayout.grid2,
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

    await upload.uploadEditorImages(
      files: groupFiles,
      onCreateNode: (localPath) {
        debugPrint(
          '[MediaUploadHandler] 📝 onCreateNode: 기존 그룹 ID 재사용 $groupPlaceholderId',
        );
        // 이미 생성된 그룹 노드 ID 반환
        return groupPlaceholderId;
      },
      onUploadComplete: (nodeId, url) async {
        // 🎯 성능 최적화: Set 사용으로 O(1) 조회
        String? targetLocalPath;
        for (final path in localPaths) {
          if (!uploadedPathsSet.contains(path)) {
            targetLocalPath = path;
            break;
          }
        }

        if (targetLocalPath != null) {
          uploadedPathsSet.add(targetLocalPath);
          pendingUrls[targetLocalPath] = url;

          assert(() {
            debugPrint(
              '[MediaUploadHandler] 📦 ImageRow URL 배치 대기 (${pendingUrls.length}/${groupFiles.length}): $targetLocalPath → $url',
            );
            return true;
          }());

          // 🎯 모든 이미지가 완료되면 즉시 배치 처리
          // 1-6개라는 작은 수이므로 타이머 없이 즉시 처리
          if (pendingUrls.length == groupFiles.length) {
            await flushBatch();
          }
          // 일부만 완료된 경우는 다음 완료 시점에 처리 (타이머 불필요)
        } else {
          assert(() {
            debugPrint(
              '[MediaUploadHandler] ⚠️ ImageRow URL 교체 실패: targetLocalPath를 찾을 수 없음 (nodeId=$nodeId)',
            );
            return true;
          }());
        }
      },
      onDeleteNode: (nodeId) {
        debugPrint('[MediaUploadHandler] ❌ ImageRow 그룹 노드 삭제: $nodeId');
        final doc = editorService.document;
        if (doc.getNodeById(groupPlaceholderId) != null) {
          doc.deleteNode(groupPlaceholderId);
        }
      },
      isMounted: () => context.mounted,
      context: context,
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

    await upload.uploadEditorImages(
      files: files,
      onCreateNode: (localPath) {
        final nodeId = editorService.addImageNode(localPath);
        nodeIdToLocalPath[nodeId] = localPath; // 매핑 저장
        return nodeId;
      },
      onUploadComplete: (nodeId, url) async {
        // 🎯 매핑에서 정확한 localPath 가져오기
        final localPath = nodeIdToLocalPath[nodeId];
        if (localPath != null) {
          await editorService.replaceImageUrlByPath(
            nodeId: nodeId,
            localPath: localPath,
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
        // 🎯 일반 노드 삭제로 통합
        final doc = editorService.document;
        if (doc.getNodeById(nodeId) != null) {
          doc.deleteNode(nodeId);
        }
      },
      isMounted: () => context.mounted,
      context: context,
      showErrorDialog: _showErrorDialog,
    );
  }

  /// 영상 업로드
  Future<void> _uploadVideo(
    File file,
    String? thumbnailPath,
    UploadService upload,
  ) async {
    final editorId = 'editor_${editorService.hashCode}';

    await upload.uploadEditorVideo(
      file: file,
      editorId: editorId,
      initialThumbnailPath: thumbnailPath,
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
      onUploadComplete: (
        nodeId,
        url, {
        fallbackLocalPath,
        processedLocalPath,
      }) async {
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
        final doc = editorService.document;
        if (doc.getNodeById(nodeId) != null) {
          doc.deleteNode(nodeId);
        }
      },
      isMounted: () => context.mounted,
      context: context,
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
          title: context.tr('notification'),
          message: context.tr('video_single_selection_only'),
        );
      }
      return;
    }

    await _uploadVideo(result.files.first, result.thumbnailPath, upload);
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
          title: context.tr('notification'),
          message: context.tr('image_max_selection_exceeded'),
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
}
