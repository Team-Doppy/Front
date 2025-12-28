import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/image/media_picker_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:doppy/image/simple_image_editor_screen.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/editor/utils/video_upload_utils.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;

/// Step 1: 썸네일 & 글 편집 컴포넌트
class Step1ThumbnailEdit extends StatefulWidget {
  final String sessionKey;
  final double cardRadius;
  final TextEditingController titleController;
  final TextEditingController excerptController;
  final FocusNode titleFocusNode;
  final FocusNode excerptFocusNode;
  final String exportedThumbnailImageUrl;
  final bool editMode;
  final bool isUploadingThumb;
  final File? localThumbnailFile;
  final File? localVideoFile;
  final VideoPlayerController? videoController;
  final AnimationController controller;
  final ValueChanged<String> onThumbnailUrlChanged;
  final ValueChanged<File?> onLocalThumbnailChanged;
  final ValueChanged<File?> onLocalVideoChanged;
  final ValueChanged<VideoPlayerController?> onVideoControllerChanged;
  final ValueChanged<bool> onIsUploadingThumbChanged;
  final ValueChanged<bool> onEditModeChanged;
  final VoidCallback onEditFocusChange;

  const Step1ThumbnailEdit({
    super.key,
    required this.sessionKey,
    required this.cardRadius,
    required this.titleController,
    required this.excerptController,
    required this.titleFocusNode,
    required this.excerptFocusNode,
    required this.exportedThumbnailImageUrl,
    required this.editMode,
    required this.isUploadingThumb,
    this.localThumbnailFile,
    this.localVideoFile,
    this.videoController,
    required this.controller,
    required this.onThumbnailUrlChanged,
    required this.onLocalThumbnailChanged,
    required this.onLocalVideoChanged,
    required this.onVideoControllerChanged,
    required this.onIsUploadingThumbChanged,
    required this.onEditModeChanged,
    required this.onEditFocusChange,
  });

  @override
  State<Step1ThumbnailEdit> createState() => _Step1ThumbnailEditState();
}

class _Step1ThumbnailEditState extends State<Step1ThumbnailEdit> {
  String get _nsKey => widget.sessionKey;

  // 🎯 업로드 태스크 추적 (썸네일 변경 시 취소용)
  UploadTask? _currentVideoUploadTask;
  UploadTask? _currentImageUploadTask; // 🎯 이미지 업로드 태스크도 추적

