import 'dart:ui' as ui;
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/editor/image/native_image_picker.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ThumbnailEditOverlay extends StatefulWidget {
  final String postId; // 서버에서 데이터 가져오기용
  final String sessionKey;
  final Function(String url, String? id) onThumbnailChanged;
  final Function(String title, String summary)?
  onMetadataChanged; // 제목/요약 변경 콜백

  const ThumbnailEditOverlay({
    super.key,
    required this.postId,
    required this.sessionKey,
    required this.onThumbnailChanged,
    this.onMetadataChanged,
  });

  @override
  State<ThumbnailEditOverlay> createState() => _ThumbnailEditOverlayState();
}

class _ThumbnailEditOverlayState extends State<ThumbnailEditOverlay> {
  String _thumbnailUrl = '';
  String? _thumbnailId;
  bool _isUploadingThumb = false;
  bool _isLoading = true;

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
      final blogService = BlogService();
      final metadata = await blogService.getPostMetadata(widget.postId);

      if (mounted) {
        final title = metadata['title'] ?? '';
        final summary = metadata['summary'] ?? '';
        final thumbnailUrl = metadata['thumbnailImageUrl'] ?? '';
        final thumbnailId = metadata['thumbnailImageId']?.toString();

        setState(() {
          // 제목
          _titleController.text = title;
          _originalTitle = title;

          // 요약
          _excerptController.text = summary;
          _originalSummary = summary;

          // 썸네일
          _thumbnailUrl = thumbnailUrl;
          _thumbnailId = thumbnailId;
          _originalThumbnailUrl = thumbnailUrl;

          _isLoading = false;
        });

        print('[ThumbnailEditOverlay] 메타데이터 로드 완료');
        print('  - 제목: ${_titleController.text}');
        print('  - 요약: ${_excerptController.text}');
        print('  - 썸네일: $_thumbnailUrl');
      }
    } catch (e) {
      print('[ThumbnailEditOverlay] 메타데이터 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.showError(context, '게시물 정보를 불러올 수 없습니다');
      }
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
    // 애니메이션 제거됨
    super.dispose();
  }

  void _toggleEditMode() {
    setState(() => _editMode = !_editMode);
  }

  Future<void> _openGalleryPicker() async {
    final picker = NativeImagePicker();
    final file = await picker.pickSingleImage();

    if (file != null) {
      if (!mounted) return;
      setState(() => _isUploadingThumb = true);
      try {
        final upload = context.read<UploadService>();
        final tasks = await upload.uploadFilesViaServerBatches([
          file,
        ], kind: UploadKind.editorImage);

        if (tasks.isNotEmpty) {
          final t = tasks.first;
          final hasUrl = (t.url ?? '').isNotEmpty;
          final hasServerImageId = (t.imageId ?? '').toString().isNotEmpty;

          if (t.state == UploadState.success && hasUrl && hasServerImageId) {
            // 먼저 persist (setState 전에)
            _thumbnailUrl = t.url!;
            _thumbnailId = t.imageId;
            // 원본도 업데이트 (업로드 후에는 이것이 새로운 기준)
            _originalThumbnailUrl = _thumbnailUrl;

            // Persist thumbnail
            NodeComponentService().setTempThumbnail(
              widget.sessionKey,
              url: _thumbnailUrl,
              id: _thumbnailId,
            );

            // 그 다음 UI 업데이트
            if (mounted) {
              setState(() {
                // 이미 위에서 설정했으므로 여기서는 UI만 업데이트
              });
            }

            // Notify parent
            widget.onThumbnailChanged(_thumbnailUrl, _thumbnailId);
          } else {
            if (mounted) {
              ErrorHandler.showError(context, '썸네일 업로드에 실패했어요. 다시 시도해주세요.');
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

  Widget _buildEditButton() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
            borderRadius: BorderRadius.circular(35),
          ),
          child: Row(
            children: [
              Text(
                '편집하기',
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

    print('[ThumbnailEditOverlay] ===== 변경사항 확인 =====');
    print('[ThumbnailEditOverlay] 원본 제목: "$_originalTitle"');
    print('[ThumbnailEditOverlay] 현재 제목: "$title"');
    print('[ThumbnailEditOverlay] 원본 요약: "$_originalSummary"');
    print('[ThumbnailEditOverlay] 현재 요약: "$summary"');
    print('[ThumbnailEditOverlay] 원본 썸네일: "$_originalThumbnailUrl"');
    print('[ThumbnailEditOverlay] 현재 썸네일: "$_thumbnailUrl"');

    // 변경사항 확인
    final titleChanged = title != _originalTitle;
    final summaryChanged = summary != _originalSummary;
    final thumbnailChanged = _thumbnailUrl != _originalThumbnailUrl;

    if (!titleChanged && !summaryChanged && !thumbnailChanged) {
      print('[ThumbnailEditOverlay] 변경사항 없음 - 서버 요청 스킵');

      // 변경사항이 없어도 제목/요약을 부모에게 알림 (동기화 유지)
      if (mounted) {
        widget.onMetadataChanged?.call(title, summary);
        Navigator.of(context).pop();
      }
      return;
    }

    print('[ThumbnailEditOverlay] ===== 변경사항 저장 시작 =====');
    print('[ThumbnailEditOverlay] postId: ${widget.postId}');
    print('[ThumbnailEditOverlay] 제목 변경: $titleChanged');
    print('[ThumbnailEditOverlay] 요약 변경: $summaryChanged');
    print('[ThumbnailEditOverlay] 썸네일 변경: $thumbnailChanged');

    try {
      // 변경된 항목만 전송
      final String? thumbnailParam =
          thumbnailChanged
              ? (_thumbnailUrl.isNotEmpty ? _thumbnailUrl : null)
              : null;
      final String? titleParam =
          titleChanged ? (title.isNotEmpty ? title : null) : null;
      final String? summaryParam =
          summaryChanged ? (summary.isNotEmpty ? summary : null) : null;

      print('[ThumbnailEditOverlay] 전송 파라미터:');
      print('  - thumbnailImageUrl: $thumbnailParam');
      print('  - title: $titleParam');
      print('  - summary: $summaryParam');

      await BlogService().updatePostThumbnail(
        postId: int.parse(widget.postId),
        thumbnailImageUrl: thumbnailParam,
        title: titleParam,
        summary: summaryParam,
      );

      print('[ThumbnailEditOverlay] ✅ 서버 업데이트 성공');

      if (mounted) {
        // 제목/요약을 부모에게 알림 (변경 여부와 관계없이 현재 값 전달)
        widget.onMetadataChanged?.call(title, summary);
        print('[ThumbnailEditOverlay] 메타데이터 콜백 호출');

        ErrorHandler.showInfo(context, '수정이 완료되었습니다');
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('[ThumbnailEditOverlay] ❌ 저장 실패: $e');
      if (mounted) {
        ErrorHandler.handleError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardRadius = 20.0;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // 항상 버튼 표시: 편집 모드면 "완료", 아니면 "수정 완료"
          TextButton(
            onPressed: _saveChanges, // 항상 서버에 저장
            child: Text(
              _editMode ? '완료' : '수정 완료',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
              ),
            ),
          ),
          SizedBox(width: 10),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

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
                          padding: const EdgeInsets.symmetric(horizontal: 50.0),
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.1),
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      cardRadius,
                                    ),
                                    child: Stack(
                                      children: [
                                        // 배경 이미지
                                        Positioned.fill(
                                          child:
                                              _isUploadingThumb
                                                  ? const _ShimmerPlaceholder()
                                                  : (_thumbnailUrl.isEmpty
                                                      ? const _EmptyImagePlaceholder()
                                                      : Image.network(
                                                        _thumbnailUrl,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (c, e, s) =>
                                                                const _EmptyImagePlaceholder(),
                                                      )),
                                        ),

                                        // 편집하기 버튼
                                        Positioned(
                                          left: 6,
                                          bottom: 6,
                                          child: GestureDetector(
                                            onTap: _openGalleryPicker,
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
                          MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : 0,
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
    );
  }
}

// 빈 이미지 자리표시자
class _EmptyImagePlaceholder extends StatelessWidget {
  const _EmptyImagePlaceholder();

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

// 쉬머 플레이스홀더
class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final gradient = LinearGradient(
          begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
          end: Alignment(1.0 + 2.0 * _ctrl.value, 0),
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
            Theme.of(context).colorScheme.surface,
          ],
        );
        return Container(decoration: BoxDecoration(gradient: gradient));
      },
    );
  }
}
