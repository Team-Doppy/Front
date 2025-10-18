import 'dart:convert';
import 'dart:ui' as ui;
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/image/native_image_picker.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/data/models/group_model.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/utils/error_handler.dart';

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
    with SingleTickerProviderStateMixin {
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
  String _audienceButtonText = '전체 공개';
  final Set<int> _selectedAudienceGroupIds = {};
  bool _audienceSelectAll = true;
  bool _audiencePrivateOnly = false;

  // Step 3: 카테고리 선택
  int? _selectedCategoryId;
  String _selectedCategoryName = '미분류';
  bool _isCreatingCategory = false;
  final TextEditingController _newCategoryController = TextEditingController();
  List<Map<String, dynamic>>? _cachedCategories; // 캐시된 카테고리 목록

  bool _isUploading = false;
  bool _isUploadingThumb = false;
  String? _thumbnailImageId;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Animation<double> _introCurve = CurvedAnimation(
    parent: _intro,
    curve: Curves.elasticOut,
  );

  @override
  void initState() {
    super.initState();
    _hydrateFromExported(jsonDecode(widget.exported));
    _intro.forward();
    _loadPersistedThumbnail();
    _titleFocusNode.addListener(_onEditFocusChange);
    _excerptFocusNode.addListener(_onEditFocusChange);
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
    } catch (_) {}
    super.dispose();
  }

  void _onEditFocusChange() {
    // Step 1에서만 편집 모드 활성화
    if (_currentStep != 0) return;

    final bool nowEditing =
        _titleFocusNode.hasFocus || _excerptFocusNode.hasFocus;
    if (_editMode != nowEditing) {
      setState(() => _editMode = nowEditing);
    }
  }

  void _hydrateFromExported(Map<String, dynamic> exported) {
    _exportedBase = exported;
    // 제목
    final String? exportedTitle = _readString(exported, keys: const ['title']);
    if (exportedTitle != null && exportedTitle.trim().isNotEmpty) {
      _title = exportedTitle.trim();
      _titleController.text = _title;
    }

    _exportedThumbnailImageUrl =
        _readString(
          exported,
          keys: const ['thumbnailImageUrl', 'thumbnailUrl', 'thumnailUrl'],
        ) ??
        '';

    // 본문 전체 내용
    String collected = _collectText(exported);
    collected =
        collected
            .replaceAll(RegExp('\\s+'), ' ')
            .replaceAll('\u200B', '')
            .trim();
    // 제목이 포함되어 있으면 제목 부분 제거
    String preview = collected;
    if (_title.isNotEmpty && preview.startsWith(_title)) {
      preview = preview.substring(_title.length).trim();
    }
    if (preview.isEmpty) preview = _excerpt;
    _excerpt = preview;
    _excerptController.text = _excerpt;
    setState(() {});
  }

  // ImageService의 휘발성 캐시에 저장/로드/삭제
  void _loadPersistedThumbnail() {
    final svc = NodeComponentService();
    final url = svc.getTempThumbnailUrl(_nsKey) ?? '';
    final id = svc.getTempThumbnailId(_nsKey);
    if (mounted && _exportedThumbnailImageUrl.isEmpty && url.isNotEmpty) {
      setState(() {
        _exportedThumbnailImageUrl = url;
        _thumbnailImageId = id;
      });
    }
  }

  Future<void> _persistThumbnail() async {
    if (_exportedThumbnailImageUrl.isNotEmpty) {
      NodeComponentService().setTempThumbnail(
        _nsKey,
        url: _exportedThumbnailImageUrl,
        id: _thumbnailImageId,
      );
    }
  }

  String? _readString(Map<String, dynamic> map, {required List<String> keys}) {
    for (final k in keys) {
      final v = map[k];
      if (v is String) return v;
    }
    return null;
  }

  String _collectText(dynamic node) {
    final buffer = StringBuffer();
    void walk(dynamic n) {
      if (n is Map) {
        // 제목 노드는 건너뛰기
        if (n['isTitle'] == true) {
          return;
        }

        n.forEach((key, value) {
          final k = key.toString().toLowerCase();
          if (value is String) {
            if (k.contains('text') ||
                k.contains('content') ||
                k.contains('paragraph') ||
                k.contains('description') ||
                k.contains('body')) {
              buffer.write(' ');
              buffer.write(value);
            }
          } else {
            walk(value);
          }
        });
      } else if (n is List) {
        for (final item in n) {
          walk(item);
        }
      }
    }

    walk(node);
    return buffer.toString();
  }

  void _toggleEditMode() {
    setState(() => _editMode = !_editMode);
    if (_editMode) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  // 등록 가능 여부 확인 (서버 API 스펙 준수)
  bool _canPublish() {
    // 1. 기본 상태 확인
    if (_isUploading || _isUploadingThumb) {
      return false;
    }

    // 2. 필수 필드 확인 (모든 공개 범위에서 필수)
    if (_title.trim().isEmpty) {
      return false;
    }
    if (_excerpt.trim().isEmpty) {
      return false;
    }
    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return false;
    }

    // 3. 그룹 공유시 그룹 선택 확인
    if (!_audienceSelectAll &&
        !_audiencePrivateOnly &&
        _selectedAudienceGroupIds.isEmpty) {
      return false;
    }

    return true;
  }

  // 등록 불가능할 때 표시할 에러 메시지 (서버 API 스펙 준수)
  String _getPublishErrorMessage() {
    if (_isUploadingThumb) {
      return '이미지 업로드 중입니다.';
    }
    if (_title.trim().isEmpty) {
      return '제목을 입력해주세요.';
    }
    if (_excerpt.trim().isEmpty) {
      return '본문 내용을 입력해주세요.';
    }
    if (_exportedThumbnailImageUrl.trim().isEmpty) {
      return '썸네일 이미지를 먼저 선택하세요.';
    }
    if (!_audienceSelectAll &&
        !_audiencePrivateOnly &&
        _selectedAudienceGroupIds.isEmpty) {
      return '그룹 공유를 선택했을 경우 최소 1개 이상의 그룹을 선택해주세요.';
    }
    return '등록할 수 없습니다.';
  }

  Future<void> _publish() async {
    try {
      // 1. 제목 검증 (모든 공개 범위에서 필수)
      if (_title.trim().isEmpty) {
        ErrorHandler.showError(context, '제목을 입력해주세요.');
        return;
      }

      // 2. 컨텐츠 검증 (모든 공개 범위에서 필수)
      if (_excerpt.trim().isEmpty) {
        ErrorHandler.showError(context, '본문 내용을 입력해주세요.');
        return;
      }

      // 3. 썸네일 검증 (모든 공개 범위에서 필수)
      if (_exportedThumbnailImageUrl.trim().isEmpty) {
        ErrorHandler.showError(context, '썸네일 이미지를 먼저 선택하세요.');
        return;
      }

      // 4. 그룹 공유시 그룹 선택 검증
      if (!_audienceSelectAll &&
          !_audiencePrivateOnly &&
          _selectedAudienceGroupIds.isEmpty) {
        ErrorHandler.showError(context, '그룹 공유를 선택했을 경우 최소 1개 이상의 그룹을 선택해주세요.');
        return;
      }

      // 모든 검증 통과 후 업로드 시작
      setState(() {
        _isUploading = true;
      });

      final Map<String, dynamic> payload = await _buildFinalJson();

      // 최종 검증된 데이터 로깅
      final String json = const JsonEncoder.withIndent('  ').convert(payload);
      debugPrint('===== FINAL POST JSON (API SPEC COMPLIANT) =====');
      debugPrint('제목: $_title');
      debugPrint('컨텐츠: $_excerpt');
      debugPrint('썸네일: $_exportedThumbnailImageUrl');
      debugPrint(
        '공개 범위: ${_audienceSelectAll ? "PUBLIC" : (_audiencePrivateOnly ? "PRIVATE" : "GROUPS")}',
      );
      if (!_audienceSelectAll && !_audiencePrivateOnly) {
        debugPrint('선택된 그룹: $_selectedAudienceGroupIds');
      }
      printLarge(json);

      if (!mounted) return;

      // BlogService를 통한 서버 업로드

      final blogService = BlogService();
      // 썸네일 ID 일관성 보장: URL→ID 매핑 우선, 없으면 기존 값 사용
      String? resolvedThumbId;
      try {
        final map = NodeComponentService().urlToImageIdMap;
        final String? idStr = map[_exportedThumbnailImageUrl];
        if (idStr != null && idStr.isNotEmpty) {
          resolvedThumbId = idStr;
        } else {
          resolvedThumbId = _thumbnailImageId?.toString();
        }
      } catch (_) {
        resolvedThumbId = _thumbnailImageId?.toString();
      }

      final uploadResult = await blogService.uploadPost(
        postData: payload,
        thumbnailImageId: resolvedThumbId,
      );

      debugPrint('===== UPLOAD RESULT =====');
      debugPrint('Upload successful: ${uploadResult}');

      if (!mounted) return;

      // 스티커 캔버스 청소
      try {
        context.read<StickerService>().removeAll();
      } catch (_) {}

      // 이미지 매핑 맵 정리 (발행 완료 후)
      NodeComponentService().clearImageUrlMapping();

      // 내 프로필 피드 캐시 무효화 (새 포스트 발행)
      try {
        context.read<ProfileFeedProvider>().invalidateCache();
      } catch (e) {
        print('[PostExport] 캐시 무효화 실패: $e');
      }

      Navigator.of(context).pop();

      // 업로드 성공 시 바로 글보기 화면으로 이동
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 1000),
          pageBuilder:
              (_, __, ___) => PostReaderScreen(
                exported: uploadResult, // 서버 응답 데이터 직접 사용
                heroTag:
                    'uploaded-post-${DateTime.now().millisecondsSinceEpoch}',
              ),
          transitionsBuilder: (_, animation, __, child) => child,
        ),
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

  Future<Map<String, dynamic>> _buildFinalJson() async {
    return PostExporter.composeFinalPayload(
      thumbnailImageUrl: _exportedThumbnailImageUrl,
      base: Map<String, dynamic>.from(_exportedBase),
      privateOnly: _audiencePrivateOnly,
      publicOnly: _audienceSelectAll,
      selectedGroupIds: _selectedAudienceGroupIds.toList(),
      createdAt: DateTime.now(),
    );
  }

  void _openGalleryPicker() async {
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
            setState(() {
              _exportedThumbnailImageUrl = t.url!;
              _thumbnailImageId = t.imageId; // 서버 imageId만 사용
            });
            await _persistThumbnail();
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

  Widget _buildDynamicBackground() {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    return Positioned.fill(
      child: Stack(
        children: [
          // 썸네일 이미지 또는 단색 배경
          Positioned.fill(
            child:
                _exportedThumbnailImageUrl.isNotEmpty
                    ? Image.network(
                      _exportedThumbnailImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) =>
                              Container(color: AppColors.darkSurface),
                    )
                    : Container(color: AppColors.darkSurface),
          ),
          // 블러 오버레이 (썸네일이 있을 때만)
          if (_exportedThumbnailImageUrl.isNotEmpty)
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        isDark
                            ? Theme.of(
                              context,
                            ).colorScheme.background.withOpacity(0.8)
                            : Theme.of(
                              context,
                            ).colorScheme.background.withOpacity(0.6),
                        isDark
                            ? Theme.of(
                              context,
                            ).colorScheme.background.withOpacity(0.8)
                            : Theme.of(
                              context,
                            ).colorScheme.background.withOpacity(0.6),
                        isDark
                            ? Theme.of(
                              context,
                            ).colorScheme.background.withOpacity(0.8)
                            : Theme.of(
                              context,
                            ).colorScheme.background.withOpacity(0.6),
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
    if (_currentStep < _totalSteps - 1) {
      FocusScope.of(context).unfocus();
      setState(() {
        _currentStep++;
        _editMode = false;
      });

      // Step 3 진입 시 카테고리 로드
      if (_currentStep == 2 && _cachedCategories == null) {
        _loadCategoriesOnce();
      }
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
        return _exportedThumbnailImageUrl.isNotEmpty &&
            _title.trim().isNotEmpty &&
            _excerpt.trim().isNotEmpty;
      case 1: // Step 2: 공개 범위
        // 전체공개, 나만보기, 또는 그룹 중 하나는 선택되어야 함
        return _audienceSelectAll ||
            _audiencePrivateOnly ||
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
        if (_currentStep > 0) {
          _previousStep();
          return false;
        }
        Navigator.of(context).pop({
          'thumbnailImageUrl': _exportedThumbnailImageUrl,
          'thumbnailImageId': _thumbnailImageId,
        });
        return true;
      },
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
                  _buildStep1ThumbnailAndEdit(cardRadius),
                  _buildStep2AudienceSelection(),
                  _buildStep3CategorySelection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 포커스 상태의 간단한 앱바 (완료 버튼만)
  PreferredSizeWidget _buildFocusAppBar() {
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
              setState(() {
                _title = _titleController.text.trim();
                _excerpt = _excerptController.text.trim();
                _editMode = false;
              });
              FocusScope.of(context).unfocus();
            },
            child: const Text(
              '수정완료',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 일반 상태의 앱바 (진행바와 다음/업로드 버튼)
  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      toolbarHeight: 50,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: GestureDetector(
        onTap: () {
          if (_currentStep > 0) {
            _previousStep();
          } else {
            Navigator.of(context).pop();
          }
        },
        child: Padding(
          padding: const EdgeInsets.only(left: 20, top: 16),
          child: Text(
            '이전',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),

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
              '다음',
              style: TextStyle(
                color:
                    _canProceedToNextStep()
                        ? Theme.of(context).colorScheme.onSurface.withOpacity(1)
                        : Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.3),
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: TextButton(
              onPressed: () {
                final bool canPublish = _canPublish();
                if (canPublish) {
                  _publish();
                } else {
                  String msg = _getPublishErrorMessage();
                  ErrorHandler.showError(context, msg);
                }
              },
              child:
                  _isUploading
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                      : const Text(
                        '업로드',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
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
            backgroundColor: Colors.white.withOpacity(0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );
  }

  // Step 1: 썸네일 & 글 편집
  Widget _buildStep1ThumbnailAndEdit(double cardRadius) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          // PostList와 동일한 카드 디자인
          // 키보드 열리거나 그룹 바텀시트가 열리면 썸네일 카드 임시 숨김 → 오버플로우 방지
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
                        child: AnimatedBuilder(
                          animation: _introCurve,
                          builder: (context, _) {
                            final double scale =
                                0.85 +
                                0.15 * _introCurve.value; // PostList와 동일한 스케일
                            final double translateY =
                                (1 - _introCurve.value) * 10;
                            return Transform.translate(
                              offset: Offset(0, translateY),
                              child: Transform.scale(
                                scale: scale,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      cardRadius,
                                    ),
                                    border: Border.all(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceVariant,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      cardRadius,
                                    ),
                                    child: Stack(
                                      children: [
                                        // 배경 이미지 (PostCard와 동일)
                                        Positioned.fill(
                                          child:
                                              _isUploadingThumb
                                                  ? const _ShimmerPlaceholder()
                                                  : (_exportedThumbnailImageUrl
                                                          .isEmpty
                                                      ? const _EmptyImagePlaceholder()
                                                      : Image.network(
                                                        _exportedThumbnailImageUrl,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (c, e, s) =>
                                                                const _EmptyImagePlaceholder(),
                                                      )),
                                        ),
                                        // 좌하단 작성자 정보 (PostCard와 동일)
                                        Positioned(
                                          left: 6,
                                          bottom: 6,
                                          child: GestureDetector(
                                            onTap: () {
                                              print('edit');
                                            },
                                            child: _buildEditButton(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                /*
                        if (_exportedThumbnailImageUrl.isEmpty)
                          Positioned(
                            right: 40,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: Theme.of(context).colorScheme.surface,
                              ),
                            ),
                          ),*/
              ],
            ),
            secondChild: const SizedBox(height: 8),
          ),

          // 하단 텍스트 영역 (PostList의 StickyAuthor와 동일)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              // 바텀시트가 열려있으면 텍스트 영역을 약간 위로 올려 겹침 최소화
              vertical: 30,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // 제목 (탭 시 인라인 편집) - 바텀시트 중 편집 차단
                GestureDetector(
                  onTap: () {
                    setState(() => _editMode = true);
                    FocusScope.of(context).requestFocus(_titleFocusNode);
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
                      onChanged: (v) => _title = v,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 내용 (탭 시 인라인 편집 가능) - 바텀시트 중 편집 차단
                GestureDetector(
                  onTap: () {
                    setState(() => _editMode = true);
                    FocusScope.of(context).requestFocus(_excerptFocusNode);
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
                      scrollPhysics: NeverScrollableScrollPhysics(),
                      onChanged: (v) => _excerpt = v,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // Step 2: 공개 범위 선택
  Widget _buildStep2AudienceSelection() {
    return Consumer<GroupProvider>(
      builder: (context, groupProvider, child) {
        // 그룹 목록 로드
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (groupProvider.myGroups.isEmpty && !groupProvider.isLoading) {
            groupProvider.fetchMyGroups();
          }
        });

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),
              Text(
                '누구에게 공개할까요?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // 전체공개/나만보기 선택 영역
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    // 전체공개
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color:
                            _audienceSelectAll
                                ? Colors.white.withOpacity(0.4)
                                : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              _audienceSelectAll = true;
                              _audiencePrivateOnly = false;
                              _selectedAudienceGroupIds.clear();
                              _audienceButtonText = '전체 공개';
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '전체 공개',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (_audienceSelectAll)
                                      Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 나만보기
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color:
                            _audiencePrivateOnly
                                ? Colors.white.withOpacity(0.4)
                                : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              _audiencePrivateOnly = true;
                              _audienceSelectAll = false;
                              _selectedAudienceGroupIds.clear();
                              _audienceButtonText = '나만 보기';
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '나만 보기',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (_audiencePrivateOnly)
                                      Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 그룹 공유 헤더
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  '그룹 선택',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),

              // 그룹 리스트 (항상 표시)
              Expanded(
                child:
                    groupProvider.isLoading
                        ? Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : ListView.builder(
                          itemCount: groupProvider.myGroups.length,
                          itemBuilder: (context, index) {
                            final group = groupProvider.myGroups[index];
                            final isSelected = _selectedAudienceGroupIds
                                .contains(group.id);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? Colors.white.withOpacity(0.4)
                                        : Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedAudienceGroupIds.remove(
                                          group.id,
                                        );
                                      } else {
                                        _selectedAudienceGroupIds.add(group.id);
                                      }

                                      // 그룹 선택 시 전체공개/나만보기 해제
                                      if (_selectedAudienceGroupIds
                                          .isNotEmpty) {
                                        _audienceSelectAll = false;
                                        _audiencePrivateOnly = false;
                                      }

                                      // 선택된 그룹이 있으면 버튼 텍스트 업데이트
                                      if (_selectedAudienceGroupIds
                                          .isNotEmpty) {
                                        final selectedNames =
                                            groupProvider.myGroups
                                                .where(
                                                  (g) =>
                                                      _selectedAudienceGroupIds
                                                          .contains(g.id),
                                                )
                                                .map((g) => g.name)
                                                .toList();

                                        if (selectedNames.length > 3) {
                                          final extra =
                                              selectedNames.length - 3;
                                          _audienceButtonText =
                                              '${selectedNames.take(3).join(', ')} 외 $extra개';
                                        } else {
                                          _audienceButtonText = selectedNames
                                              .join(', ');
                                        }
                                      } else {
                                        _audienceButtonText = '그룹 공유';
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            group.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Step 3: 카테고리 선택
  Widget _buildStep3CategorySelection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 36),
          Text(
            '어느 카테고리에 저장할까요?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 20),
          Expanded(
            child:
                _cachedCategories == null
                    ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                    : ListView(
                      children: [
                        // 새 카테고리 만들기 버튼
                        _buildCreateCategoryButton(),
                        const SizedBox(height: 12),
                        // 실제 카테고리 목록
                        ..._cachedCategories!.map((category) {
                          final id = category['id'] as int?;
                          var name = category['name'] as String? ?? '이름 없음';

                          if (name == 'system_doppy_uncategorized') {
                            name = '지정 안 함';
                          }

                          return _buildCategoryOption(
                            title: name,
                            isSelected: _selectedCategoryId == id,
                            onTap: () {
                              setState(() {
                                _selectedCategoryId = id;
                                _selectedCategoryName = name;
                              });
                            },
                          );
                        }).toList(),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCategoriesOnce() async {
    if (_cachedCategories != null) return; // 이미 로드됨

    try {
      final currentUser =
          Provider.of<UserProvider>(context, listen: false).currentUser;
      final username = currentUser?.username ?? '';

      if (username.isEmpty) {
        throw Exception('사용자 정보를 찾을 수 없습니다.');
      }

      final categories = await BlogService().getUserCategories(username);
      setState(() {
        _cachedCategories = categories;
      });
    } catch (e) {
      print('[PostExportScreen] 카테고리 로드 실패: $e');
      // 에러 발생 시 빈 리스트로 설정하여 재시도 방지
      setState(() {
        _cachedCategories = [];
      });
    }
  }

  Widget _buildCreateCategoryButton() {
    if (_isCreatingCategory) {
      // 인라인 텍스트 필드 표시
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            TextField(
              cursorColor: Theme.of(context).colorScheme.onSurface,
              controller: _newCategoryController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: '카테고리 이름 입력',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 16,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isCreatingCategory = false;
                      _newCategoryController.clear();
                    });
                  },
                  child: Text(
                    '취소',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _createNewCategory,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.9),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: const Text('추가', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 새 카테고리 만들기 버튼
    return GestureDetector(
      onTap: () {
        setState(() {
          _isCreatingCategory = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '새 카테고리 만들기',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createNewCategory() async {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) {
      ErrorHandler.showError(context, '카테고리 이름을 입력하세요.');
      return;
    }

    try {
      await BlogService().createCategory(
        name: name,
        isPrivate: false,
        description: '',
      );

      if (mounted) {
        // 캐시 무효화하여 다음 로드 시 새로고침
        _cachedCategories = null;

        setState(() {
          _isCreatingCategory = false;
          _newCategoryController.clear();
        });

        // 카테고리 목록 즉시 새로고침
        await _loadCategoriesOnce();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: '카테고리 생성 실패');
      }
    }
  }

  Widget _buildCategoryOption({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? Colors.white.withOpacity(0.4)
                  : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.8),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }

  // PostCard와 동일한 좌하단 작성자 정보
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
}

class _AudiencePicker extends StatefulWidget {
  final Set<int> initialSelectedIds;
  final bool initialSelectAll;
  final bool initialPrivateOnly;
  final String title;
  final String excerpt;
  final String thumbnailImageUrl;
  final Function(
    bool selectAll,
    bool privateOnly,
    Set<int> selectedGroupIds,
    List<String> selectedNames,
  )
  onSelectionChanged;

  const _AudiencePicker({
    this.initialSelectedIds = const {},
    this.initialSelectAll = true,
    this.initialPrivateOnly = false,
    required this.title,
    required this.excerpt,
    required this.thumbnailImageUrl,
    required this.onSelectionChanged,
  });

  @override
  State<_AudiencePicker> createState() => _AudiencePickerState();
}

class _AudiencePickerState extends State<_AudiencePicker> {
  late Set<int> _selectedGroupIds;
  late bool _selectAll; // 전체공개 토글
  late bool _privateOnly; // 나만보기

  @override
  void initState() {
    super.initState();
    _selectedGroupIds = Set<int>.from(widget.initialSelectedIds);
    _selectAll = widget.initialSelectAll;
    _privateOnly = widget.initialPrivateOnly;

    // 바텀시트 진입 시 실제 그룹 목록 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (context.read<GroupProvider>().myGroups.isEmpty) {
          context.read<GroupProvider>().fetchMyGroups();
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupProv = context.watch<GroupProvider>();
    final List<Group> groups = groupProv.myGroups;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.24),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: Row(
                children: [
                  Text(
                    '공개 범위 선택',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Icon(
                      Icons.close_outlined,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.5),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Builder(
                builder: (context) {
                  final list = _displayGroups(groups, groupProv.isLoading);

                  return ListView.builder(
                    itemCount:
                        list.length + 1, // +1 for the audience options row
                    itemBuilder: (context, i) {
                      // 첫 번째 아이템: 전체공개-나만보기 로우
                      if (i == 0) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8, top: 8),
                          child: Column(
                            children: [
                              // 전체공개
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.only(right: 3),
                                  decoration: BoxDecoration(
                                    color:
                                        _selectAll
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.onSurface
                                            : Theme.of(context)
                                                .colorScheme
                                                .surface
                                                .withOpacity(1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        setState(() {
                                          _selectAll = true;
                                          _privateOnly = false;
                                          _selectedGroupIds.clear();
                                        });
                                        _notifySelectionChanged();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '전체 공개',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          _selectAll
                                                              ? Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .surface
                                                              : Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .onSurface,
                                                    ),
                                                  ),
                                                ),
                                                if (_selectAll)
                                                  Icon(
                                                    Icons.check,
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.surface,
                                                    size: 20,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '모든 사용자에게 공개',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color:
                                                    _selectAll
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .surface
                                                            .withOpacity(0.8)
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.7),
                                                height: 1.2,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // 나만보기
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.only(left: 3),
                                  decoration: BoxDecoration(
                                    color:
                                        _privateOnly
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.onSurface
                                            : Theme.of(context)
                                                .colorScheme
                                                .surface
                                                .withOpacity(1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        setState(() {
                                          _privateOnly = true;
                                          _selectAll = false;
                                          _selectedGroupIds.clear();
                                        });
                                        _notifySelectionChanged();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '나만 보기',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          _privateOnly
                                                              ? Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .surface
                                                              : Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .onSurface,
                                                    ),
                                                  ),
                                                ),
                                                if (_privateOnly)
                                                  Icon(
                                                    Icons.check,
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.surface,
                                                    size: 20,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '본인만 볼 수 있음',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color:
                                                    _privateOnly
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .surface
                                                            .withOpacity(0.8)
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.7),
                                                height: 1.2,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // 그룹 아이템들 (i-1로 인덱스 조정)
                      final g = list[i - 1];
                      final checked = _selectedGroupIds.contains(g.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),

                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setState(() {
                                if (checked) {
                                  _selectedGroupIds.remove(g.id);
                                } else {
                                  // 그룹 선택 시 다른 옵션들 취소
                                  _selectAll = false;
                                  _privateOnly = false;
                                  _selectedGroupIds.add(g.id);
                                }
                              });
                              _notifySelectionChanged();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // 그룹 정보
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          g.name,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                checked
                                                    ? Theme.of(
                                                      context,
                                                    ).colorScheme.surface
                                                    : Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          g.description,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color:
                                                checked
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .surface
                                                        .withOpacity(0.8)
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                        .withOpacity(0.7),
                                            height: 1.3,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 선택 아이콘
                                  checked
                                      ? Icon(
                                        Icons.check,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                        size: 20,
                                      )
                                      : Icon(
                                        Icons.circle_outlined,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.4),
                                        size: 20,
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
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

  List<Group> _displayGroups(List<Group> original, bool isLoading) {
    return List<Group>.from(original);
  }

  void _notifySelectionChanged() {
    final current = _displayGroups(
      context.read<GroupProvider>().myGroups,
      false,
    );
    final selectedNames =
        current
            .where((g) => _selectedGroupIds.contains(g.id))
            .map((g) => g.name)
            .toList();

    widget.onSelectionChanged(
      _selectAll,
      _privateOnly,
      _selectedGroupIds,
      selectedNames,
    );
  }
}

enum _StickerType { text, emoji, image }

class _Sticker {
  final _StickerType type;
  final String text;
  final Uint8List? bytes;
  Offset offset;

  _Sticker({
    required this.type,
    required this.text,
    required this.bytes,
    required this.offset,
  });
}

class _DraggableSticker extends StatefulWidget {
  final _Sticker sticker;
  final bool enabled;

  const _DraggableSticker({required this.sticker, required this.enabled});

  @override
  State<_DraggableSticker> createState() => _DraggableStickerState();
}

class _DraggableStickerState extends State<_DraggableSticker> {
  @override
  Widget build(BuildContext context) {
    final Widget child;
    switch (widget.sticker.type) {
      case _StickerType.text:
        child = _buildTextChip(widget.sticker.text);
        break;
      case _StickerType.emoji:
        child = _buildEmoji(widget.sticker.text);
        break;
      case _StickerType.image:
        child = _buildImageSticker(widget.sticker.bytes);
        break;
    }

    return Positioned(
      left: widget.sticker.offset.dx,
      top: widget.sticker.offset.dy,
      child:
          widget.enabled
              ? GestureDetector(
                onPanUpdate: (d) {
                  setState(() {
                    widget.sticker.offset += d.delta;
                  });
                },
                child: child,
              )
              : child,
    );
  }

  Widget _buildTextChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEmoji(String emoji) {
    return Text(emoji, style: const TextStyle(fontSize: 28));
  }

  Widget _buildImageSticker(Uint8List? bytes) {
    if (bytes == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.memory(bytes, width: 96, height: 96, fit: BoxFit.cover),
    );
  }
}

/// 빈 이미지 자리표시자 (업로드 전/오류 시 사용)
class _EmptyImagePlaceholder extends StatelessWidget {
  const _EmptyImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.background,
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

/// 간단한 쉬머 플레이스홀더 (썸네일 업로드 중 표시)
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
            Colors.grey.shade800,
            Colors.grey.shade700,
            Colors.grey.shade800,
          ],
          stops: const [0.25, 0.5, 0.75],
        );
        return Container(decoration: BoxDecoration(gradient: gradient));
      },
    );
  }
}
