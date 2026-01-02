import 'dart:convert';
import 'dart:ui' as ui;
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/pages/components/share_post_overlay.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/editor/publish/service/post_publish_service.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/access_level_parser.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/editor/publish/component/step1_thumbnail_edit.dart';
import 'package:doppy/editor/publish/component/step2_audience_selection.dart';
import 'package:doppy/editor/publish/component/step3_category_selection.dart';
import 'package:doppy/pages/screens/manage_group_screen.dart';
import 'package:doppy/data/services/draft_service.dart';
import 'package:doppy/image/utils/edit_image_cache_manager.dart';
import 'package:doppy/image/utils/editor_image_provider.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show cleanupAllVideoPlayers;
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/retry_cancel_bottom_sheet.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

void printLarge(String text, {int chunkSize = 800}) {
  final int len = text.length;
  for (int i = 0; i < len; i += chunkSize) {
    final int end = (i + chunkSize < len) ? i + chunkSize : len;
    debugPrint(text.substring(i, end));
  }
}

class PostExportScreen extends StatefulWidget {
  const PostExportScreen({super.key, required this.exported, this.sessionKey});
  final String exported;
  final String? sessionKey; // 블로그/드래프트별 네임스페이스 키

  @override
  State<PostExportScreen> createState() => _PostExportScreenState();
}

