import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/service/special_node_info.dart';
import 'package:doppy/image/group_image_layout_selector.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 🎯 이미지 관련 작업 전담 서비스
class ImageService {
  final Editor editor;
  final MutableDocument document;
  final VoidCallback notifyListeners;
  final Function(bool) setHistoryExecuting;
  final Function(bool, VoidCallback?) saveHistory;

  ImageService({
    required this.editor,
    required this.document,
    required this.notifyListeners,
    required this.setHistoryExecuting,
    required this.saveHistory,
  });

  /// 이미지 추가: 현재 커서 다음 줄에 로컬 경로 기반 이미지 노드 삽입
  String addImageNode(
    String thumbnailImageUrl,
    Function(DocumentNode) insertComponentNodeAtNextLine,
  ) {
    try {
      debugPrint('이미지 추가: $thumbnailImageUrl');

      final id = 'image_${DateTime.now().millisecondsSinceEpoch}';
      final imageNode = AppImageNode(
        id: id,
        imageUrl: thumbnailImageUrl,
        altText: '',
      );
      insertComponentNodeAtNextLine(imageNode);
      return id;
    } catch (e) {
      debugPrint('이미지 추가 중 오류: $e');
      rethrow;
    }
  }

  /// 그룹 이미지 노드 추가 (로컬 경로 기반)
  String addGroupImageNode({
    required List<String> localPaths,
    required GroupImageLayout layout,
    required Function(DocumentNode) insertComponentNodeAtNextLine,
  }) {
    final id = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final node =
        layout == GroupImageLayout.pageview
            ? PageViewImageNode(id: id, imageUrls: localPaths)
            : ImageRowNode(id: id, imageUrls: localPaths);
    insertComponentNodeAtNextLine(node);
    return id;
  }

  /// 단일 이미지의 URL을 메타데이터에 저장
  Future<void> replaceImageUrlByPath({
    required String nodeId,
    required String localPath,
    required String url,
    required Function(bool) setHistoryExecuting,
    required VoidCallback notifyListeners,
  }) async {
    setHistoryExecuting(true);
    try {
      final node = document.getNodeById(nodeId);
      if (node is ImageNode) {
        final meta = node.metadata;
        final uploadedUrls = Map<String, String>.from(
          (meta['uploadedUrls'] as Map<String, dynamic>?)
                  ?.cast<String, String>() ??
              {},
        );
        uploadedUrls[localPath] = url;

        final updated = AppImageNode(
          id: nodeId,
          imageUrl: localPath, // 로컬 경로 유지
          altText: node.altText,
          metadata: {...meta, 'uploadedUrls': uploadedUrls},
        );
        document.replaceNodeById(nodeId, updated);
        notifyListeners();
      }
    } finally {
      setHistoryExecuting(false);
    }
  }

  /// 그룹 이미지의 특정 로컬 경로를 URL로 교체
  Future<void> replaceGroupImageUrlByPath({
    required String groupNodeId,
    required String localPath,
    required String url,
    required Function(bool) setHistoryExecuting,
    required VoidCallback notifyListeners,
  }) async {
    setHistoryExecuting(true);
    try {
      final node = document.getNodeById(groupNodeId);

      if (node is ImageRowNode) {
        final meta = node.metadata;
        final uploadedUrls = Map<String, String>.from(
          (meta['uploadedUrls'] as Map<String, dynamic>?)
                  ?.cast<String, String>() ??
              {},
        );

        uploadedUrls[localPath] = url;
        debugPrint(
          '[ImageService] 🔄 ImageRow URL 저장 (${uploadedUrls.length}/${node.imageUrls.length}): $localPath -> $url',
        );

        final allUploaded = node.imageUrls.every(
          (path) => uploadedUrls.containsKey(path),
        );

        final updated = node.copyWith(
          metadata: {...meta, 'uploadedUrls': uploadedUrls},
        );
        document.replaceNodeById(groupNodeId, updated);

        if (allUploaded) {
          debugPrint('[ImageService] ✅ ImageRow 모든 이미지 업로드 완료: $groupNodeId');
        }
        notifyListeners();
      } else if (node is PageViewImageNode) {
        final meta = node.metadata;
        final uploadedUrls = Map<String, String>.from(
          (meta['uploadedUrls'] as Map<String, dynamic>?)
                  ?.cast<String, String>() ??
              {},
        );

        uploadedUrls[localPath] = url;
        debugPrint(
          '[ImageService] 🔄 PageView URL 저장 (${uploadedUrls.length}/${node.imageUrls.length}): $localPath -> $url',
        );

        final allUploaded = node.imageUrls.every(
          (path) => uploadedUrls.containsKey(path),
        );

        final updated = node.copyWith(
          metadata: {...meta, 'uploadedUrls': uploadedUrls},
        );
        document.replaceNodeById(groupNodeId, updated);

        if (allUploaded) {
          debugPrint('[ImageService] ✅ PageView 모든 이미지 업로드 완료: $groupNodeId');
        }
        notifyListeners();
      }
    } finally {
      setHistoryExecuting(false);
    }
  }

