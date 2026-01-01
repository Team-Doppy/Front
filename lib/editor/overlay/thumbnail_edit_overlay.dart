import 'dart:io';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/editor/publish/component/step1_thumbnail_edit.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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

            _isLoading = false;
          });

          // 영상이면 VideoPlayer 초기화 (캐시 사용)
          if (isVideo && thumbnailUrl.isNotEmpty) {
            _cachedVideoUrl = thumbnailUrl;
            _videoController = VideoCacheService().getOrCreateController(
              _cachedVideoUrl!,
              namespace: 'profile',
            );

            // 이미 초기화된 경우 바로 재생, 아니면 리스너 등록 후 재생
            if (_videoController!.value.isInitialized) {
              _videoController!.setLooping(true);
              _videoController!.play();
              if (mounted) setState(() {});
            } else {
              _videoController!.addListener(_onServerVideoInitialized);
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

          _isLoading = false;
        });

        // 영상이면 VideoPlayer 초기화 (캐시 사용)
        if (isVideo && thumbnailUrl.isNotEmpty) {
          _cachedVideoUrl = thumbnailUrl;
          _videoController = VideoCacheService().getOrCreateController(
            _cachedVideoUrl!,
            namespace: 'profile',
          );

          // 이미 초기화된 경우 바로 재생, 아니면 리스너 등록 후 재생
          if (_videoController!.value.isInitialized) {
            _videoController!.setLooping(true);
            _videoController!.play();
            if (mounted) setState(() {});
          } else {
            _videoController!.addListener(_onServerVideoInitialized);
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
    try {
      _videoController?.setVolume(0);
    } catch (_) {}

    // 비디오 컨트롤러는 절대 dispose하지 않음
    // - 캐시된 서버 비디오: VideoCacheService가 관리
    // - 로컬 비디오 (업로드 중): 업로드가 완료될 때까지 유지

    super.dispose();
  }

  void _onServerVideoInitialized() {
    if (_videoController?.value.isInitialized ?? false) {
      _videoController?.removeListener(_onServerVideoInitialized);
      try {
        _videoController?.setLooping(true);
        _videoController?.play();
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  Widget _buildLoadingSkeleton() {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardRadius = 20.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 1),
        // 썸네일 영역 (4:5 비율)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 50.0),
          child: AspectRatio(
            aspectRatio: 4 / 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cardRadius),
              child: ShimmerBox(
                width: screenWidth,
                height: (screenWidth - 100) * 5 / 4,
              ),
            ),
          ),
        ),

        const SizedBox(height: 40),

        // 텍스트 영역 (제목, 요약 쉬머)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            children: [
              // 제목 쉬머 (1줄)
              ShimmerBox(width: screenWidth * 0.6, height: 35),
              const SizedBox(height: 20),
              // 요약 쉬머 (3줄)
              ShimmerBox(width: screenWidth * 0.8, height: 18),
              const SizedBox(height: 8),
              ShimmerBox(width: screenWidth * 0.75, height: 18),
              const SizedBox(height: 8),
              ShimmerBox(width: screenWidth * 0.7, height: 18),
            ],
          ),
        ),

        const Spacer(flex: 3),
        const SizedBox(height: 10),
      ],
    );
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

    // 변경사항 확인
    final titleChanged = title != _originalTitle;
    final summaryChanged = summary != _originalSummary;
    final thumbnailChanged = _thumbnailUrl != _originalThumbnailUrl;

    if (!titleChanged && !summaryChanged && !thumbnailChanged) {
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
    debugPrint('[ThumbnailEditOverlay] 제목 변경: $titleChanged');
    debugPrint('[ThumbnailEditOverlay] 요약 변경: $summaryChanged');
    debugPrint('[ThumbnailEditOverlay] 썸네일 변경: $thumbnailChanged');

    // 🎯 저장 시작 시 로딩 상태 활성화
    if (mounted) {
      setState(() {
        _isSaving = true;
      });
    }

    try {
      // 변경된 항목만 전송
      final String? thumbnailParam =
          thumbnailChanged && _thumbnailUrl.isNotEmpty ? _thumbnailUrl : null;
      final String? titleParam =
          titleChanged ? (title.isNotEmpty ? title : null) : null;
      final String? summaryParam =
          summaryChanged ? (summary.isNotEmpty ? summary : null) : null;

      debugPrint('[ThumbnailEditOverlay] 전송 파라미터:');
      debugPrint('  - thumbnailImageUrl: $thumbnailParam');
      debugPrint('  - title: $titleParam');
      debugPrint('  - summary: $summaryParam');

      await BlogService().updatePostThumbnail(
        postId: int.parse(widget.postId),
        thumbnailImageUrl: thumbnailParam,
        title: titleParam,
        summary: summaryParam,
      );

      debugPrint('[ThumbnailEditOverlay] ✅ 서버 업데이트 성공');
      // 서버 반영 성공 후에만 원본 스냅샷 갱신
      if (thumbnailChanged) {
        _originalThumbnailUrl = _thumbnailUrl;
      }
      if (titleChanged) {
        _originalTitle = title;
      }
      if (summaryChanged) {
        _originalSummary = summary;
      }

      if (mounted) {
        // 제목/요약이 변경되었을 때만 부모에게 알림 (피드 새로고침 트리거)
        if (titleChanged || summaryChanged) {
          widget.onMetadataChanged?.call(title, summary);
          debugPrint('[ThumbnailEditOverlay] 메타데이터 변경 콜백 호출');
        }

        // 썸네일이 변경되었을 때만 onThumbnailChanged 호출 (피드 새로고침 트리거)
        if (thumbnailChanged) {
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
        ErrorHandler.handleError(context, e);
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

  @override
  Widget build(BuildContext context) {
    final cardRadius = 20.0;

    return Scaffold(
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
                    Icons.close,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  onPressed: () async {
                    // 업로드 중인지 확인
                    if (_isUploadingThumb) {
                      final shouldExit = await DialogUtils.showConfirmDialog(
                        context,
                        title: context.tr('uploading_title'),
                        message: context.tr('uploading_message'),
                        confirmText: context.tr('cancel_and_exit'),
                        cancelText: context.tr('continue_upload'),
                      );
                      if (shouldExit == true && mounted) {
                        // 업로드 중이므로 컨트롤러는 정리하지 않고 그냥 나가기
                        Navigator.of(context).pop();
                      }
                      return;
                    }

                    // 썸네일 변경사항이 있는지 확인
                    final thumbnailChanged =
                        _thumbnailUrl != _originalThumbnailUrl;

                    if (thumbnailChanged) {
                      final shouldExit = await DialogUtils.showConfirmDialog(
                        context,
                        title: context.tr('has_changes_title'),
                        message: context.tr('has_changes_message'),
                        confirmText: context.tr('exit'),
                        cancelText: context.tr('cancel'),
                      );
                      if (shouldExit != true) return;
                    }

                    // 변경사항 여부와 관계없이 그냥 나가기
                    if (mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
        actions: [
          // 편집모드: "완료" (편집모드만 종료), 비편집모드: "수정 완료" (서버 저장 후 화면 닫기)
          TextButton(
            onPressed:
                (_isUploadingThumb || _isSaving)
                    ? null // 업로드 중이거나 저장 중이면 비활성화
                    : (_editMode ? _exitEditMode : _saveChanges),
            child:
                (_isSaving && !_editMode)
                    ? SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.onSurface,
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
                            (!_editMode && (_isUploadingThumb || _isSaving))
                                ? Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.3)
                                : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.9),
                      ),
                    ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: AnimatedSwitcher(
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
        child:
            _isLoading
                ? KeyedSubtree(
                  key: const ValueKey('skeleton'),
                  child: _buildLoadingSkeleton(),
                )
                : KeyedSubtree(
                  key: const ValueKey('content'),
                  child: Stack(
                    children: [
                      // 🎯 Step1ThumbnailEdit 재사용
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
                          });
                        },
                        onEditFocusChange: () {},
                      ),

                      // 수정 완료 중 전체 화면 투명 오버레이 (post_export_screen과 동일한 방식)
                      if (_isSaving)
                        Positioned.fill(
                          child: AbsorbPointer(
                            absorbing: true,
                            child: Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.3),
                              child: Center(
                                child: SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
      ),
    );
  }
}
