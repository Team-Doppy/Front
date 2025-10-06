import 'dart:convert';
import 'dart:ui' as ui;
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:doppy/editor/image/gallery_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/data/models/group_model.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/data/services/blog_service.dart';

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
  // 더미 데이터
  String _exportedThumbnailImageUrl = '';
  String _title = '';
  String _excerpt = '';

  Map<String, dynamic> _exportedBase = <String, dynamic>{};

  bool _editMode = false;

  String _audienceButtonText = '전체 공개';
  final Set<int> _selectedAudienceGroupIds = {};
  bool _audienceSelectAll = true;
  bool _audiencePrivateOnly = false;
  bool _isUploading = false;
  bool _isUploadingThumb = false;
  String? _thumbnailImageId;

  bool isGrouping = false;

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
  }

  void _hydrateFromExported(Map<String, dynamic> exported) {
    _exportedBase = exported;
    // 제목
    final String? exportedTitle = _readString(exported, keys: const ['title']);
    if (exportedTitle != null && exportedTitle.trim().isNotEmpty) {
      _title = exportedTitle.trim();
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
    setState(() {});
  }

  // ImageService의 휘발성 캐시에 저장/로드/삭제
  void _loadPersistedThumbnail() {
    final svc = ImageService();
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
      ImageService().setTempThumbnail(
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

  void _openVisibilitySheet() async {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    setState(() {
      isGrouping = true;
    });
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      barrierColor: isDark ? null : Colors.black.withOpacity(0.2),
      builder: (_) {
        return ChangeNotifierProvider.value(
          value: context.read<GroupProvider>(),
          child: _AudiencePicker(
            initialSelectedIds: _selectedAudienceGroupIds,
            initialSelectAll: _audienceSelectAll,
            initialPrivateOnly: _audiencePrivateOnly,
            title: _title,
            excerpt: _excerpt,
            thumbnailImageUrl: _exportedThumbnailImageUrl,
            onSelectionChanged: (
              selectAll,
              privateOnly,
              selectedGroupIds,
              selectedNames,
            ) {
              // 실시간으로 상태 업데이트
              String label;
              if (selectAll) {
                label = '전체 공개';
              } else if (privateOnly) {
                label = '나만 보기';
              } else {
                if (selectedNames.length > 3) {
                  final int extra = selectedNames.length - 3;
                  label =
                      '${selectedNames[0]}, ${selectedNames[1]}, ${selectedNames[2]} +$extra';
                } else {
                  label = selectedNames.join(', ');
                }
              }
              setState(() {
                _audienceButtonText = label;
                _audienceSelectAll = selectAll;
                _audiencePrivateOnly = privateOnly;
                _selectedAudienceGroupIds
                  ..clear()
                  ..addAll(selectedGroupIds);
              });
            },
          ),
        );
      },
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
    );
    setState(() {
      isGrouping = false;
    });
  }

  Future<void> _publish() async {
    try {
      // 1. 제목 검증 (모든 공개 범위에서 필수)
      if (_title.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('제목을 입력해주세요.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 2. 컨텐츠 검증 (모든 공개 범위에서 필수)
      if (_excerpt.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('본문 내용을 입력해주세요.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 3. 썸네일 검증 (모든 공개 범위에서 필수)
      if (_exportedThumbnailImageUrl.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('썸네일 이미지를 먼저 선택하세요.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 4. 그룹 공유시 그룹 선택 검증
      if (!_audienceSelectAll &&
          !_audiencePrivateOnly &&
          _selectedAudienceGroupIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('그룹 공유를 선택했을 경우 최소 1개 이상의 그룹을 선택해주세요.'),
            backgroundColor: Colors.red,
          ),
        );
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
      final uploadResult = await blogService.uploadPost(
        postData: payload,
        thumbnailImageId: _thumbnailImageId?.toString(),
      );

      debugPrint('===== UPLOAD RESULT =====');
      debugPrint('Upload successful: ${uploadResult}');

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('성공적으로 등록되었어요'),
          backgroundColor: Theme.of(context).colorScheme.onSurface,
          action: SnackBarAction(
            label: '확인',
            textColor: Theme.of(context).colorScheme.onSurface,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('발행 중 오류가 발생했습니다: ${e.toString()}'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: '다시 시도',
            textColor: Colors.white,
            onPressed: () => _publish(),
          ),
        ),
      );
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
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => GalleryBottomSheet(
            onImagesSelected: (files) async {
              if (files.isEmpty) return;
              if (!mounted) return;
              setState(() => _isUploadingThumb = true);
              try {
                final upload = context.read<UploadService>();
                final tasks = await upload.uploadFilesViaServerBatches([
                  files.first,
                ], kind: UploadKind.editorImage);
                if (tasks.isNotEmpty) {
                  final t = tasks.first;
                  if (t.state == UploadState.success &&
                      (t.url ?? '').isNotEmpty) {
                    setState(() {
                      _exportedThumbnailImageUrl = t.url!;
                      _thumbnailImageId = t.imageId ?? t.id;
                    });
                    await _persistThumbnail();
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('이미지 업로드에 실패했습니다.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('업로드 오류: $e')));
                }
              } finally {
                if (mounted) setState(() => _isUploadingThumb = false);
                // 이전 화면으로 돌아가지 않음. 바텀시트만 닫도록 유지.
              }
            },
          ),
    );
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

  @override
  Widget build(BuildContext context) {
    final cardRadius = 12.0; // PostCard와 동일한 라운드

    return WillPopScope(
      onWillPop: () async {
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
            appBar:
                isGrouping
                    ? null
                    : AppBar(
                      toolbarHeight: 50,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      leading: IconButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        icon: Icon(
                          Icons.arrow_back_ios_new_outlined,
                          size: 18,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),

                      centerTitle: false,
                      actions: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0),
                          child: TextButton(
                            onPressed: () {
                              final bool canPublish = _canPublish();
                              if (canPublish) {
                                _publish();
                              } else {
                                String msg = _getPublishErrorMessage();
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text(msg)));
                              }
                            },
                            child:
                                _isUploading
                                    ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                          ),
                                        ),
                                      ],
                                    )
                                    : Builder(
                                      builder: (context) {
                                        final bool canPublish = _canPublish();
                                        return Text(
                                          '등록',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface.withValues(
                                              alpha: canPublish ? 1.0 : 0.4,
                                            ),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        );
                                      },
                                    ),
                          ),
                        ),
                      ],
                    ),
            body: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!isGrouping) const Spacer(flex: 2),
                  // PostList와 동일한 카드 디자인
                  if (!isGrouping)
                    Stack(
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
                                        0.15 *
                                            _introCurve
                                                .value; // PostList와 동일한 스케일
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
                                                                fit:
                                                                    BoxFit
                                                                        .cover,
                                                                errorBuilder:
                                                                    (c, e, s) =>
                                                                        const _EmptyImagePlaceholder(),
                                                              )),
                                                ),
                                                // 좌하단 작성자 정보 (PostCard와 동일)
                                                Positioned(
                                                  left: 6,
                                                  bottom: 6,
                                                  child: _buildAuthorInfo(),
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
                          ),
                      ],
                    ),

                  // 하단 텍스트 영역 (PostList의 StickyAuthor와 동일)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 30,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        // 제목
                        Text(
                          _title,
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
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // 내용
                        Text(
                          _excerpt,
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
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                  const Spacer(),

                  // 공개 설정 버튼
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22.0,
                      vertical: 0.0,
                    ),
                    child: ElevatedButton(
                      onPressed: _openVisibilitySheet,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        foregroundColor:
                            Theme.of(context).colorScheme.onSurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _audienceButtonText,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          Spacer(),
                          Icon(
                            Icons.arrow_drop_up_outlined,
                            size: 20,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // PostCard와 동일한 좌하단 작성자 정보
  Widget _buildAuthorInfo() {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        final currentUser = userProvider.currentUser;
        final username =
            currentUser?.username ?? currentUser?.alias ?? 'Unknown';
        final profileImageUrl = currentUser?.profileImageUrl ?? '';

        return ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.15),
                borderRadius: BorderRadius.circular(35),
              ),
              child: Row(
                children: [
                  CommonProfileAvatar(
                    imageUrl: profileImageUrl,
                    username: username,
                    size: 35,
                    borderWidth: 1,
                    borderColor: Theme.of(
                      context,
                    ).colorScheme.surface.withOpacity(0.2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    username,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        );
      },
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
                          child: Row(
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
                        decoration: BoxDecoration(
                          color:
                              checked
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(
                                    context,
                                  ).colorScheme.background.withOpacity(1),
                          borderRadius: BorderRadius.circular(16),
                        ),
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
      color: AppColors.darkSurface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '썸네일을 선택해주세요',
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
