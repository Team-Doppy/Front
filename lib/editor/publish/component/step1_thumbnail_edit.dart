import 'dart:io';
import 'dart:ui' as ui;
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/image/media_picker_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:doppy/image/simple_image_editor_screen.dart';
import 'package:doppy/image/trimmer/video_trim_screen.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/editor/utils/video_upload_utils.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:doppy/editor/publish/component/thumbnail_edit_bottom_sheet.dart';
import 'package:doppy/image/utils/editor_image_provider.dart';
import 'package:doppy/pages/components/shimmer_box.dart';

/// 🎯 2줄 제한 TextInputFormatter
class _TwoLineTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final lines = text.split('\n');

    // 🎯 2줄을 넘어가면 입력 차단
    if (lines.length > 2) {
      // 기존 값 유지 (입력 무시)
      return oldValue;
    }

    return newValue;
  }
}

/// Step 1: 썸네일 & 글 편집 컴포넌트
class Step1ThumbnailEdit extends StatefulWidget {
  final String sessionKey;
  final double cardRadius;
  final TextEditingController titleController;
  final FocusNode titleFocusNode;
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
  final bool isThumbnailEditMode; // 썸네일 편집 모드로 들어왔는지 여부
  final bool isLoading; // 로딩 중인지 여부 (placeholder 숨김용)

  const Step1ThumbnailEdit({
    super.key,
    required this.sessionKey,
    required this.cardRadius,
    required this.titleController,
    required this.titleFocusNode,
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
    this.isThumbnailEditMode = false,
    this.isLoading = false,
  });

  @override
  State<Step1ThumbnailEdit> createState() => _Step1ThumbnailEditState();
}

class _Step1ThumbnailEditState extends State<Step1ThumbnailEdit> {
  String get _nsKey => widget.sessionKey;
  String get _thumbRefId => 'thumb_${widget.sessionKey}';

  // 🎯 업로드 태스크 추적 (썸네일 변경 시 취소용)
  UploadTask? _currentImageUploadTask;

  // ✅ 썸네일 첫 프레임 지연(디스크 캐시 → 디코딩/업로드) 체감 완화용 precache 트래킹
  String? _lastPrecacheSignature;

  // 🎯 포커스/키보드에 따른 UI 전환을 더 부드럽게 만들기 위한 내부 상태
  bool _hasTextFocus = false;

  // ✅ 미디어 피커/전환 중 "빈 썸네일 플레이스홀더"가 파르르 깜빡이는 문제 방지용
  bool _suppressEmptyPlaceholder = false;

  // 🎯 비디오 첫 프레임 전 검정 플래시 방지용 "포스터(썸네일) 유지" 상태
  VideoPlayerController? _posterObservedController;
  VoidCallback? _posterListener;
  bool _showVideoPoster = false;

  // 🎯 상태 스냅샷 (취소 시 복원용)
  _ThumbnailStateSnapshot? _stateSnapshot;

  /// 상태 스냅샷 저장
  void _saveStateSnapshot() {
    _stateSnapshot = _ThumbnailStateSnapshot(
      localThumbnail: widget.localThumbnailFile,
      localVideo: widget.localVideoFile,
      videoController: widget.videoController,
      thumbnailUrl: widget.exportedThumbnailImageUrl,
      isUploading: widget.isUploadingThumb,
    );
  }

  /// 상태 복원
  void _restoreStateSnapshot() {
    if (_stateSnapshot == null || !_isMounted()) return;
    final snapshot = _stateSnapshot!;
    if (snapshot.localThumbnail != widget.localThumbnailFile) {
      widget.onLocalThumbnailChanged(snapshot.localThumbnail);
    }
    if (snapshot.localVideo != widget.localVideoFile) {
      widget.onLocalVideoChanged(snapshot.localVideo);
    }
    if (snapshot.videoController != widget.videoController) {
      widget.onVideoControllerChanged(snapshot.videoController);
    }
    if (snapshot.thumbnailUrl != widget.exportedThumbnailImageUrl) {
      widget.onThumbnailUrlChanged(snapshot.thumbnailUrl);
    }
    if (snapshot.isUploading != widget.isUploadingThumb) {
      widget.onIsUploadingThumbChanged(snapshot.isUploading);
    }
  }

  /// 업로드 태스크 취소
  void _cancelUploadTasks() {
    if (!_isMounted()) return;
    try {
      final upload = context.read<UploadService>();
      upload.cancelByRef(_thumbRefId);
      if (_currentImageUploadTask != null) {
        upload.cancel(_currentImageUploadTask!.id);
        _currentImageUploadTask?.removeListener(() {});
        _currentImageUploadTask = null;
      }
    } catch (e) {
      debugPrint('[Step1] 업로드 태스크 취소 중 오류: $e');
    }
  }

