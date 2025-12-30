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
  String get _thumbRefId => 'thumb_${widget.sessionKey}';

  // 🎯 업로드 태스크 추적 (썸네일 변경 시 취소용)
  UploadTask? _currentImageUploadTask; // 🎯 이미지 업로드 태스크도 추적

  // 🎯 포커스/키보드에 따른 UI 전환을 더 부드럽게 만들기 위한 내부 상태
  bool _hasTextFocus = false;

  // 🎯 비디오 첫 프레임 전 검정 플래시 방지용 "포스터(썸네일) 유지" 상태
  VideoPlayerController? _posterObservedController;
  VoidCallback? _posterListener;
  bool _showVideoPoster = false;

  @override
  void initState() {
    super.initState();
    _hasTextFocus =
        widget.titleFocusNode.hasFocus || widget.excerptFocusNode.hasFocus;
    widget.titleFocusNode.addListener(_onTextFocusChanged);
    widget.excerptFocusNode.addListener(_onTextFocusChanged);

    _attachPosterListener(widget.videoController);
  }

  @override
  void didUpdateWidget(covariant Step1ThumbnailEdit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoController != widget.videoController) {
      _attachPosterListener(widget.videoController);
    }
  }

  @override
  void dispose() {
    widget.titleFocusNode.removeListener(_onTextFocusChanged);
    widget.excerptFocusNode.removeListener(_onTextFocusChanged);

    _detachPosterListener();
    super.dispose();
  }

  void _detachPosterListener() {
    if (_posterObservedController != null && _posterListener != null) {
      try {
        _posterObservedController!.removeListener(_posterListener!);
      } catch (_) {}
    }
    _posterObservedController = null;
    _posterListener = null;
  }

  void _attachPosterListener(VideoPlayerController? controller) {
    if (_posterObservedController == controller) return;

    _detachPosterListener();
    _posterObservedController = controller;

    if (controller == null) {
      _showVideoPoster = false;
      return;
    }

    // 새 컨트롤러가 오면 일단 포스터를 보여주고, 실제 재생 프레임이 진행되면 숨긴다.
    _showVideoPoster = true;

    void listener() {
      final v = controller.value;
      // position이 조금이라도 진행되면(첫 프레임 디코딩/표시 이후) 포스터를 내린다.
      if (v.isInitialized && v.position > const Duration(milliseconds: 50)) {
        if (!_showVideoPoster) return;
        if (!mounted) return;
        setState(() => _showVideoPoster = false);
      }
    }

    _posterListener = listener;
    controller.addListener(listener);
  }

  void _onTextFocusChanged() {
    final hasFocus =
        widget.titleFocusNode.hasFocus || widget.excerptFocusNode.hasFocus;
    if (_hasTextFocus == hasFocus) return;
    setState(() => _hasTextFocus = hasFocus);

    // ✅ 포커스 변화에 맞춰 editMode + 썸네일 애니메이션 동기화
    widget.onEditModeChanged(hasFocus);
    _syncThumbnailAnimation(shouldHide: hasFocus);

    // 외부에서 “포커스에 따른 UI 변화”를 추가로 처리할 수 있도록 콜백 유지
    widget.onEditFocusChange();
  }

  void _syncThumbnailAnimation({required bool shouldHide}) {
    // controller 값 0.0: 썸네일 fully shown, 1.0: hidden
    // 여기서는 포커스 진입/이탈에 맞춰 부드럽게 animateTo로 동기화한다.
    // ✅ 더 빠르고 타이트한 애니메이션: 120ms + easeOut (쫀쫀/반응성 우선)
    final target = shouldHide ? 1.0 : 0.0;
    try {
      widget.controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
      );
    } catch (_) {
      // controller가 dispose된 타이밍 등은 무시
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              children: [
                // ✅ 성능: 여러 implicit animation(AnimatedContainer/Opacity)을 쓰면 각각이 애니메이션을 구동하며
                // 프레임당 레이아웃/컴포지팅 비용이 늘 수 있다.
                // 여기서는 "controller 하나"로만 모든 값을 보간해서 버벅임을 줄인다.
                AnimatedBuilder(
                  animation: widget.controller,
                  child: RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40.0),
                      child: _buildAnimatedThumbnail(),
                    ),
                  ),
                  builder: (context, thumbChild) {
                    final t = widget.controller.value.clamp(0.0, 1.0);

                    // 0.0(기본) -> 1.0(포커스/키보드): 값 보간
                    final topSpace = ui.lerpDouble(40, 28, t)!;
                    // ✅ "복귀 시 몇 px 툭 떨어짐" 방지:
                    // 내부 썸네일은 AspectRatio(4/5)라서 화면 너비(패딩 제외)에 의해 최대 높이가 결정됨.
                    // 컨테이너가 그 최대치를 넘어가면 Center 정렬로 인해 마지막 구간에서 몇 px 흔들릴 수 있다.
                    // 따라서 최대 높이를 "실제 4/5 비율 높이"로 계산해서 정확히 맞춘다.
                    final availableWidth = (MediaQuery.sizeOf(context).width -
                            80.0)
                        .clamp(0.0, double.infinity);
                    final maxThumbHeight = availableWidth * 5.0 / 4.0;
                    final thumbHeight = ui.lerpDouble(maxThumbHeight, 120, t)!;

                    // ✅ opacity 변화는 최소화(1.0 -> 0.85)해서 컴포지팅 부담 감소
                    final thumbOpacity = ui.lerpDouble(1.0, 0.85, t)!;
                    final gapThumbText = ui.lerpDouble(20, 14, t)!;
                    final textTopPad = ui.lerpDouble(30, 22, t)!;
                    final titleExcerptGap = ui.lerpDouble(12, 10, t)!;
                    // ✅ 키보드 dismiss 시 "bottomSpace 점프" 방지:
                    // viewInsets.bottom은 키보드 애니메이션과 함께 연속적으로 변한다.
                    final keyboardInset =
                        MediaQuery.viewInsetsOf(context).bottom;
                    final keyboardT = (keyboardInset / 320.0).clamp(0.0, 1.0);
                    final bottomBase = ui.lerpDouble(120, 100, t)!;
                    final bottomSpace =
                        ui.lerpDouble(bottomBase, 40.0, keyboardT)!;

                    return Column(
                      children: [
                        SizedBox(height: topSpace),
                        ClipRect(
                          child: Opacity(
                            opacity: thumbOpacity,
                            child: SizedBox(
                              height: thumbHeight,
                              child: thumbChild,
                            ),
                          ),
                        ),
                        SizedBox(height: gapThumbText),
                        Padding(
                          padding: EdgeInsets.fromLTRB(30, textTopPad, 30, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildTitleField(),
                              SizedBox(height: titleExcerptGap),
                              _buildExcerptField(),
                            ],
                          ),
                        ),
                        SizedBox(height: bottomSpace),
                      ],
                    );
                  },
                ),
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
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 4,
                            ),
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
            // ✅ 바닥: 썸네일(포스터). 비디오 첫 프레임 전에는 이게 화면을 책임짐.
            if (widget.localThumbnailFile != null)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                opacity: _showVideoPoster ? 1.0 : 0.0,
                child: Image.file(
                  widget.localThumbnailFile!,
                  fit: BoxFit.cover,
                ),
              ),

            // ✅ 위: 비디오. 첫 프레임이 나온 뒤에만 페이드인해서 검정 플래시를 숨김.
            if (widget.videoController!.value.isInitialized)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                opacity: _showVideoPoster ? 0.0 : 1.0,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: widget.videoController!.value.size.width,
                    height: widget.videoController!.value.size.height,
                    child: VideoPlayer(widget.videoController!),
                  ),
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
      // 🎯 포커스가 있는 동안은 자리표시자 숨김
      if (_hasTextFocus) {
        return const SizedBox.expand(
          key: ValueKey('empty_hidden'),
          child: SizedBox.shrink(),
        );
      }
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 2),
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
                // ✅ 포커스 기반 전환이 메인 로직 (리스너에서 애니메이션/상태 동기화)
                widget.onEditModeChanged(true);
                _syncThumbnailAnimation(shouldHide: true);
              },
            ),
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
        fontSize: 15,
        fontWeight: FontWeight.w400,
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
        _syncThumbnailAnimation(shouldHide: true);
      },
    );
  }

  void _toggleEditMode() {
    widget.onEditModeChanged(!widget.editMode);
    if (!widget.editMode) {
      _syncThumbnailAnimation(shouldHide: true);
    } else {
      _syncThumbnailAnimation(shouldHide: false);
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

    // ✅ 바텀시트 없이 바로 미디어 피커로 연결 (이미지 타입, 1개 제한)
    await _pickAndUploadImage();
  }

  Future<void> _pickAndUploadImage() async {
    // ✅ 취소 시 이미지가 비지 않도록 기존 상태 저장
    final previousLocalThumbnail = widget.localThumbnailFile;
    final previousLocalVideo = widget.localVideoFile;
    final previousVideoController = widget.videoController;
    final previousThumbnailUrl = widget.exportedThumbnailImageUrl;
    final previousIsUploading = widget.isUploadingThumb;

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

    // ✅ 취소 시 기존 상태 복원
    if (result == null || result.files.isEmpty) {
      if (!mounted) return;
      // 기존 상태로 복원 (이미지가 비지 않도록)
      if (previousLocalThumbnail != widget.localThumbnailFile) {
        widget.onLocalThumbnailChanged(previousLocalThumbnail);
      }
      if (previousLocalVideo != widget.localVideoFile) {
        widget.onLocalVideoChanged(previousLocalVideo);
      }
      if (previousVideoController != widget.videoController) {
        widget.onVideoControllerChanged(previousVideoController);
      }
      if (previousThumbnailUrl != widget.exportedThumbnailImageUrl) {
        widget.onThumbnailUrlChanged(previousThumbnailUrl);
      }
      if (previousIsUploading != widget.isUploadingThumb) {
        widget.onIsUploadingThumbChanged(previousIsUploading);
      }
      return;
    }

    // 🎯 단일 선택이므로 첫 번째 파일만 사용 (안전장치)
    final file = result.files.first;
    if (!mounted) return;

    // 🎯 실제로 선택된 미디어 타입 확인
    if (result.selectedMediaType == MediaType.video) {
      await _processVideoFileFromPicker(
        file,
        initialThumbnailPath: result.thumbnailPath,
      );
      return;
    }

    // 🎯 기존 업로드 태스크 모두 취소 (이미지/영상)
    final upload = context.read<UploadService>();
    // ✅ 클립 노드 방식: refId 기반으로 압축/업로드를 함께 취소
    upload.cancelByRef(_thumbRefId);
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
        ErrorHandler.handleError(
          context,
          e,
          customMessage: AppLocalizations.of(context).t('upload_error'),
        );
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

  /// 🎯 선택된 영상 파일 처리 (MediaPickerScreen에서 선택된 파일을 바로 처리)
  Future<void> _processVideoFileFromPicker(
    File videoFile, {
    String? initialThumbnailPath,
  }) async {
    // ✅ 취소 시 이미지가 비지 않도록 기존 상태 저장
    final previousLocalThumbnail = widget.localThumbnailFile;
    final previousLocalVideo = widget.localVideoFile;
    final previousVideoController = widget.videoController;
    final previousThumbnailUrl = widget.exportedThumbnailImageUrl;
    final previousIsUploading = widget.isUploadingThumb;

    final validationError = await VideoUploadUtils.validateFile(
      context,
      videoFile.path,
    );
    if (validationError != null) {
      // ✅ 검증 실패 시 기존 상태 복원
      if (!mounted) return;
      if (previousLocalThumbnail != widget.localThumbnailFile) {
        widget.onLocalThumbnailChanged(previousLocalThumbnail);
      }
      if (previousLocalVideo != widget.localVideoFile) {
        widget.onLocalVideoChanged(previousLocalVideo);
      }
      if (previousVideoController != widget.videoController) {
        widget.onVideoControllerChanged(previousVideoController);
      }
      if (previousThumbnailUrl != widget.exportedThumbnailImageUrl) {
        widget.onThumbnailUrlChanged(previousThumbnailUrl);
      }
      if (previousIsUploading != widget.isUploadingThumb) {
        widget.onIsUploadingThumbChanged(previousIsUploading);
      }
      return;
    }

    try {
      final upload = context.read<UploadService>();
      // ✅ 클립 노드 방식: refId 기반으로 압축/업로드를 함께 취소
      upload.cancelByRef(_thumbRefId);
      // 이미지 업로드 태스크도 취소 (썸네일 교체 중 중복 업로드 방지)
      if (_currentImageUploadTask != null) {
        upload.cancel(_currentImageUploadTask!.id);
        _currentImageUploadTask?.removeListener(() {});
        _currentImageUploadTask = null;
      }

      // ✅ 1) 트림 화면에서 넘어온 썸네일이 있으면 즉시 사용 (검정 플래시 방지)
      File? thumbnailFile;
      final thumbPath = (initialThumbnailPath ?? '').trim();
      if (thumbPath.isNotEmpty) {
        final f = File(thumbPath);
        if (await f.exists()) {
          thumbnailFile = f;
        }
      }

      // ✅ 2) 없으면 기존 방식으로 생성
      thumbnailFile ??= await VideoUploadUtils.generateThumbnail(
        videoFile.path,
      );
      if (thumbnailFile == null) {
        throw Exception('썸네일 생성 실패');
      }

      // ✅ 3) UI는 "썸네일 먼저" 세팅 → 검정 화면 방지를 위해 썸네일을 먼저 설정한 후 로딩 상태 활성화
      if (mounted) {
        widget.onLocalThumbnailChanged(thumbnailFile);
        widget.onLocalVideoChanged(videoFile);

        final svc = NodeComponentService();
        svc.setTempVideoFile(_nsKey, videoFile.path);
        svc.setTempVideoThumbnail(_nsKey, thumbnailFile.path);
      }

      // ✅ 4) 썸네일이 설정된 후에 로딩 상태 활성화 (검정 화면 방지)
      widget.onIsUploadingThumbChanged(true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final vc = VideoPlayerController.file(videoFile);
        widget.onVideoControllerChanged(vc);
        vc
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
              if (!mounted) return;
              widget.onVideoControllerChanged(null);
              setState(() {
                widget.onIsUploadingThumbChanged(false);
                widget.onLocalVideoChanged(null);
                widget.onLocalThumbnailChanged(null);
              });
            });
      });

      // ✅ 클립 노드와 동일한 업로드 플로우 사용 (썸네일/압축/업로드/취소 추적)
      await upload.uploadEditorVideo(
        file: videoFile,
        existingNodeId: _thumbRefId, // refId로 재사용
        editorId: 'publish_${_nsKey}',
        initialThumbnailPath: thumbnailFile.path, // ✅ 트림 썸네일이면 즉시 사용
        onCreateNode: (localPath, fileName, {thumbnailPath, aspectRatio}) {
          // Step1에는 실제 노드를 만들지 않지만, refId를 반환해서 UploadService가 추적하게 함
          return _thumbRefId;
        },
        onUpdateThumbnail: (nodeId, thumbnailPath) {
          if (!mounted) return;
          if (thumbnailPath.isEmpty) return;
          widget.onLocalThumbnailChanged(File(thumbnailPath));
          final svc = NodeComponentService();
          svc.setTempVideoThumbnail(_nsKey, thumbnailPath);
        },
        onCompressionComplete: (nodeId, processedLocalPath) {
          if (!mounted) return;
          if (processedLocalPath.isEmpty) return;

          // ✅ 압축 완료 즉시 로컬 비디오를 교체 (검정 화면 방지 패턴)
          // 썸네일은 유지한 채로 비디오 파일만 교체하여 검정 화면 방지
          final f = File(processedLocalPath);
          widget.onLocalVideoChanged(f);
          final svc = NodeComponentService();
          svc.setTempVideoFile(_nsKey, processedLocalPath);

          // ✅ 컨트롤러를 새 경로로 교체 (썸네일은 유지되어 검정 화면 방지)
          final vc = VideoPlayerController.file(f);
          widget.onVideoControllerChanged(vc);
          vc
              .initialize()
              .then((_) {
                if (mounted && widget.videoController == vc) {
                  widget.videoController?.play();
                  widget.videoController?.setLooping(true);
                  setState(() {});
                }
              })
              .catchError((e) {
                debugPrint('[Step1] 압축 후 비디오 컨트롤러 초기화 실패: $e');
                if (mounted) {
                  widget.onVideoControllerChanged(null);
                }
              });
        },
        onUploadComplete: (
          nodeId,
          url, {
          fallbackLocalPath,
          processedLocalPath,
        }) async {
          if (!mounted) return;
          if (url.isEmpty) {
            ErrorHandler.showError(
              context,
              AppLocalizations.of(context).t('video_url_failed'),
            );
            widget.onIsUploadingThumbChanged(false);
            return;
          }

          widget.onThumbnailUrlChanged(url);
          widget.onIsUploadingThumbChanged(false);
          widget.onEditModeChanged(false);
          widget.controller.reverse();
          FocusScope.of(context).unfocus();
        },
        onDeleteNode: (nodeId) {
          // Step1에서는 노드 삭제 대신 상태 초기화
          if (!mounted) return;
          widget.onVideoControllerChanged(null);
          widget.onLocalVideoChanged(null);
          widget.onLocalThumbnailChanged(null);
          widget.onIsUploadingThumbChanged(false);
        },
        isMounted: () => mounted,
        context: context,
        showErrorDialog: (title, message) async {
          if (!mounted) return;
          await DialogUtils.showInfoDialog(
            context,
            title: title,
            message: message,
          );
        },
      );
    } catch (e) {
      if (mounted) {
        await VideoUploadUtils.showGeneralErrorDialog(context);
        // ✅ 에러 발생 시 기존 상태 복원 (이미지가 비지 않도록)
        if (previousLocalThumbnail != widget.localThumbnailFile) {
          widget.onLocalThumbnailChanged(previousLocalThumbnail);
        }
        if (previousLocalVideo != widget.localVideoFile) {
          widget.onLocalVideoChanged(previousLocalVideo);
        }
        if (previousVideoController != widget.videoController) {
          widget.onVideoControllerChanged(previousVideoController);
        }
        if (previousThumbnailUrl != widget.exportedThumbnailImageUrl) {
          widget.onThumbnailUrlChanged(previousThumbnailUrl);
        }
        widget.onIsUploadingThumbChanged(previousIsUploading);
        widget.onEditModeChanged(false);
        widget.controller.reverse();
        FocusScope.of(context).unfocus();
      }
    }
  }

  Future<void> _editThumbnail() async {
    widget.onEditModeChanged(false);
    widget.controller.reverse();
    FocusScope.of(context).unfocus();

    // ✅ 바텀시트 없이 바로 처리
    // 비디오가 있거나 썸네일이 없으면 갤러리 피커로, 아니면 편집 화면으로
    if (widget.exportedThumbnailImageUrl.isEmpty ||
        widget.localVideoFile != null) {
      await _openGalleryPicker();
      return;
    }

    // 이미지가 있으면 바로 편집 화면으로
    await _editThumbnailImage();
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
        ErrorHandler.handleError(
          context,
          e,
          customMessage: AppLocalizations.of(context).t('image_edit_failed'),
        );
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