  @override
  Widget build(BuildContext context) {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: 40),
                // 🎯 썸네일 영역 (부드럽게 사라짐)
                AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, child) {
                    // editMode나 포커스가 활성화되면 이미지 축소
                    final shouldHide = isKeyboardVisible || widget.editMode;
                    final animationValue = widget.controller.value;
                    // controller 애니메이션 값에 따라 높이와 투명도 조정 (0.0 ~ 1.0)
                    // forward() 시 값이 0.0에서 1.0으로 증가하면서 이미지가 사라짐
                    final targetHeight =
                        shouldHide
                            ? 8.0
                            : 400.0 * (1.0 - animationValue * 0.98);
                    final targetOpacity =
                        shouldHide ? 0.0 : 1.0 - animationValue * 0.98;

                    return ClipRect(
                      child: Opacity(
                        opacity: targetOpacity,
                        child: SizedBox(
                          height: targetHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40.0,
                            ),
                            child: _buildAnimatedThumbnail(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                // 🎯 텍스트 영역
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 30, 30, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildTitleField(),
                      const SizedBox(height: 12),
                      _buildExcerptField(),
                    ],
                  ),
                ),
                // 키보드 여유 공간
                SizedBox(height: isKeyboardVisible ? 50 : 150),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedThumbnail() {
    return Center(
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque, // 🎯 터치 이벤트가 다른 위젯으로 전파되지 않도록
          onTapDown: (_) {
            // 🎯 이미지 탭 시 즉시 포커스 해제하여 편집 모드 촉발 방지
            // 텍스트 필드 포커스 노드 직접 해제
            widget.titleFocusNode.unfocus();
            widget.excerptFocusNode.unfocus();
            FocusScope.of(context).unfocus();
            widget.onEditModeChanged(false);
          },
          onTap: () {
            // 🎯 이미지 탭 완료 시 갤러리 피커 열기
            // 텍스트 필드 포커스 노드 직접 해제
            widget.titleFocusNode.unfocus();
            widget.excerptFocusNode.unfocus();
            FocusScope.of(context).unfocus();
            widget.onEditModeChanged(false);
            _openGalleryPicker();
          },
          onLongPress: _toggleEditMode,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.cardRadius + 2),
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.cardRadius),
              child: Stack(
                children: [
                  // 🎯 이미지/비디오 전환
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        child: _buildThumbnailContent(),
                      ),
                    ),
                  ),

                  // 업로드 중 로딩 오버레이
                  if (widget.isUploadingThumb)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.3),
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                    ),

                  // 음소거 버튼 (영상일 때만 표시)
                  if (widget.localVideoFile != null &&
                      widget.videoController != null &&
                      widget.videoController!.value.isInitialized)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: RepaintBoundary(
                        child: AnimatedOpacity(
                          opacity: widget.editMode ? 0.3 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                if (widget.videoController!.value.volume > 0) {
                                  widget.videoController!.setVolume(0);
                                } else {
                                  widget.videoController!.setVolume(1);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.videoController!.value.volume > 0
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_off_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 편집/변경 버튼
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: GestureDetector(
                      onTap: _editThumbnail,
                      child: _buildEditButton(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailContent() {
    if (widget.localVideoFile != null && widget.videoController != null) {
      return SizedBox.expand(
        key: ValueKey('video_${widget.localVideoFile!.path}'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.localThumbnailFile != null)
              Image.file(widget.localThumbnailFile!, fit: BoxFit.cover),
            if (widget.videoController!.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: widget.videoController!.value.size.width,
                  height: widget.videoController!.value.size.height,
                  child: VideoPlayer(widget.videoController!),
                ),
              ),
          ],
        ),
      );
    } else if (widget.localThumbnailFile != null) {
      return SizedBox.expand(
        key: ValueKey('local_${widget.localThumbnailFile!.path}'),
        child: Image.file(widget.localThumbnailFile!, fit: BoxFit.cover),
      );
    } else if (widget.exportedThumbnailImageUrl.isEmpty) {
      return const SizedBox.expand(
        key: ValueKey('empty'),
        child: _EmptyImagePlaceholder(),
      );
    } else {
      return SizedBox.expand(
        key: ValueKey('network_${widget.exportedThumbnailImageUrl}'),
        child: Image.network(
          widget.exportedThumbnailImageUrl,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => const _EmptyImagePlaceholder(),
        ),
      );
    }
  }

  Widget _buildTitleField() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            cursorColor: Theme.of(context).colorScheme.primary,
            controller: widget.titleController,
            focusNode: widget.titleFocusNode,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            scrollPhysics: const NeverScrollableScrollPhysics(),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(
                context,
              ).t('title_input_placeholder'),
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
            ),
            onTap: () {
              widget.onEditModeChanged(true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExcerptField() {
    return TextField(
      controller: widget.excerptController,
      focusNode: widget.excerptFocusNode,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withOpacity(0.85),
        fontSize: 14,
        fontWeight: FontWeight.w300,
        height: 1.8,
        letterSpacing: -0.1,
      ),
      cursorColor: Theme.of(context).colorScheme.primary,
      maxLines: 4,
      minLines: 2,
      keyboardType: TextInputType.multiline,
      scrollPhysics: const NeverScrollableScrollPhysics(),
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).t('content_input_placeholder'),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        border: InputBorder.none,
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
      ),
      onTap: () {
        widget.onEditModeChanged(true);
      },
    );
  }

  void _toggleEditMode() {
    widget.onEditModeChanged(!widget.editMode);
    if (!widget.editMode) {
      widget.controller.forward();
    } else {
      widget.controller.reverse();
    }
  }

  Widget _buildEditButton() {
    final bool isVideo = widget.localVideoFile != null;
    final String buttonText =
        isVideo
            ? AppLocalizations.of(context).t('change_thumbnail')
            : AppLocalizations.of(context).t('edit_thumbnail');

    return ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const ui.Color.fromARGB(255, 44, 44, 44).withOpacity(0.4),
            borderRadius: BorderRadius.circular(35),
          ),
          child: Row(
            children: [
              Text(
                buttonText,
                style: const TextStyle(
                  color: Colors.white,
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

  Future<void> _openGalleryPicker() async {
    // 🎯 이미지 선택 시 즉시 포커스 해제 및 편집 모드 비활성화
    FocusScope.of(context).unfocus();
    widget.onEditModeChanged(false);
    widget.controller.reverse();

    // 포커스 해제가 완료될 때까지 약간 대기
    await Future.delayed(const Duration(milliseconds: 50));

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
                      title: Text(
                        AppLocalizations.of(context).t('select_image'),
                      ),
                    ),
                    ListTile(
                      onTap: () => Navigator.of(context).pop('video'),
                      title: Text(
                        AppLocalizations.of(context).t('select_video'),
                      ),
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
      await _pickAndExtractVideoThumbnail();
    }
  }

  Future<void> _pickAndUploadImage() async {
    final result = await Navigator.push<MediaPickerResult>(
      context,
      CupertinoPageRoute(
        fullscreenDialog: true, // 🎯 defaultToolbar와 동일한 전환 애니메이션
        builder:
            (context) => MediaPickerScreen(
              initialMediaType: MediaType.image,
              maxSelectionCount: 1,
              enableToggle: true, // 이미지/영상 토글 가능
              onMediaSelected: (file) {
                // 단일 선택이므로 바로 처리
              },
            ),
      ),
    );

    if (result != null && result.files.isNotEmpty) {
      // 🎯 단일 선택이므로 첫 번째 파일만 사용 (안전장치)
      final file = result.files.first;
      if (!mounted) return;

      // 🎯 실제로 선택된 미디어 타입 확인
      if (result.selectedMediaType == MediaType.video) {
        await _processVideoFileFromPicker(file);
        return;
      }

      // 🎯 기존 업로드 태스크 모두 취소 (이미지/영상)
      final upload = context.read<UploadService>();
      if (_currentVideoUploadTask != null) {
        upload.cancel(_currentVideoUploadTask!.id);
        _currentVideoUploadTask?.removeListener(() {});
        _currentVideoUploadTask = null;
        debugPrint('[Step1] 이전 영상 업로드 태스크 취소');
      }
      if (_currentImageUploadTask != null) {
        upload.cancel(_currentImageUploadTask!.id);
        _currentImageUploadTask?.removeListener(() {});
        _currentImageUploadTask = null;
        debugPrint('[Step1] 이전 이미지 업로드 태스크 취소');
      }

      widget.onLocalThumbnailChanged(file);
      widget.onIsUploadingThumbChanged(true);
      widget.onVideoControllerChanged(null);
      widget.onLocalVideoChanged(null);

      final svc = NodeComponentService();
      svc.clearTempVideoFile(_nsKey);

      try {
        final tasks = await upload.uploadFilesViaServerBatches([
          file,
        ], kind: UploadKind.editorImage);
        if (tasks.isNotEmpty) {
          final t = tasks.first;
          // 🎯 이미지 업로드 태스크 추적
          _currentImageUploadTask = t;

          // 업로드 완료/실패 리스너 추가
          bool handled = false;
          void listener() {
            if (handled) return;
            if (t.state == UploadState.success ||
                t.state == UploadState.failed ||
                t.state == UploadState.cancelled) {
              handled = true;
              t.removeListener(listener);
              if (_currentImageUploadTask?.id == t.id) {
                _currentImageUploadTask = null;
              }
            }
          }

          t.addListener(listener);

          final hasUrl = (t.url ?? '').isNotEmpty;
          if (t.state == UploadState.success && hasUrl) {
            widget.onThumbnailUrlChanged(t.url!);

            await precacheImage(NetworkImage(t.url!), context);

            if (mounted) {
              widget.onLocalThumbnailChanged(null);
            }
          } else {
            if (mounted) {
              ErrorHandler.showError(
                context,
                AppLocalizations.of(context).t('thumbnail_upload_failed'),
              );
              widget.onLocalThumbnailChanged(null);
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ErrorHandler.handleError(context, e, customMessage: '업로드 오류');
          widget.onLocalThumbnailChanged(null);
        }
      } finally {
        if (mounted) {
          widget.onIsUploadingThumbChanged(false);
          widget.onEditModeChanged(false);
          widget.controller.reverse();
          FocusScope.of(context).unfocus();
        }
      }
    }
  }

  Future<void> _pickAndExtractVideoThumbnail() async {
    final result = await Navigator.push<MediaPickerResult>(
      context,
      CupertinoPageRoute(
        fullscreenDialog: true, // 🎯 defaultToolbar와 동일한 전환 애니메이션
        builder:
            (context) => MediaPickerScreen(
              initialMediaType: MediaType.video,
              maxSelectionCount: 1,
              enableToggle: true, // 이미지/영상 토글 가능
              onMediaSelected: (file) {
                // 단일 선택이므로 바로 처리
              },
            ),
      ),
    );

    if (result == null || result.files.isEmpty || !mounted) return;

    // 🎯 실제로 선택된 미디어 타입 확인
    if (result.selectedMediaType == MediaType.image) {
      // 이미지가 선택된 경우 이미지 업로드로 처리 (이미 선택된 파일 사용)
      final file = result.files.first;
      if (!mounted) return;

      // 🎯 영상 업로드 중이면 이전 업로드 태스크 취소
      if (_currentVideoUploadTask != null) {
        final upload = context.read<UploadService>();
        upload.cancel(_currentVideoUploadTask!.id);
        _currentVideoUploadTask?.removeListener(() {});
        _currentVideoUploadTask = null;
        debugPrint('[Step1] 이전 영상 업로드 태스크 취소');
      }

      widget.onLocalThumbnailChanged(file);
      widget.onIsUploadingThumbChanged(true);
      widget.onVideoControllerChanged(null);
      widget.onLocalVideoChanged(null);

      final svc = NodeComponentService();
      svc.clearTempVideoFile(_nsKey);

      try {
        final upload = context.read<UploadService>();
        final tasks = await upload.uploadFilesViaServerBatches([
          file,
        ], kind: UploadKind.editorImage);
        if (tasks.isNotEmpty) {
          final t = tasks.first;
          final hasUrl = (t.url ?? '').isNotEmpty;
          if (t.state == UploadState.success && hasUrl) {
            widget.onThumbnailUrlChanged(t.url!);

            await precacheImage(NetworkImage(t.url!), context);

            if (mounted) {
              widget.onLocalThumbnailChanged(null);
            }
          } else {
            if (mounted) {
              ErrorHandler.showError(
                context,
                AppLocalizations.of(context).t('thumbnail_upload_failed'),
              );
              widget.onLocalThumbnailChanged(null);
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ErrorHandler.handleError(context, e, customMessage: '업로드 오류');
          widget.onLocalThumbnailChanged(null);
        }
      } finally {
        if (mounted) {
          widget.onIsUploadingThumbChanged(false);
          widget.onEditModeChanged(false);
          widget.controller.reverse();
          FocusScope.of(context).unfocus();
        }
      }
      return;
    }

    // 🎯 단일 선택이므로 첫 번째 파일만 사용 (안전장치)
    final videoFile = result.files.first;
    await _processVideoFileFromPicker(videoFile);
  }

  /// 🎯 선택된 영상 파일 처리 (MediaPickerScreen에서 선택된 파일을 바로 처리)
  Future<void> _processVideoFileFromPicker(File videoFile) async {
    final validationError = await VideoUploadUtils.validateFile(
      context,
      videoFile.path,
    );
    if (validationError != null) return;

    // 🎯 기존 업로드 태스크 모두 취소 (이미지/영상)
    final upload = context.read<UploadService>();
    if (_currentVideoUploadTask != null) {
      upload.cancel(_currentVideoUploadTask!.id);
      _currentVideoUploadTask?.removeListener(() {});
      _currentVideoUploadTask = null;
      debugPrint('[Step1] 이전 영상 업로드 태스크 취소');
    }
    if (_currentImageUploadTask != null) {
      upload.cancel(_currentImageUploadTask!.id);
      _currentImageUploadTask?.removeListener(() {});
      _currentImageUploadTask = null;
      debugPrint('[Step1] 이전 이미지 업로드 태스크 취소');
    }

    widget.onIsUploadingThumbChanged(true);

    try {
      final thumbnail = await VideoUploadUtils.generateThumbnail(
        videoFile.path,
      );
      if (thumbnail == null) {
        throw Exception('썸네일 생성 실패');
      }

      widget.videoController?.dispose();
      final videoController = VideoPlayerController.file(videoFile);
      widget.onVideoControllerChanged(videoController);
      videoController
          .initialize()
          .then((_) {
            if (mounted && widget.videoController != null) {
              widget.videoController?.play();
              widget.videoController?.setLooping(true);
              setState(() {});
            }
          })
          .catchError((error) {
            debugPrint('[Step1] 비디오 컨트롤러 초기화 실패: $error');
            if (mounted) {
              widget.onVideoControllerChanged(null);
              setState(() {
                widget.onIsUploadingThumbChanged(false);
                widget.onLocalVideoChanged(null);
                widget.onLocalThumbnailChanged(null);
              });
            }
          });

      if (mounted) {
        widget.onLocalVideoChanged(videoFile);
        widget.onLocalThumbnailChanged(thumbnail);
        final svc = NodeComponentService();
        svc.setTempVideoFile(_nsKey, videoFile.path);
        svc.setTempVideoThumbnail(_nsKey, thumbnail.path);
      }

      final mp4File = await VideoUploadUtils.compressVideo(videoFile.path);
      if (mp4File == null) {
        if (mounted) {
          await DialogUtils.showInfoDialog(
            context,
            title: '업로드 불가',
            message: '파일이 너무 큽니다.',
          );
          widget.onVideoControllerChanged(null);
          widget.onLocalVideoChanged(null);
          widget.onLocalThumbnailChanged(null);
          widget.onIsUploadingThumbChanged(false);
        }
        return;
      }

      // 🎯 이전 영상 업로드 태스크 취소
      if (_currentVideoUploadTask != null) {
        final upload = context.read<UploadService>();
        upload.cancel(_currentVideoUploadTask!.id);
        _currentVideoUploadTask?.removeListener(() {});
        _currentVideoUploadTask = null;
        debugPrint('[Step1] 이전 영상 업로드 태스크 취소');
      }

      final upload = context.read<UploadService>();
      final task = upload.enqueueFile(mp4File, kind: UploadKind.video);

      // 🎯 현재 업로드 태스크 저장
      _currentVideoUploadTask = task;

      bool handled = false;
      void listener() async {
        if (handled) return;

        if (task.state == UploadState.success) {
          handled = true;
          final videoUrl = task.url;

          if (videoUrl == null || videoUrl.isEmpty) {
            if (mounted) {
              ErrorHandler.showError(
                context,
                AppLocalizations.of(context).t('video_url_failed'),
              );
              widget.onVideoControllerChanged(null);
              widget.onLocalVideoChanged(null);
              widget.onIsUploadingThumbChanged(false);
            }
            return;
          }

          widget.onThumbnailUrlChanged(videoUrl);

          if (mounted) {
            widget.onIsUploadingThumbChanged(false);
            widget.onEditModeChanged(false);
            widget.controller.reverse();
            FocusScope.of(context).unfocus();
          }

          // 🎯 업로드 완료 시 태스크 추적 해제
          _currentVideoUploadTask = null;
        } else if (task.state == UploadState.failed) {
          handled = true;
          if (mounted) {
            await VideoUploadUtils.showUploadFailedDialog(context, task.error);
            widget.onVideoControllerChanged(null);
            widget.onLocalVideoChanged(null);
            widget.onLocalThumbnailChanged(null);
            widget.onIsUploadingThumbChanged(false);
            widget.onEditModeChanged(false);
            widget.controller.reverse();
            FocusScope.of(context).unfocus();
          }

          // 🎯 업로드 실패 시 태스크 추적 해제
          _currentVideoUploadTask = null;
        } else if (task.state == UploadState.cancelled) {
          handled = true;
          if (mounted) {
            await VideoUploadUtils.showUploadCancelledDialog(context);
            widget.onVideoControllerChanged(null);
            widget.onLocalVideoChanged(null);
            widget.onLocalThumbnailChanged(null);
            widget.onIsUploadingThumbChanged(false);
            widget.onEditModeChanged(false);
            widget.controller.reverse();
            FocusScope.of(context).unfocus();
          }

          // 🎯 업로드 취소 시 태스크 추적 해제
          _currentVideoUploadTask = null;
        }
      }

      task.addListener(listener);

      Future.delayed(const Duration(minutes: 2), () async {
        if (!handled && mounted) {
          task.removeListener(listener);
          await VideoUploadUtils.showUploadTimeoutDialog(context);
          widget.onVideoControllerChanged(null);
          widget.onLocalVideoChanged(null);
          widget.onLocalThumbnailChanged(null);
          widget.onIsUploadingThumbChanged(false);
          widget.onEditModeChanged(false);
          widget.controller.reverse();
          FocusScope.of(context).unfocus();

          // 🎯 타임아웃 시 태스크 추적 해제
          _currentVideoUploadTask = null;
        }
      });
    } catch (e) {
      if (mounted) {
        await VideoUploadUtils.showGeneralErrorDialog(context);
        widget.onVideoControllerChanged(null);
        widget.onLocalVideoChanged(null);
        widget.onLocalThumbnailChanged(null);
        widget.onIsUploadingThumbChanged(false);
        widget.onEditModeChanged(false);
        widget.controller.reverse();
        FocusScope.of(context).unfocus();
      }

      // 🎯 에러 시 태스크 추적 해제
      _currentVideoUploadTask = null;
    }
  }

  Future<void> _editThumbnail() async {
    widget.onEditModeChanged(false);
    widget.controller.reverse();
    FocusScope.of(context).unfocus();

    if (widget.exportedThumbnailImageUrl.isEmpty ||
        widget.localVideoFile != null) {
      await _openGalleryPicker();
      return;
    }

    final action = await showModalBottomSheet<String>(
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
                      onTap: () => Navigator.of(context).pop('edit'),
                      title: Text(
                        AppLocalizations.of(context).t('edit_thumbnail'),
                      ),
                    ),
                    ListTile(
                      onTap: () => Navigator.of(context).pop('change'),
                      title: Text(
                        AppLocalizations.of(context).t('change_thumbnail'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    if (action == null || !mounted) return;

    if (action == 'edit') {
      await _editThumbnailImage();
    } else if (action == 'change') {
      await _openGalleryPicker();
    }
  }

  Future<void> _editThumbnailImage() async {
    try {
      widget.onEditModeChanged(false);
      widget.controller.reverse();
      FocusScope.of(context).unfocus();

      final response = await http.get(
        Uri.parse(widget.exportedThumbnailImageUrl),
      );
      if (response.statusCode != 200) {
        if (mounted) {
          ErrorHandler.showError(
            context,
            AppLocalizations.of(context).t('image_load_failed'),
          );
        }
        return;
      }

      final imageBytes = response.bodyBytes;

      final dynamic result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SimpleImageEditorScreen(imageBytes: imageBytes),
          fullscreenDialog: true,
        ),
      );

      if (result == null || !mounted) return;

      final Uint8List? editedBytes = result is Uint8List ? result : null;
      if (editedBytes == null) return;

      widget.onIsUploadingThumbChanged(true);

      final upload = context.read<UploadService>();
      final tempFile = File(
        '${Directory.systemTemp.path}/edited_thumbnail_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(editedBytes);

      final tasks = await upload.uploadFilesViaServerBatches([
        tempFile,
      ], kind: UploadKind.editorImage);

      try {
        await tempFile.delete();
      } catch (_) {}

      if (tasks.isEmpty || tasks.first.state != UploadState.success) {
        if (mounted) {
          ErrorHandler.showError(
            context,
            AppLocalizations.of(context).t('thumbnail_upload_failed'),
          );
        }
        return;
      }

      final newUrl = tasks.first.url;

      if (newUrl == null || newUrl.isEmpty) {
        if (mounted) {
          ErrorHandler.showError(
            context,
            AppLocalizations.of(context).t('upload_url_failed'),
          );
        }
        return;
      }

      widget.onThumbnailUrlChanged(newUrl);

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: '편집 중 오류가 발생했습니다');
      }
    } finally {
      if (mounted) {
        widget.onIsUploadingThumbChanged(false);
      }
    }
  }
}

/// 빈 이미지 자리표시자
class _EmptyImagePlaceholder extends StatelessWidget {
  const _EmptyImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).t('tap_to_select_thumbnail'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
