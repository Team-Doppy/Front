import 'dart:async';

import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/data/services/draft_service.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show cleanupAllVideoPlayers;
import 'package:doppy/editor/publish/service/post_publish_service.dart'
    show PostExporter, PostPublishService;
import 'package:doppy/image/utils/edit_image_cache_manager.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/main.dart' show navigatorKey;
import 'package:doppy/pages/components/retry_cancel_bottom_sheet.dart';
import 'package:doppy/pages/components/share_post_overlay.dart';
import 'package:doppy/providers/military_grid_provider.dart';
import 'package:doppy/pages/screens/splash_screen.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/feed_provider/profile_feed_sections_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum PublishFlowStatus { idle, publishing, success, failure }

class PublishLogEntry {
  final DateTime at;
  final String message;

  PublishLogEntry(this.message) : at = DateTime.now();
}

class PublishRequest {
  final Map<String, dynamic> exportedBase;
  final String title;
  final String thumbnailImageUrl;
  final String accessLevel;
  final int? year;
  final int? nthWeek;
  final String? sessionKey;
  final bool isOnboardingMode; // 🎯 온보딩 모드 여부
  final String?
  lifePhase; // 🎯 작성 모드 (MILITARY_LIFE, LEAVE_OR_PRE_ENLISTMENT, GENERAL, LETTER, PROMISE)
  final int? recipientUserId; // ✅ 편지 모드: 수신인 user id (API 명세)
  final String? recipientUsername; // ✅ 편지 모드: 수신인 username (클라에서 확실히 보장되는 값)
  final String?
  writingType; // ✅ 글 타입 (LETTER, PROMISE, GENERAL, MILITARY_LIFE, LEAVE_OR_PRE_ENLISTMENT)
  final String? phase; // ✅ 복무 단계 코드 (preEnlistment, training, private, etc.)

  const PublishRequest({
    required this.exportedBase,
    required this.title,
    required this.thumbnailImageUrl,
    required this.accessLevel,
    required this.year,
    required this.nthWeek,
    required this.sessionKey,
    this.isOnboardingMode = false, // 🎯 기본값은 false
    this.lifePhase, // 🎯 기본값은 null
    this.recipientUserId, // ✅ 편지 모드일 때만 설정
    this.recipientUsername, // ✅ 편지 모드일 때만 설정
    this.writingType, // ✅ Promise 모드일 때 PROMISE, 편지 모드일 때 LETTER (선택적)
    this.phase, // ✅ MILITARY_LIFE일 때 필수
  });
}

/// 🎯 전역 발행 상태/사이드이펙트를 담당하는 Provider
/// - PostExportScreen/PostwriteScreen은 "요청만 던지고 즉시 pop" 한다.
/// - 업로드/피드갱신/실패 다이얼로그/완료 ShareOverlay 표시를 여기서 처리한다.
class PublishProvider extends ChangeNotifier {
  PublishFlowStatus _status = PublishFlowStatus.idle;
  PublishFlowStatus get status => _status;

  Object? _lastError;
  Object? get lastError => _lastError;

  Map<String, dynamic>? _lastUploadResult;
  Map<String, dynamic>? get lastUploadResult => _lastUploadResult;

  final List<PublishLogEntry> _logs = <PublishLogEntry>[];
  List<PublishLogEntry> get logs => List.unmodifiable(_logs);

  PublishRequest? _lastRequest;
  PublishRequest? get lastRequest => _lastRequest;

  void _log(String message) {
    _logs.add(PublishLogEntry(message));
    // 로그는 테스트용이므로 메모리 무한 증가 방지
    if (_logs.length > 50) {
      _logs.removeRange(0, _logs.length - 50);
    }
    notifyListeners();
  }

  /// UI에서 호출: 요청을 던지고 바로 return (fire-and-forget)
  void startPublish(PublishRequest request) {
    // 동시에 여러 발행을 허용하지 않는다.
    if (_status == PublishFlowStatus.publishing) {
      _log('⚠️ 이미 발행 중: 중복 요청 무시');
      return;
    }

    _lastRequest = request;
    _lastError = null;
    _lastUploadResult = null;
    _status = PublishFlowStatus.publishing;
    _log('🚀 발행 시작');

    // ✅ 발행 중일 때 모든 비디오 플레이어 정리 (UI와 분리)
    try {
      cleanupAllVideoPlayers();
    } catch (_) {}

    // 🎯 발행 중 스낵바 표시 (모든 경우 3초 유지)
    _showPublishingSnackBar();

    // 🎯 온보딩 모드: 즉시 스플래시로 이동 (업로드는 스플래시에서 대기)
    if (request.isOnboardingMode) {
      _navigateToSplashForOnboardingPublish();
    }

    unawaited(_runPublish(request));
  }

