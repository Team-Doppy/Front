import 'dart:convert';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/content_change_detector.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/editor/publish/service/post_publish_service.dart'
    show PostContentUtils, PostExporter;
import 'package:doppy/providers/publish_provider.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/access_level_parser.dart';
import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/editor/publish/component/step1_thumbnail_edit.dart';
import 'package:doppy/pages/components/access_level_sheet.dart'
    show AccessLevelSheet, AccessLevelSelectMode;
import 'package:doppy/image/utils/editor_image_provider.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show cleanupAllVideoPlayers;
import 'package:doppy/pages/components/retry_cancel_bottom_sheet.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/utils/mentioned_usernames_extractor.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/main.dart' show navigatorKey;
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';

void printLarge(String text, {int chunkSize = 800}) {
  final int len = text.length;
  for (int i = 0; i < len; i += chunkSize) {
    final int end = (i + chunkSize < len) ? i + chunkSize : len;
    debugPrint(text.substring(i, end));
  }
}

class PostExportScreen extends StatefulWidget {
  const PostExportScreen({
    super.key,
    required this.exported,
    this.sessionKey,
    this.isEditMode = false,
    this.postId,
    this.initialAccessLevel,
    this.initialExportedForComparison,
    this.initialYear,
    this.initialYearOfWeek,
    this.isOnboardingMode = false, // 🎯 온보딩 모드 여부
  });
  final String exported;
  final String? sessionKey; // 블로그/드래프트별 네임스페이스 키
  final bool isEditMode; // 🎯 수정 모드 여부
  final String? postId; // 🎯 수정 모드일 때 포스트 ID
  final String? initialAccessLevel; // 🎯 수정 모드일 때 초기 공개범위
  final String? initialExportedForComparison; // 🎯 수정 진입 시 원본 exported(JSON)
  final int? initialYear; // 초기 연도
  final int? initialYearOfWeek; // 초기 주차 (1-53)
  final bool isOnboardingMode; // 🎯 온보딩 모드 여부

  @override
  State<PostExportScreen> createState() => _PostExportScreenState();
}

