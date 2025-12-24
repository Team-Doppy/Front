import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/service/post_reader_service.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 🎯 비디오 관련 작업 전담 서비스
class VideoService {
  final Editor editor;
  final MutableDocument document;
  final VoidCallback notifyListeners;
  final Function(bool) setHistoryExecuting;
  final Function(bool, VoidCallback?) saveHistory;
  final Function(DocumentNode) insertComponentNodeAtNextLine;

  VideoService({
    required this.editor,
    required this.document,
    required this.notifyListeners,
    required this.setHistoryExecuting,
    required this.saveHistory,
    required this.insertComponentNodeAtNextLine,
  });

  /// Video clip placeholder 노드 추가
  String addVideoClipPlaceholderNode(
    String localPath,
    String label, {
    String? thumbnailPath,
    double? aspectRatio, // 🎯 영상 비율 정보
  }) {
    // 🎯 플레이스홀더 추가 시 히스토리 저장 방지
    setHistoryExecuting(true);
    try {
      final id = 'clip_${DateTime.now().millisecondsSinceEpoch}';
      // 🎯 label이 UUID나 긴 문자열이면 빈 문자열로 설정 (표시되지 않도록)
      final cleanLabel =
          (label.length > 50 || label.contains('-') && label.length > 30)
              ? ''
              : label;

      // 🎯 metadata에 비율 및 썸네일 정보 저장 (플레이스홀더 렌더링 시 사용)
      final metadata = <String, dynamic>{
        'padding': 'center',
        if (aspectRatio != null) 'aspectRatio': aspectRatio,
        if (thumbnailPath != null && thumbnailPath.isNotEmpty)
          'thumbnailPath': thumbnailPath,
      };

      final node = ClipNode(
        id: id,
        label: cleanLabel,
        colorHex: '#FF5252',
        url: '',
        localPath: localPath,
        thumbnailPath: thumbnailPath ?? '',
        metadata: metadata, // 🎯 비율 및 썸네일 정보 포함
      );
      insertComponentNodeAtNextLine(node);

      // 🎯 _insertComponentNodeAtNextLine()이 이미 document 리스너를 호출하므로 notifyListeners() 불필요
      return id;
    } finally {
      setHistoryExecuting(false);
      // 히스토리는 저장하지 않음
    }
  }

  /// Video placeholder의 썸네일 경로 업데이트
  void updateVideoPlaceholderThumbnail(String id, String thumbnailPath) {
    // 🎯 플레이스홀더 업데이트 시 히스토리 저장 방지
    setHistoryExecuting(true);
    try {
      final node = editor.document.getNodeById(id);
      if (node is ClipNode && node.url.isEmpty) {
        // placeholder 상태일 때만 업데이트
        // 기존 metadata 보존 (패딩 정보 포함) + 썸네일 경로 추가
        final existingMetadata = Map<String, dynamic>.from(node.metadata);
        existingMetadata['thumbnailPath'] =
            thumbnailPath; // 🎯 썸네일 경로도 metadata에 저장

        final updated = ClipNode(
          id: node.id,
          label: node.label,
          colorHex: node.colorHex,
          url: node.url,
          localPath: node.localPath,
          thumbnailPath: thumbnailPath,
          metadata: existingMetadata, // 패딩 정보 + 썸네일 정보 보존
        );
        editor.execute([
          ReplaceNodeRequest(existingNodeId: id, newNode: updated),
        ]);
        // 🎯 editor.execute()가 자동으로 document 리스너를 호출하므로 notifyListeners() 불필요
      }
    } catch (e) {
      debugPrint('[VideoService] 썸네일 업데이트 실패: $e');
    } finally {
      setHistoryExecuting(false);
      // 히스토리는 저장하지 않음
    }
  }

