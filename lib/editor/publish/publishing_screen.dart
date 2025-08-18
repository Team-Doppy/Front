import 'package:doppy/pages/post/postview_screen.dart';
import 'package:flutter/material.dart' hide Visibility;
import 'package:super_editor/super_editor.dart';
import '../../pages/post/postwrite_screen.dart';
import 'publish_service.dart';
import '../spatial_manager.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';
import 'package:top_snackbar_flutter/custom_snack_bar.dart';
import 'package:doppy/editor/util/custom_bottom_sheet.dart';
import 'package:doppy/editor/util/tag_bottom_sheet.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';

class PublishingScreen extends StatefulWidget {
  final PreviewData preview;
  final MutableDocument document;
  final SpatialManager spatialManager;
  final VisibilityOption visibilityOption;

  const PublishingScreen({
    super.key,
    required this.preview,
    required this.document,
    required this.spatialManager,
    required this.visibilityOption,
  });

  @override
  State<PublishingScreen> createState() => _PublishingScreenState();
}

class _PublishingScreenState extends State<PublishingScreen> {
  final PublishService _publishService = PublishService();

  // 태그 입력 관련 상태
  final TextEditingController _tagController = TextEditingController();
  final List<String> _userTags = [];
  final FocusNode _tagFocusNode = FocusNode();

  // 텍스트 오버레이 상태
  List<OverlayText> _overlayTexts = [];
  int? _selectedOverlayIndex;
  Offset? _initFocalPoint;
  double? _initScale;
  Offset? _dragStart;
  Offset? _dragOrigin;

  bool _isPublishing = false;
  VisibilityOption _selectedVisibility = VisibilityOption.public;

  String? selectedThumbnailId;

  @override
  void initState() {
    super.initState();
    _selectedVisibility = widget.visibilityOption;
    _initializePublishing();
    selectedThumbnailId = widget.preview.thumbnailUrl;
  }