class _PostExportScreenState extends State<PostExportScreen>
    with TickerProviderStateMixin {
  String get _nsKey => widget.sessionKey ?? 'default';

  // 🎯 Step 2, 3 제거됨 - 이제 bottomNavigationBar에서 직접 선택

  // 더미 데이터
  String _exportedThumbnailImageUrl = '';
  // ✅ 썸네일(특히 영상)을 선택/변경했는데, URL 비교 타이밍 때문에 "변경사항 없음"으로 떨어지는 케이스 방지용
  bool _thumbnailTouchedInSession = false;
  String _firstBodyImageUrl = '';
  String _title = '';
  late final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();

  Map<String, dynamic> _exportedBase = <String, dynamic>{};

  bool _editMode = false;

  // 공개 범위 선택 (기본값: 전체공개)
  String _currentAccessLevel = SystemCategoryKeys.public;

  // ✅ 수정 모드: 원본 exported(변경 감지용)
  Map<String, dynamic>? _initialExportedForComparisonMap;

  bool _isUploading = false;
  bool _isUploadingThumb = false;
  bool _showInitialThumbnailShimmer = true; // ✅ 첫 진입: placeholder 대신 쉬머 먼저
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

  // 🎯 dispose()에서 안전하게 사용하기 위해 UploadService 참조 저장
  UploadService? _uploadService;

  @override
  void initState() {
    super.initState();
    // 🎯 수정 진입 시 원본 payload 파싱 (있으면)
    if (widget.initialExportedForComparison != null &&
        widget.initialExportedForComparison!.trim().isNotEmpty) {
      try {
        final decoded =
            jsonDecode(widget.initialExportedForComparison!)
                as Map<String, dynamic>;
        _initialExportedForComparisonMap = decoded;
      } catch (e) {
        debugPrint('[PostExportScreen] initialExportedForComparison 파싱 실패: $e');
        _initialExportedForComparisonMap = null;
      }
    }
    _hydrateFromExported(jsonDecode(widget.exported));
    cleanupAllVideoPlayers();
    _intro.forward();

    // ✅ 첫 프레임에서는 "눌러서 썸네일 선택" 문구가 튀지 않도록 쉬머를 잠깐 보여준다.
    // 이후에는 Step1ThumbnailEdit의 frameBuilder(이미지) / controller 초기화(비디오) 쉬머가 이어받는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 260), () {
        if (!mounted) return;
        setState(() {
          _showInitialThumbnailShimmer = false;
        });
      });
    });

    // 카테고리는 Step3 컴포넌트에서 로드함
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _uploadService = context.read<UploadService>();
  }

  @override
  void dispose() {
    try {
      _titleController.dispose();
      _titleFocusNode.dispose();

      // 🎯 비디오 컨트롤러 정리 (로컬/서버 구분하여 처리)
      // _disposeVideoController 내부에서 _cachedVideoUrl 여부에 따라 처리
      _disposeVideoController(context: 'dispose');

      // 🎯 업로드 태스크 취소 (비동기로 처리하여 위젯 트리 잠금 방지)
      // dispose() 중에는 notifyListeners()가 호출되면 위젯 트리가 잠겨있어 에러 발생
      // 다음 프레임에서 처리하도록 비동기로 실행
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _cancelUploadTasks();
        } catch (e) {
          debugPrint('[PostExport] dispose 후 업로드 태스크 취소 오류: $e');
        }
      });
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

    // ✅ 본문 첫 미디어 URL (이미지 우선, 없으면 영상) - Step1 카드/배경 기본값
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

    // ✅ 썸네일이 비어있으면 "본문 첫 미디어(이미지 우선, 없으면 영상)"를 기본값으로 사용한다.
    // - 카드 + 배경 이미지/영상이 즉시 보여야 함
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

      // 🎯 비디오 URL인 경우: 표준 방식으로 처리
      if (isVideo) {
        _cachedVideoUrl = thumb;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            // 🎯 표준 방식: 직접 컨트롤러 생성
            _videoController = VideoPlayerController.networkUrl(
              Uri.parse(thumb),
              httpHeaders: const {
                'Accept': 'video/*',
                'Connection': 'keep-alive',
              },
              videoPlayerOptions: VideoPlayerOptions(
                mixWithOthers: false,
                allowBackgroundPlayback: false,
              ),
            );

            // 리스너 추가
            _videoController!.addListener(_onVideoControllerInitialized);

            // 초기화 시작
            _videoController!
                .initialize()
                .then((_) {
                  if (!mounted || _videoController == null) return;
                  try {
                    _videoController!.play();
                    _videoController!.setLooping(true);
                    if (mounted) setState(() {});
                  } catch (e) {
                    debugPrint('[PostExport] 초기화 후 설정 오류: $e');
                  }
                })
                .catchError((e) {
                  debugPrint('[PostExport] 초기화 실패: $e');
                });
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

    // ✅ 수정 모드에서는 영상 파일/썸네일 복원을 하지 않음 (서버 원본 사용)
    if (widget.isEditMode) {
      // 수정 모드: 로컬 임시 파일 복원 스킵
      debugPrint('[PostExport] 수정 모드: 영상 파일/썸네일 복원 스킵');
    } else {
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
              debugPrint(
                '[PostExport] 영상 썸네일 복원: $persistedVideoThumbnailPath',
              );
            }
          }
        } else {
          debugPrint('[PostExport] 영상 파일이 존재하지 않음: $persistedVideoPath');
          svc.clearTempVideoFile(_nsKey);
        }
      }
    }

    // 🎯 summary/excerpt 필드 제거됨 - 이제 node를 직접 검사

    // 🎯 수정 모드일 때 초기값 설정, 아니면 exported에서 파싱
    if (widget.isEditMode) {
      // 수정 모드: 전달받은 초기값 사용
      if (widget.initialAccessLevel != null &&
          widget.initialAccessLevel!.isNotEmpty) {
        _currentAccessLevel = widget.initialAccessLevel!;
      }
    } else {
      // 발행 모드: exported에서 파싱
      try {
        // 🎯 공통 파싱 유틸리티 사용
        final level =
            AccessLevelParser.parseAccessLevelString(exported['accessLevel']) ??
            '';

        // 공개범위 초기화
        if (level == SystemCategoryKeys.private) {
          _currentAccessLevel = SystemCategoryKeys.private;
        } else if (level == SystemCategoryKeys.public) {
          _currentAccessLevel = SystemCategoryKeys.public;
        } else if (level == SystemCategoryKeys.friends) {
          _currentAccessLevel = SystemCategoryKeys.friends;
        } else {
          _currentAccessLevel = SystemCategoryKeys.public; // 기본값
        }
      } catch (_) {}
    }
    setState(() {});
  }

  // 🎯 비디오 컨트롤러 안전하게 dispose하는 헬퍼 메서드
  void _disposeVideoController({String? context}) {
    if (_videoController == null) return;

    // 🎯 표준 방식: 모든 컨트롤러 dispose
    try {
      _videoController!.removeListener(_onVideoControllerInitialized);
      if (_videoController!.value.isInitialized) {
        _videoController!.pause();
      }
      _videoController!.dispose();
      debugPrint('[PostExport] ${context ?? "dispose"}: 컨트롤러 dispose 완료');
    } catch (e) {
      debugPrint('[PostExport] ${context ?? "dispose"}: 컨트롤러 dispose 오류: $e');
    }

    _videoController = null;
    _cachedVideoUrl = null;
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
      // 🎯 summary 필드 제거됨
    });
  }

  // 🎯 본문(content)이 있는지 확인하는 헬퍼 함수
  bool _hasContent() {
    try {
      final dynamic content = _exportedBase['content'];
      if (content is Map) {
        final List<dynamic> nodes = List<dynamic>.from(
          content['nodes'] as List? ?? const [],
        );
        // 노드가 하나라도 있으면 본문이 있는 것으로 간주
        return nodes.isNotEmpty;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // 등록 가능 여부 확인 (서버 API 스펙 준수)
  bool _canPublish() {
    // 1. 기본 상태 확인
    if (_isUploading || _isUploadingThumb) {
      return false;
    }

    // 2. 필수 필드 확인 (편집된 내용 기준)
    final editedTitle = _titleController.text.trim();

    if (editedTitle.isEmpty) {
      return false;
    }

    // 🎯 본문(content)이 있는지 확인
    if (!_hasContent()) {
      return false;
    }

    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return false;
    }

    // 3. 공개범위 확인 (항상 선택되어 있음)

    return true;
  }

  // 등록 불가능할 때 표시할 에러 메시지 (서버 API 스펙 준수)
  String _getPublishErrorMessage() {
    if (_isUploadingThumb) {
      return context.tr('image_uploading');
    }
    final editedTitle = _titleController.text.trim();

    if (editedTitle.isEmpty) {
      return context.tr('title_required');
    }

    // 🎯 본문(content)이 있는지 확인
    if (!_hasContent()) {
      return context.tr('content_required');
    }

    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return context.tr('thumbnail_required');
    }
    // 공개범위는 항상 선택되어 있음
    return context.tr('cannot_publish');
  }

  /// 🎯 공통 검증 로직
  String? _validateInputs() {
    final finalTitle = _titleController.text.trim();

    if (finalTitle.isEmpty) {
      return context.tr('title_required');
    }

    if (!_hasContent()) {
      return context.tr('content_required');
    }

    final trimmedThumbnailUrl = _exportedThumbnailImageUrl.trim();
    if (trimmedThumbnailUrl.isEmpty) {
      return context.tr('thumbnail_required');
    }

    final isHttpUrl =
        trimmedThumbnailUrl.startsWith('http://') ||
        trimmedThumbnailUrl.startsWith('https://');
    if (!isHttpUrl) {
      return context.tr('thumbnail_upload_required');
    }

    return null; // 검증 통과
  }

  /// 🎯 수정 모드: 포스트 업데이트
  Future<void> _updatePost() async {
    try {
      // 검증
      final validationError = _validateInputs();
      if (validationError != null) {
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('error'),
          message: validationError,
        );
        return;
      }

      if (widget.postId == null) {
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('error'),
          message: context.tr('invalid_post_id'),
        );
        return;
      }

      cleanupAllVideoPlayers();

      final finalTitle = _titleController.text.trim();
      final content = _exportedBase['content'] as Map<String, dynamic>?;
      if (content == null) {
        throw Exception('본문 데이터를 추출할 수 없습니다.');
      }

      // ✅ 변경 감지 (본문/스티커 + 메타데이터)
      final initialMap = _initialExportedForComparisonMap;
      final initialTitle = (initialMap?['title'] ?? '').toString().trim();
      final initialThumbnail =
          (initialMap?['thumbnailImageUrl'] ?? '').toString().trim();
      final initialAccessLevel =
          AccessLevelParser.parseAccessLevelString(
            initialMap?['accessLevel'],
          ) ??
          (widget.initialAccessLevel?.trim().isNotEmpty ?? false
              ? widget.initialAccessLevel!.trim()
              : SystemCategoryKeys.public);

      final currentThumbnail = _exportedThumbnailImageUrl.trim();
      final currentAccessLevel = _currentAccessLevel.trim();

      final titleChanged = finalTitle != initialTitle;
      final thumbnailChanged = currentThumbnail != initialThumbnail;
      final accessLevelChanged = currentAccessLevel != initialAccessLevel;

      // 본문 변경은 exported(Map) 비교로 판단 (노드 id 등은 ContentChangeDetector에서 무시)
      final contentChanged =
          (initialMap != null)
              ? ContentChangeDetector.hasExportedContentChanged(
                originalExported: initialMap,
                currentExported: _exportedBase,
              )
              : true; // 원본이 없으면 안전하게 변경된 것으로 간주

      final hasAnyChange =
          contentChanged ||
          titleChanged ||
          thumbnailChanged ||
          accessLevelChanged;

      debugPrint(
        '[PostExportScreen] 변경 감지: content=$contentChanged, title=$titleChanged, thumbnail=$thumbnailChanged, accessLevel=$accessLevelChanged',
      );

      // ✅ 썸네일을 "선택/변경"했는데도 URL 비교상 동일해서 '변경사항 없음'으로 떨어지는 케이스 방지
      // - 특히 영상 썸네일은 로컬 상태(영상/포스터) 변화가 먼저 일어나고, URL 반영은 약간 늦을 수 있음
      final hasLocalThumbState =
          _localVideoFile != null || _localThumbnailFile != null;
      if (!hasAnyChange &&
          _thumbnailTouchedInSession &&
          hasLocalThumbState &&
          !thumbnailChanged) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          ErrorHandler.showInfo(
            ctx,
            '썸네일 업로드/반영이 아직 완료되지 않았어요.\n잠시 후 다시 시도해 주세요.',
            duration: const Duration(seconds: 2),
          );
        }
        return;
      }

      if (!hasAnyChange) {
        if (!mounted) return;
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          ErrorHandler.showInfo(
            ctx,
            '변경사항이 없습니다.',
            duration: const Duration(seconds: 2),
          );
        }
        return;
      }

      setState(() {
        _isUploading = true;
      });

      // 사용된 미디어 URL 수집
      final usedImageUrls = PostExporter.collectUsedMediaUrls(_exportedBase);
      final mentionedUsernames = MentionedUsernamesExtractor.extractFromContent(
        content,
      );

      // 🎯 연도와 주차 결정
      int? year;
      int? nthWeek;
      if (widget.initialYear != null && widget.initialYearOfWeek != null) {
        year = widget.initialYear;
        nthWeek = widget.initialYearOfWeek;
      }

      final postIdInt = int.parse(widget.postId!);

      // ✅ 1) 본문이 바뀐 경우만 content 엔드포인트 호출 (필요 시 title도 함께)
      if (contentChanged) {
        await BlogService().updatePostContent(
          postId: postIdInt,
          content: content,
          title: titleChanged ? finalTitle : null,
          usedImageUrls: usedImageUrls,
          mentionedUsernames: mentionedUsernames,
          year: year,
          nthWeek: nthWeek,
        );
      }

      // ✅ 2) 썸네일/제목만 바뀐 경우엔 thumbnail 엔드포인트로 (content는 안 보냄)
      // - contentChanged가 false인데 titleChanged/thumbnailChanged 중 하나라도 true면 여기서 처리
      // - contentChanged가 true일 때는 "썸네일"만 별도로 처리 (제목은 updatePostContent로 처리 가능)
      if (thumbnailChanged || (!contentChanged && titleChanged)) {
        await BlogService().updatePostThumbnail(
          postId: postIdInt,
          thumbnailImageUrl: thumbnailChanged ? currentThumbnail : null,
          title: (!contentChanged && titleChanged) ? finalTitle : null,
        );
      }

      // ✅ 3) 공개범위 변경은 전용 엔드포인트로
      if (accessLevelChanged) {
        await BlogService().updatePostAccessLevel(
          postId: postIdInt,
          accessLevel: currentAccessLevel,
        );
      }

      if (!mounted) return;

      // 🎯 publish처럼 바로 화면 닫기 (PostExportScreen + PostWriteScreen)
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);

      // 🎯 스낵바 표시
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ErrorHandler.showInfo(
          ctx,
          '포스트가 수정되었습니다.',
          duration: const Duration(seconds: 2),
        );
      }

      // 🎯 피드 업데이트 (백그라운드)
      try {
        final feed = MyProfileFeedProvider();
        final exportedForUpdate = Map<String, dynamic>.from(_exportedBase);
        exportedForUpdate['title'] = finalTitle;
        exportedForUpdate['thumbnailImageUrl'] = _exportedThumbnailImageUrl;
        exportedForUpdate['accessLevel'] = _currentAccessLevel;
        exportedForUpdate['id'] = int.parse(widget.postId!);
        feed.updatePostInCache(exportedForUpdate);
        debugPrint('[PostExportScreen] ✅ 피드 업데이트 완료');
      } catch (e) {
        debugPrint('[PostExportScreen] ⚠️ 피드 업데이트 실패: $e');
      }
    } catch (e) {
      debugPrint('Update failed: $e');

      if (!mounted) return;

      final action = await RetryCancelBottomSheet.show(
        context,
        title: context.tr('edit_failed_title'),
        error: e,
      );
      if (!mounted) return;
      if (action == RetryCancelAction.retry) {
        await _updatePost();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// 🎯 발행 모드: 새 포스트 발행
  Future<void> _publish() async {
    try {
      // 검증
      final validationError = _validateInputs();
      if (validationError != null) {
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('error'),
          message: validationError,
        );
        return;
      }

      final finalTitle = _titleController.text.trim();

      int? year;
      int? nthWeek;
      if (widget.initialYear != null && widget.initialYearOfWeek != null) {
        year = widget.initialYear;
        nthWeek = widget.initialYearOfWeek;
        debugPrint(
          '[PostExportScreen] 지정된 연도/주차 사용: year=$year, nthWeek=$nthWeek',
        );
      } else {
        debugPrint(
          '[PostExportScreen] 현재 주차 기준 사용 (initialYear/initialYearOfWeek 없음)',
        );
      }

      // 🎯 아래 모든 로직은 Provider(백그라운드)의 몫
      // - payload 생성/업로드/피드갱신/실패 다이얼로그/완료 ShareOverlay 표시
      context.read<PublishProvider>().startPublish(
        PublishRequest(
          exportedBase: _exportedBase,
          title: finalTitle,
          thumbnailImageUrl: _exportedThumbnailImageUrl,
          accessLevel: _currentAccessLevel,
          year: year,
          nthWeek: nthWeek,
          sessionKey: widget.sessionKey,
          isOnboardingMode: widget.isOnboardingMode, // 🎯 온보딩 모드 전달
        ),
      );

      // 🎯 일반 모드: 요청 던지고 즉시 화면 닫기 (PostExportScreen + PostWriteScreen)
      // ✅ 온보딩 모드: PublishProvider가 즉시 Splash로 네비게이션하므로 여기서 popUntil 하면 레이스가 날 수 있다.
      if (!mounted) return;
      if (!widget.isOnboardingMode) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      debugPrint('Upload failed: $e');

      if (!mounted) return;

      // 🎯 실패 UX: 스낵바 대신 재시도/취소 바텀시트 (등록/발행)
      final action = await RetryCancelBottomSheet.show(
        context,
        title: context.tr('publish_failed_title'),
        error: e,
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

  Widget _buildDynamicBackground() {
    return Positioned.fill(
      child: Container(color: Theme.of(context).colorScheme.surface),
    );
  }

  /// 업로드 태스크 취소 헬퍼
  void _cancelUploadTasks() {
    try {
      // 🎯 dispose()에서도 안전하게 사용하기 위해 저장된 참조 사용
      final upload = _uploadService;
      if (upload != null) {
        upload.cancelByRef('thumb_$_nsKey');
        upload.cancelEditorCompressions('publish_$_nsKey');
      } else if (mounted) {
        // 🎯 mounted 상태이고 참조가 없으면 context에서 가져오기 (일반적인 경우)
        try {
          final uploadFromContext = context.read<UploadService>();
          uploadFromContext.cancelByRef('thumb_$_nsKey');
          uploadFromContext.cancelEditorCompressions('publish_$_nsKey');
        } catch (e) {
          debugPrint('[PostExport] 업로드 태스크 취소 오류 (context): $e');
        }
      }
    } catch (e) {
      debugPrint('[PostExport] 업로드 태스크 취소 오류: $e');
    }
  }

  // 🎯 Step 2, 3 제거됨 - 더 이상 step 이동 없음

  @override
  Widget build(BuildContext context) {
    final cardRadius = 12.0; // PostCard와 동일한 라운드

    return WillPopScope(
      onWillPop: () async {
        // 🎯 업로드 중에는 다이얼로그 표시 후 뒤로 가기 차단
        if (_isUploading || _isUploadingThumb) {
          await DialogUtils.showInfoDialog(
            context,
            title: context.tr('uploading'),
            message:
                _isUploadingThumb
                    ? context.tr('image_uploading')
                    : context.tr('uploading'),
          );
          return false;
        }

        // 뒤로가기 시 부드러운 애니메이션과 함께 닫기
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
                child: GestureDetector(
                  onTap: () {
                    // 🎯 편집 모드가 활성화되어 있을 때 여백을 탭하면 편집 모드 닫기
                    if (_editMode) {
                      _titleFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _editMode = false;
                      });
                      _controller.reverse();
                      // 추가로 포커스가 완전히 해제될 때까지 약간 대기
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (mounted) {
                          _titleFocusNode.unfocus();
                          FocusScope.of(context).unfocus();
                        }
                      });
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Step1ThumbnailEdit(
                    sessionKey: _nsKey,
                    cardRadius: cardRadius,
                    titleController: _titleController,
                    titleFocusNode: _titleFocusNode,
                    exportedThumbnailImageUrl: _exportedThumbnailImageUrl,
                    editMode: _editMode,
                    isUploadingThumb: _isUploadingThumb,
                    isLoading:
                        _showInitialThumbnailShimmer &&
                        _exportedThumbnailImageUrl.trim().isEmpty &&
                        _localThumbnailFile == null &&
                        _localVideoFile == null,
                    localThumbnailFile: _localThumbnailFile,
                    localVideoFile: _localVideoFile,
                    videoController: _videoController,
                    controller: _controller,
                    onThumbnailUrlChanged: (url) {
                      setState(() {
                        _exportedThumbnailImageUrl = url;
                        _thumbnailTouchedInSession = true;
                      });
                    },
                    onLocalThumbnailChanged: (file) {
                      setState(() {
                        _localThumbnailFile = file;
                        if (file != null) _thumbnailTouchedInSession = true;
                      });
                    },
                    onLocalVideoChanged: (file) {
                      setState(() {
                        _localVideoFile = file;
                        if (file != null) _thumbnailTouchedInSession = true;
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
                ),
              ),

              bottomNavigationBar: _buildBottomNavigationBar(),
            ),
          ],
        ),
      ),
    );
  }

  // 포커스 상태의 간단한 앱바 (완료 버튼만)
  PreferredSizeWidget _buildFocusAppBar() {
    final textColor = Theme.of(context).colorScheme.onSurface;

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
              FocusScope.of(context).unfocus();

              setState(() {
                _editMode = false;
              });
              _controller.reverse();

              // 추가로 포커스가 완전히 해제될 때까지 약간 대기
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) {
                  _titleFocusNode.unfocus();
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
    final textColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.75);

    return AppBar(
      toolbarHeight: 56,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,

      // 이전 버튼이 잘리지 않도록 너비 확장
      leading: GestureDetector(
        onTap: () async {
          // 뒤로가기 시 부드러운 애니메이션
          await _closeWithAnimation();
        },
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 24,
          color: textColor,
        ),
      ),

      // 중앙에 year, yearOfWeek 표시 (있는 경우만)
      title:
          widget.initialYear != null && widget.initialYearOfWeek != null
              ? Text(
                '${widget.initialYear}년 ${widget.initialYearOfWeek}주차',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor.withOpacity(0.8),
                ),
              )
              : null,
      centerTitle: true,

      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: TextButton(
            onPressed:
                _isUploading
                    ? null
                    : () async {
                      final bool canPublish = _canPublish();
                      if (canPublish) {
                        // 🎯 수정 모드면 업데이트, 발행 모드면 발행
                        if (widget.isEditMode) {
                          await _updatePost();
                        } else {
                          await _publish();
                        }
                      } else {
                        String msg = _getPublishErrorMessage();
                        await DialogUtils.showInfoDialog(
                          context,
                          title: context.tr('error'),
                          message: msg,
                        );
                      }
                    },
            child:
                _isUploading
                    ? Container(
                      key: const ValueKey('loading'),
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    )
                    : Text(
                      widget.isEditMode
                          ? context.tr('modify_complete')
                          : context.tr('publish'),
                      key: ValueKey(widget.isEditMode ? 'edit' : 'publish'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  // 🎯 공개범위 이름 가져오기
  String _getAccessLevelName(String accessLevel) {
    if (accessLevel == SystemCategoryKeys.private) {
      return context.tr('private');
    } else if (accessLevel == SystemCategoryKeys.friends) {
      return context.tr('friends');
    } else {
      return context.tr('public');
    }
  }

  // 🎯 하단 네비게이션 바 (공개범위 선택)
  Widget _buildBottomNavigationBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
        child: Row(
          children: [
            // 공개범위 선택 버튼
            Expanded(
              child: _buildSelectionButton(
                icon: Icons.lock_outline,
                label: _getAccessLevelName(_currentAccessLevel),
                onTap: () async {
                  // 공개범위 선택 시트 표시 (지정 모드로 호출)
                  AccessLevelSheet.show(
                    context,
                    postId: 'new', // 새 포스트이므로 임시 ID
                    currentAccessLevel: _currentAccessLevel,
                    mode: AccessLevelSelectMode.selectionOnly, // 🎯 지정 모드
                    onChanged: (accessLevel) {
                      setState(() {
                        _currentAccessLevel = accessLevel;
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎯 선택 버튼 위젯
  Widget _buildSelectionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.arrow_drop_up,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
