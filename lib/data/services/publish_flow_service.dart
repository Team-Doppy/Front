import 'package:flutter/material.dart';

import 'package:doppy/editor/service/draft_service.dart';
import 'package:doppy/editor/utils/dialog_util.dart';
import 'package:doppy/providers/graph_provider.dart';
import 'package:doppy/providers/post_provider.dart';
import 'package:doppy/utils/snackbar_util.dart';

/// 발행 플로우: WebSocket 연결 → 업로드 → WebSocket 응답 대기 → 그래프 재로드 / 드래프트 정리
/// [navContext] 에디터(다이얼로그·pop), [hostContext] 홈(스낵바·GraphProvider)
class PublishFlowService {
  static const wsConnectTimeout = Duration(seconds: 10);
  static const uploadTimeout = Duration(seconds: 60);
  static const analysisResponseTimeout = Duration(seconds: 120);

  final PostProvider _postProvider = PostProvider();
  final GraphProvider _graphProvider = GraphProvider();
  final DraftService _draftService = DraftService();

  /// 발행 실행. 실패 시 에디터에서 다이얼로그 후 return, 성공 시 pop 후 홈에서 스낵바·그래프 갱신
  Future<void> execute({
    required BuildContext navContext,
    required BuildContext hostContext,
    required String title,
    required String? thumbnailImageUrl,
    required String accessLevel,
    required Map<String, dynamic> content,
    required List<String> usedImageUrls,
    required String author,
    String? currentDraftId,
  }) async {
    // 1. WebSocket 먼저 연결 → 실패 시 발행 중단 (에디터에서 다이얼로그)
    try {
      await _postProvider.ensureAnalysisConnection(wsConnectTimeout);
    } catch (e) {
      _postProvider.stopAnalysisEvents();
      if (!navContext.mounted) return;
      await DialogUtils.showInfoDialog(
        navContext,
        title: '발행 실패',
        message: '연결에 실패했어요. 다시 시도해 주세요.',
      );
      return;
    }

    // 2. 동기적 업로드 (타임아웃 시 에디터에서 다이얼로그)
    final post = await _postProvider.publish(
      title: title,
      author: author,
      thumbnailImageUrl: thumbnailImageUrl,
      content: content,
      usedImageUrls: usedImageUrls,
      accessLevel: accessLevel,
      timeout: uploadTimeout,
    );

    if (post == null) {
      _postProvider.stopAnalysisEvents();
      if (!navContext.mounted) return;
      await DialogUtils.showInfoDialog(
        navContext,
        title: '업로드 오류',
        message: _postProvider.publishError ?? '업로드에 실패했어요.',
      );
      return;
    }

    if (!navContext.mounted) return;
    Navigator.of(navContext).pop();

    if (!hostContext.mounted) return;
    _graphProvider.enterPublishingMode();
    SnackbarUtil.show(hostContext, '업로드 중', variant: SnackBarVariant.loading);

    // 3. WebSocket 응답 대기 → ANALYSIS_COMPLETE 시에만 그래프 재로드, ANALYSIS_FAILED/타임아웃 시 reason 스낵바만
    final result = await _postProvider.waitForAnalysisComplete(
      post.id,
      analysisResponseTimeout,
    );

    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).hideCurrentSnackBar();

    // 발행 플로우 종료 시 WebSocket 구독 해제 (연결 정리)
    _postProvider.stopAnalysisEvents();

    if (result.ok) {
      await _graphProvider.loadGraph();
      _graphProvider.exitPublishingMode();
      await _draftService.clearAutoDraft();
      if (currentDraftId != null && currentDraftId.isNotEmpty) {
        await _draftService.deleteDraft(currentDraftId);
      }
      SnackbarUtil.showInfo(hostContext, '발행됐어요');
    } else {
      _graphProvider.exitPublishingMode();
      // ANALYSIS_FAILED 또는 타임아웃: 그래프 재로드 하지 않음, reason 표시
      final message =
          result.failureReason?.isNotEmpty == true
              ? result.failureReason!
              : '분석 중 문제가 생겼어요';

      debugPrint('분석 중 문제가 생겼어요: $message');
      SnackbarUtil.showInfo(hostContext, '분석 중 문제가 생겼어요');
    }
  }
}