  @override
  void dispose() {
    _tagController.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  void _initializePublishing() {
    // 태그/텍스트 모두 기본값 없이 빈 상태로 시작
    _userTags.clear();
    _overlayTexts.clear();
  }

  String _visibilityLabel(VisibilityOption option) {
    switch (option) {
      case VisibilityOption.public:
        return '전체공개';
      case VisibilityOption.partial:
        return '일부공개';
      case VisibilityOption.private:
        return '나만보기';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(Icons.arrow_back_ios_new, color: Colors.black),
        ),
        centerTitle: true,
        title: PopupMenuButton<VisibilityOption>(
          initialValue: _selectedVisibility,
          onSelected: (value) {
            setState(() {
              _selectedVisibility = value;
            });
          },
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.withOpacity(0.15)),
          ),
          itemBuilder:
              (context) => [
                PopupMenuItem(
                  value: VisibilityOption.public,
                  child: Text(
                    _visibilityLabel(VisibilityOption.public),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                PopupMenuItem(
                  value: VisibilityOption.partial,
                  child: Text(
                    _visibilityLabel(VisibilityOption.partial),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                PopupMenuItem(
                  value: VisibilityOption.private,
                  child: Text(
                    _visibilityLabel(VisibilityOption.private),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _visibilityLabel(_selectedVisibility),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.black,
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 미리보기 섹션
            _buildPreviewSection(),

            // 메인 이미지 영역
            Spacer(),
            _buildMainImageArea(),

            // 편집 도구
            _buildEditTools(),
            Spacer(),
            // 발행 버튼
            _buildPublishButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection() {
    final thumbnailUrl = selectedThumbnailId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
          border: Border.all(
            color: const Color.fromARGB(255, 134, 134, 134),
            width: 0.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 2,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '미리보기',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: const Color.fromARGB(221, 132, 132, 132),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 130,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 0.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                              ? Image.network(
                                thumbnailUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[300],
                                    child: const Icon(
                                      Icons.image,
                                      color: Colors.grey,
                                    ),
                                  );
                                },
                              )
                              : Container(
                                color: Colors.grey[300],
                                child: const Icon(
                                  Icons.image,
                                  color: Colors.grey,
                                ),
                              ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 텍스트 내용 + 태그 칩
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_userTags.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            children: [
                              ..._userTags
                                  .take(3)
                                  .map(
                                    (tag) => Chip(
                                      label: Text(
                                        tag,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF5888FF),
                                        ),
                                      ),
                                      backgroundColor: const Color(0xFFF4F5F8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 0,
                                      ),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                              if (_userTags.length > 3)
                                Chip(
                                  label: const Text(
                                    '...',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  backgroundColor: const Color(0xFFF4F5F8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 0,
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                            ],
                          ),
                        Text(
                          widget.preview.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.preview.previewText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainImageArea() {
    final imageHeight = MediaQuery.of(context).size.height * 0.3;
    final thumbnailUrl = selectedThumbnailId;
    return GestureDetector(
      onTap: () {
        setState(() {
          for (final t in _overlayTexts) {
            t.isEditing = false;
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // 이미지
              (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                  ? Image.network(
                    thumbnailUrl,
                    width: MediaQuery.of(context).size.width,
                    height: imageHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: MediaQuery.of(context).size.width,
                        height: imageHeight,
                        color: Colors.grey[300],
                        child: const Center(
                          child: Icon(
                            Icons.image,
                            size: 64,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  )
                  : Container(
                    width: MediaQuery.of(context).size.width,
                    height: imageHeight,
                    color: Colors.grey[300],
                    child: const Center(
                      child: Icon(Icons.image, size: 64, color: Colors.grey),
                    ),
                  ),
              // 여러 오버레이 텍스트 렌더링
              ..._overlayTexts.asMap().entries.map((entry) {
                final i = entry.key;
                final overlay = entry.value;
                return Positioned(
                  left: overlay.position.dx,
                  top: overlay.position.dy,
                  child:
                      overlay.isEditing
                          ? IntrinsicWidth(
                            child: TextField(
                              autofocus: true,
                              controller: TextEditingController(
                                text: overlay.text,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 4,
                                    offset: Offset(1, 1),
                                  ),
                                ],
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (val) {
                                overlay.text = val;
                                setState(() {}); // 길이 반영
                              },
                              onEditingComplete: () {
                                setState(() {
                                  overlay.isEditing = false;
                                });
                              },
                            ),
                          )
                          : GestureDetector(
                            onTap: () {
                              setState(() {
                                for (final t in _overlayTexts) {
                                  t.isEditing = false;
                                }
                                overlay.isEditing = true;
                              });
                            },
                            onScaleStart:
                                overlay.isEditing
                                    ? null
                                    : (details) {
                                      _initFocalPoint = details.focalPoint;
                                      _initScale = overlay.scale;
                                      _dragStart = details.focalPoint;
                                      _dragOrigin = overlay.position;
                                      setState(() => _selectedOverlayIndex = i);
                                    },
                            onScaleUpdate:
                                overlay.isEditing
                                    ? null
                                    : (details) {
                                      setState(() {
                                        overlay.scale =
                                            (_initScale ?? 1.0) * details.scale;
                                        if (details.scale == 1.0 &&
                                            details.focalPoint !=
                                                _initFocalPoint) {
                                          overlay.position =
                                              _dragOrigin! +
                                              (details.focalPoint -
                                                  _dragStart!);
                                        }
                                      });
                                    },
                            child: Text(
                              overlay.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 4,
                                    offset: Offset(1, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditTools() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(), // iOS 스타일 바운스 효과
        child: Row(
          children: [
            // 'Aa' 버튼: 오버레이 텍스트 추가
            _buildEditTool(
              'Aa',
              Icons.text_fields,
              40,
              onTap: () {
                setState(() {
                  for (final t in _overlayTexts) {
                    t.isEditing = false;
                  }
                  _overlayTexts.add(
                    OverlayText(
                      text: '텍스트를 입력하세요',
                      position: const Offset(100, 100),
                      scale: 1.0,
                      isEditing: true,
                    ),
                  );
                  _selectedOverlayIndex = _overlayTexts.length - 1;
                });
              },
            ),
            const SizedBox(width: 20),
            _buildEditTool(
              '사진',
              Icons.photo,
              40,
              onTap: () async {
                final url = await pickSingleImage(context);
                if (url != null) {
                  setState(() {
                    selectedThumbnailId = url;
                  });
                }
              },
            ),
            const SizedBox(width: 20),
            _buildEditTool('자르기', Icons.crop, 40),
            const SizedBox(width: 20),
            _buildEditTool('스티커', Icons.emoji_emotions, 40),
            const SizedBox(width: 20),
            _buildEditTool('필터', Icons.filter, 40),
            const SizedBox(width: 20),
            _buildEditTool('위치', Icons.location_on, 40),
            const SizedBox(width: 20),
            _buildEditTool(
              '태그',
              Icons.tag,
              40,
              onTap: () async {
                final height =
                    MediaQuery.of(context).size.height -
                    _previewSectionHeight -
                    60;
                await showCustomBottomSheet(
                  context: context,
                  height: height,
                  child: TagBottomSheet(
                    initialTags: _userTags,
                    onChanged: (tags) {
                      setState(() {
                        _userTags
                          ..clear()
                          ..addAll(tags);
                      });
                    },
                  ),
                );
              },
            ),
            const SizedBox(width: 20),
            _buildEditTool('텍스트', Icons.format_size, 40),
            const SizedBox(width: 20),
            _buildEditTool('색상', Icons.palette, 40),
            const SizedBox(width: 20),
            _buildEditTool('효과', Icons.auto_fix_high, 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPublishButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _isPublishing ? null : _handlePublish,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                backgroundColor:
                    _isPublishing
                        ? Colors.grey
                        : const Color.fromARGB(255, 158, 186, 255),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 2,
              ),
              child: const Text(
                '발행하기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 발행 처리
  Future<void> _handlePublish() async {
    setState(() => _isPublishing = true);
    try {
      final context = this.context;
      final title = widget.preview.title;
      await _publishService.publishFromEditor(
        context: context,
        document: widget.document,
        spatialManager: widget.spatialManager,
        title: title,
        thumbnailImageUrl: widget.preview.thumbnailUrl,
        tags: widget.preview.tags,
        visibility: _toServiceVisibility(_selectedVisibility),
        onSuccess: (contentJson) {
          final int postId = contentJson["blogId"];
          print(postId);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder:
                  (context) =>
                      PostviewScreen(postId: postId), // TODO: 게시글 API 연동
            ),
          );
        },
        onError: (msg) {
          showTopSnackBar(
            Overlay.of(context),
            CustomSnackBar.error(message: msg),
            displayDuration: Duration(seconds: 2),
          );
        },
      );
    } finally {
      setState(() => _isPublishing = false);
    }
  }

  Visibility _toServiceVisibility(VisibilityOption option) {
    switch (option) {
      case VisibilityOption.public:
        return Visibility.public;
      case VisibilityOption.partial:
        return Visibility.groups;
      case VisibilityOption.private:
        return Visibility.private;
    }
  }

  Widget _buildEditTool(
    String label,
    IconData icon,
    double size, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: size + 8, // 패딩을 위해 크기 증가
            height: size + 8,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, size: size * 0.5, color: Colors.grey[800]),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  double get _previewSectionHeight => 180; // 미리보기 섹션 예상 높이(조정 가능)

  Future<String?> pickSingleImage(BuildContext context) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      return picked.path;
    }
    return null;
  }
}

class OverlayText {
  String text;
  Offset position;
  double scale;
  bool isEditing;
  OverlayText({
    required this.text,
    required this.position,
    this.scale = 1.0,
    this.isEditing = false,
  });
}