  /// mounted 체크 헬퍼
  bool _isMounted() => mounted && context.mounted;

  @override
  void initState() {
    super.initState();
    _hasTextFocus = widget.titleFocusNode.hasFocus;
    widget.titleFocusNode.addListener(_onTextFocusChanged);

    _attachPosterListener(widget.videoController);

    // ✅ 첫 진입에서 썸네일이 "흰 카드 → 늦게 등장"하는 체감 완화: 다음 프레임에 미리 디코딩
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheThumbnailIfNeeded();
    });
  }

  @override
  void didUpdateWidget(covariant Step1ThumbnailEdit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoController != widget.videoController) {
      // 🎯 dispose 체크: 새 컨트롤러 유효성 확인
      if (widget.videoController != null) {
        try {
          // 🎯 dispose 체크: value 접근으로 컨트롤러 유효성 확인
          final _ = widget.videoController!.value;
          _attachPosterListener(widget.videoController);
        } catch (e) {
          debugPrint('[Step1] didUpdateWidget: dispose된 컨트롤러 무시: $e');
          _attachPosterListener(null);
        }
      } else {
        _attachPosterListener(null);
      }
    }

    // ✅ 이미지 URL이 변경되면 미리 캐시
    if (oldWidget.exportedThumbnailImageUrl !=
            widget.exportedThumbnailImageUrl &&
        widget.exportedThumbnailImageUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _precacheThumbnailIfNeeded();
      });
    }
  }

  Future<void> _precacheThumbnailIfNeeded() async {
    if (!_isMounted()) return;

    // 로컬 파일/비디오는 여기서 precache하지 않음 (이미 file/video path로 즉시 렌더링됨)
    if (widget.localThumbnailFile != null || widget.localVideoFile != null) {
      return;
    }

    final url = widget.exportedThumbnailImageUrl;
    if (url.isEmpty) return;
    if (_isVideoUrl(url)) return;

    // 썸네일 렌더링과 동일한 provider/Resize 정책을 사용해야 캐시 히트가 보장됨
    final screenWidth = MediaQuery.sizeOf(context).width;
    final decodeWidth = EditorImageProvider.editingDecodeWidth(
      context,
      screenWidth,
    );
    final signature = '${EditorImageProvider.normalizeUrl(url)}@$decodeWidth';
    if (_lastPrecacheSignature == signature) return;
    _lastPrecacheSignature = signature;

    final built = EditorImageProvider.build(
      url: url,
      isEditing: true,
      decodeWidth: decodeWidth,
    );

    try {
      await precacheImage(built.effectiveProvider, context);
    } catch (e) {
      // precache 실패는 UI를 막지 않도록 무시
      debugPrint('[Step1ThumbnailEdit] ⚠️ precache 실패: url=$url, e=$e');
    }
  }

  @override
  void dispose() {
    widget.titleFocusNode.removeListener(_onTextFocusChanged);

    _detachPosterListener();

    // 🎯 업로드 태스크 취소 (dispose 시 모든 진행 중인 업로드 중단)
    try {
      if (mounted) {
        _cancelUploadTasks();
        debugPrint('[Step1] dispose: 업로드 태스크 취소 완료');
      }
    } catch (e) {
      debugPrint('[Step1] dispose: 업로드 태스크 취소 중 오류 (무시): $e');
    }

    super.dispose();
  }

  void _detachPosterListener() {
    if (_posterObservedController != null && _posterListener != null) {
      try {
        // 🎯 dispose 체크: 컨트롤러 유효성 확인
        // value 접근 전에 먼저 try-catch로 감싸서 안전하게 처리
        final controller = _posterObservedController!;
        final listener = _posterListener!;

        try {
          // value 접근 시도 (dispose된 경우 예외 발생)
          final _ = controller.value;
          controller.removeListener(listener);
        } catch (e) {
          // controller가 dispose된 타이밍 등은 무시
          debugPrint('[Step1] 포스터 리스너 제거 오류 (dispose됨): $e');
        }
      } catch (e) {
        // 예상치 못한 오류
        debugPrint('[Step1] 포스터 리스너 제거 중 예상치 못한 오류: $e');
      }
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
      // 🎯 dispose 체크: 위젯이 mounted인지 확인
      if (!_isMounted()) {
        _detachPosterListener();
        return;
      }

      // 🎯 dispose 체크: 컨트롤러 참조 저장 (클로저에서 사용)
      final controllerRef = controller;

      try {
        // 🎯 dispose 체크: value 접근으로 컨트롤러 유효성 확인
        final v = controllerRef.value;

        // position이 조금이라도 진행되면(첫 프레임 디코딩/표시 이후) 포스터를 내린다.
        if (v.isInitialized && v.position > const Duration(milliseconds: 50)) {
          // 🎯 dispose 체크: setState 전에 위젯이 여전히 mounted인지 재확인
          if (!_isMounted() || !_showVideoPoster) return;

          try {
            // 🎯 dispose 체크: setState 전에 컨트롤러 유효성 재확인
            final _ = controllerRef.value;
            setState(() => _showVideoPoster = false);
          } catch (e) {
            // dispose된 컨트롤러
            debugPrint('[Step1] 포스터 리스너 setState 전 오류 (dispose됨): $e');
            _detachPosterListener();
          }
        }
      } catch (e) {
        // dispose된 컨트롤러
        debugPrint('[Step1] 포스터 리스너 오류 (dispose됨): $e');
        _detachPosterListener();
      }
    }

    _posterListener = listener;

    // 🎯 dispose 체크: 리스너 추가 전 컨트롤러 유효성 확인
    try {
      // value 접근 시도 (dispose된 경우 예외 발생)
      final _ = controller.value;
      controller.addListener(listener);
    } catch (e) {
      debugPrint('[Step1] 포스터 리스너 추가 오류 (dispose됨): $e');
      // dispose된 컨트롤러는 정리
      _posterObservedController = null;
      _posterListener = null;
      _showVideoPoster = false;
    }
  }

  void _onTextFocusChanged() {
    final hasFocus = widget.titleFocusNode.hasFocus;
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
    // ✅ 애니메이션 최적화: 더 빠른 duration과 부드러운 curve
    final target = shouldHide ? 1.0 : 0.0;
    try {
      widget.controller.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic, // ✅ 더 부드러운 애니메이션
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
                            children: [_buildTitleField()],
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
            FocusScope.of(context).unfocus();
            widget.onEditModeChanged(false);
          },
          onTap: () {
            // 🎯 이미지 탭 완료 시 갤러리 피커 열기
            // 텍스트 필드 포커스 노드 직접 해제
            widget.titleFocusNode.unfocus();
            FocusScope.of(context).unfocus();
            widget.onEditModeChanged(false);
            _openGalleryPicker();
          },
          onLongPress: _toggleEditMode,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                (widget.cardRadius + 2) * 2,
              ), // ✅ 더 둥글게
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                widget.cardRadius * 2,
              ), // ✅ 더 둥글게
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
                            width: 20,
                            height: 20,
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
                      widget.videoController != null)
                    Builder(
                      builder: (context) {
                        // 🎯 dispose 체크: 컨트롤러 유효성 확인
                        if (widget.videoController == null) {
                          return const SizedBox.shrink();
                        }

                        try {
                          // 🎯 dispose 체크: value 접근으로 컨트롤러 유효성 확인
                          final isInitialized =
                              widget.videoController!.value.isInitialized;
                          if (!isInitialized) {
                            return const SizedBox.shrink();
                          }
                        } catch (e) {
                          // dispose된 컨트롤러
                          debugPrint('[Step1] 음소거 버튼 빌드 오류 (dispose됨): $e');
                          return const SizedBox.shrink();
                        }

                        return Positioned(
                          right: 12,
                          bottom: 12,
                          child: RepaintBoundary(
                            child: AnimatedOpacity(
                              opacity: widget.editMode ? 0.3 : 1.0,
                              duration: const Duration(milliseconds: 150),
                              child: GestureDetector(
                                onTap: () {
                                  // 🎯 dispose 체크: 컨트롤러 유효성 확인
                                  if (widget.videoController == null) return;

                                  try {
                                    // 🎯 dispose 체크: value 접근으로 컨트롤러 유효성 확인
                                    final controller = widget.videoController!;
                                    final isInitialized =
                                        controller.value.isInitialized;

                                    if (!isInitialized) return;

                                    // 🎯 dispose 체크: volume 접근 전에 컨트롤러 유효성 재확인
                                    final currentVolume =
                                        controller.value.volume;

                                    if (mounted) {
                                      setState(() {
                                        try {
                                          // 🎯 dispose 체크: setVolume 전에 컨트롤러 유효성 재확인
                                          final _ = controller.value;
                                          if (currentVolume > 0) {
                                            controller.setVolume(0);
                                          } else {
                                            controller.setVolume(1);
                                          }
                                        } catch (e) {
                                          debugPrint(
                                            '[Step1] 음소거 버튼 setVolume 오류 (dispose됨): $e',
                                          );
                                        }
                                      });
                                    }
                                  } catch (e) {
                                    debugPrint(
                                      '[Step1] 음소거 버튼 오류 (dispose됨): $e',
                                    );
                                  }
                                },
                                child: Builder(
                                  builder: (context) {
                                    if (widget.videoController == null) {
                                      return const SizedBox.shrink();
                                    }

                                    try {
                                      // 🎯 dispose 체크: value 접근으로 컨트롤러 유효성 확인
                                      final volume =
                                          widget.videoController!.value.volume;
                                      final isMuted = volume > 0;

                                      return Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.5),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isMuted
                                              ? Icons.volume_up_rounded
                                              : Icons.volume_off_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      );
                                    } catch (e) {
                                      debugPrint(
                                        '[Step1] 음소거 버튼 아이콘 빌드 오류 (dispose됨): $e',
                                      );
                                      return const SizedBox.shrink();
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                  // 편집/변경 버튼 (포커스 시 숨김)
                  if (!widget.editMode && !_hasTextFocus)
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

  Widget _buildThumbnailContent() {
    // 🎯 로컬 비디오 파일이 있는 경우
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
            Builder(
              builder: (context) {
                // 🎯 dispose 체크: 컨트롤러 유효성 확인
                if (widget.videoController == null) {
                  return const SizedBox.shrink();
                }

                try {
                  // 🎯 dispose 체크: value 접근으로 컨트롤러 유효성 확인
                  final controller = widget.videoController!;
                  final isInitialized = controller.value.isInitialized;

                  if (!isInitialized) {
                    return const SizedBox.shrink();
                  }

                  // 🎯 dispose 체크: size 접근 전에 컨트롤러 유효성 재확인
                  final size = controller.value.size;

                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    opacity: _showVideoPoster ? 0.0 : 1.0,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  );
                } catch (e) {
                  // dispose된 컨트롤러
                  debugPrint('[Step1] 비디오 렌더링 오류 (dispose됨): $e');
                  return const SizedBox.shrink();
                }
              },
            ),
          ],
        ),
      );
    }

    // 🎯 서버 비디오 URL인 경우 (videoController가 이미 설정됨)
    // 썸네일 편집 모드가 아니어도 비디오 URL이면 비디오 플레이어 표시
    if (widget.exportedThumbnailImageUrl.isNotEmpty &&
        _isVideoUrl(widget.exportedThumbnailImageUrl) &&
        widget.videoController != null) {
      return SizedBox.expand(
        key: ValueKey('server_video_${widget.exportedThumbnailImageUrl}'),
        child: Builder(
          builder: (context) {
            // 🎯 dispose 체크: 컨트롤러 유효성 확인
            if (widget.videoController == null) {
              return const ShimmerBox(
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.zero,
              );
            }

            try {
              // 🎯 dispose 체크: value 접근으로 컨트롤러 유효성 확인
              final controller = widget.videoController!;
              final isInitialized = controller.value.isInitialized;

              if (!isInitialized) {
                return const ShimmerBox(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                );
              }

              // 🎯 dispose 체크: size 접근 전에 컨트롤러 유효성 재확인
              final size = controller.value.size;

              return FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: VideoPlayer(controller),
                ),
              );
            } catch (e) {
              // dispose된 컨트롤러
              debugPrint('[Step1] 서버 비디오 렌더링 오류 (dispose됨): $e');
              return const ShimmerBox(
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.zero,
              );
            }
          },
        ),
      );
    }

    // 🎯 로컬 썸네일 파일이 있는 경우
    if (widget.localThumbnailFile != null) {
      return SizedBox.expand(
        key: ValueKey('local_${widget.localThumbnailFile!.path}'),
        child: Image.file(widget.localThumbnailFile!, fit: BoxFit.cover),
      );
    }

    // 🎯 빈 썸네일 상태
    if (widget.exportedThumbnailImageUrl.isEmpty) {
      // ✅ 빈 썸네일 상태:
      // - 포커스 중이거나, 피커 전환 중에는 placeholder를 숨긴다.
      // - 로딩 중일 때는 placeholder를 숨기고 쉬머만 보인다.
      // - "empty ↔ hidden"을 서로 다른 key로 스위칭하면 AnimatedSwitcher가
      //   짧은 시간에 여러 번 트리거되어 번쩍임이 생길 수 있으므로 key를 고정한다.
      final shouldShow =
          !_hasTextFocus && !_suppressEmptyPlaceholder && !widget.isLoading;

      // 로딩 중일 때는 쉬머만 보이기
      if (widget.isLoading) {
        return SizedBox.expand(
          key: const ValueKey('loading'),
          child: ShimmerBox(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
          ),
        );
      }

      return SizedBox.expand(
        key: const ValueKey('empty'),
        child: IgnorePointer(
          ignoring: !shouldShow,
          child: AnimatedOpacity(
            opacity: shouldShow ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
            child: const _EmptyImagePlaceholder(),
          ),
        ),
      );
    } else {
      // 🎯 네트워크 이미지 URL인 경우: EditorImageProvider를 사용하여 single_image_component/row_image_component와
      // 동일한 캐시 키(ResizeImage)를 사용하여 캐시 재사용률을 높임
      // 🎯 비디오 URL인 경우는 이미 위에서 처리했으므로 여기서는 이미지만 처리
      final screenWidth = MediaQuery.sizeOf(context).width;
      final decodeWidth = EditorImageProvider.editingDecodeWidth(
        context,
        screenWidth,
      );
      final built = EditorImageProvider.build(
        url: widget.exportedThumbnailImageUrl,
        isEditing: true, // 썸네일 편집은 항상 편집 모드
        decodeWidth: decodeWidth,
      );

      return SizedBox.expand(
        key: ValueKey('network_${widget.exportedThumbnailImageUrl}'),
        child: Image(
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
                '[Step1ThumbnailEdit] ❌ 썸네일 로드 실패: url=${widget.exportedThumbnailImageUrl}, error=$error',
              );
              return true;
            }());
            return const _EmptyImagePlaceholder();
          },
        ),
      );
    }
  }

  Widget _buildTitleField() {
    // 🎯 로딩 중일 때는 쉬머 표시
    if (widget.isLoading) {
      return Center(
        child: ShimmerBox(
          width: MediaQuery.of(context).size.width * 0.6,
          height: 35,
        ),
      );
    }

    // ✅ 항상 onSurface 색상 사용
    final textColor = Theme.of(context).colorScheme.onSurface;

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
                color: textColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
              maxLines: 2,
              minLines: 1,
              scrollPhysics: const NeverScrollableScrollPhysics(),
              inputFormatters: [
                // 🎯 2줄 제한: 최대 2줄까지만 입력 허용
                _TwoLineTextInputFormatter(),
              ],
              decoration: InputDecoration(
                hintText: AppLocalizations.of(
                  context,
                ).t('title_input_placeholder'),
                hintStyle: TextStyle(color: textColor.withOpacity(0.3)),
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

  void _toggleEditMode() {
    widget.onEditModeChanged(!widget.editMode);
    if (!widget.editMode) {
      _syncThumbnailAnimation(shouldHide: true);
    } else {
      _syncThumbnailAnimation(shouldHide: false);
    }
  }

  Widget _buildEditButton() {
    final bool isVideo =
        widget.localVideoFile != null ||
        _isVideoUrl(widget.exportedThumbnailImageUrl);
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
    if (_isMounted()) {
      setState(() => _suppressEmptyPlaceholder = true);
    }
    FocusScope.of(context).unfocus();
    widget.onEditModeChanged(false);
    widget.controller.reverse();
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      await _pickAndUploadImage();
    } finally {
      if (_isMounted()) {
        setState(() => _suppressEmptyPlaceholder = false);
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    _saveStateSnapshot();

    final result = await Navigator.push<MediaPickerResult>(
      context,
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder:
            (context) => MediaPickerScreen(
              initialMediaType: MediaType.image,
              maxSelectionCount: 1,
              enableToggle: true,
              onMediaSelected: (_) {},
            ),
      ),
    );

    if (result == null || result.files.isEmpty) {
      _restoreStateSnapshot();
      return;
    }

    if (!_isMounted()) return;

    final file = result.files.first;
    if (result.selectedMediaType == MediaType.video) {
      await _processVideoFileFromPicker(
        file,
        initialThumbnailPath: result.thumbnailPath,
      );
      return;
    }

    _cancelUploadTasks();

    widget.onLocalThumbnailChanged(file);
    widget.onIsUploadingThumbChanged(true);
    widget.onVideoControllerChanged(null);
    widget.onLocalVideoChanged(null);

    final svc = NodeComponentService();
    svc.clearTempVideoFile(_nsKey);

    try {
      final upload = context.read<UploadService>();
      final tasks = await upload.uploadFilesViaServerBatches(
        [file],
        kind: UploadKind.editorImage,
        refId: _nsKey,
      );
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

        if (t.state == UploadState.success && (t.url ?? '').isNotEmpty) {
          if (_isMounted()) {
            widget.onThumbnailUrlChanged(t.url!);
            widget.onLocalThumbnailChanged(null);
          }
        } else if (_isMounted()) {
          DialogUtils.showInfoDialog(
            context,
            title: AppLocalizations.of(context).t('thumbnail_upload_failed'),
            message: AppLocalizations.of(context).t('upload_error_occurred'),
          );
          widget.onLocalThumbnailChanged(null);
        }
      }
    } catch (e) {
      if (_isMounted()) {
        DialogUtils.showInfoDialog(
          context,
          title: AppLocalizations.of(context).t('upload_error'),
          message: AppLocalizations.of(context).t('upload_error_occurred'),
          buttonText: AppLocalizations.of(context).t('ok'),
        );
        widget.onLocalThumbnailChanged(null);
      }
    } finally {
      if (_isMounted()) {
        widget.onIsUploadingThumbChanged(false);
        // 🎯 제목 필드에 포커스가 있으면 편집 모드(축소 모드) 유지
        if (!widget.titleFocusNode.hasFocus) {
          widget.onEditModeChanged(false);
          widget.controller.reverse();
          FocusScope.of(context).unfocus();
        }
      }
    }
  }

  /// 🎯 선택된 영상 파일 처리
  Future<void> _processVideoFileFromPicker(
    File videoFile, {
    String? initialThumbnailPath,
  }) async {
    _saveStateSnapshot();

    final validationError = await VideoUploadUtils.validateFile(
      context,
      videoFile.path,
    );
    if (validationError != null) {
      _restoreStateSnapshot();
      return;
    }

    try {
      _cancelUploadTasks();

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

      if (_isMounted()) {
        widget.onLocalThumbnailChanged(thumbnailFile);
        widget.onLocalVideoChanged(videoFile);
        final svc = NodeComponentService();
        svc.setTempVideoFile(_nsKey, videoFile.path);
        svc.setTempVideoThumbnail(_nsKey, thumbnailFile.path);
      }

      widget.onIsUploadingThumbChanged(true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 🎯 dispose 체크: addPostFrameCallback 실행 시점에 위젯이 dispose되었을 수 있음
        if (!_isMounted()) return;

        final vc = VideoPlayerController.file(videoFile);

        // 🎯 컨트롤러 참조 저장 (dispose 체크용)
        final controllerRef = vc;

        // 🎯 dispose 체크: 위젯이 여전히 mounted인지 재확인
        if (!_isMounted()) {
          try {
            controllerRef.dispose();
          } catch (_) {}
          return;
        }

        widget.onVideoControllerChanged(vc);

        vc
            .initialize()
            .then((_) {
              // 🎯 dispose 체크 강화: controllerRef만 사용 (widget.videoController 접근 최소화)
              if (!_isMounted()) {
                try {
                  controllerRef.dispose();
                } catch (_) {}
                return;
              }

              // 🎯 controllerRef만 사용하여 dispose 체크
              try {
                // 🎯 dispose 체크: value 접근으로 컨트롤러 유효성 확인
                final isInitialized = controllerRef.value.isInitialized;

                if (isInitialized) {
                  // 🎯 dispose 체크: play/setLooping 전에 컨트롤러 유효성 재확인
                  final _ = controllerRef.value;
                  controllerRef.play();
                  controllerRef.setLooping(true);

                  // 🎯 dispose 체크: setState 전에 위젯이 여전히 mounted인지 재확인
                  if (_isMounted()) {
                    try {
                      // 🎯 dispose 체크: setState 전에 컨트롤러 유효성 재확인
                      final _ = controllerRef.value;
                      setState(() {});
                    } catch (e) {
                      debugPrint('[Step1] 비디오 컨트롤러 setState 오류 (dispose됨): $e');
                    }
                  }
                }
              } catch (e) {
                debugPrint('[Step1] 비디오 컨트롤러 접근 오류 (dispose됨): $e');
                if (_isMounted()) {
                  widget.onVideoControllerChanged(null);
                }
              }
            })
            .catchError((error) {
              debugPrint('[Step1] 비디오 컨트롤러 초기화 실패: $error');
              if (!_isMounted()) return;

              // 🎯 controllerRef만 사용하여 dispose 체크
              try {
                controllerRef.dispose();
              } catch (_) {}
              widget.onVideoControllerChanged(null);
              if (_isMounted()) {
                setState(() {
                  widget.onIsUploadingThumbChanged(false);
                  widget.onLocalVideoChanged(null);
                  widget.onLocalThumbnailChanged(null);
                });
              }
            });
      });

      // ✅ 클립 노드와 동일한 업로드 플로우 사용 (썸네일/압축/업로드/취소 추적)
      final upload = context.read<UploadService>();
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
          if (!_isMounted() || thumbnailPath.isEmpty) return;
          widget.onLocalThumbnailChanged(File(thumbnailPath));
          NodeComponentService().setTempVideoThumbnail(_nsKey, thumbnailPath);
        },
        onCompressionComplete: (nodeId, processedLocalPath) {
          if (!_isMounted() || processedLocalPath.isEmpty) return;
          final f = File(processedLocalPath);
          widget.onLocalVideoChanged(f);
          NodeComponentService().setTempVideoFile(_nsKey, processedLocalPath);
          final vc = VideoPlayerController.file(f);

          // 🎯 컨트롤러 참조 저장 (dispose 체크용)
          final controllerRef = vc;
          widget.onVideoControllerChanged(vc);

          vc
              .initialize()
              .then((_) {
                // 🎯 dispose 체크 강화: controllerRef만 사용 (widget.videoController 접근 최소화)
                if (!_isMounted()) {
                  try {
                    controllerRef.dispose();
                  } catch (_) {}
                  return;
                }

                // 🎯 controllerRef만 사용하여 dispose 체크
                try {
                  // 🎯 dispose 체크: value 접근으로 컨트롤러 유효성 확인
                  final isInitialized = controllerRef.value.isInitialized;

                  if (isInitialized) {
                    // 🎯 dispose 체크: play/setLooping 전에 컨트롤러 유효성 재확인
                    final _ = controllerRef.value;
                    controllerRef.play();
                    controllerRef.setLooping(true);

                    // 🎯 dispose 체크: setState 전에 위젯이 여전히 mounted인지 재확인
                    if (_isMounted()) {
                      try {
                        // 🎯 dispose 체크: setState 전에 컨트롤러 유효성 재확인
                        final _ = controllerRef.value;
                        setState(() {});
                      } catch (e) {
                        debugPrint(
                          '[Step1] 압축 후 비디오 컨트롤러 setState 오류 (dispose됨): $e',
                        );
                      }
                    }
                  }
                } catch (e) {
                  debugPrint('[Step1] 압축 후 비디오 컨트롤러 접근 오류 (dispose됨): $e');
                  if (_isMounted()) {
                    widget.onVideoControllerChanged(null);
                  }
                }
              })
              .catchError((e) {
                debugPrint('[Step1] 압축 후 비디오 컨트롤러 초기화 실패: $e');
                if (!_isMounted()) return;

                // 🎯 controllerRef만 사용하여 dispose 체크
                try {
                  controllerRef.dispose();
                } catch (_) {}
                widget.onVideoControllerChanged(null);
              });
        },
        onUploadComplete: (
          nodeId,
          url, {
          fallbackLocalPath,
          processedLocalPath,
        }) async {
          if (!_isMounted()) return;
          if (url.isEmpty) {
            DialogUtils.showInfoDialog(
              context,
              title: AppLocalizations.of(context).t('video_url_failed'),
              message: AppLocalizations.of(context).t('upload_error_occurred'),
              buttonText: AppLocalizations.of(context).t('ok'),
            );
            widget.onIsUploadingThumbChanged(false);
            return;
          }
          widget.onThumbnailUrlChanged(url);
          widget.onIsUploadingThumbChanged(false);
          // 🎯 제목 필드에 포커스가 있으면 편집 모드(축소 모드) 유지
          if (!widget.titleFocusNode.hasFocus) {
            widget.onEditModeChanged(false);
            widget.controller.reverse();
            FocusScope.of(context).unfocus();
          }
        },
        onDeleteNode: (_) {
          if (!_isMounted()) return;
          widget.onVideoControllerChanged(null);
          widget.onLocalVideoChanged(null);
          widget.onLocalThumbnailChanged(null);
          widget.onIsUploadingThumbChanged(false);
        },
        isMounted: () => mounted,
        context: context,
        showErrorDialog: (title, message) async {
          if (!_isMounted()) return;
          await DialogUtils.showInfoDialog(
            context,
            title: title,
            message: message,
          );
        },
      );
    } catch (e) {
      if (_isMounted()) {
        await VideoUploadUtils.showGeneralErrorDialog(context);
        _restoreStateSnapshot();
        // 🎯 제목 필드에 포커스가 있으면 편집 모드(축소 모드) 유지
        if (!widget.titleFocusNode.hasFocus) {
          widget.onEditModeChanged(false);
          widget.controller.reverse();
          FocusScope.of(context).unfocus();
        }
      }
    }
  }

  Future<void> _editThumbnail() async {
    widget.onEditModeChanged(false);
    widget.controller.reverse();
    FocusScope.of(context).unfocus();

    final isVideoThumb =
        widget.localVideoFile != null ||
        _isVideoUrl(widget.exportedThumbnailImageUrl);

    // ✅ 비디오 썸네일이면: 이미지 편집기가 아니라 영상 편집기로 들어간다.
    if (isVideoThumb) {
      await _editThumbnailVideo();
      return;
    }

    // 썸네일이 비어있으면 갤러리로
    if (widget.exportedThumbnailImageUrl.isEmpty) {
      await _openGalleryPicker();
      return;
    }

    final choice = await ThumbnailEditBottomSheet.show(context);
    if (!_isMounted()) return;

    if (choice == ThumbnailEditChoice.edit) {
      await _editThumbnailImage();
    } else if (choice == ThumbnailEditChoice.change) {
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
          DialogUtils.showInfoDialog(
            context,
            title: AppLocalizations.of(context).t('image_load_failed'),
            message: AppLocalizations.of(context).t('upload_error_occurred'),
            buttonText: AppLocalizations.of(context).t('ok'),
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

      if (result == null || !_isMounted() || result is! Uint8List) return;

      widget.onIsUploadingThumbChanged(true);

      final upload = context.read<UploadService>();
      final tempFile = File(
        '${Directory.systemTemp.path}/edited_thumbnail_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(result);

      final tasks = await upload.uploadFilesViaServerBatches(
        [tempFile],
        kind: UploadKind.editorImage,
        refId: _nsKey,
      );

      try {
        await tempFile.delete();
      } catch (_) {}

      final newUrl = tasks.firstOrNull?.url;
      if (newUrl == null || newUrl.isEmpty) {
        if (_isMounted()) {
          DialogUtils.showInfoDialog(
            context,
            title:
                tasks.isEmpty
                    ? AppLocalizations.of(context).t('thumbnail_upload_failed')
                    : AppLocalizations.of(context).t('upload_url_failed'),
            message: AppLocalizations.of(context).t('upload_error_occurred'),
            buttonText: AppLocalizations.of(context).t('ok'),
          );
        }
        return;
      }

      if (_isMounted()) {
        widget.onThumbnailUrlChanged(newUrl);
        setState(() {});
      }
    } catch (e) {
      if (_isMounted()) {
        DialogUtils.showInfoDialog(
          context,
          title: AppLocalizations.of(context).t('image_edit_failed'),
          message: AppLocalizations.of(context).t('upload_error_occurred'),
          buttonText: AppLocalizations.of(context).t('ok'),
        );
      }
    } finally {
      if (_isMounted()) {
        widget.onIsUploadingThumbChanged(false);
      }
    }
  }

  Future<void> _editThumbnailVideo() async {
    // ✅ 로컬 비디오가 있어야 “영상 편집기”로 들어갈 수 있다.
    // 서버 비디오 URL만 있는 경우는 안전하게 “변경(갤러리)”로 유도한다.
    final file = widget.localVideoFile;
    if (file == null) {
      await _openGalleryPicker();
      return;
    }

    try {
      // VideoTrimScreen은 videoDuration이 필요하므로 file로 duration을 얻는다.
      final probe = VideoPlayerController.file(file);
      await probe.initialize();
      final duration = probe.value.duration;
      await probe.dispose();

      if (!_isMounted()) return;

      final trimResult = await Navigator.push<VideoTrimResult>(
        context,
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  VideoTrimScreen(videoFile: file, videoDuration: duration),
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );

      if (trimResult == null || !_isMounted()) return;

      // ✅ 트림 화면에서 생성된 썸네일(포스터)을 반영
      final thumbPath = trimResult.thumbnailPath;
      if (thumbPath != null && thumbPath.isNotEmpty) {
        final thumbFile = File(thumbPath);
        if (thumbFile.existsSync()) {
          widget.onLocalThumbnailChanged(thumbFile);
          // 세션 스코프에 썸네일 경로 저장 (복원/발행 플로우에서 사용)
          NodeComponentService().setTempVideoThumbnail(_nsKey, thumbPath);
        }
      }
    } catch (e) {
      debugPrint('[Step1ThumbnailEdit] 비디오 편집 진입 실패: $e');
      if (_isMounted()) {
        DialogUtils.showInfoDialog(
          context,
          title: AppLocalizations.of(context).t('video_load_failed'),
          message: AppLocalizations.of(context).t('upload_error_occurred'),
          buttonText: AppLocalizations.of(context).t('ok'),
        );
      }
    }
  }
}

/// 상태 스냅샷 클래스
class _ThumbnailStateSnapshot {
  final File? localThumbnail;
  final File? localVideo;
  final VideoPlayerController? videoController;
  final String thumbnailUrl;
  final bool isUploading;

  _ThumbnailStateSnapshot({
    required this.localThumbnail,
    required this.localVideo,
    required this.videoController,
    required this.thumbnailUrl,
    required this.isUploading,
  });
}

/// 빈 이미지 자리표시자
class _EmptyImagePlaceholder extends StatelessWidget {
  const _EmptyImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 30,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).t('tap_to_select_thumbnail'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
