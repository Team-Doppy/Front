import 'dart:io';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/editor/publish/component/step1_thumbnail_edit.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:doppy/pages/components/access_level_sheet.dart';
import 'package:doppy/pages/components/category_select_sheet.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/editor/utils/post_metadata_change_detector.dart';
import 'package:doppy/pages/components/retry_cancel_bottom_sheet.dart';

/// 🎯 썸네일 편집 오버레이 (Step1ThumbnailEdit 재사용)
class ThumbnailEditOverlay extends StatefulWidget {
  final String postId; // 서버에서 데이터 가져오기용
  final String sessionKey;
  final Function(String url) onThumbnailChanged;
  final Function(String title, String summary)?
  onMetadataChanged; // 제목/요약 변경 콜백

  // 🎯 이미 로드된 데이터 (있으면 메타데이터 재조회 불필요)
  final String? initialTitle;
  final String? initialSummary;
  final String? initialThumbnailUrl;

  const ThumbnailEditOverlay({
    super.key,
    required this.postId,
    required this.sessionKey,
    required this.onThumbnailChanged,
    this.onMetadataChanged,
    this.initialTitle,
    this.initialSummary,
    this.initialThumbnailUrl,
  });

  @override
  State<ThumbnailEditOverlay> createState() => _ThumbnailEditOverlayState();
}

