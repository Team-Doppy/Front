import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/image/native_image_picker.dart';
import 'package:doppy/image/custom_image_editor_screen.dart';
import 'package:doppy/editor/utils/video_upload_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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

class _ThumbnailEditOverlayState extends State<ThumbnailEditOverlay> {
  String _thumbnailUrl = '';
  bool _isUploadingThumb = false;
  bool _isLoading = true;
  bool _isSaving = false; // 🎯 수정완료 저장 중 상태
  bool _isVideo = false; // 썸네일이 영상인지 여부

  File? _localVideoFile; // 영상 선택 시 원본 비디오 파일
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

  // 애니메이션 제거됨

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
      // title/summary는 메타데이터에 있으므로, 없으면 메타데이터를 조회해야 함
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
            _isVideo = isVideo;

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
          _isVideo = isVideo;

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

    // 비디오 소리만 끄기 (컨트롤러는 dispose하지 않음)
    try {
      _videoController?.setVolume(0);
    } catch (_) {}

    // 비디오 컨트롤러는 절대 dispose하지 않음
    // - 캐시된 서버 비디오: VideoCacheService가 관리
    // - 로컬 비디오 (업로드 중): 업로드가 완료될 때까지 유지
    // 앱이 종료될 때 자동으로 정리됨

    super.dispose();
  }

  void _toggleEditMode() {
    setState(() => _editMode = !_editMode);
  }

  void _exitEditMode() {
    // 포커스 해제하여 편집모드 종료
    FocusScope.of(context).unfocus();
    setState(() => _editMode = false);
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

  /// 이미지 편집기 열기
  Future<void> _editCurrentImage() async {
    if (_thumbnailUrl.isEmpty) {
      ErrorHandler.showInfo(context, context.tr('thumbnail_select_first'));
      return;
    }

    try {
      FocusScope.of(context).unfocus();

      // 현재 썸네일 이미지를 네트워크에서 로드
      final response = await http.get(Uri.parse(_thumbnailUrl));
      if (response.statusCode != 200) {
        if (mounted) {
          ErrorHandler.showError(context, context.tr('image_load_failed'));
        }
        return;
      }

      final imageBytes = response.bodyBytes;

      // 커스텀 이미지 에디터 열기
      final editedBytes = await Navigator.push<Uint8List?>(
        context,
        MaterialPageRoute(
          builder: (context) => CustomImageEditorScreen(imageBytes: imageBytes),
          fullscreenDialog: true,
        ),
      );

      if (editedBytes == null || !mounted) return;

      // 편집된 이미지를 서버에 업로드
      setState(() => _isUploadingThumb = true);

      final upload = context.read<UploadService>();
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/edited_thumbnail_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(editedBytes);

      final tasks = await upload.uploadFilesViaServerBatches([
        tempFile,
      ], kind: UploadKind.editorImage);

      // 임시 파일 삭제
      try {
        await tempFile.delete();
      } catch (_) {}

      if (tasks.isEmpty || tasks.first.state != UploadState.success) {
        if (mounted) {
          ErrorHandler.showError(
            context,
            context.tr('thumbnail_upload_failed'),
          );
          setState(() => _isUploadingThumb = false);
        }
        return;
      }

      final newUrl = tasks.first.url;

      if (newUrl == null || newUrl.isEmpty) {
        if (mounted) {
          ErrorHandler.showError(context, context.tr('upload_url_failed'));
          setState(() => _isUploadingThumb = false);
        }
        return;
      }

      // 새 썸네일 정보 저장 (화면이 살아있을 때만 반영)
      _thumbnailUrl = newUrl;

      if (mounted) {
        setState(() {
          _isUploadingThumb = false;
          _isVideo = false; // 편집 후 이미지로 변경
        });
      }

      // 업로드 완료 시점에는 콜백 호출하지 않음 (수정 완료 버튼 클릭 시에만 호출)
      debugPrint('[ThumbnailEditOverlay] 이미지 편집 완료: $_thumbnailUrl');
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e);
        setState(() => _isUploadingThumb = false);
      }
    }
  }

  Future<void> _openGalleryPicker() async {
    // 이미지 또는 영상 선택 옵션 제공
    final mediaType = await showModalBottomSheet<String>(
      backgroundColor: Colors.transparent,
      context: context,
      builder:
          (context) => ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
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
                      title: Text(context.tr('select_image')),
                    ),
                    ListTile(
                      onTap: () => Navigator.of(context).pop('video'),
                      title: Text(context.tr('select_video')),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    if (mediaType == null || !mounted) return;

    if (mediaType == 'image') {
      await _pickAndUploadImage();
    } else if (mediaType == 'video') {
      await _pickAndUploadVideo();
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = NativeImagePicker();
    final file = await picker.pickSingleImage();

    if (file != null) {
      if (!mounted) return;

      // 영상 정리 (컨트롤러는 dispose하지 않고 상태만 초기화)
      _videoController = null;
      _localVideoFile = null;
      _cachedVideoUrl = null;

      setState(() {
        _isUploadingThumb = true;
        _isVideo = false; // 이미지로 변경
      });
      try {
        final upload = context.read<UploadService>();
        final tasks = await upload.uploadFilesViaServerBatches([
          file,
        ], kind: UploadKind.editorImage);

        if (tasks.isNotEmpty) {
          final t = tasks.first;
          final hasUrl = (t.url ?? '').isNotEmpty;

          if (t.state == UploadState.success && hasUrl) {
            _thumbnailUrl = t.url!;

            // 업로드 완료 시점에는 콜백 호출하지 않음 (수정 완료 버튼 클릭 시에만 호출)
          } else {
            if (mounted) {
              ErrorHandler.showError(
                context,
                context.tr('thumbnail_upload_failed'),
              );
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ErrorHandler.handleError(context, e, customMessage: '업로드 오류');
        }
      } finally {
        if (mounted) setState(() => _isUploadingThumb = false);
      }
    }
  }

  Future<void> _pickAndUploadVideo() async {
    final picker = NativeImagePicker();
    final videoFile = await picker.pickSingleVideo();

    if (videoFile == null || !mounted) return;

    // 파일 검증
    final validationError = await VideoUploadUtils.validateFile(
      context,
      videoFile.path,
    );
    if (validationError != null) return;

    setState(() => _isUploadingThumb = true);

    try {
      // 썸네일 생성
      final thumbnail = await VideoUploadUtils.generateThumbnail(
        videoFile.path,
      );
      if (thumbnail == null) {
        throw Exception('썸네일 생성 실패');
      }

      // 비디오 플레이어 초기화 (기존 컨트롤러는 dispose하지 않음)
      _videoController = VideoPlayerController.file(videoFile)
        ..initialize().then((_) {
          if (mounted) {
            _videoController?.play();
            _videoController?.setLooping(true);
            setState(() {});
          }
        });

      if (mounted) {
        setState(() => _localVideoFile = videoFile);
      }

      // 비디오 압축
      final mp4File = await VideoUploadUtils.compressVideo(videoFile.path);
      if (mp4File == null) {
        if (mounted) {
          await DialogUtils.showInfoDialog(
            context,
            title: '업로드 불가',
            message: '파일이 너무 큽니다.',
          );
          // 컨트롤러는 dispose하지 않고 상태만 초기화
          setState(() {
            _localVideoFile = null;
            _isUploadingThumb = false;
          });
        }
        return;
      }

      // 서버 업로드
      final upload = context.read<UploadService>();
      final task = upload.enqueueFile(mp4File, kind: UploadKind.video);

      bool handled = false;
      void listener() async {
        if (handled) return;

        if (task.state == UploadState.success) {
          handled = true;
          final videoUrl = task.url;

          if (videoUrl == null || videoUrl.isEmpty) {
            if (mounted) {
              ErrorHandler.showError(context, context.tr('video_url_failed'));
              setState(() => _isUploadingThumb = false);
            }
            return;
          }

          _thumbnailUrl = videoUrl;

          if (mounted) {
            setState(() {
              _isUploadingThumb = false;
              _isVideo = true; // 영상 업로드 완료
            });
          }

          debugPrint('[ThumbnailEditOverlay] 영상 업로드 완료 콜백 호출: $_thumbnailUrl');
          // 업로드 완료 시점에는 콜백 호출하지 않음 (수정 완료 버튼 클릭 시에만 호출)
        } else if (task.state == UploadState.failed) {
          handled = true;
          if (mounted) {
            await VideoUploadUtils.showUploadFailedDialog(context, task.error);
            // 컨트롤러는 dispose하지 않고 상태만 초기화
            setState(() {
              _localVideoFile = null;
              _isUploadingThumb = false;
            });
          }
        } else if (task.state == UploadState.cancelled) {
          handled = true;
          if (mounted) {
            await VideoUploadUtils.showUploadCancelledDialog(context);
            // 컨트롤러는 dispose하지 않고 상태만 초기화
            setState(() {
              _localVideoFile = null;
              _isUploadingThumb = false;
            });
          }
        }
      }

      task.addListener(listener);

      Future.delayed(const Duration(minutes: 2), () async {
        if (!handled && mounted) {
          task.removeListener(listener);
          await VideoUploadUtils.showUploadTimeoutDialog(context);
          // 컨트롤러는 dispose하지 않고 상태만 초기화
          setState(() {
            _localVideoFile = null;
            _isUploadingThumb = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        await VideoUploadUtils.showGeneralErrorDialog(context);
        // 컨트롤러는 dispose하지 않고 상태만 초기화
        setState(() {
          _localVideoFile = null;
          _isUploadingThumb = false;
        });
      }
    }
  }

  Widget _buildEditButton() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(35),
          ),
          child: Row(
            children: [
              Text(
                context.tr('edit_thumbnail'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      ),
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
                        // 비디오 일시정지만 함

                        // 적용 없이 종료: 상태 변경 없음 (재빌드 유발 방지)

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

                      // 사용자가 "나가기"를 선택 -> 변경사항 버리고 그냥 나가기
                      // 컨트롤러는 정리하지 않음 (변경사항을 적용하지 않으므로)
                      // 적용 없이 종료: 상태 변경 없음 (재빌드 유발 방지)
                    }

                    // 변경사항 여부와 관계없이 그냥 나가기
                    if (mounted) {
                      // 비디오 일시정지 (소리는 이미 dispose에서 끔)

                      // 적용 없이 종료: 상태 변경 없음 (재빌드 유발 방지)

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
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.9),
                        ),
                      ),
                    )
                    : Text(
                      _editMode
                          ? context.tr('done')
                          : context.tr('modify_complete'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
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
          SizedBox(width: 10),
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 1),

                      // 썸네일 카드 (키보드 열리면 숨김)
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 100),
                        crossFadeState:
                            (MediaQuery.of(context).viewInsets.bottom > 0)
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                        firstChild: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 50.0,
                              ),
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: 4 / 5, // PostList와 동일한 4:5 비율
                                  child: GestureDetector(
                                    onTap: _openGalleryPicker,
                                    onLongPress: _toggleEditMode,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          cardRadius + 2,
                                        ),
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.1),
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          cardRadius,
                                        ),
                                        child: Stack(
                                          children: [
                                            // 배경 이미지 또는 비디오
                                            Positioned.fill(
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                  milliseconds: 300,
                                                ),
                                                child:
                                                    _localVideoFile != null &&
                                                            _videoController !=
                                                                null
                                                        ? _videoController!
                                                                .value
                                                                .isInitialized
                                                            ? ClipRRect(
                                                              key: ValueKey(
                                                                'video_${_videoController.hashCode}',
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    cardRadius,
                                                                  ),
                                                              child: SizedBox.expand(
                                                                child: FittedBox(
                                                                  fit:
                                                                      BoxFit
                                                                          .cover,
                                                                  child: SizedBox(
                                                                    width:
                                                                        _videoController!
                                                                            .value
                                                                            .size
                                                                            .width,
                                                                    height:
                                                                        _videoController!
                                                                            .value
                                                                            .size
                                                                            .height,
                                                                    child: VideoPlayer(
                                                                      _videoController!,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            )
                                                            : ShimmerBox(
                                                              key: const ValueKey(
                                                                'shimmer_local',
                                                              ),
                                                              width:
                                                                  MediaQuery.of(
                                                                    context,
                                                                  ).size.width,
                                                              height:
                                                                  MediaQuery.of(
                                                                    context,
                                                                  ).size.height,
                                                            )
                                                        : _thumbnailUrl.isEmpty
                                                        ? const _EmptyImagePlaceholder(
                                                          key: ValueKey(
                                                            'empty',
                                                          ),
                                                        )
                                                        : _isVideo
                                                        ? _videoController !=
                                                                    null &&
                                                                _videoController!
                                                                    .value
                                                                    .isInitialized
                                                            ? ClipRRect(
                                                              key: ValueKey(
                                                                'video_network_${_thumbnailUrl}',
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    cardRadius,
                                                                  ),
                                                              child: SizedBox.expand(
                                                                child: FittedBox(
                                                                  fit:
                                                                      BoxFit
                                                                          .cover,
                                                                  child: SizedBox(
                                                                    width:
                                                                        _videoController!
                                                                            .value
                                                                            .size
                                                                            .width,
                                                                    height:
                                                                        _videoController!
                                                                            .value
                                                                            .size
                                                                            .height,
                                                                    child: VideoPlayer(
                                                                      _videoController!,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            )
                                                            : ShimmerBox(
                                                              key: const ValueKey(
                                                                'shimmer_network',
                                                              ),
                                                              width:
                                                                  MediaQuery.of(
                                                                    context,
                                                                  ).size.width,
                                                              height:
                                                                  MediaQuery.of(
                                                                    context,
                                                                  ).size.height,
                                                            )
                                                        : ClipRRect(
                                                          key: ValueKey(
                                                            'image_$_thumbnailUrl',
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                cardRadius,
                                                              ),
                                                          child: SizedBox.expand(
                                                            child: FittedBox(
                                                              fit: BoxFit.cover,
                                                              child: Image.network(
                                                                _thumbnailUrl,
                                                                errorBuilder:
                                                                    (
                                                                      c,
                                                                      e,
                                                                      s,
                                                                    ) => const _EmptyImagePlaceholder(
                                                                      key: ValueKey(
                                                                        'error',
                                                                      ),
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                              ),
                                            ),

                                            // 업로드 중 로딩 오버레이
                                            if (_isUploadingThumb)
                                              Positioned.fill(
                                                child: Container(
                                                  color: Colors.black
                                                      .withOpacity(0.3),
                                                  child: const Center(
                                                    child: CircularProgressIndicator(
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                            Color
                                                          >(Colors.white),
                                                      strokeWidth: 3,
                                                    ),
                                                  ),
                                                ),
                                              ),

                                            // 음소거 버튼 (영상일 때만)
                                            if (_videoController != null &&
                                                _videoController!
                                                    .value
                                                    .isInitialized &&
                                                (_localVideoFile != null ||
                                                    _isVideo))
                                              Positioned(
                                                right: 6,
                                                bottom: 6,
                                                child: GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      if (_videoController!
                                                              .value
                                                              .volume >
                                                          0) {
                                                        _videoController!
                                                            .setVolume(0);
                                                      } else {
                                                        _videoController!
                                                            .setVolume(1);
                                                      }
                                                    });
                                                  },
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black
                                                          .withOpacity(0.5),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(
                                                      _videoController!
                                                                  .value
                                                                  .volume >
                                                              0
                                                          ? Icons
                                                              .volume_up_rounded
                                                          : Icons
                                                              .volume_off_rounded,
                                                      color: Colors.white,
                                                      size: 16,
                                                    ),
                                                  ),
                                                ),
                                              ),

                                            // 편집하기 버튼
                                            if (!_isUploadingThumb)
                                              Positioned(
                                                left: 6,
                                                bottom: 6,
                                                child: GestureDetector(
                                                  onTap: () {
                                                    // 이미지면 바로 편집기 열기, 비디오면 선택 바텀시트
                                                    if (_thumbnailUrl
                                                            .isNotEmpty &&
                                                        !_isVideo) {
                                                      _editCurrentImage();
                                                    } else {
                                                      _openGalleryPicker();
                                                    }
                                                  },
                                                  child: _buildEditButton(),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        secondChild: const SizedBox(height: 8),
                      ),

                      // 하단 텍스트 영역 (post_export_screen과 동일)
                      AnimatedPadding(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        padding: EdgeInsets.only(
                          bottom:
                              MediaQuery.of(context).viewInsets.bottom > 0
                                  ? 0
                                  : 0,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 30,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              // 제목 (탭 시 인라인 편집)
                              GestureDetector(
                                onTap: () {
                                  setState(() => _editMode = true);
                                  FocusScope.of(
                                    context,
                                  ).requestFocus(_titleFocusNode);
                                },
                                child: AbsorbPointer(
                                  absorbing: false,
                                  child: TextField(
                                    controller: _titleController,
                                    focusNode: _titleFocusNode,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.9),
                                      fontSize: 35,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // 내용 (탭 시 인라인 편집 가능)
                              GestureDetector(
                                onTap: () {
                                  setState(() => _editMode = true);
                                  FocusScope.of(
                                    context,
                                  ).requestFocus(_excerptFocusNode);
                                },
                                child: AbsorbPointer(
                                  absorbing: false,
                                  child: TextField(
                                    controller: _excerptController,
                                    focusNode: _excerptFocusNode,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.7),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w300,
                                      height: 1.8,
                                      letterSpacing: -0.1,
                                    ),
                                    maxLines: 5,
                                    minLines: 5,
                                    keyboardType: TextInputType.multiline,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    scrollPhysics:
                                        const NeverScrollableScrollPhysics(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
      ),
    );
  }
}

// 빈 이미지 자리표시자
class _EmptyImagePlaceholder extends StatelessWidget {
  const _EmptyImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '눌러서 썸네일을 선택해주세요',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
