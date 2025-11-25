import 'dart:convert';
import 'dart:ui' as ui;
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
    _titleFocusNode.addListener(_onEditFocusChange);
    _excerptFocusNode.addListener(_onEditFocusChange);

    // 카테고리는 Step3 컴포넌트에서 로드함
  }

  @override
  void dispose() {
    try {
      _titleFocusNode.removeListener(_onEditFocusChange);
      _excerptFocusNode.removeListener(_onEditFocusChange);

      _titleController.dispose();
      _titleFocusNode.dispose();
      _excerptController.dispose();
      _excerptFocusNode.dispose();

      // 로컬 비디오 컨트롤러는 직접 dispose
      if (_localVideoFile != null && _videoController != null) {
        _videoController?.dispose();
      }

      // 캐시된 서버 비디오는 참조 해제
      if (_cachedVideoUrl != null) {
        VideoCacheService().releaseController(
          _cachedVideoUrl!,
          namespace: 'profile',
        );
      }
    } catch (e) {
      debugPrint('[PostExport] dispose 에러: $e');
    }
    super.dispose();
  }

  void _onEditFocusChange() {
    // Step 1에서만 편집 모드 활성화
    if (_currentStep != 0) return;

    final bool nowEditing =
        _titleFocusNode.hasFocus || _excerptFocusNode.hasFocus;
    if (_editMode != nowEditing) {
      setState(() => _editMode = nowEditing);
      // 🎯 포커스 변화에 따라 애니메이션 실행
      if (nowEditing) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
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

    _exportedThumbnailImageUrl = exportedThumbnailUrl;
    debugPrint('[PostExport] 썸네일 초기화: $_exportedThumbnailImageUrl');

    // 영상 파일만 복원 (persist 사용)
    final svc = NodeComponentService();
    final persistedVideoPath = svc.getTempVideoFilePath(_nsKey);
    final persistedVideoThumbnailPath = svc.getTempVideoThumbnailPath(_nsKey);

    // 영상 파일 복원 (있다면)
    if (persistedVideoPath != null && persistedVideoPath.isNotEmpty) {
      final videoFile = File(persistedVideoPath);
      if (videoFile.existsSync()) {
        _localVideoFile = videoFile;
        _videoController?.dispose();
        _videoController = VideoPlayerController.file(videoFile);
        _videoController!
            .initialize()
            .then((_) {
              if (mounted && _videoController != null) {
                _videoController?.play();
                _videoController?.setLooping(true);
                setState(() {});
              }
            })
            .catchError((error) {
              debugPrint('[PostExport] 비디오 컨트롤러 초기화 실패: $error');
              if (mounted) {
                _videoController?.dispose();
                _videoController = null;
                setState(() {});
              }
            });
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

    // 🎯 Summary는 항상 자동 추출
    final collected = PostContentUtils.collectText(exported);
    _excerpt = PostContentUtils.extractSummary(
      collectedText: collected,
      title: _title,
      maxLength: 100,
    );
    _excerptController.text = _excerpt;
    debugPrint('[PostExport] ℹ️ 자동 추출 summary 사용: $_excerpt');

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

  // 부드러운 애니메이션과 함께 닫기
  Future<void> _closeWithAnimation() async {
    // 닫힐 때는 빠르게 (250ms)
    _intro.duration = const Duration(milliseconds: 250);
    await _intro.reverse();
    // 다시 원래 duration으로 복원
    _intro.duration = const Duration(milliseconds: 800);

    if (!mounted) return;

    Navigator.of(context).pop({
      'thumbnailImageUrl': _exportedThumbnailImageUrl,
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

    // 4. 카테고리는 기본값 0(미지정)이 있으므로 항상 유효

    return true;
  }

  // 등록 불가능할 때 표시할 에러 메시지 (서버 API 스펙 준수)
  String _getPublishErrorMessage() {
    if (_isUploadingThumb) {
      return '이미지 업로드 중입니다.';
    }
    final editedTitle = _titleController.text.trim();
    final editedExcerpt = _excerptController.text.trim();

    if (editedTitle.isEmpty) {
      return '제목을 입력해주세요.';
    }
    if (editedExcerpt.isEmpty) {
      return '본문 내용을 입력해주세요.';
    }
    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return '썸네일 이미지를 먼저 선택하세요.';
    }
    if (!_audienceSelectAll &&
        !_audiencePrivateOnly &&
        !_audienceFriendsOnly &&
        _selectedAudienceGroupIds.isEmpty) {
      return '그룹 공유를 선택했을 경우 최소 1개 이상의 그룹을 선택해주세요.';
    }
    return '등록할 수 없습니다.';
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
      if (_exportedThumbnailImageUrl.trim().isEmpty) {
        ErrorHandler.showError(context, context.tr('thumbnail_required'));
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

      // 스티커 캔버스 청소
      try {
        context.read<StickerService>().removeAll();
      } catch (_) {}

      // 이미지 매핑 정리 로직 제거됨

      try {
        final feedProvider = context.read<MyProfileFeedProvider>();
        feedProvider.refresh().catchError((e) {
          debugPrint('[PostExport] 백그라운드 재로드 실패: $e');
        });
        debugPrint('[PostExport] 백그라운드 재로드 시작');

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

      // 🎯 등록 완료 애니메이션과 함께 현재 화면 닫기
      await _closeWithAnimation();

      if (!mounted) return;

      // 🎯 공유 오버레이를 pushReplacement로 띄우기
      await SharePostOverlay.show(
        context,
        postId: uploadResult['id']?.toString() ?? '',
        title: uploadResult['title']?.toString() ?? '',
        summary: uploadResult['summary']?.toString() ?? '',
        authorUsername: uploadResult['author']?.toString() ?? '',
        authorProfileImageUrl:
            uploadResult['authorProfileImageUrl']?.toString(),
        thumbnailUrl: uploadResult['thumbnailImageUrl']?.toString(),
        readTime: (uploadResult['readTime'] as int?) ?? 1,
        isNewPost: true, // 🎯 최초 등록
        uploadedData: uploadResult, // 🎯 전체 데이터 전달
        useReplacement: true, // 🎯 pushReplacement 사용
      );
    } catch (e) {
      debugPrint('Upload failed: $e');

      if (!mounted) return;

      // 에러 메시지 표시
      ErrorHandler.handleError(context, e, customMessage: '업로드 중 오류가 발생했어요');
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
      child: Stack(
        children: [
          // 썸네일 이미지 또는 단색 배경
          Positioned.fill(
            child:
                // 우선순위: 로컬 썸네일 > 서버 URL > 기본 배경
                _localThumbnailFile != null
                    ? Image.file(_localThumbnailFile!, fit: BoxFit.cover)
                    : _exportedThumbnailImageUrl.isNotEmpty
                    ? Image.network(
                      _exportedThumbnailImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) =>
                              Container(color: AppColors.darkSurface),
                    )
                    : Container(color: Theme.of(context).colorScheme.surface),
          ),
          // 블러 오버레이 (썸네일이 있을 때만)
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

  void _nextStep() {
    // 썸네일 업로드 중이면 진행 불가
    if (_isUploadingThumb) {
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      FocusScope.of(context).unfocus();
      setState(() {
        _currentStep++;
        _editMode = false;
      });

      // 카테고리는 Step3 컴포넌트에서 로드함
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
        final editedTitle = _titleController.text.trim();
        final editedExcerpt = _excerptController.text.trim();
        return _exportedThumbnailImageUrl.isNotEmpty &&
            editedTitle.isNotEmpty &&
            editedExcerpt.isNotEmpty;
      case 1: // Step 2: 공개 범위
        // 전체공개, 나만보기, 전체 친구 또는 그룹 중 하나는 선택되어야 함
        return _audienceSelectAll ||
            _audiencePrivateOnly ||
            _audienceFriendsOnly ||
            _selectedAudienceGroupIds.isNotEmpty;
      case 2: // Step 3: 카테고리
        return true; // 항상 진행 가능
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardRadius = 12.0; // PostCard와 동일한 라운드

    return WillPopScope(
      onWillPop: () async {
        // 업로드 중에는 뒤로 가기 방지
        if (_isUploading) {
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
                        setState(() {
                          _videoController?.dispose();
                          _videoController = controller;
                        });
                      },
                      onIsUploadingThumbChanged: (value) {
                        setState(() {
                          _isUploadingThumb = value;
                        });
                      },
                      onEditModeChanged: (value) {
                        setState(() {
                          _editMode = value;
                          if (value) {
                            _controller.forward();
                          } else {
                            _controller.reverse();
                          }
                        });
                      },
                      onEditFocusChange: _onEditFocusChange,
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
                        setState(() {
                          _selectedCategoryId = id;
                        });
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
              style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
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
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),

      actions: [
        if (_currentStep < _totalSteps - 1)
          TextButton(
            onPressed: _canProceedToNextStep() ? _nextStep : null,
            child: Text(
              context.tr('next'),
              style: TextStyle(
                color:
                    _canProceedToNextStep()
                        ? textColor.withOpacity(1)
                        : textColor.withOpacity(0.3),
                fontWeight: FontWeight.w500,
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
                          width: 20,
                          height: 20,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.5,
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
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
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