class _ThumbnailEditOverlayState extends State<ThumbnailEditOverlay>
    with TickerProviderStateMixin {
  String _thumbnailUrl = '';
  bool _isUploadingThumb = false;
  bool _isLoading = true;
  bool _isSaving = false; // 🎯 수정완료 저장 중 상태

  File? _localVideoFile; // 영상 선택 시 원본 비디오 파일
  File? _localThumbnailFile; // 로컬 썸네일 파일
  VideoPlayerController? _videoController; // 영상 재생 컨트롤러
  String? _cachedVideoUrl; // 캐시된 비디오 URL (서버 영상용)

  late final TextEditingController _titleController;
  late final TextEditingController _excerptController;
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _excerptFocusNode = FocusNode();
  bool _editMode = false;

  // 원본 데이터 (변경 감지용)
  String _originalTitle = '';
  String _originalSummary = '';
  String _originalThumbnailUrl = '';

  // 카테고리 및 공개범위 정보
  int? _currentCategoryId;
  String _currentAccessLevel = 'PUBLIC';
  List<int>? _currentSharedGroupIds;
  List<String>? _currentSharedGroupNames;

  // 원본 카테고리 및 공개범위 (변경 감지용)
  int? _originalCategoryId;
  String _originalAccessLevel = 'PUBLIC';
  List<int>? _originalSharedGroupIds;

  // 애니메이션 컨트롤러 (Step1ThumbnailEdit에서 필요)
  late final AnimationController _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _excerptController = TextEditingController();
    _titleFocusNode.addListener(_onEditFocusChange);
    _excerptFocusNode.addListener(_onEditFocusChange);
    _loadPostData();
  }

  void _onEditFocusChange() {
    final bool nowEditing =
        _titleFocusNode.hasFocus || _excerptFocusNode.hasFocus;
    if (_editMode != nowEditing) {
      setState(() => _editMode = nowEditing);
    }
  }

  Future<void> _loadPostData() async {
    try {
      // 🎯 이미 로드된 썸네일 데이터가 있고, title/summary도 모두 있으면 메타데이터 재조회 불필요
      if (widget.initialThumbnailUrl != null &&
          widget.initialTitle != null &&
          widget.initialSummary != null) {
        // 🎯 공개범위 정보를 위해 메타데이터 조회 (카테고리는 로컬에서 가져옴)
        final blogService = BlogService();
        final metadata = await blogService.getPostMetadata(widget.postId);

        // 🎯 로컬 피드에서 카테고리 정보 가져오기
        final feedProvider = MyProfileFeedProvider();
        int? localCategoryId;
        for (final categoryId in feedProvider.postsByCategory.keys) {
          final posts = feedProvider.postsByCategory[categoryId]!;
          final foundPost = posts.firstWhere(
            (p) => '${p['id']}' == widget.postId,
            orElse: () => <String, dynamic>{},
          );
          if (foundPost.isNotEmpty) {
            localCategoryId = int.tryParse(categoryId);
            break;
          }
        }

        if (mounted) {
          final title = widget.initialTitle!;
          final summary = widget.initialSummary!;
          final thumbnailUrl = widget.initialThumbnailUrl!;
          // 썸네일이 영상인지 판단
          final url = thumbnailUrl.toLowerCase();
          final isVideo =
              url.endsWith('.mp4') ||
              url.endsWith('.mov') ||
              url.endsWith('.m4v') ||
              url.contains('/videos/') ||
              url.contains('video');

          setState(() {
            // 제목
            _titleController.text = title;
            _originalTitle = title;

            // 요약
            _excerptController.text = summary;
            _originalSummary = summary;

            // 썸네일
            _thumbnailUrl = thumbnailUrl;
            _originalThumbnailUrl = thumbnailUrl;

            // 🎯 카테고리는 로컬에서 가져온 값 사용, 공개범위는 서버에서 가져옴
            _currentCategoryId = localCategoryId;
            _currentAccessLevel =
                metadata['accessLevel'] as String? ?? 'PUBLIC';
            _currentSharedGroupIds = metadata['sharedGroupIds'] as List<int>?;
            _currentSharedGroupNames =
                metadata['sharedGroupNames'] as List<String>?;

            // 원본 카테고리 및 공개범위 저장 (변경 감지용)
            _originalCategoryId = _currentCategoryId;
            _originalAccessLevel = _currentAccessLevel;
            _originalSharedGroupIds =
                _currentSharedGroupIds != null
                    ? List<int>.from(_currentSharedGroupIds!)
                    : null;

            _isLoading = false;
          });

          debugPrint('✅!!!!isVideo: $isVideo');

          // 영상이면 VideoPlayer 초기화 (캐시 사용)
          if (isVideo && thumbnailUrl.isNotEmpty) {
            _cachedVideoUrl = thumbnailUrl;
            _videoController = VideoCacheService().getOrCreateController(
              _cachedVideoUrl!,
              namespace: 'profile',
            );

            // 🎯 dispose 체크: 컨트롤러 유효성 확인
            try {
              // 이미 초기화된 경우 바로 재생, 아니면 리스너 등록 후 재생
              if (_videoController!.value.isInitialized) {
                _videoController!.setLooping(true);
                _videoController!.play();
                if (mounted) setState(() {});
              } else {
                _videoController!.addListener(_onServerVideoInitialized);
              }
            } catch (e) {
              debugPrint(
                '[ThumbnailEditOverlay] 서버 비디오 컨트롤러 설정 오류 (dispose됨): $e',
              );
              _videoController = null;
            }
          }

          debugPrint('[ThumbnailEditOverlay] 기존 데이터 사용 (메타데이터 재조회 생략)');
          debugPrint('  - 제목: ${_titleController.text}');
          debugPrint('  - 요약: ${_excerptController.text}');
          debugPrint('  - 썸네일: $_thumbnailUrl (영상: $isVideo)');
        }
        return;
      }

      // 🎯 기존 데이터가 없으면 메타데이터 조회
      final blogService = BlogService();
      final metadata = await blogService.getPostMetadata(widget.postId);

      // 🎯 로컬 피드에서 카테고리 정보 가져오기
      final feedProvider = MyProfileFeedProvider();
      int? localCategoryId;
      for (final categoryId in feedProvider.postsByCategory.keys) {
        final posts = feedProvider.postsByCategory[categoryId]!;
        final foundPost = posts.firstWhere(
          (p) => '${p['id']}' == widget.postId,
          orElse: () => <String, dynamic>{},
        );
        if (foundPost.isNotEmpty) {
          localCategoryId = int.tryParse(categoryId);
          break;
        }
      }

      if (mounted) {
        final title = metadata['title'] ?? '';
        final summary = metadata['summary'] ?? '';
        final thumbnailUrl = metadata['thumbnailImageUrl'] ?? '';
        // 썸네일이 영상인지 판단
        final url = thumbnailUrl.toLowerCase();
        final isVideo =
            url.endsWith('.mp4') ||
            url.endsWith('.mov') ||
            url.endsWith('.m4v') ||
            url.contains('/videos/') ||
            url.contains('video');

        setState(() {
          // 제목
          _titleController.text = title;
          _originalTitle = title;

          // 요약
          _excerptController.text = summary;
          _originalSummary = summary;

          // 썸네일
          _thumbnailUrl = thumbnailUrl;
          _originalThumbnailUrl = thumbnailUrl;

          // 🎯 카테고리는 로컬에서 가져온 값 사용, 공개범위는 서버에서 가져옴
          _currentCategoryId = localCategoryId;
          _currentAccessLevel = metadata['accessLevel'] as String? ?? 'PUBLIC';
          _currentSharedGroupIds = metadata['sharedGroupIds'] as List<int>?;
          _currentSharedGroupNames =
              metadata['sharedGroupNames'] as List<String>?;

          // 원본 카테고리 및 공개범위 저장 (변경 감지용)
          _originalCategoryId = _currentCategoryId;
          _originalAccessLevel = _currentAccessLevel;
          _originalSharedGroupIds =
              _currentSharedGroupIds != null
                  ? List<int>.from(_currentSharedGroupIds!)
                  : null;

          _isLoading = false;
        });

        // 영상이면 VideoPlayer 초기화 (캐시 사용)
        if (isVideo && thumbnailUrl.isNotEmpty) {
          _cachedVideoUrl = thumbnailUrl;
          _videoController = VideoCacheService().getOrCreateController(
            _cachedVideoUrl!,
            namespace: 'profile',
          );

          // 🎯 dispose 체크: 컨트롤러 유효성 확인
          try {
            // 이미 초기화된 경우 바로 재생, 아니면 리스너 등록 후 재생
            if (_videoController!.value.isInitialized) {
              _videoController!.setLooping(true);
              _videoController!.play();
              if (mounted) setState(() {});
            } else {
              _videoController!.addListener(_onServerVideoInitialized);
            }
          } catch (e) {
            debugPrint(
              '[ThumbnailEditOverlay] 서버 비디오 컨트롤러 설정 오류 (dispose됨): $e',
            );
            _videoController = null;
          }
        }

        debugPrint('[ThumbnailEditOverlay] 메타데이터 로드 완료');
        debugPrint('  - 제목: ${_titleController.text}');
        debugPrint('  - 요약: ${_excerptController.text}');
        debugPrint('  - 썸네일: $_thumbnailUrl (영상: $isVideo)');
      }
    } catch (e) {
      // 실패 시에도 스켈레톤 UI를 유지한다 (무한 쉬머)
      debugPrint('[ThumbnailEditOverlay] 메타데이터 로드 실패 - 쉬머 유지: $e');
      // 의도적으로 _isLoading 상태를 변경하지 않음
    }
  }

  @override
  void dispose() {
    _titleFocusNode.removeListener(_onEditFocusChange);
    _excerptFocusNode.removeListener(_onEditFocusChange);
    _titleController.dispose();
    _titleFocusNode.dispose();
    _excerptController.dispose();
    _excerptFocusNode.dispose();
    _animationController.dispose();

    // 비디오 소리만 끄기 (컨트롤러는 dispose하지 않음)
    // 🎯 dispose 체크: 컨트롤러 유효성 확인
    if (_videoController != null) {
      try {
        // 🎯 dispose 체크: value 접근으로 컨트롤러 유효성 확인
        final _ = _videoController!.value;
        _videoController!.setVolume(0);
      } catch (e) {
        // dispose된 컨트롤러는 무시
        debugPrint('[ThumbnailEditOverlay] dispose 시 볼륨 조절 오류 (dispose됨): $e');
      }
    }

    // 비디오 컨트롤러는 절대 dispose하지 않음
    // - 캐시된 서버 비디오: VideoCacheService가 관리
    // - 로컬 비디오 (업로드 중): 업로드가 완료될 때까지 유지

    super.dispose();
  }

  void _onServerVideoInitialized() {
    // 🎯 dispose 체크: 컨트롤러 유효성 확인
    if (!mounted || _videoController == null) return;

    try {
      // 🎯 dispose 체크: value 접근 전에 컨트롤러 유효성 확인
      final controller = _videoController!;
      final isInitialized = controller.value.isInitialized;

      if (isInitialized) {
        try {
          controller.removeListener(_onServerVideoInitialized);
          controller.setLooping(true);
          controller.play();
          if (mounted) setState(() {});
        } catch (e) {
          debugPrint(
            '[ThumbnailEditOverlay] 서버 비디오 초기화 후 재생 오류 (dispose됨): $e',
          );
        }
      }
    } catch (e) {
      // dispose된 컨트롤러
      debugPrint('[ThumbnailEditOverlay] 서버 비디오 초기화 리스너 오류 (dispose됨): $e');
      // 리스너 제거 시도 (안전하게)
      try {
        _videoController?.removeListener(_onServerVideoInitialized);
      } catch (_) {}
    }
  }

  Future<void> _saveChanges() async {
    final title = _titleController.text.trim();
    final summary = _excerptController.text.trim();

    debugPrint('[ThumbnailEditOverlay] ===== 변경사항 확인 =====');
    debugPrint('[ThumbnailEditOverlay] 원본 제목: "$_originalTitle"');
    debugPrint('[ThumbnailEditOverlay] 현재 제목: "$title"');
    debugPrint('[ThumbnailEditOverlay] 원본 요약: "$_originalSummary"');
    debugPrint('[ThumbnailEditOverlay] 현재 요약: "$summary"');
    debugPrint('[ThumbnailEditOverlay] 원본 썸네일: "$_originalThumbnailUrl"');
    debugPrint('[ThumbnailEditOverlay] 현재 썸네일: "$_thumbnailUrl"');
    debugPrint('[ThumbnailEditOverlay] 원본 카테고리: $_originalCategoryId');
    debugPrint('[ThumbnailEditOverlay] 현재 카테고리: $_currentCategoryId');
    debugPrint('[ThumbnailEditOverlay] 원본 공개범위: $_originalAccessLevel');
    debugPrint('[ThumbnailEditOverlay] 현재 공개범위: $_currentAccessLevel');

    // 🎯 변경사항 확인 (공통 유틸 사용)
    final changeResult = detectPostMetadataChanges(
      currentTitle: title,
      originalTitle: _originalTitle,
      currentSummary: summary,
      originalSummary: _originalSummary,
      currentThumbnailUrl: _thumbnailUrl,
      originalThumbnailUrl: _originalThumbnailUrl,
      currentCategoryId: _currentCategoryId,
      originalCategoryId: _originalCategoryId,
      currentAccessLevel: _currentAccessLevel,
      originalAccessLevel: _originalAccessLevel,
      currentSharedGroupIds: _currentSharedGroupIds,
      originalSharedGroupIds: _originalSharedGroupIds,
    );

    if (!changeResult.hasChanges) {
      debugPrint('[ThumbnailEditOverlay] 변경사항 없음 - 서버 요청 스킵');

      // 변경사항이 없어도 제목/요약을 부모에게 알림 (동기화 유지)
      if (mounted) {
        widget.onMetadataChanged?.call(title, summary);
        Navigator.of(context).pop();
      }
      return;
    }

    debugPrint('[ThumbnailEditOverlay] ===== 변경사항 저장 시작 =====');
    debugPrint('[ThumbnailEditOverlay] postId: ${widget.postId}');
    debugPrint('[ThumbnailEditOverlay] 제목 변경: ${changeResult.titleChanged}');
    debugPrint('[ThumbnailEditOverlay] 요약 변경: ${changeResult.summaryChanged}');
    debugPrint(
      '[ThumbnailEditOverlay] 썸네일 변경: ${changeResult.thumbnailChanged}',
    );
    debugPrint(
      '[ThumbnailEditOverlay] 카테고리 변경: ${changeResult.categoryChanged}',
    );
    debugPrint(
      '[ThumbnailEditOverlay] 공개범위 변경: ${changeResult.hasAccessLevelChanges}',
    );

    // 🎯 저장 시작 시 로딩 상태 활성화
    if (mounted) {
      setState(() {
        _isSaving = true;
      });
    }

    try {
      // 변경된 항목만 전송
      final String? thumbnailParam =
          changeResult.thumbnailChanged && _thumbnailUrl.isNotEmpty
              ? _thumbnailUrl
              : null;
      final String? titleParam =
          changeResult.titleChanged ? (title.isNotEmpty ? title : null) : null;
      final String? summaryParam =
          changeResult.summaryChanged
              ? (summary.isNotEmpty ? summary : null)
              : null;

      debugPrint('[ThumbnailEditOverlay] 전송 파라미터:');
      debugPrint('  - thumbnailImageUrl: $thumbnailParam');
      debugPrint('  - title: $titleParam');
      debugPrint('  - summary: $summaryParam');

      final blogService = BlogService();

      // 썸네일/제목/요약 변경이 있으면 업데이트
      if (changeResult.hasMetadataChanges) {
        await blogService.updatePostThumbnail(
          postId: int.parse(widget.postId),
          thumbnailImageUrl: thumbnailParam,
          title: titleParam,
          summary: summaryParam,
        );
      }

      // 카테고리 변경이 있으면 업데이트
      if (changeResult.categoryChanged && _currentCategoryId != null) {
        await blogService.movePostToCategory(
          postId: int.parse(widget.postId),
          targetCategoryId: _currentCategoryId!,
        );

        // 🎯 피드 프로바이더에서 로컬 피드 구조 재배치
        try {
          final feedProvider = MyProfileFeedProvider();
          feedProvider.movePostLocally(widget.postId, _currentCategoryId!);
          debugPrint(
            '[ThumbnailEditOverlay] 피드 프로바이더 로컬 재배치 완료: postId=${widget.postId}, categoryId=$_currentCategoryId',
          );
        } catch (e) {
          debugPrint('[ThumbnailEditOverlay] 피드 프로바이더 로컬 재배치 실패: $e');
        }
      }

      // 공개범위 변경이 있으면 업데이트
      if (changeResult.hasAccessLevelChanges) {
        await blogService.updatePostAccessLevel(
          postId: int.parse(widget.postId),
          accessLevel: _currentAccessLevel,
          sharedGroupIds: _currentSharedGroupIds,
        );

        // 🎯 피드 프로바이더에서 메타데이터 업데이트 (공개범위 변경)
        try {
          final feedProvider = MyProfileFeedProvider();
          feedProvider.updatePostMetadata(
            widget.postId,
            accessLevel: _currentAccessLevel,
            sharedGroupIds: _currentSharedGroupIds,
          );
          debugPrint(
            '[ThumbnailEditOverlay] 피드 프로바이더 메타데이터 업데이트 완료: postId=${widget.postId}, accessLevel=$_currentAccessLevel',
          );
        } catch (e) {
          debugPrint('[ThumbnailEditOverlay] 피드 프로바이더 메타데이터 업데이트 실패: $e');
        }
      }

      debugPrint('[ThumbnailEditOverlay] ✅ 서버 업데이트 성공');
      // 서버 반영 성공 후에만 원본 스냅샷 갱신
      if (changeResult.thumbnailChanged) {
        _originalThumbnailUrl = _thumbnailUrl;
      }
      if (changeResult.titleChanged) {
        _originalTitle = title;
      }
      if (changeResult.summaryChanged) {
        _originalSummary = summary;
      }
      if (changeResult.categoryChanged) {
        _originalCategoryId = _currentCategoryId;
      }
      if (changeResult.hasAccessLevelChanges) {
        _originalAccessLevel = _currentAccessLevel;
        _originalSharedGroupIds =
            _currentSharedGroupIds != null
                ? List<int>.from(_currentSharedGroupIds!)
                : null;
      }

      if (mounted) {
        // 제목/요약이 변경되었을 때만 부모에게 알림 (피드 새로고침 트리거)
        if (changeResult.titleChanged || changeResult.summaryChanged) {
          widget.onMetadataChanged?.call(title, summary);
          debugPrint('[ThumbnailEditOverlay] 메타데이터 변경 콜백 호출');
        }

        // 썸네일이 변경되었을 때만 onThumbnailChanged 호출 (피드 새로고침 트리거)
        if (changeResult.thumbnailChanged) {
          widget.onThumbnailChanged(_thumbnailUrl);
          debugPrint('[ThumbnailEditOverlay] 썸네일 변경 콜백 호출');
        }

        ErrorHandler.showInfo(context, '수정이 완료되었습니다');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[ThumbnailEditOverlay] ❌ 저장 실패: $e');
      if (mounted) {
        setState(() {
          _isSaving = false; // 🎯 저장 실패 시 로딩 상태 해제
        });

        // 🎯 실패 UX: 스낵바 대신 재시도/취소 바텀시트
        final action = await RetryCancelBottomSheet.show(
          context,
          title: context.tr('edit_failed_title'),
          message: context.tr('retry_error_message'),
          details: e.toString(),
        );
        if (!mounted) return;
        if (action == RetryCancelAction.retry) {
          // 재시도
          await _saveChanges();
        }
      }
    } finally {
      // 🎯 저장 완료/실패 모두 로딩 상태 해제 (안전장치)
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _exitEditMode() {
    // 포커스 해제하여 편집모드 종료
    FocusScope.of(context).unfocus();
    setState(() => _editMode = false);
  }

  /// 카테고리 변경 시트 표시
  void _showCategorySheet(BuildContext context) {
    CategorySelectSheet.show(
      context,
      postId: widget.postId,
      currentCategoryId: _currentCategoryId,
      onChanged: (categoryId) {
        if (mounted) {
          setState(() {
            _currentCategoryId = categoryId;
          });
        }
      },
    );
  }

  /// 공개범위 변경 시트 표시
  void _showAccessLevelSheet(BuildContext context) {
    AccessLevelSheet.show(
      context,
      postId: widget.postId,
      currentAccessLevel: _currentAccessLevel,
      currentSharedGroupIds: _currentSharedGroupIds,
      currentSharedGroupNames: _currentSharedGroupNames,
      isBatchMode: false,
      onChanged: (String accessLevel, List<int>? sharedGroupIds) async {
        if (mounted) {
          setState(() {
            _currentAccessLevel = accessLevel;
            _currentSharedGroupIds = sharedGroupIds;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardRadius = 20.0;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: Theme.of(context).colorScheme.background,
            elevation: 0,
            leading:
                _editMode
                    ? null // 편집모드에서는 X 버튼 숨김
                    : IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 24,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.75),
                      ),
                      onPressed: () async {
                        // 업로드 중인지 확인
                        if (_isUploadingThumb) {
                          final shouldExit =
                              await DialogUtils.showConfirmDialog(
                                context,
                                title: context.tr('uploading_title'),
                                message: context.tr('uploading_message'),
                                confirmText: context.tr('cancel_and_exit'),
                                cancelText: context.tr('continue_upload'),
                              );
                          if (shouldExit == true && mounted) {
                            // 🎯 업로드 취소
                            try {
                              final upload = context.read<UploadService>();
                              final thumbRefId = 'thumb_${widget.sessionKey}';
                              upload.cancelByRef(thumbRefId);
                              debugPrint(
                                '[ThumbnailEditOverlay] 업로드 취소: refId=$thumbRefId',
                              );
                            } catch (e) {
                              debugPrint(
                                '[ThumbnailEditOverlay] 업로드 취소 중 오류: $e',
                              );
                            }
                            Navigator.of(context).pop();
                          }
                          return;
                        }

                        // 🎯 변경사항 확인 (공통 유틸 사용)
                        final title = _titleController.text.trim();
                        final summary = _excerptController.text.trim();
                        final changeResult = detectPostMetadataChanges(
                          currentTitle: title,
                          originalTitle: _originalTitle,
                          currentSummary: summary,
                          originalSummary: _originalSummary,
                          currentThumbnailUrl: _thumbnailUrl,
                          originalThumbnailUrl: _originalThumbnailUrl,
                          currentCategoryId: _currentCategoryId,
                          originalCategoryId: _originalCategoryId,
                          currentAccessLevel: _currentAccessLevel,
                          originalAccessLevel: _originalAccessLevel,
                          currentSharedGroupIds: _currentSharedGroupIds,
                          originalSharedGroupIds: _originalSharedGroupIds,
                        );

                        if (changeResult.hasChanges) {
                          final shouldExit =
                              await DialogUtils.showConfirmDialog(
                                context,
                                title: context.tr('has_changes_title'),
                                message: context.tr('has_changes_message'),
                                confirmText: context.tr('exit'),
                                cancelText: context.tr('cancel'),
                              );
                          if (shouldExit != true) return;
                        }

                        // 변경사항이 없거나 확인 다이얼로그에서 나가기 선택한 경우
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
            title:
                (!_editMode &&
                        !_titleFocusNode.hasFocus &&
                        !_excerptFocusNode.hasFocus)
                    ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 카테고리 변경 버튼
                        GestureDetector(
                          onTap: () => _showCategorySheet(context),
                          child: Container(
                            width: 35,
                            height: 35,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            child: Icon(
                              Icons.category_rounded,
                              color: Theme.of(context).colorScheme.surface,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 공개범위 변경 버튼
                        GestureDetector(
                          onTap: () => _showAccessLevelSheet(context),
                          child: Container(
                            width: 35,
                            height: 35,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            child: Icon(
                              Icons.lock_outline_rounded,
                              color: Theme.of(context).colorScheme.surface,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    )
                    : null,
            centerTitle: false,
            actions: [
              // 편집모드: "완료" (편집모드만 종료), 비편집모드: "수정 완료" (서버 저장 후 화면 닫기)
              Builder(
                builder: (context) {
                  // 제목, 요약, 썸네일 중 하나라도 비어있으면 비활성화
                  final title = _titleController.text.trim();
                  final summary = _excerptController.text.trim();
                  final hasTitle = title.isNotEmpty;
                  final hasSummary = summary.isNotEmpty;
                  final hasThumbnail = _thumbnailUrl.isNotEmpty;
                  final isValid = hasTitle && hasSummary && hasThumbnail;

                  // 🎯 변경사항 확인 (공통 유틸 사용)
                  final changeResult = detectPostMetadataChanges(
                    currentTitle: title,
                    originalTitle: _originalTitle,
                    currentSummary: summary,
                    originalSummary: _originalSummary,
                    currentThumbnailUrl: _thumbnailUrl,
                    originalThumbnailUrl: _originalThumbnailUrl,
                    currentCategoryId: _currentCategoryId,
                    originalCategoryId: _originalCategoryId,
                    currentAccessLevel: _currentAccessLevel,
                    originalAccessLevel: _originalAccessLevel,
                    currentSharedGroupIds: _currentSharedGroupIds,
                    originalSharedGroupIds: _originalSharedGroupIds,
                  );

                  final isDisabled =
                      _isUploadingThumb ||
                      _isSaving ||
                      (!_editMode && (!isValid || !changeResult.hasChanges));

                  return TextButton(
                    onPressed:
                        isDisabled
                            ? null
                            : (_editMode ? _exitEditMode : _saveChanges),
                    child:
                        (_isSaving && !_editMode)
                            ? SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            )
                            : Text(
                              _editMode
                                  ? context.tr('done')
                                  : context.tr('modify_complete'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    isDisabled
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.onSurface.withOpacity(0.3)
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.9),
                              ),
                            ),
                  );
                },
              ),
              const SizedBox(width: 10),
            ],
          ),
          body: Stack(
            children: [
              // 메인 콘텐츠
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder:
                    (child, animation) => FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeInOutCubic,
                      ),
                      child: child,
                    ),
                child: KeyedSubtree(
                  key: const ValueKey('content'),
                  child: Stack(
                    children: [
                      Step1ThumbnailEdit(
                        sessionKey: widget.sessionKey,
                        cardRadius: cardRadius,
                        titleController: _titleController,
                        excerptController: _excerptController,
                        titleFocusNode: _titleFocusNode,
                        excerptFocusNode: _excerptFocusNode,
                        exportedThumbnailImageUrl: _thumbnailUrl,
                        editMode: _editMode,
                        isUploadingThumb: _isUploadingThumb,
                        localThumbnailFile: _localThumbnailFile,
                        localVideoFile: _localVideoFile,
                        videoController: _videoController,
                        controller: _animationController,
                        isThumbnailEditMode: true, // 🎯 썸네일 편집 모드
                        isLoading: _isLoading, // 🎯 로딩 중일 때 placeholder 숨김
                        onThumbnailUrlChanged: (url) {
                          setState(() {
                            _thumbnailUrl = url;
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
                            // 🎯 VideoCacheService에서 가져온 컨트롤러는 dispose하지 않음
                            // 로컬 비디오 컨트롤러만 dispose
                            if (_videoController != null &&
                                _cachedVideoUrl == null) {
                              // 로컬 비디오 컨트롤러인 경우에만 dispose
                              try {
                                _videoController?.dispose();
                              } catch (e) {
                                debugPrint(
                                  '[ThumbnailEditOverlay] 컨트롤러 dispose 오류 (무시): $e',
                                );
                              }
                            }
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
                          });
                        },
                        onEditFocusChange: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