  void _navigateToSplashForOnboardingPublish() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    // 스낵바는 띄우지 않지만, 혹시 남아있다면 정리
    try {
      ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
    } catch (_) {}

    Navigator.of(ctx).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SplashScreen(skipOnboarding: true),
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
      (route) => false,
    );
  }

  void _showPublishingSnackBar() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final theme = Theme.of(ctx);
    final surfaceColor = theme.colorScheme.surface;
    final onSurfaceColor = theme.colorScheme.onSurface;

    ScaffoldMessenger.of(ctx).hideCurrentSnackBar();

    // ✅ 업로드 완료될 때까지 표시되도록 매우 긴 duration 설정
    // (실제로는 업로드 완료/실패 시 hideCurrentSnackBar()로 수동 닫기)
    ErrorHandler.showInfo(
      ctx,
      ctx.tr('uploading'),
      duration: const Duration(days: 1), // ✅ 매우 긴 duration (수동으로 닫을 예정)
      bgColor: onSurfaceColor,
      fgColor: surfaceColor,
      leading: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(surfaceColor),
        ),
      ),
    );
  }

  Future<void> _runPublish(PublishRequest request) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      _lastError = 'navigatorKey.currentContext is null';
      _status = PublishFlowStatus.failure;
      _log('❌ 발행 실패: context 없음');
      notifyListeners();
      return;
    }

    try {
      final publishService = PostPublishService();

      _log('🧱 payload 생성 중…');
      final payload = await publishService.buildFinalPayload(
        exportedBase: request.exportedBase,
        title: request.title,
        thumbnailImageUrl: request.thumbnailImageUrl,
        privateOnly: request.accessLevel == SystemCategoryKeys.private,
        publicOnly: request.accessLevel == SystemCategoryKeys.public,
        friendsOnly: request.accessLevel == SystemCategoryKeys.friends,
        year: request.year,
        nthWeek: request.nthWeek,
        lifePhase: request.lifePhase, // 🎯 작성 모드 전달
        recipientUserId: request.recipientUserId, // ✅ 편지 모드: 수신인 user id
        recipientUsername: request.recipientUsername, // ✅ 편지 모드: 수신인 username
        writingType: request.writingType, // ✅ 글 타입 (PROMISE, LETTER 등)
        phase: request.phase, // ✅ 복무 단계 코드
      );

      _log('☁️ 업로드 중…');
      final uploadResult = await publishService.publishPost(payload: payload);
      _lastUploadResult = uploadResult;

      // ✅ 온보딩 모드면: 코치마크를 위해 onboardingCompleted를 업데이트하지 않는다.
      // - 코치마크는 홈 화면에서 onboardingCompleted == false일 때 표시된다.
      // - 코치마크를 표시한 후에만 onboardingCompleted를 true로 업데이트한다.
      // if (request.isOnboardingMode) {
      //   await _markOnboardingCompleted();
      // }

      _status = PublishFlowStatus.success;
      _log('✅ 발행 완료: id=${uploadResult['id'] ?? ''}');
      notifyListeners();

      // ✅ 홈 그리드 즉시 갱신
      try {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          ctx.read<MilitaryGridProvider>().reloadGrid();
        }
      } catch (_) {}

      // 🎯 발행 성공 후 임시저장 삭제 및 편집 디스크 캐시 삭제 (백그라운드)
      unawaited(_cleanupAfterSuccess(payload: payload, request: request));

      // 🎯 피드 새로고침/정렬은 Provider의 몫
      unawaited(_refreshMyFeed(uploadResult: uploadResult));

      // ✅ 업로드 중 스낵바 닫기
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
      }

      // 🎯 일반 모드: 완료 스낵바 표시 (공유하기 버튼 포함)
      if (!request.isOnboardingMode) {
        // 🎯 완료 스낵바 표시 (공유하기 버튼 포함)
        _showSuccessSnackBar();
      }
    } catch (e) {
      _lastError = e;
      _status = PublishFlowStatus.failure;
      _log('❌ 발행 실패: $e');
      notifyListeners();

      // 🎯 실패 스낵바 닫기
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
      }

      await _showFailureDialogAndMaybeRetry();
    }
  }

  Future<void> _cleanupAfterSuccess({
    required Map<String, dynamic> payload,
    required PublishRequest request,
  }) async {
    try {
      // 스티커 캔버스 청소
      try {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          ctx.read<StickerService>().removeAll();
        }
      } catch (_) {}

      final sessionKey = request.sessionKey;
      if (sessionKey != null && sessionKey.startsWith('draft_')) {
        final draftId = sessionKey;
        final thumbnailUrl = request.thumbnailImageUrl;

        final usedImageUrls = PostExporter.collectUsedMediaUrls(payload);
        if (thumbnailUrl.isNotEmpty) {
          usedImageUrls.add(thumbnailUrl);
        }

        if (usedImageUrls.isNotEmpty) {
          await EditImageCacheManager.instance.removeCachesForUrls(
            usedImageUrls,
          );
        }

        final draftService = DraftService();
        await draftService.deleteDraft(draftId);
        await draftService.clearAutoDraft();
      } else {
        // 임시저장이 아니어도 자동저장은 삭제
        final draftService = DraftService();
        await draftService.clearAutoDraft();
      }
    } catch (e) {
      _log('⚠️ 후처리 중 오류(무시): $e');
    }
  }

  Future<void> _refreshMyFeed({
    required Map<String, dynamic> uploadResult,
  }) async {
    try {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;

      // ✅ 포스트 작성 시 "전체 & 모든 포스트 모드"로 재로드
      // ProfileFeedSectionsProvider를 통해 sections 재로드 (필터 리셋)
      try {
        final sectionsProvider = ctx.read<ProfileFeedSectionsProvider>();
        final userProvider = ctx.read<UserProvider>();
        final currentUser = userProvider.currentUser;
        final username = currentUser?.username;

        if (username != null && username.isNotEmpty) {
          await sectionsProvider.loadSections(username: username, force: true);
          _log('🔄 프로필 피드 sections 재로드 완료 (전체 모드)');
        }
      } catch (e) {
        _log('⚠️ sections 재로드 실패(무시): $e');
        // 폴백: 기존 방식으로 피드만 새로고침
        final feedProvider = ctx.read<MyProfileFeedProvider>();
        await feedProvider.refresh().catchError((_) {});
      }
    } catch (e) {
      _log('⚠️ 피드 갱신 실패(무시): $e');
    }
  }

  void _showSuccessSnackBar() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final theme = Theme.of(ctx);
    final surfaceColor = theme.colorScheme.surface;
    final onSurfaceColor = theme.colorScheme.onSurface;

    ScaffoldMessenger.of(ctx).hideCurrentSnackBar();

    ErrorHandler.showInfo(
      ctx,
      ctx.tr('upload_complete'),
      duration: const Duration(seconds: 3),
      bgColor: onSurfaceColor,
      fgColor: surfaceColor,
      action: SnackBarAction(
        label: ctx.tr('share'),

        textColor: surfaceColor,
        onPressed: () {
          ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
          _showShareOverlay();
        },
      ),
    );
  }

  void _showShareOverlay() {
    if (_lastUploadResult == null) return;

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final safeCtx = navigatorKey.currentContext;
      if (safeCtx == null) return;

      try {
        SharePostOverlay.show(
          safeCtx,
          postId: _lastUploadResult!['id']?.toString() ?? '',
          title: _lastUploadResult!['title']?.toString() ?? '',
          summary: '',
          authorUsername: _lastUploadResult!['author']?.toString() ?? '',
          authorProfileImageUrl:
              _lastUploadResult!['authorProfileImageUrl']?.toString(),
          thumbnailUrl: _lastUploadResult!['thumbnailImageUrl']?.toString(),
          readTime: (_lastUploadResult!['readTime'] as int?) ?? 1,
          isNewPost: true,
          uploadedData: _lastUploadResult,
          useReplacement: false,
        );
      } catch (e) {
        _log('⚠️ ShareOverlay 표시 실패(무시): $e');
      }
    });
  }

  Future<void> _showFailureDialogAndMaybeRetry() async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    // 화면이 이미 pop된 상태여야 하므로 root context에서 띄운다.
    final action = await RetryCancelBottomSheet.show(
      ctx,
      title: ctx.tr('publish_failed_title'),
      error: _lastError,
    );

    if (action == RetryCancelAction.retry && _lastRequest != null) {
      _log('🔁 재시도 선택');
      startPublish(_lastRequest!);
    } else {
      _log('🛑 재시도 취소');
      // 실패 후에도 로그는 유지하되 overlay는 사용자가 닫을 수 있게 둔다.
    }
  }
}