  /// 이미지 플레이스홀더 노드 추가
  String addImagePlaceholderNode(
    String localPath,
    Function(DocumentNode) insertComponentNodeAtNextLine,
    Function(DocumentNode) copyNode,
    Function(String, SpecialNodeInfo) registerSpecialNode,
  ) {
    // 🎯 플레이스홀더 추가 시 히스토리 저장 방지
    setHistoryExecuting(true);
    try {
      final id = 'img_${DateTime.now().microsecondsSinceEpoch}';
      // 🚀 로컬 이미지가 이미 있으므로 imageUrl에 바로 저장, 플레이스홀더 불필요
      final imageNode = AppImageNode(
        id: id,
        imageUrl: localPath,
        altText: '',
        metadata: {},
      );
      insertComponentNodeAtNextLine(imageNode);

      // 🎯 플레이스홀더도 레지스트리에 등록 (선택 시 툴바 변경을 위해)
      final nodeIndex = document.getNodeIndexById(id);
      if (nodeIndex != -1) {
        registerSpecialNode(
          id,
          SpecialNodeInfo(
            node: copyNode(imageNode),
            index: nodeIndex,
            selection: null,
            isAtDownstream: false,
          ),
        );
        debugPrint(
          '[ImageService] ✅ 이미지 플레이스홀더 레지스트리 등록: nodeId=$id, index=$nodeIndex',
        );
      }

      return id;
    } finally {
      setHistoryExecuting(false);
      // 히스토리는 저장하지 않음
    }
  }

  /// 🎯 그룹 이미지 플레이스홀더 노드 추가 (RowImage 또는 PageViewImage)
  String addGroupImagePlaceholderNode({
    required List<String> localPaths,
    required GroupImageLayout layout,
    required Function(DocumentNode) insertComponentNodeAtNextLine,
    required Function(DocumentNode) copyNode,
    required Function(String, SpecialNodeInfo) registerSpecialNode,
  }) {
    debugPrint(
      '[ImageService] 🔨 그룹 이미지 플레이스홀더 생성 시작: ${localPaths.length}개, layout: $layout',
    );

    setHistoryExecuting(true);
    try {
      final id = 'group_${DateTime.now().microsecondsSinceEpoch}';

      DocumentNode node;
      if (layout == GroupImageLayout.pageview) {
        // PageViewImageNode 생성
        // 🚀 로컬 이미지가 이미 있으므로 플레이스홀더 불필요
        node = PageViewImageNode(id: id, imageUrls: localPaths, metadata: {});
        debugPrint('[ImageService] 📦 PageViewImageNode 생성: $id');
      } else {
        // ImageRowNode 생성 (2열 또는 3열)
        // 🚀 로컬 이미지가 이미 있으므로 플레이스홀더 불필요
        node = ImageRowNode(
          id: id,
          imageUrls: localPaths,
          spacing: 2.0,
          metadata: {},
        );
        debugPrint('[ImageService] 📦 ImageRowNode 생성: $id');
      }

      debugPrint('[ImageService] 📍 노드 삽입 시작: $id');
      insertComponentNodeAtNextLine(node);
      debugPrint('[ImageService] 📍 노드 삽입 완료: $id');

      final nodeIndex = document.getNodeIndexById(id);
      debugPrint('[ImageService] 📍 노드 인덱스 확인: $nodeIndex');

      if (nodeIndex != -1) {
        registerSpecialNode(
          id,
          SpecialNodeInfo(
            node: copyNode(node),
            index: nodeIndex,
            selection: null,
            isAtDownstream: false,
          ),
        );
        debugPrint('[ImageService] ✅ 그룹 이미지 플레이스홀더 레지스트리 등록 완료: $id');
      } else {
        debugPrint('[ImageService] ⚠️ 노드 인덱스를 찾을 수 없음: $id');
      }

      debugPrint('[ImageService] ✅ 그룹 이미지 플레이스홀더 생성 완료: $id');
      return id;
    } catch (e, stack) {
      debugPrint('[ImageService] ❌ 그룹 이미지 플레이스홀더 생성 실패: $e');
      debugPrint('[ImageService] 스택: $stack');
      rethrow;
    } finally {
      setHistoryExecuting(false);
    }
  }