class _PostExportScreenState extends State<PostExportScreen>
    with TickerProviderStateMixin {
  String get _nsKey => widget.sessionKey ?? 'default';

  // 3단계 진행 상태
  int _currentStep = 0;
  static const int _totalSteps = 3;

  // 더미 데이터
  String _exportedThumbnailImageUrl = '';
  String _firstBodyImageUrl = '';
  String _title = '';
  String _excerpt = '';
  late final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  late final TextEditingController _excerptController = TextEditingController();
  final FocusNode _excerptFocusNode = FocusNode();

  Map<String, dynamic> _exportedBase = <String, dynamic>{};

  bool _editMode = false;

  // Step 2: 공개 범위 선택
  final Set<int> _selectedAudienceGroupIds = {};
  bool _audienceSelectAll = false;
  bool _audiencePrivateOnly = false;
  bool _audienceFriendsOnly = false;

  // Step 3: 카테고리 선택
  int? _selectedCategoryId = 0; // 기본값: 미지정 카테고리 (ID: 0)
  List<Map<String, dynamic>>? _cachedCategories; // 캐시된 카테고리 목록
  bool _isLoadingCategories = false; // 카테고리 로딩 상태
  bool _showCategoryLoading = false; // 1초 후에만 표시할 카테고리 로딩
  bool _showGroupLoading = false; // 1초 후에만 표시할 그룹 로딩
  bool _isGroupLoadingStarted = false; // 그룹 로딩 시작 여부

  bool _isUploading = false;
  bool _isUploadingThumb = false;
  File? _localThumbnailFile; // 업로드 중 로컬 파일 미리보기용
  File? _localVideoFile; // 영상 선택 시 원본 비디오 파일
  VideoPlayerController? _videoController; // 영상 재생 컨트롤러
  String? _cachedVideoUrl; // 캐시된 비디오 URL (서버 영상용)

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    debugPrint('[PostExport] ═══════════════════════════════════════');
    debugPrint('[PostExport] initState 호출됨 - sessionKey: $_nsKey');
    debugPrint('[PostExport] ═══════════════════════════════════════');
    _hydrateFromExported(jsonDecode(widget.exported));
    _intro.forward();

    // 카테고리는 Step3 컴포넌트에서 로드함
  }

  @override
  void dispose() {
    try {
      _titleController.dispose();
      _titleFocusNode.dispose();
      _excerptController.dispose();
      _excerptFocusNode.dispose();

      // 🎯 비디오 컨트롤러 정리 (로컬/서버 구분하여 처리)
      // _disposeVideoController 내부에서 _cachedVideoUrl 여부에 따라 처리
      _disposeVideoController(context: 'dispose');

      // 🎯 업로드 태스크 취소
      _cancelUploadTasks();
    } catch (e) {
      debugPrint('[PostExport] dispose 에러: $e');
    }
    super.dispose();
  }

  void _hydrateFromExported(Map<String, dynamic> exported) {
    _exportedBase = exported;
    // 제목
    final String? exportedTitle = PostContentUtils.readString(
      exported,
      keys: const ['title'],
    );
    if (exportedTitle != null && exportedTitle.trim().isNotEmpty) {
      _title = exportedTitle.trim();
      _titleController.text = _title;
    }

    // 🎯 썸네일: exported에서 가져오기 (임시저장 사용 안 함)
    final exportedThumbnailUrl = exported['thumbnailImageUrl'] as String? ?? '';

    // ✅ 본문 첫 이미지 URL (Step1 카드/배경 기본값)
    _firstBodyImageUrl = PostContentUtils.findFirstBodyImageUrl(exported);

    assert(() {
      final nodes =
          (exported['content'] is Map)
              ? List<dynamic>.from(
                ((exported['content'] as Map)['nodes'] as List?) ?? const [],
              )
              : const [];
      debugPrint(
        '[ThumbAuto][PostExportScreen] exportedThumbnailUrl="$exportedThumbnailUrl", firstBody="$_firstBodyImageUrl", nodes=${nodes.length}',
      );
      if (nodes.isNotEmpty) {
        for (int i = 0; i < nodes.length && i < 6; i++) {
          final n = nodes[i];
          if (n is! Map) continue;
          debugPrint('[ThumbAuto][PostExportScreen] node[$i] = ${n['type']}');
        }
      }
      debugPrint(
        '[ThumbAuto][PostExportScreen] usedImageUrls=${(exported['usedImageUrls'] as List?)?.length ?? 0}',
      );
      return true;
    }());

    // ✅ 썸네일이 비어있으면 "본문 첫 이미지"를 기본값으로 사용한다.
    // - 카드 + 배경 이미지가 즉시 보여야 함
    // - http(s)만 채택
    _exportedThumbnailImageUrl =
        exportedThumbnailUrl.trim().isNotEmpty
            ? exportedThumbnailUrl.trim()
            : _firstBodyImageUrl.trim();

    debugPrint(
      '[PostExport] 썸네일 초기화: $_exportedThumbnailImageUrl (firstBody=$_firstBodyImageUrl)',
    );

    // ✅ 같은 캐시 매니저(EditImageCacheManager)로 precache해서 "즉시 표시" 확률을 높인다.
    // 🎯 비디오 URL인 경우: precache 스킵 (이미지로 로드할 수 없음)
    final thumb = _exportedThumbnailImageUrl.trim();
    if (thumb.isNotEmpty &&
        (thumb.startsWith('http://') || thumb.startsWith('https://'))) {
      // 🎯 비디오 URL인지 확인
      final lowerUrl = thumb.toLowerCase();
      final isVideo =
          lowerUrl.endsWith('.mp4') ||
          lowerUrl.endsWith('.mov') ||
          lowerUrl.endsWith('.m4v') ||
          lowerUrl.contains('/videos/') ||
          lowerUrl.contains('video');

      // 🎯 비디오 URL인 경우: VideoCacheService로 처리 (precache 스킵)
      if (isVideo) {
        _cachedVideoUrl = thumb;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            final videoCache = VideoCacheService();
            _videoController = videoCache.getOrCreateController(
              thumb,
              namespace: 'profile',
            );

            // 🎯 dispose 체크: 컨트롤러 유효성 확인
            try {
              // 이미 초기화된 경우 바로 재생
              if (_videoController!.value.isInitialized) {
                if (mounted) {
                  _videoController!.play();
                  _videoController!.setLooping(true);
                  setState(() {});
                }
              } else {
                // 초기화 대기
                _videoController!.addListener(_onVideoControllerInitialized);
              }
            } catch (e) {
              debugPrint('[PostExport] 서버 비디오 컨트롤러 접근 오류 (dispose됨): $e');
              _videoController = null;
              _cachedVideoUrl = null;
            }
          } catch (e) {
            debugPrint('[PostExport] 서버 비디오 컨트롤러 생성 오류: $e');
            _videoController = null;
            _cachedVideoUrl = null;
          }
        });
      } else {
        // 🎯 이미지 URL인 경우: EditorImageProvider를 사용하여 step1_thumbnail_edit과 동일한 캐시 키 사용
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            final screenWidth = MediaQuery.sizeOf(context).width;
            final decodeWidth = EditorImageProvider.editingDecodeWidth(
              context,
              screenWidth,
            );
            final built = EditorImageProvider.build(
              url: thumb,
              isEditing: true,
              decodeWidth: decodeWidth,
            );
            precacheImage(built.effectiveProvider, context).catchError((_) {});
          } catch (_) {}
        });
      }
    }

    // 영상 파일만 복원 (persist 사용)
    final svc = NodeComponentService();
    final persistedVideoPath = svc.getTempVideoFilePath(_nsKey);
    final persistedVideoThumbnailPath = svc.getTempVideoThumbnailPath(_nsKey);

    // 영상 파일 복원 (있다면)
    if (persistedVideoPath != null && persistedVideoPath.isNotEmpty) {
      final videoFile = File(persistedVideoPath);
      if (videoFile.existsSync()) {
        _localVideoFile = videoFile;

        // 🎯 기존 컨트롤러 안전하게 dispose
        _disposeVideoController(context: '_hydrateFromExported');

        // 🎯 로컬 비디오는 직접 관리 (VideoCacheService 불필요)
        try {
          final controller = VideoPlayerController.file(videoFile);

          // 🎯 컨트롤러 참조 저장 (비동기 콜백에서 dispose 체크용)
          final controllerRef = controller;

          _videoController = controller;

          // 🎯 dispose 체크: 리스너 추가 전 컨트롤러 유효성 확인
          try {
            controller.addListener(_onVideoControllerInitialized);
          } catch (e) {
            debugPrint('[PostExport] 리스너 추가 오류 (dispose됨): $e');
            _videoController = null;
            return;
          }

          controller
              .initialize()
              .then((_) {
                // 🎯 dispose 체크 강화: mounted, controller 유효성, 참조 일치 확인
                if (!mounted || _videoController != controllerRef) {
                  try {
                    controllerRef.dispose();
                  } catch (_) {}
                  return;
                }

                try {
                  // 🎯 dispose 체크: 컨트롤러 유효성 확인
                  if (controllerRef.value.isInitialized) {
                    controllerRef.play();
                    controllerRef.setLooping(true);
                    if (mounted) {
                      setState(() {});
                    }
                  }
                } catch (e) {
                  debugPrint('[PostExport] 비디오 재생 오류 (dispose됨): $e');
                }
              })
              .catchError((error) {
                debugPrint('[PostExport] 비디오 컨트롤러 초기화 실패: $error');
                if (!mounted) return;

                // 🎯 컨트롤러가 여전히 유효한지 확인
                if (_videoController == controllerRef) {
                  _disposeVideoController(
                    context: '_hydrateFromExported.catchError',
                  );
                  setState(() {});
                }
              });
        } catch (e) {
          debugPrint('[PostExport] 비디오 컨트롤러 생성 오류: $e');
          _videoController = null;
        }
        debugPrint('[PostExport] 영상 파일 복원: $persistedVideoPath');

        // 영상 로컬 썸네일도 복원
        if (persistedVideoThumbnailPath != null &&
            persistedVideoThumbnailPath.isNotEmpty) {
          final thumbnailFile = File(persistedVideoThumbnailPath);
          if (thumbnailFile.existsSync()) {
            _localThumbnailFile = thumbnailFile;
            debugPrint('[PostExport] 영상 썸네일 복원: $persistedVideoThumbnailPath');
          }
        }
      } else {
        debugPrint('[PostExport] 영상 파일이 존재하지 않음: $persistedVideoPath');
        svc.clearTempVideoFile(_nsKey);
      }
    }

    // 🎯 Summary: exported에 명시된 값이 있으면 그 값을 우선 사용, 없으면 자동 추출
    final exportedSummary = (exported['summary'] ?? '').toString().trim();
    if (exportedSummary.isNotEmpty) {
      _excerpt = exportedSummary;
      _excerptController.text = _excerpt;
      debugPrint('[PostExport] ℹ️ exported summary 사용: $_excerpt');
    } else {
      final collected = PostContentUtils.collectText(exported);
      _excerpt = PostContentUtils.extractSummary(
        collectedText: collected,
        title: _title,
        maxLength: 100,
      );
      _excerptController.text = _excerpt;
      debugPrint('[PostExport] ℹ️ 자동 추출 summary 사용: $_excerpt');
    }

    // 공개 범위 초기값 동기화: accessLevel/sharedGroupIds 반영
    try {
      // 🎯 공통 파싱 유틸리티 사용
      final level =
          AccessLevelParser.parseAccessLevelString(exported['accessLevel']) ??
          '';
      final sharedGroupIds = AccessLevelParser.parseSharedGroupIds(
        exported['sharedGroupIds'],
      );

      // 우선 순위: PRIVATE > PUBLIC > FRIENDS > GROUPS(shared)
      bool selectAll = false;
      bool privateOnly = false;
      bool friendsOnly = false;
      final Set<int> groups = sharedGroupIds?.toSet() ?? <int>{};

      if (level == 'PRIVATE') {
        privateOnly = true;
      } else if (level == 'PUBLIC') {
        selectAll = true;
      } else if (level == 'FRIENDS') {
        friendsOnly = true;
      } else if (level == 'GROUPS') {
        // 그룹 공유: 기존 그룹 선택 반영
      }

      _audiencePrivateOnly = privateOnly;
      _audienceSelectAll = selectAll;
      _audienceFriendsOnly = friendsOnly;
      _selectedAudienceGroupIds
        ..clear()
        ..addAll(groups);
    } catch (_) {}
    setState(() {});
  }

  // 🎯 비디오 컨트롤러 안전하게 dispose하는 헬퍼 메서드
  void _disposeVideoController({String? context}) {
    if (_videoController == null) return;

    // 🎯 VideoCacheService에서 가져온 서버 비디오 컨트롤러는 dispose하지 않음
    if (_cachedVideoUrl != null) {
      // 서버 비디오: 리스너만 제거하고 releaseController 호출
      try {
        _videoController!.removeListener(_onVideoControllerInitialized);
      } catch (e) {
        debugPrint('[PostExport] ${context ?? "dispose"}: 리스너 제거 오류: $e');
      }

      // VideoCacheService에서 참조 해제
      try {
        VideoCacheService().releaseController(
          _cachedVideoUrl!,
          namespace: 'profile',
        );
        debugPrint(
          '[PostExport] ${context ?? "dispose"}: 서버 비디오 컨트롤러 참조 해제 완료',
        );
      } catch (e) {
        debugPrint('[PostExport] ${context ?? "dispose"}: 서버 비디오 참조 해제 오류: $e');
      }

      _videoController = null;
      return;
    }

    // 🎯 로컬 비디오 컨트롤러만 dispose
    try {
      // 리스너 제거 (먼저 제거하여 콜백 방지)
      _videoController!.removeListener(_onVideoControllerInitialized);
    } catch (e) {
      debugPrint('[PostExport] ${context ?? "dispose"}: 리스너 제거 오류: $e');
    }

    try {
      // 일시정지
      if (_videoController!.value.isInitialized) {
        _videoController!.pause();
      }
    } catch (e) {
      debugPrint(
        '[PostExport] ${context ?? "dispose"}: 일시정지 오류 (dispose됨): $e',
      );
    }

    try {
      // dispose
      _videoController!.dispose();
      debugPrint(
        '[PostExport] ${context ?? "dispose"}: 로컬 비디오 컨트롤러 dispose 완료',
      );
    } catch (e) {
      debugPrint('[PostExport] ${context ?? "dispose"}: 컨트롤러 dispose 오류: $e');
    }

    _videoController = null;
  }

  // 🎯 비디오 컨트롤러 초기화 완료 리스너
  void _onVideoControllerInitialized() {
    // 🎯 dispose 체크: mounted 및 컨트롤러 유효성 확인
    if (!mounted || _videoController == null) {
      // dispose된 경우 리스너 제거 시도
      try {
        _videoController?.removeListener(_onVideoControllerInitialized);
      } catch (_) {}
      return;
    }

    // 🎯 컨트롤러 참조 저장 (리스너 제거 전에)
    final controller = _videoController!;

    try {
      // 🎯 dispose 체크: 컨트롤러 유효성 확인
      if (controller.value.isInitialized) {
        // 🎯 리스너 제거 (먼저 제거하여 재진입 방지)
        try {
          controller.removeListener(_onVideoControllerInitialized);
        } catch (e) {
          debugPrint('[PostExport] 리스너 제거 오류 (dispose됨): $e');
          return;
        }

        if (mounted) {
          try {
            controller.play();
            controller.setLooping(true);
            setState(() {});
          } catch (e) {
            debugPrint('[PostExport] 비디오 재생 오류 (dispose됨): $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[PostExport] 비디오 컨트롤러 초기화 리스너 오류 (dispose됨): $e');
      // dispose된 경우 리스너 제거 시도
      try {
        controller.removeListener(_onVideoControllerInitialized);
      } catch (_) {}
    }
  }

  // 부드러운 애니메이션과 함께 닫기
  Future<void> _closeWithAnimation() async {
    _cancelUploadTasks();

    // 🎯 로컬 비디오 컨트롤러 직접 dispose
    _disposeVideoController(context: '_closeWithAnimation');

    // 닫힐 때는 빠르게 (250ms)
    _intro.duration = const Duration(milliseconds: 250);
    await _intro.reverse();
    // 다시 원래 duration으로 복원
    _intro.duration = const Duration(milliseconds: 800);

    if (!mounted || !context.mounted) return;

    Navigator.of(context).pop({
      'thumbnailImageUrl': _exportedThumbnailImageUrl,
      'title': _titleController.text.trim(),
      'summary': _excerptController.text.trim(),
    });
  }

  // 등록 가능 여부 확인 (서버 API 스펙 준수)
  bool _canPublish() {
    // 1. 기본 상태 확인
    if (_isUploading || _isUploadingThumb) {
      return false;
    }

    // 2. 필수 필드 확인 (편집된 내용 기준)
    final editedTitle = _titleController.text.trim();
    final editedExcerpt = _excerptController.text.trim();

    if (editedTitle.isEmpty) {
      return false;
    }
    if (editedExcerpt.isEmpty) {
      return false;
    }
    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return false;
    }

    // 3. 그룹 공유시 그룹 선택 확인
    if (!_audienceSelectAll &&
        !_audiencePrivateOnly &&
        !_audienceFriendsOnly &&
        _selectedAudienceGroupIds.isEmpty) {
      return false;
    }

    // 4. 카테고리 리스트 확인
    // 🎯 카테고리 리스트가 비어있거나 null이면 게시 불가
    if (_cachedCategories == null || _cachedCategories!.isEmpty) {
      return false;
    }

    // 5. 카테고리가 선택되어 있어야 함
    if (_selectedCategoryId == null) {
      return false;
    }

    return true;
  }

  // 등록 불가능할 때 표시할 에러 메시지 (서버 API 스펙 준수)
  String _getPublishErrorMessage() {
    if (_isUploadingThumb) {
      return context.tr('image_uploading');
    }
    final editedTitle = _titleController.text.trim();
    final editedExcerpt = _excerptController.text.trim();

    if (editedTitle.isEmpty) {
      return context.tr('title_required');
    }
    if (editedExcerpt.isEmpty) {
      return context.tr('content_required');
    }
    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return context.tr('thumbnail_required');
    }
    if (!_audienceSelectAll &&
        !_audiencePrivateOnly &&
        !_audienceFriendsOnly &&
        _selectedAudienceGroupIds.isEmpty) {
      return context.tr('group_required');
    }
    // 🎯 카테고리 리스트가 비어있으면 에러 메시지
    if (_cachedCategories == null || _cachedCategories!.isEmpty) {
      return context.tr('category_list_load_failed');
    }
    if (_selectedCategoryId == null) {
      return context.tr('category_required');
    }
    return context.tr('cannot_publish');
  }

  Future<void> _publish() async {
    try {
      // 최종 편집된 내용으로 검증
      final finalTitle = _titleController.text.trim();
      final finalExcerpt = _excerptController.text.trim();

      // 1. 제목 검증 (모든 공개 범위에서 필수)
      if (finalTitle.isEmpty) {
        ErrorHandler.showError(context, context.tr('title_required'));
        return;
      }

      // 2. 컨텐츠 검증 (모든 공개 범위에서 필수)
      if (finalExcerpt.isEmpty) {
        ErrorHandler.showError(context, context.tr('content_required'));
        return;
      }

      // 3. 썸네일 검증 (모든 공개 범위에서 필수)
      final trimmedThumbnailUrl = _exportedThumbnailImageUrl.trim();
      if (trimmedThumbnailUrl.isEmpty) {
        ErrorHandler.showError(context, context.tr('thumbnail_required'));
        return;
      }
      // ✅ 썸네일 URL이 네트워크 경로인지 검증 (로컬 경로 허용 X)
      final isHttpUrl =
          trimmedThumbnailUrl.startsWith('http://') ||
          trimmedThumbnailUrl.startsWith('https://');
      if (!isHttpUrl) {
        ErrorHandler.showError(
          context,
          context.tr('thumbnail_upload_required'),
        );
        return;
      }

      // 4. 그룹 공유시 그룹 선택 검증 (친구공유는 예외)
      if (!_audienceSelectAll &&
          !_audiencePrivateOnly &&
          !_audienceFriendsOnly &&
          _selectedAudienceGroupIds.isEmpty) {
        ErrorHandler.showError(context, context.tr('group_required'));
        return;
      }

      // 5. 카테고리는 기본값 0(미지정)이 있으므로 검증 불필요

      // 모든 검증 통과 후 업로드 시작
      setState(() {
        _isUploading = true;
      });

      // ✅ 발행 중일 때 모든 비디오 플레이어 정리 (ClipComponent의 컨트롤러 dispose)
      cleanupAllVideoPlayers();

      // 🎯 포스트 발행 서비스를 통한 최종 JSON 빌드
      final publishService = PostPublishService();
      final Map<String, dynamic> payload = await publishService
          .buildFinalPayload(
            exportedBase: _exportedBase,
            title: finalTitle,
            excerpt: finalExcerpt,
            thumbnailImageUrl: _exportedThumbnailImageUrl,
            privateOnly: _audiencePrivateOnly,
            publicOnly: _audienceSelectAll,
            friendsOnly: _audienceFriendsOnly,
            selectedGroupIds: _selectedAudienceGroupIds.toList(),
            categoryId: _selectedCategoryId,
          );

      // 최종 검증된 데이터 로깅
      final String json = const JsonEncoder.withIndent('  ').convert(payload);
      debugPrint('===== FINAL POST JSON (API SPEC COMPLIANT) =====');
      debugPrint('제목: $finalTitle');
      debugPrint('컨텐츠: $finalExcerpt');
      debugPrint('썸네일: $_exportedThumbnailImageUrl');
      final scopeLabel =
          _audienceSelectAll
              ? 'PUBLIC'
              : (_audiencePrivateOnly
                  ? 'PRIVATE'
                  : (_audienceFriendsOnly ? 'FRIENDS' : 'GROUPS'));
      debugPrint('공개 범위: $scopeLabel');
      if (!_audienceSelectAll && !_audiencePrivateOnly) {
        debugPrint('선택된 그룹: $_selectedAudienceGroupIds');
      }
      debugPrint('카테고리 ID: $_selectedCategoryId');
      printLarge(json);

      if (!mounted) return;

      // 🎯 포스트 발행 서비스를 통한 서버 업로드
      final uploadResult = await publishService.publishPost(payload: payload);

      debugPrint('===== UPLOAD RESULT =====');
      debugPrint('Upload successful: ${uploadResult}');

      if (!mounted) return;

      // 🎯 발행 성공 후 임시저장 삭제 및 관련 디스크 캐시 삭제 (비동기 처리)
      // 사용자 경험에 영향을 주지 않도록 백그라운드에서 처리
      if (widget.sessionKey != null &&
          widget.sessionKey!.startsWith('draft_')) {
        final draftId = widget.sessionKey!;
        final thumbnailUrl = _exportedThumbnailImageUrl;

        // 비동기로 실행 (await 제거)
        Future.microtask(() async {
          try {
            debugPrint('[PostExport] 임시저장 삭제 시작: $draftId');

            // 1. 사용된 이미지 URL 수집
            final usedImageUrls = PostExporter.collectUsedMediaUrls(payload);
            // 썸네일 URL도 포함
            if (thumbnailUrl.isNotEmpty) {
              usedImageUrls.add(thumbnailUrl);
            }

            debugPrint('[PostExport] 삭제할 이미지 URL 개수: ${usedImageUrls.length}');

            // 2. 편집 모드 디스크 캐시 삭제
            if (usedImageUrls.isNotEmpty) {
              await EditImageCacheManager.instance.removeCachesForUrls(
                usedImageUrls,
              );
              debugPrint('[PostExport] ✅ 편집 모드 디스크 캐시 삭제 완료');
            }

            // 3. 임시저장 삭제
            final draftService = DraftService();
            final deleted = await draftService.deleteDraft(draftId);
            if (deleted) {
              debugPrint('[PostExport] ✅ 임시저장 삭제 완료: $draftId');
            } else {
              debugPrint('[PostExport] ⚠️ 임시저장 삭제 실패: $draftId');
            }

            // 4. 자동저장 삭제 (발행 성공 시 항상 삭제)
            await draftService.clearAutoDraft();
            debugPrint('[PostExport] ✅ 자동저장 삭제 완료');
          } catch (e) {
            debugPrint('[PostExport] ⚠️ 임시저장/캐시 삭제 중 오류 (무시): $e');
            // 발행은 성공했으므로 오류를 무시하고 계속 진행
          }
        });
      } else {
        // ✅ sessionKey가 없거나 draft_로 시작하지 않아도 자동저장은 삭제
        // (자동저장에서 발행한 경우를 대비)
        Future.microtask(() async {
          try {
            final draftService = DraftService();
            await draftService.clearAutoDraft();
            debugPrint('[PostExport] ✅ 자동저장 삭제 완료 (임시저장 없음)');
          } catch (e) {
            debugPrint('[PostExport] ⚠️ 자동저장 삭제 중 오류 (무시): $e');
          }
        });
      }

      // 스티커 캔버스 청소
      try {
        context.read<StickerService>().removeAll();
      } catch (_) {}

      // 이미지 매핑 정리 로직 제거됨

      try {
        final feedProvider = context.read<MyProfileFeedProvider>();
        final newPostId = uploadResult['id']?.toString();

        // 🎯 피드 업데이트 전에 VideoCache 재사용 차단
        // 피드가 업데이트되면서 프로필 화면이 리빌드될 때 CardView/ImageView가
        // VideoCache 컨트롤러를 재사용하지 못하도록 막아 위젯 트리 변경 중 충돌 방지
        final videoCache = VideoCacheService();
        try {
          videoCache.pauseAll();
          videoCache.blockReuse();
          debugPrint('[PostExport] 게시 전 VideoCache 재사용 차단 완료');
        } catch (e) {
          debugPrint('[PostExport] VideoCacheService 차단 오류: $e');
        }

        // 🎯 새 글 발행 후 피드 새로고침
        await feedProvider.refresh().catchError((e) {
          debugPrint('[PostExport] 백그라운드 재로드 실패: $e');
        });
        debugPrint('[PostExport] 백그라운드 재로드 시작');

        // 🎯 피드 업데이트 완료 후 재사용 차단 해제
        try {
          videoCache.unblockReuse();
          debugPrint('[PostExport] VideoCache 재사용 차단 해제 완료');
        } catch (e) {
          debugPrint('[PostExport] VideoCacheService 차단 해제 오류: $e');
        }

        // 🎯 새로 발행한 글을 해당 카테고리의 맨 앞에 배치 (서버 동기화 포함)
        // 실패해도 시스템이 뻑나지 않도록 안전하게 처리
        if (newPostId != null) {
          // refresh() 완료 후 약간의 지연을 두고 새 글을 맨 앞으로 이동
          // (서버 응답이 완전히 처리된 후에 이동하기 위해)
          Future.delayed(const Duration(milliseconds: 100), () async {
            try {
              // 🎯 moveNewPostToFront 전에도 VideoCache 재사용 차단
              // moveNewPostToFront 내부에서 notifyListeners()가 호출되어
              // 프로필 화면이 리빌드될 때 위젯 트리 충돌 방지
              final videoCache = VideoCacheService();
              try {
                videoCache.pauseAll();
                videoCache.blockReuse();
                debugPrint(
                  '[PostExport] moveNewPostToFront 전 VideoCache 재사용 차단 완료',
                );
              } catch (e) {
                debugPrint('[PostExport] VideoCacheService 차단 오류: $e');
              }

              await feedProvider.moveNewPostToFront(newPostId);
              debugPrint('[PostExport] 새 글을 맨 앞에 배치 완료: $newPostId');

              // 🎯 moveNewPostToFront 완료 후 재사용 차단 해제
              try {
                videoCache.unblockReuse();
                debugPrint(
                  '[PostExport] moveNewPostToFront 후 VideoCache 재사용 차단 해제 완료',
                );
              } catch (e) {
                debugPrint('[PostExport] VideoCacheService 차단 해제 오류: $e');
              }
            } catch (e, stackTrace) {
              // 에러 발생해도 시스템이 뻑나지 않도록 안전하게 처리
              debugPrint('[PostExport] ⚠️ 새 글 맨 앞 배치 실패 (시스템은 정상 동작): $e');
              debugPrint('[PostExport] 스택 트레이스: $stackTrace');
              // 에러를 다시 throw하지 않음 - 글 발행은 이미 성공했으므로
            }
          });
        }

        // 🎯 포스트 생성 후 관련 그룹의 postCount 및 포스트 캐시 동기화
        final groupProvider = context.read<GroupProvider>();

        // 🎯 GROUPS 공개범위: 선택된 그룹들의 postCount 업데이트 및 포스트 캐시 무효화
        if (scopeLabel == 'GROUPS' && _selectedAudienceGroupIds.isNotEmpty) {
          final groupIdToDelta = <int, int>{};
          for (final groupId in _selectedAudienceGroupIds) {
            groupIdToDelta[groupId] = 1; // 포스트 생성으로 +1
          }
          groupProvider.updateMultipleGroupsPostCount(groupIdToDelta);

          // 🎯 그룹 포스트 캐시 무효화 (동기화)
          ManageGroupScreen.invalidateMultipleGroupsPostsCache(
            _selectedAudienceGroupIds.toList(),
          );

          debugPrint(
            '[PostExport] 관련 그룹 postCount 및 포스트 캐시 동기화 완료: ${_selectedAudienceGroupIds.length}개 그룹',
          );
        }
        // 🎯 FRIENDS 공개범위: allFriends 그룹의 postCount 업데이트 및 포스트 캐시 무효화
        // ManageGroupScreen에서는 -1을 allFriends 그룹 ID로 사용하므로 -1도 함께 등록
        else if (scopeLabel == 'FRIENDS') {
          final allFriendsGroupId = groupProvider.allFriendsGroupId;
          final groupIdToDelta = <int, int>{};
          // 실제 그룹 ID로 업데이트 (postCount 업데이트용)
          if (allFriendsGroupId != null) {
            groupIdToDelta[allFriendsGroupId] = 1;
          }
          // ManageGroupScreen에서 사용하는 -1도 함께 등록 (스마트 감지기용)
          groupIdToDelta[-1] = 1;
          groupProvider.updateMultipleGroupsPostCount(groupIdToDelta);

          // 🎯 allFriends 그룹 포스트 캐시 무효화 (동기화)
          ManageGroupScreen.invalidateGroupPostsCache(-1);

          debugPrint('[PostExport] allFriends 그룹 postCount 및 포스트 캐시 동기화 완료');
        }
        // PUBLIC/PRIVATE는 그룹 postCount에 영향 없음
      } catch (e) {
        debugPrint('[PostExport] 백그라운드 재로드 실패: $e');
      }

      if (!mounted) return;

      // 🎯 게시 전에 비디오 썸네일이면 미리 추출 (동기 처리)
      String? preExtractedThumbnailPath;
      final thumbnailUrl = _exportedThumbnailImageUrl;
      if (thumbnailUrl.isNotEmpty) {
        final url = thumbnailUrl.toLowerCase();
        final isVideo =
            url.endsWith('.mp4') ||
            url.endsWith('.mov') ||
            url.endsWith('.avi') ||
            url.contains('/video/') ||
            url.contains('video');

        if (isVideo) {
          debugPrint('[PostExport] 비디오 썸네일 미리 추출 시작: $thumbnailUrl');
          try {
            final tempDir = await getTemporaryDirectory();
            final thumbnailPath = await VideoThumbnail.thumbnailFile(
              video: thumbnailUrl,
              thumbnailPath: tempDir.path,
              imageFormat: ImageFormat.PNG,
              maxHeight: 1920,
              quality: 90,
            );
            if (thumbnailPath != null) {
              preExtractedThumbnailPath = thumbnailPath;
              debugPrint('[PostExport] 비디오 썸네일 추출 완료: $thumbnailPath');
            }
          } catch (e) {
            debugPrint('[PostExport] 비디오 썸네일 추출 실패: $e');
            // 실패해도 계속 진행 (원본 URL 사용)
          }
        }
      }

      if (!mounted) return;

      // 🎯 등록 완료 애니메이션 실행
      _intro.duration = const Duration(milliseconds: 250);
      await _intro.reverse();
      _intro.duration = const Duration(milliseconds: 800);

      if (!mounted) return;

      // 🎯 게시 완료 후 화면 이동 플로우 재설계
      // 1. PostExportScreen을 제거하고
      // 2. SharePostOverlay를 pushReplacement로 표시하여 PostwriteScreen을 대체

      // NavigatorState를 미리 저장
      final navigator = Navigator.of(context);

      // PostExportScreen 제거
      navigator.pop();

      // 다음 프레임에서 SharePostOverlay를 pushReplacement로 표시 (PostwriteScreen을 대체)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        SharePostOverlay.show(
          context,
          postId: uploadResult['id']?.toString() ?? '',
          title: uploadResult['title']?.toString() ?? '',
          summary: uploadResult['summary']?.toString() ?? '',
          authorUsername: uploadResult['author']?.toString() ?? '',
          authorProfileImageUrl:
              uploadResult['authorProfileImageUrl']?.toString(),
          thumbnailUrl: thumbnailUrl,
          preExtractedThumbnailPath: preExtractedThumbnailPath,
          readTime: (uploadResult['readTime'] as int?) ?? 1,
          isNewPost: true, // 🎯 최초 등록
          uploadedData: uploadResult, // 🎯 전체 데이터 전달 (썸네일 포함)
          useReplacement: true,
        );
      });
    } catch (e) {
      debugPrint('Upload failed: $e');

      if (!mounted) return;

      // 🎯 실패 UX: 스낵바 대신 재시도/취소 바텀시트 (등록/발행)
      final action = await RetryCancelBottomSheet.show(
        context,
        title: context.tr('publish_failed_title'),
        message: context.tr('retry_error_message'),
        details: e.toString(),
      );
      if (!mounted) return;
      if (action == RetryCancelAction.retry) {
        await _publish();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// 🎯 URL이 비디오인지 확인하는 헬퍼 메서드
  static bool _isVideoUrl(String url) {
    if (url.isEmpty) return false;
    final lowerUrl = url.toLowerCase();
    return lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.mov') ||
        lowerUrl.endsWith('.m4v') ||
        lowerUrl.contains('/videos/') ||
        lowerUrl.contains('video');
  }

  Widget _buildDynamicBackground() {
    return Positioned.fill(
      child: Stack(
        children: [
          // 썸네일 이미지 또는 단색 배경
          Positioned.fill(
            child:
                // 우선순위: 로컬 썸네일 > 서버 URL (비디오/이미지) > 기본 배경
                _localThumbnailFile != null
                    ? Image.file(_localThumbnailFile!, fit: BoxFit.cover)
                    : _exportedThumbnailImageUrl.isNotEmpty
                    ? Builder(
                      builder: (context) {
                        // 🎯 비디오 URL인 경우: 비디오 플레이어 표시
                        if (_isVideoUrl(_exportedThumbnailImageUrl)) {
                          if (_videoController != null) {
                            try {
                              if (_videoController!.value.isInitialized) {
                                final size = _videoController!.value.size;
                                return FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: size.width,
                                    height: size.height,
                                    child: VideoPlayer(_videoController!),
                                  ),
                                );
                              }
                            } catch (e) {
                              debugPrint('[PostExportScreen] 비디오 컨트롤러 오류: $e');
                            }
                          }
                          // 비디오 컨트롤러가 없거나 초기화되지 않은 경우 shimmer 표시
                          return ShimmerBox(
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: BorderRadius.zero,
                          );
                        }

                        // 🎯 이미지 URL인 경우: EditorImageProvider를 사용하여 step1_thumbnail_edit과
                        // 동일한 캐시 키(ResizeImage)를 사용하여 캐시 재사용률을 높임
                        final screenWidth = MediaQuery.sizeOf(context).width;
                        final decodeWidth =
                            EditorImageProvider.editingDecodeWidth(
                              context,
                              screenWidth,
                            );
                        final built = EditorImageProvider.build(
                          url: _exportedThumbnailImageUrl,
                          isEditing: true, // 배경 이미지도 편집 모드
                          decodeWidth: decodeWidth,
                        );

                        return Image(
                          image: built.effectiveProvider,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          gaplessPlayback: true, // ✅ provider가 바뀌어도 기존 프레임 유지
                          frameBuilder: (context, child, frame, wasSyncLoaded) {
                            if (wasSyncLoaded || frame != null) {
                              return child;
                            }
                            // 로딩 중: shimmer placeholder
                            return ShimmerBox(
                              width: double.infinity,
                              height: double.infinity,
                              borderRadius: BorderRadius.zero,
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            assert(() {
                              debugPrint(
                                '[PostExportScreen] ❌ 배경 이미지 로드 실패: url=$_exportedThumbnailImageUrl, error=$error',
                              );
                              return true;
                            }());
                            return Container(color: AppColors.darkSurface);
                          },
                        );
                      },
                    )
                    : Container(color: Theme.of(context).colorScheme.surface),
          ), // 블러 오버레이 (썸네일이 있을 때만)
          if (_localThumbnailFile != null ||
              _exportedThumbnailImageUrl.isNotEmpty)
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const ui.Color.fromARGB(
                          235,
                          45,
                          45,
                          45,
                        ).withOpacity(0.7),
                        const ui.Color.fromARGB(
                          235,
                          45,
                          45,
                          45,
                        ).withOpacity(0.7),
                        const ui.Color.fromARGB(
                          235,
                          45,
                          45,
                          45,
                        ).withOpacity(0.7),
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 업로드 상태 체크 헬퍼
  bool _hasActiveUploads() {
    if (!mounted || !context.mounted) return false;
    try {
      final upload = context.read<UploadService>();
      return upload.hasActiveUploads(
        kinds: {UploadKind.editorImage, UploadKind.video, UploadKind.thumbnail},
      );
    } catch (e) {
      debugPrint('[PostExport] 업로드 상태 체크 오류: $e');
      return false;
    }
  }

  /// 업로드 태스크 취소 헬퍼
  void _cancelUploadTasks() {
    if (!mounted) return;
    try {
      final upload = context.read<UploadService>();
      upload.cancelByRef('thumb_$_nsKey');
      upload.cancelEditorCompressions('publish_$_nsKey');
    } catch (e) {
      debugPrint('[PostExport] 업로드 태스크 취소 오류: $e');
    }
  }

  void _nextStep() {
    if (_isUploadingThumb || _hasActiveUploads()) return;

    if (_currentStep < _totalSteps - 1) {
      FocusScope.of(context).unfocus();
      setState(() {
        _currentStep++;
        _editMode = false;
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      FocusScope.of(context).unfocus();
      setState(() {
        _currentStep--;
        _editMode = false;
      });
    }
  }

  bool _canProceedToNextStep() {
    switch (_currentStep) {
      case 0: // Step 1: 썸네일 & 글 편집
        // 🎯 썸네일, 제목, 요약이 모두 있어야 다음 버튼 활성화
        final editedTitle = _titleController.text.trim();
        final editedExcerpt = _excerptController.text.trim();
        final thumbnailUrl = _exportedThumbnailImageUrl.trim();
        final isHttpUrl =
            thumbnailUrl.startsWith('http://') ||
            thumbnailUrl.startsWith('https://');

        // 🎯 업로드 중이면 비활성화
        if (_isUploadingThumb || _hasActiveUploads()) {
          return false;
        }

        // 🎯 썸네일, 제목, 요약이 모두 있어야 함
        final hasThumbnail = thumbnailUrl.isNotEmpty && isHttpUrl;
        final hasTitle = editedTitle.isNotEmpty;
        final hasExcerpt = editedExcerpt.isNotEmpty;

        return hasThumbnail && hasTitle && hasExcerpt;
      case 1: // Step 2: 공개 범위
        // 전체공개, 나만보기, 전체 친구 또는 그룹 중 하나는 선택되어야 함
        return _audienceSelectAll ||
            _audiencePrivateOnly ||
            _audienceFriendsOnly ||
            _selectedAudienceGroupIds.isNotEmpty;
      case 2: // Step 3: 카테고리
        // 🎯 카테고리가 실제로 선택되어 있어야 다음 버튼 활성화
        return _selectedCategoryId != null;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardRadius = 12.0; // PostCard와 동일한 라운드

    return WillPopScope(
      onWillPop: () async {
        // 🎯 업로드 중에는 뒤로 가기 완전 차단
        if (_isUploading || _isUploadingThumb) {
          return false;
        }

        if (_currentStep > 0) {
          _previousStep();
          return false;
        }

        // Step 0에서 뒤로가기 시 부드러운 애니메이션과 함께 닫기
        await _closeWithAnimation();
        return false; // WillPopScope가 직접 처리하지 않도록 false 반환
      },
      child: FadeTransition(
        opacity: _intro,
        child: Stack(
          children: [
            _buildDynamicBackground(),
            Scaffold(
              backgroundColor: Colors.transparent,
              extendBodyBehindAppBar: true,
              appBar: _editMode ? _buildFocusAppBar() : _buildNormalAppBar(),
              body: SafeArea(
                child: IndexedStack(
                  index: _currentStep,
                  children: [
                    Step1ThumbnailEdit(
                      sessionKey: _nsKey,
                      cardRadius: cardRadius,
                      titleController: _titleController,
                      excerptController: _excerptController,
                      titleFocusNode: _titleFocusNode,
                      excerptFocusNode: _excerptFocusNode,
                      exportedThumbnailImageUrl: _exportedThumbnailImageUrl,
                      editMode: _editMode,
                      isUploadingThumb: _isUploadingThumb,
                      localThumbnailFile: _localThumbnailFile,
                      localVideoFile: _localVideoFile,
                      videoController: _videoController,
                      controller: _controller,
                      onThumbnailUrlChanged: (url) {
                        setState(() {
                          _exportedThumbnailImageUrl = url;
                        });
                      },
                      onLocalThumbnailChanged: (file) {
                        setState(() {
                          _localThumbnailFile = file;
                        });
                      },
                      onLocalVideoChanged: (file) {
                        setState(() {
                          _localVideoFile = file;
                        });
                      },
                      onVideoControllerChanged: (controller) {
                        // 🎯 기존 컨트롤러 안전하게 정리
                        if (_videoController != null &&
                            _videoController != controller) {
                          // 🎯 서버 비디오 컨트롤러인 경우 _cachedVideoUrl 초기화
                          if (_cachedVideoUrl != null) {
                            _cachedVideoUrl = null;
                          }
                          _disposeVideoController(
                            context: 'onVideoControllerChanged',
                          );
                        }

                        // 🎯 새 컨트롤러 설정 및 리스너 추가
                        _videoController = controller;
                        if (controller != null) {
                          _localVideoFile = null; // Step1에서 새로 생성한 컨트롤러
                          _cachedVideoUrl = null; // 로컬 비디오이므로 서버 비디오 URL 초기화
                          try {
                            // 🎯 dispose 체크: 컨트롤러 유효성 확인
                            if (!controller.value.isInitialized) {
                              // 🎯 리스너 추가 전 dispose 체크
                              try {
                                controller.addListener(
                                  _onVideoControllerInitialized,
                                );
                              } catch (e) {
                                debugPrint(
                                  '[PostExport] 리스너 추가 오류 (dispose됨): $e',
                                );
                                _videoController = null;
                                return;
                              }
                            } else {
                              // 이미 초기화된 경우 즉시 재생
                              if (mounted) {
                                try {
                                  // 🎯 dispose 체크: 컨트롤러 유효성 재확인
                                  if (controller.value.isInitialized) {
                                    controller.play();
                                    controller.setLooping(true);
                                  }
                                } catch (e) {
                                  debugPrint(
                                    '[PostExport] 새 컨트롤러 재생 오류 (dispose됨): $e',
                                  );
                                }
                              }
                            }
                          } catch (e) {
                            debugPrint(
                              '[PostExport] 새 컨트롤러 설정 오류 (dispose됨): $e',
                            );
                          }
                        }

                        if (mounted) {
                          setState(() {});
                        }
                      },
                      onIsUploadingThumbChanged: (value) {
                        setState(() {
                          _isUploadingThumb = value;
                        });
                      },
                      onEditModeChanged: (value) {
                        setState(() {
                          _editMode = value;
                        });
                      },
                      // ✅ Step1 내부에서 포커스/애니메이션을 관리한다.
                      // (중복 리스너로 인한 불필요한 setState 루프 방지)
                      onEditFocusChange: () {},
                    ),
                    Step2AudienceSelection(
                      selectedAudienceGroupIds: _selectedAudienceGroupIds,
                      audienceSelectAll: _audienceSelectAll,
                      audiencePrivateOnly: _audiencePrivateOnly,
                      audienceFriendsOnly: _audienceFriendsOnly,
                      onAudienceSelectAllChanged: (value) {
                        setState(() {
                          _audienceSelectAll = value;
                          if (value) {
                            _audiencePrivateOnly = false;
                            _audienceFriendsOnly = false;
                            _selectedAudienceGroupIds.clear();
                          }
                        });
                      },
                      onAudiencePrivateOnlyChanged: (value) {
                        setState(() {
                          _audiencePrivateOnly = value;
                          if (value) {
                            _audienceSelectAll = false;
                            _audienceFriendsOnly = false;
                            _selectedAudienceGroupIds.clear();
                          }
                        });
                      },
                      onAudienceFriendsOnlyChanged: (value) {
                        setState(() {
                          _audienceFriendsOnly = value;
                          if (value) {
                            _audienceSelectAll = false;
                            _audiencePrivateOnly = false;
                            _selectedAudienceGroupIds.clear();
                          }
                        });
                      },
                      onSelectedAudienceGroupIdsChanged: (ids) {
                        setState(() {
                          _selectedAudienceGroupIds.clear();
                          _selectedAudienceGroupIds.addAll(ids);
                        });
                      },
                      showGroupLoading: _showGroupLoading,
                      isGroupLoadingStarted: _isGroupLoadingStarted,
                      onShowGroupLoadingChanged: (value) {
                        setState(() {
                          _showGroupLoading = value;
                        });
                      },
                      onIsGroupLoadingStartedChanged: (value) {
                        setState(() {
                          _isGroupLoadingStarted = value;
                        });
                      },
                    ),
                    Step3CategorySelection(
                      selectedCategoryId: _selectedCategoryId,
                      onSelectedCategoryIdChanged: (id) {
                        if (!_isUploading) {
                          setState(() {
                            _selectedCategoryId = id;
                          });
                        }
                      },
                      cachedCategories: _cachedCategories,
                      onCachedCategoriesChanged: (categories) {
                        setState(() {
                          _cachedCategories = categories;
                        });
                      },
                      isLoadingCategories: _isLoadingCategories,
                      onIsLoadingCategoriesChanged: (value) {
                        setState(() {
                          _isLoadingCategories = value;
                        });
                      },
                      showCategoryLoading: _showCategoryLoading,
                      onShowCategoryLoadingChanged: (value) {
                        setState(() {
                          _showCategoryLoading = value;
                        });
                      },
                      isUploading: _isUploading, // 🎯 발행 중 상태 전달
                      isActive: _currentStep == 2, // 🎯 step3가 활성화되어 있을 때만 true
                    ),
                  ],
                ),
              ),
            ),

            // 업로드 중 전체 화면 오버레이 (0.8초 후에만 표시)
          ],
        ),
      ),
    );
  }

  // 포커스 상태의 간단한 앱바 (완료 버튼만)
  PreferredSizeWidget _buildFocusAppBar() {
    // 1단계(Step 0)이고 이미지가 없을 때만 테마 색상 사용
    final textColor =
        _currentStep == 0 && _exportedThumbnailImageUrl.isEmpty
            ? Theme.of(context).colorScheme.onSurface
            : AppColors.darkTextPrimary;

    return AppBar(
      toolbarHeight: 53,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      centerTitle: true,

      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: TextButton(
            onPressed: () {
              // 🎯 수정완료 시 명시적으로 포커스 노드 모두 해제
              _titleFocusNode.unfocus();
              _excerptFocusNode.unfocus();
              FocusScope.of(context).unfocus();

              setState(() {
                _editMode = false;
              });
              _controller.reverse();

              // 추가로 포커스가 완전히 해제될 때까지 약간 대기
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) {
                  _titleFocusNode.unfocus();
                  _excerptFocusNode.unfocus();
                  FocusScope.of(context).unfocus();
                }
              });
            },
            child: Text(
              context.tr('modify_complete'),
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 일반 상태의 앱바 (진행바와 다음/업로드 버튼)
  PreferredSizeWidget _buildNormalAppBar() {
    // 1단계(Step 0)이고 이미지가 없을 때만 테마 색상 사용
    final textColor =
        _currentStep == 0 && _exportedThumbnailImageUrl.isEmpty
            ? Theme.of(context).colorScheme.onSurface
            : AppColors.darkTextPrimary;

    return AppBar(
      toolbarHeight: 50,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 80, // 이전 버튼이 잘리지 않도록 너비 확장
      leading: GestureDetector(
        onTap: () async {
          if (_currentStep > 0) {
            _previousStep();
          } else {
            // Step 0에서 뒤로가기 시 부드러운 애니메이션
            await _closeWithAnimation();
          }
        },
        child: Padding(
          padding: const EdgeInsets.only(left: 20, top: 16),
          child: Text(
            context.tr('previous').length > 4
                ? context.tr('previous').substring(0, 4)
                : context.tr('previous'),
            style: TextStyle(
              color: textColor.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),

      actions: [
        if (_currentStep < _totalSteps - 1)
          GestureDetector(
            onTap: _canProceedToNextStep() ? _nextStep : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                context.tr('next'),
                style: TextStyle(
                  color:
                      _canProceedToNextStep()
                          ? textColor.withOpacity(1)
                          : textColor.withOpacity(0.3),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: TextButton(
              onPressed:
                  _isUploading
                      ? null
                      : () async {
                        final bool canPublish = _canPublish();
                        if (canPublish) {
                          await _publish();
                        } else {
                          String msg = _getPublishErrorMessage();
                          ErrorHandler.showError(context, msg);
                        }
                      },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  );
                },
                child:
                    _isUploading
                        ? Container(
                          key: const ValueKey('loading'),
                          width: 26,
                          height: 26,
                          child: const CircularProgressIndicator(
                            strokeWidth: 4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : Text(
                          context.tr('publish'),
                          key: const ValueKey('text'),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
              ),
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.onSurface.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(textColor),
          ),
        ),
      ),
    );
  }
}
