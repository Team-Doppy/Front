import 'dart:convert';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
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
  String _title = '오늘 하루도 힘내자고 화이팅!';
  String _excerpt = '여기에 본문 요약이 들어갑니다. 간단한 설명을 추가해 주세요.';

  Map<String, dynamic> _exportedBase = <String, dynamic>{};

  bool _editMode = false;

  String _audienceButtonText = '전체 공개';
  final Set<int> _selectedAudienceGroupIds = {};
  bool _audienceSelectAll = true;
  bool _audiencePrivateOnly = false;
  bool _isUploading = false;
  bool _isUploadingThumb = false;
  String? _thumbnailImageId;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _introCurve = CurvedAnimation(
    parent: _intro,
    curve: Curves.easeOutCubic,
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

    // 본문 요약
    String collected = _collectText(exported);
    collected =
        collected
            .replaceAll(RegExp('\\s+'), ' ')
            .replaceAll('\u200B', '')
            .trim();
    String preview = collected;
    if (_title.isNotEmpty && preview.startsWith(_title)) {
      preview = preview.substring(_title.length).trim();
    }
    if (preview.isEmpty) preview = _excerpt;
    const int maxLen = 140;
    if (preview.length > maxLen) {
      preview = preview.substring(0, maxLen).trimRight();
      if (!preview.endsWith('…')) preview = '$preview…';
    }
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
        n.forEach((key, value) {
          final k = key.toString().toLowerCase();
          if (k == 'title') return; // 제목 제외
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

  void _openVisibilitySheet() async {
    final result = await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      barrierColor: Colors.black54,
      builder: (_) {
        return ChangeNotifierProvider.value(
          value: context.read<GroupProvider>(),
          child: _AudiencePicker(
            initialSelectedIds: _selectedAudienceGroupIds,
            initialSelectAll: _audienceSelectAll,
            initialPrivateOnly: _audiencePrivateOnly,
          ),
        );
      },
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
    );
    if (!mounted) return;
    if (result is Map) {
      final bool selectAll = result['selectAll'] == true;
      final bool privateOnly = result['privateOnly'] == true;
      final List<dynamic> names =
          (result['selectedNames'] as List?) ?? const [];
      final List<dynamic> ids = (result['selectedIds'] as List?) ?? const [];
      String label;
      if (selectAll) {
        label = '전체 공개';
      } else if (privateOnly) {
        label = '나만 보기';
      } else {
        if (names.length > 3) {
          final int extra = names.length - 3;
          label = '${names[0]}, ${names[1]}, ${names[2]} +$extra';
        } else {
          label = names.join(', ');
        }
      }
      setState(() {
        _audienceButtonText = label;
        _audienceSelectAll = selectAll;
        _audiencePrivateOnly = privateOnly;
        _selectedAudienceGroupIds
          ..clear()
          ..addAll(ids.whereType<int>());
      });
    }
  }

  Future<void> _publish() async {
    try {
      // 썸네일 필수 검증 (이중 방어)
      if (_exportedThumbnailImageUrl.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('썸네일 이미지를 먼저 선택하세요.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 업로드 시작 - 로딩 상태 표시
      setState(() {
        _isUploading = true;
      });

      final Map<String, dynamic> payload = await _buildFinalJson();
      // 썸네일 정보 포함 (키 통일)
      payload['thumbnailImageUrl'] = _exportedThumbnailImageUrl;
      if (_thumbnailImageId != null) {
        payload['thumbnailImageId'] = _thumbnailImageId;
      }
      final String json = const JsonEncoder.withIndent('  ').convert(payload);
      debugPrint('===== FINAL POST JSON =====');
      printLarge(json);

      if (!mounted) return;

      // BlogService를 통한 서버 업로드
      final blogService = BlogService();
      final uploadResult = await blogService.uploadPost(
        postData: payload,
        thumbnailImageId: payload['thumbnailImageId']?.toString(),
      );

      debugPrint('===== UPLOAD RESULT =====');
      debugPrint('Upload successful: ${uploadResult}');

      if (!mounted) return;

      // 성공 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('블로그가 성공적으로 발행되었습니다!'),
          backgroundColor: Colors.green,
        ),
      );

      // 업로드 성공 시 바로 글보기 화면으로 이동
      Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 420),
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

  @override
  Widget build(BuildContext context) {
    final cardRadius = 15.0; // PostCard와 동일한 라운드

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop({
          'thumbnailImageUrl': _exportedThumbnailImageUrl,
          'thumbnailImageId': _thumbnailImageId,
        });
        return false;
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          title: Text(
            '',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          iconTheme: IconThemeData(
            color: Theme.of(context).colorScheme.onSurface,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: TextButton(
                onPressed: () {
                  final bool canPublish =
                      !_isUploading &&
                      !_isUploadingThumb &&
                      _exportedThumbnailImageUrl.isNotEmpty;
                  if (canPublish) {
                    _publish();
                  } else {
                    String msg =
                        _isUploadingThumb
                            ? '이미지 업로드 중입니다.'
                            : '썸네일 이미지를 먼저 선택하세요.';
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        )
                        : Builder(
                          builder: (context) {
                            final bool canPublish =
                                !_isUploading &&
                                !_isUploadingThumb &&
                                _exportedThumbnailImageUrl.isNotEmpty;
                            return Text(
                              '등록',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: canPublish ? 1.0 : 0.4),
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            );
                          },
                        ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  Spacer(),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '미리보기',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        AspectRatio(
                          aspectRatio: 9 / 15, // PostCard와 동일한 4:5 비율
                          child: GestureDetector(
                            onTap: _openGalleryPicker,
                            onLongPress: _toggleEditMode,
                            child: AnimatedBuilder(
                              animation: _introCurve,
                              builder: (context, _) {
                                final double scale =
                                    0.9 + 0.1 * _introCurve.value;
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
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.2,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
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
                                            // 하단 그라데이션 오버레이 (PostCard와 동일)
                                            Positioned.fill(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Colors.transparent,
                                                      Colors.transparent,
                                                      Colors.black.withOpacity(
                                                        0.2,
                                                      ),
                                                      Colors.black.withOpacity(
                                                        0.35,
                                                      ),
                                                    ],
                                                    stops: const [
                                                      0.0,
                                                      0.4,
                                                      0.7,
                                                      1.0,
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // 상단 작성자 정보 (PostCard 스타일)
                                            Positioned(
                                              left: 12,
                                              right: 12,
                                              top: 12,
                                              child:
                                                  _buildOverlayAuthorPreview(),
                                            ),
                                            // 하단 제목 텍스트 (PostCard 스타일)
                                            Positioned(
                                              left: 16,
                                              right: 16,
                                              bottom: 16,
                                              child: _buildOverlayTextPreview(),
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
                      ],
                    ),
                  ),
                  Spacer(flex: 5),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22.0,
                      vertical: 10.0,
                    ),
                    child: ElevatedButton(
                      onPressed: _openVisibilitySheet,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),

                        foregroundColor:
                            Theme.of(context).colorScheme.onSurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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
                          Icon(Icons.arrow_drop_up_outlined, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // PostCard와 동일한 상단 작성자 오버레이 (미리보기용)
  Widget _buildOverlayAuthorPreview() {
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(300),
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(300),
            child: Image.network(
              "https://thumbnews.nateimg.co.kr/view610///news.nateimg.co.kr/orgImg/pt/2025/06/12/202506122116776778_684ac5398c368.jpg",
              fit: BoxFit.cover,
              width: 50,
              height: 50,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'affection-jk',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontFamily: 'Pretendard Variable',
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // PostCard와 동일한 하단 제목 텍스트 (미리보기용)
  Widget _buildOverlayTextPreview() {
    return Text(
      _title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 36,
        fontFamily: 'Pretendard Variable',
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _AudiencePicker extends StatefulWidget {
  final Set<int> initialSelectedIds;
  final bool initialSelectAll;
  final bool initialPrivateOnly;

  const _AudiencePicker({
    this.initialSelectedIds = const {},
    this.initialSelectAll = true,
    this.initialPrivateOnly = false,
  });

  @override
  State<_AudiencePicker> createState() => _AudiencePickerState();
}

class _AudiencePickerState extends State<_AudiencePicker> {
  late Set<int> _selectedGroupIds;
  late bool _selectAll; // 전체공개 토글
  late bool _privateOnly; // 나만보기

  // 초기 상태 저장(변경 감지용)
  late final Set<int> _initialSelectedIds;
  late final bool _initialSelectAll;
  late final bool _initialPrivateOnly;

  @override
  void initState() {
    super.initState();
    _selectedGroupIds = Set<int>.from(widget.initialSelectedIds);
    _selectAll = widget.initialSelectAll;
    _privateOnly = widget.initialPrivateOnly;

    _initialSelectedIds = Set<int>.from(widget.initialSelectedIds);
    _initialSelectAll = widget.initialSelectAll;
    _initialPrivateOnly = widget.initialPrivateOnly;

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
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
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
          const SizedBox(height: 20),

          Expanded(
            child: Builder(
              builder: (context) {
                final list = _displayGroups(groups, groupProv.isLoading);
                final total = list.length + 2; // + 전체공개, 나만보기
                return ListView.builder(
                  itemCount: total,
                  itemBuilder: (context, i) {
                    // 0: 전체공개
                    if (i == 0) {
                      final bool checked = _selectAll;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 30,
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceVariant,
                          child: Icon(
                            Icons.public,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        title: Text(
                          '전체 공개',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          '모든 사용자에게 공개',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        trailing: Icon(
                          checked
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color:
                              checked
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.24),
                        ),
                        onTap: () {
                          setState(() {
                            _selectAll = true;
                            _privateOnly = false;
                            _selectedGroupIds.clear();
                          });
                        },
                      );
                    }
                    // 1: 나만보기
                    if (i == 1) {
                      final bool checked = _privateOnly;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 30,
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceVariant,
                          child: Icon(
                            Icons.lock,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        title: Text(
                          '나만 보기',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          '본인만 볼 수 있음',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        trailing: Icon(
                          checked
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color:
                              checked
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.24),
                        ),
                        onTap: () {
                          setState(() {
                            _privateOnly = true;
                            _selectAll = false;
                            _selectedGroupIds.clear();
                          });
                        },
                      );
                    }

                    // 나머지: 그룹들
                    final g = list[i - 2];
                    final checked = _selectedGroupIds.contains(g.id);
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 30,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceVariant,
                        child: Text(g.name.substring(0, 1)),
                      ),
                      title: Text(
                        g.name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        g.description,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      trailing: Icon(
                        checked
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color:
                            checked
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.24),
                      ),
                      onTap: () {
                        setState(() {
                          _selectAll = false;
                          _privateOnly = false;
                          if (checked) {
                            _selectedGroupIds.remove(g.id);
                          } else {
                            _selectedGroupIds.add(g.id);
                          }
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _hasChanges() ? Colors.white : Colors.white12,
                  foregroundColor:
                      _hasChanges() ? Colors.black : Colors.white38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.check),
                label: const Text(
                  '적용하기',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  final selected = _selectedGroupIds;
                  final all = _selectAll;
                  final onlyMe = _privateOnly;
                  final current = _displayGroups(
                    context.read<GroupProvider>().myGroups,
                    false,
                  );
                  final names =
                      current
                          .where((g) => selected.contains(g.id))
                          .map((g) => g.name)
                          .toList();
                  Navigator.of(context).maybePop({
                    'selectAll': all,
                    'privateOnly': onlyMe,
                    'selectedIds': selected.toList(),
                    'selectedNames': names,
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Group> _displayGroups(List<Group> original, bool isLoading) {
    return List<Group>.from(original);
  }

  bool _hasChanges() {
    if (_selectAll != _initialSelectAll) return true;
    if (_privateOnly != _initialPrivateOnly) return true;
    if (_selectedGroupIds.length != _initialSelectedIds.length) return true;
    for (final id in _selectedGroupIds) {
      if (!_initialSelectedIds.contains(id)) return true;
    }
    return false;
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
          children: const [
            Icon(Icons.image_outlined, color: Colors.white54, size: 32),
            SizedBox(height: 6),
            Text(
              '클릭해서 이미지를 선택해주세요.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
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