  /// 두 이미지를 가로 배치로 합치는 함수
  void mergeImagesIntoRow(
    String draggingImageId,
    String targetImageId, {
    bool isFromLeft = true,
  }) {
    final draggingNode = document.getNodeById(draggingImageId);
    final targetNode = document.getNodeById(targetImageId);

    if (draggingNode == null || targetNode == null) return;

    // 🎯 업로드 중인 그룹 이미지 체크 (타겟)
    if (targetNode is ImageRowNode) {
      final targetMeta = targetNode.metadata;
      if (targetMeta['isPlaceholder'] == true) {
        debugPrint('[ImageService] ⚠️ 업로드 중인 그룹 이미지에는 병합할 수 없습니다');
        return;
      }
      addImageToRow(draggingImageId, targetImageId, isFromLeft);
      return;
    }

    // 🎯 업로드 중인 그룹 이미지 체크 (드래그 중)
    if (draggingNode is ImageRowNode) {
      final draggingMeta = draggingNode.metadata;
      if (draggingMeta['isPlaceholder'] == true) {
        debugPrint('[ImageService] ⚠️ 업로드 중인 그룹 이미지는 병합할 수 없습니다');
        return;
      }
      addImageToRow(targetImageId, draggingImageId, !isFromLeft);
      return;
    }

    // 둘 다 단일 이미지인 경우
    if (draggingNode is! ImageNode || targetNode is! ImageNode) return;

    // 🚀 로컬-네트워크 혼용 구조: 모든 이미지 경로 허용 (로컬 경로도 병합 가능)

    // 두 이미지의 URL 수집 (최대 3개)
    final imageUrls = <String>[];

    // 드래그 중인 이미지가 타겟 이미지보다 앞에 있으면 먼저 추가
    int draggingIndex = -1;
    int targetIndex = -1;

    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node?.id == draggingImageId) draggingIndex = i;
      if (node?.id == targetImageId) targetIndex = i;
    }

    if (draggingIndex == -1 || targetIndex == -1) return;

    // 🎯 각 이미지의 mediaId 추출
    String? draggingMediaId;
    String? targetMediaId;
    try {
      final draggingMeta =
          (draggingNode as dynamic).metadata as Map<String, dynamic>?;
      draggingMediaId = draggingMeta?['mediaId']?.toString();
    } catch (_) {}
    try {
      final targetMeta =
          (targetNode as dynamic).metadata as Map<String, dynamic>?;
      targetMediaId = targetMeta?['mediaId']?.toString();
    } catch (_) {}

    // 방향에 따라 이미지 순서 결정
    List<String> mediaIds = [];
    if (isFromLeft) {
      // 왼쪽에서 오는 경우: 드래그 이미지가 왼쪽에
      imageUrls.add(draggingNode.imageUrl);
      imageUrls.add(targetNode.imageUrl);
      if (draggingMediaId != null) mediaIds.add(draggingMediaId);
      if (targetMediaId != null) mediaIds.add(targetMediaId);
    } else {
      // 오른쪽에서 오는 경우: 타겟 이미지가 왼쪽에
      imageUrls.add(targetNode.imageUrl);
      imageUrls.add(draggingNode.imageUrl);
      if (targetMediaId != null) mediaIds.add(targetMediaId);
      if (draggingMediaId != null) mediaIds.add(draggingMediaId);
    }

    debugPrint('[ImageService] ImageRow 생성 - mediaIds: $mediaIds');

    // 🎯 imageCommentInfo 맵 생성 (PostExporter가 기대하는 형식)
    final imageCommentInfo = <String, Map<String, dynamic>>{};
    for (int i = 0; i < imageUrls.length; i++) {
      final url = imageUrls[i];
      if (i < mediaIds.length && mediaIds[i].isNotEmpty) {
        imageCommentInfo[url] = {
          'mediaId': mediaIds[i],
          'hasComments': false,
          'commentCount': 0,
        };
      }
    }

    debugPrint('[ImageService] 🔍 생성된 imageCommentInfo: $imageCommentInfo');

    // ImageRowNode 생성 (이미 3개 제한이 적용됨)
    final imageRowNode = ImageRowNode(
      id: 'imageRow_${DateTime.now().millisecondsSinceEpoch}',
      imageUrls: imageUrls,
      spacing: 8.0,
      metadata:
          imageCommentInfo.isNotEmpty
              ? {'imageCommentInfo': imageCommentInfo}
              : null,
    );

    // 🎯 이미지 병합 작업 중에는 히스토리 추적 일시 중단
    setHistoryExecuting(true);

    try {
      // 기존 이미지들 삭제
      document.deleteNode(draggingImageId);
      document.deleteNode(targetImageId);

      // ImageRowNode 삽입 (더 작은 인덱스 위치에)
      final insertIndex =
          draggingIndex < targetIndex ? draggingIndex : targetIndex;
      document.insertNodeAt(insertIndex, imageRowNode);
      // 🎯 notifyListeners는 finally 이후에 한 번만
    } finally {
      setHistoryExecuting(false);
      saveHistory(true, notifyListeners);
      debugPrint('[ImageService] 🖼️ 이미지 병합 완료');
      notifyListeners(); // 🎯 최종: 한 번만 호출
    }
  }

  /// 이미지 행에 이미지 추가
  void addImageToRow(String imageId, String rowId, bool isFromLeft) {
    final imageNode = document.getNodeById(imageId);
    final rowNode = document.getNodeById(rowId);

    if (imageNode == null || rowNode == null) return;
    if (imageNode is! ImageNode || rowNode is! ImageRowNode) return;

    // 🎯 업로드 중인 그룹 이미지는 병합/추가 불가
    final rowMeta = rowNode.metadata;
    if (rowMeta['isPlaceholder'] == true) {
      debugPrint('[ImageService] ⚠️ 업로드 중인 그룹 이미지에는 추가할 수 없습니다');
      return;
    }

    // 🚀 로컬-네트워크 혼용 구조: 모든 이미지 경로 허용 (로컬 경로도 추가 가능)

    // 이미 3개가 있으면 추가하지 않음
    if (rowNode.imageUrls.length >= 3) return;

    // 🎯 추가되는 이미지의 mediaId 추출
    String? newImageMediaId;
    try {
      final imageMeta =
          (imageNode as dynamic).metadata as Map<String, dynamic>?;
      newImageMediaId = imageMeta?['mediaId']?.toString();
    } catch (_) {}

    // 🎯 기존 row의 imageCommentInfo 추출
    Map<String, Map<String, dynamic>> existingCommentInfo = {};
    try {
      final rowMeta = rowNode.metadata;
      final commentInfo = rowMeta['imageCommentInfo'] as Map<String, dynamic>?;
      if (commentInfo != null) {
        existingCommentInfo = commentInfo.map(
          (key, value) => MapEntry(key, (value as Map).cast<String, dynamic>()),
        );
      }
    } catch (_) {}

    // 새로운 이미지 URL 리스트 생성
    final newImageUrls = List<String>.from(rowNode.imageUrls);
    final newImageCommentInfo = Map<String, Map<String, dynamic>>.from(
      existingCommentInfo,
    );

    if (isFromLeft) {
      newImageUrls.insert(0, imageNode.imageUrl);
      if (newImageMediaId != null && newImageMediaId.isNotEmpty) {
        newImageCommentInfo[imageNode.imageUrl] = {
          'mediaId': newImageMediaId,
          'hasComments': false,
          'commentCount': 0,
        };
      }
    } else {
      newImageUrls.add(imageNode.imageUrl);
      if (newImageMediaId != null && newImageMediaId.isNotEmpty) {
        newImageCommentInfo[imageNode.imageUrl] = {
          'mediaId': newImageMediaId,
          'hasComments': false,
          'commentCount': 0,
        };
      }
    }

    // 🎯 이미지 행 추가 작업 중에는 히스토리 추적 일시 중단
    setHistoryExecuting(true);

    try {
      // ImageRowNode 업데이트 (이미 3개 제한이 적용됨)
      final updatedRowNode = rowNode.copyWith(
        imageUrls: newImageUrls,
        metadata:
            newImageCommentInfo.isNotEmpty
                ? {'imageCommentInfo': newImageCommentInfo}
                : null,
      );
      document.replaceNodeById(rowId, updatedRowNode);

      // 기존 이미지 삭제
      document.deleteNode(imageId);
      // 🎯 notifyListeners는 finally 이후에 한 번만
    } finally {
      setHistoryExecuting(false);
      saveHistory(true, notifyListeners);
      debugPrint('[ImageService] 🖼️ ImageRow에 이미지 추가 완료');
      notifyListeners(); // 🎯 최종: 한 번만 호출
    }
  }

  /// 이미지 행에서 특정 이미지를 분리하고 분리된 이미지 ID 반환
  String? splitImageFromRow(String rowId, int imageIndex, {int? insertIndex}) {
    final rowNode = document.getNodeById(rowId);
    if (rowNode == null || rowNode is! ImageRowNode) return null;
    if (imageIndex < 0 || imageIndex >= rowNode.imageUrls.length) return null;

    // 🎯 업로드 중인 그룹 이미지는 분리 불가
    final meta = rowNode.metadata;
    if (meta['isPlaceholder'] == true) {
      debugPrint('[ImageService] ⚠️ 업로드 중인 그룹 이미지는 분리할 수 없습니다');
      return null;
    }

    // 분리할 이미지 URL
    final imageUrl = rowNode.imageUrls[imageIndex];

    // 이미지 행의 인덱스 찾기
    int rowIndex = -1;
    for (int i = 0; i < document.length; i++) {
      if (document.getNodeAt(i)?.id == rowId) {
        rowIndex = i;
        break;
      }
    }
    if (rowIndex == -1) return null;

    // 분리할 이미지의 새 ID 생성
    final newImageId = 'image_${DateTime.now().millisecondsSinceEpoch}';
    final newImageNode = AppImageNode(id: newImageId, imageUrl: imageUrl);

    // 이미지 행에서 해당 이미지 제거
    final remainingUrls = List<String>.from(rowNode.imageUrls);
    remainingUrls.removeAt(imageIndex);

    // 🎯 이미지 분리 작업 중에는 히스토리 추적 일시 중단
    setHistoryExecuting(true);

    try {
      if (remainingUrls.length == 1) {
        // 이미지가 1개만 남으면 단일 이미지로 변경
        final singleImageNode = AppImageNode(
          id: rowId,
          imageUrl: remainingUrls.first,
        );
        document.replaceNodeById(rowId, singleImageNode);
      } else if (remainingUrls.isEmpty) {
        // 이미지가 없으면 행 삭제
        document.deleteNode(rowId);
      } else {
        // 이미지 행 업데이트
        final updatedRowNode = rowNode.copyWith(imageUrls: remainingUrls);
        document.replaceNodeById(rowId, updatedRowNode);
      }

      // 분리된 이미지를 원하는 위치에 삽입 (기본: 원래 행의 위치)
      final int targetInsertIndex = insertIndex ?? rowIndex;
      document.insertNodeAt(targetInsertIndex, newImageNode);
      // 🎯 notifyListeners는 finally 이후에 한 번만

      return newImageId;
    } finally {
      setHistoryExecuting(false);
      saveHistory(true, notifyListeners);
      debugPrint('[ImageService] 🖼️ 이미지 분리 완료');
      notifyListeners(); // 🎯 최종: 한 번만 호출
    }
  }
}