  /// Video placeholder를 실제 URL로 교체
  /// - 기본은 id로 찾고, 실패 시 fallbackLocalPath가 주어지면 localPath로 검색해 교체
  /// - processedLocalPath가 주어지면 ffmpeg 처리된 경로로 localPath 업데이트
  Future<void> replaceVideoPlaceholderWithUrl(
    String id,
    String url, {
    String? fallbackLocalPath,
    String? processedLocalPath, // 🎯 ffmpeg 처리된 비디오 경로
    required bool Function(String) isNetworkUrl,
  }) async {
    // 🎯 플레이스홀더 교체 시 히스토리 저장 방지 (교체 후에는 실제 노드이므로 히스토리 저장)
    setHistoryExecuting(true);
    try {
      DocumentNode? nodeFound = editor.document.getNodeById(id);
      if (nodeFound is! ClipNode) {
        // id로 못 찾았으면 localPath로 검색 (플레이스홀더가 이동/치환된 경우 대비)
        if (fallbackLocalPath != null && fallbackLocalPath.isNotEmpty) {
          for (int i = 0; i < editor.document.length; i++) {
            final n = editor.document.getNodeAt(i);
            if (n is ClipNode) {
              final lp = n.localPath;
              final isPlaceholder = (n.url.isEmpty && lp.isNotEmpty);
              if (isPlaceholder && lp == fallbackLocalPath) {
                nodeFound = n;
                id = n.id; // 이후 교체를 위해 id 갱신
                break;
              }
            }
          }
        }
      }

      // 🎯 비디오 프리로드: 노드 교체 전에 비디오 컨트롤러를 미리 초기화하여 깜빡임 방지
      // 프리로드가 완료될 때까지 기다려서 플레이스홀더가 부드럽게 교체되도록 함
      try {
        await PostReaderService.preloadVideo(url);
        debugPrint('[VideoService] ✅ 비디오 프리로드 완료: $url');

        // 프리로드 완료 후 약간의 지연을 추가하여 UI가 안정화되도록 함
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        debugPrint('[VideoService] ⚠️ 비디오 프리로드 실패 (계속 진행): $e');
      }

      if (nodeFound is! ClipNode) return;

      // 기존 metadata 보존 (패딩 정보 포함)
      final existingMetadata = Map<String, dynamic>.from(nodeFound.metadata);

      // 🚀 비디오는 이미지와 동일한 구조: 로컬 경로를 유지하고 uploadedUrls만 메타데이터에 저장
      // - ClipComponent는 localPath가 있으면 로컬 비디오를 표시하므로, 업로드 완료 후에도 localPath 유지
      // - url은 네트워크 URL로 설정하여 발행 시 사용 (임시저장 시에는 localPath 사용)
      // - 네트워크 URL로 교체는 임시저장/발행 시 PostExporter에서 처리
      final originalLocalPath = nodeFound.localPath; // 원본 경로 (이미지의 imageUrl처럼)
      final uploadedUrls = Map<String, String>.from(
        (existingMetadata['uploadedUrls'] as Map<String, dynamic>?)
                ?.cast<String, String>() ??
            {},
      );

      // 🎯 이미지와 동일하게: uploadedUrls에는 원본 경로를 키로 저장
      if (originalLocalPath.isNotEmpty && !isNetworkUrl(originalLocalPath)) {
        uploadedUrls[originalLocalPath] = url;
        debugPrint(
          '[VideoService] 🔄 Video uploadedUrls 저장: $originalLocalPath -> $url',
        );
      }

      // 🎯 processedLocalPath가 있으면 ffmpeg 처리된 경로로 localPath 업데이트
      // 이미지와 동일한 구조: imageUrl은 원본 경로 유지, localPath는 ffmpeg 처리된 경로 사용
      final finalLocalPath =
          processedLocalPath != null && processedLocalPath.isNotEmpty
              ? processedLocalPath
              : originalLocalPath;

      // 🎯 원본 경로를 metadata에 저장하여 발행 시 찾을 수 있도록 함 (이미지와 동일한 구조)
      final updatedMetadata = <String, dynamic>{
        ...existingMetadata,
        'uploadedUrls': uploadedUrls,
      };

      // 원본 경로가 ffmpeg 처리된 경로와 다르면 metadata에 저장
      if (processedLocalPath != null &&
          processedLocalPath.isNotEmpty &&
          processedLocalPath != originalLocalPath) {
        updatedMetadata['originalLocalPath'] = originalLocalPath;
      }

      final newNode = ClipNode(
        id: nodeFound.id,
        label: nodeFound.label,
        colorHex: nodeFound.colorHex,
        url: url, // 네트워크 URL (발행 시 사용)
        localPath: finalLocalPath, // 🎯 ffmpeg 처리된 경로 사용 (있으면)
        thumbnailPath: nodeFound.thumbnailPath, // 썸네일 경로 유지
        metadata: updatedMetadata, // uploadedUrls 및 originalLocalPath 포함
      );

      editor.execute([
        ReplaceNodeRequest(existingNodeId: id, newNode: newNode),
      ]);
      // 🎯 editor.execute()가 자동으로 document 리스너를 호출하므로 notifyListeners() 불필요
    } catch (e) {
      debugPrint('replaceVideoPlaceholderWithUrl error: $e');
    } finally {
      setHistoryExecuting(false);
      // 🎯 플레이스홀더가 실제 노드로 교체되었으므로 히스토리 저장
      saveHistory(true, notifyListeners);
    }
  }

  /// 비디오 클립 노드 추가 (로컬 경로 기반)
  String addVideoClipNode({
    required String localPath,
    String label = '',
    String? thumbnailPath,
    double? aspectRatio,
  }) {
    final id = 'clip_${DateTime.now().millisecondsSinceEpoch}';
    final metadata = <String, dynamic>{
      'padding': 'center',
      if (aspectRatio != null) 'aspectRatio': aspectRatio,
      if (thumbnailPath != null && thumbnailPath.isNotEmpty)
        'thumbnailPath': thumbnailPath,
    };

    final node = ClipNode(
      id: id,
      label: label,
      colorHex: '#FF5252',
      url: '',
      localPath: localPath,
      thumbnailPath: thumbnailPath ?? '',
      metadata: metadata,
    );
    insertComponentNodeAtNextLine(node);
    return id;
  }

  /// ClipNode 추가: 현재 캐럿 다음 슬롯에 삽입 (네트워크 URL 기반)
  void addClipNode({
    String label = '',
    String colorHex = '#FF5252',
    required String url,
  }) {
    final node = ClipNode(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      colorHex: colorHex,
      url: url,
    );
    insertComponentNodeAtNextLine(node);
  }
}
