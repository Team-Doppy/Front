import 'dart:convert';
import 'package:doppy/pages/post/post_reader_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:doppy/editor/image/gallery_bottom_sheet.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/data/models/group_model.dart';
import 'package:doppy/data/models/user_model.dart';
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
  const PostExportScreen({super.key, required this.exported});
  final String exported;

  @override
  State<PostExportScreen> createState() => _PostExportScreenState();
}

class _PostExportScreenState extends State<PostExportScreen>
    with SingleTickerProviderStateMixin {
  // 더미 데이터
  String _exportedThumbnailImageUrl = '';
  String _title = '오늘 하루도 힘내자고 화이팅!';
  String _excerpt = '여기에 본문 요약이 들어갑니다. 간단한 설명을 추가해 주세요.';

  Map<String, dynamic> _exportedBase = <String, dynamic>{};

  bool _editMode = false;
  final List<_Sticker> _stickers = [];
  String _audienceButtonText = '전체 공개';
  final Set<int> _selectedAudienceGroupIds = {};
  bool _audienceSelectAll = true;
  bool _audiencePrivateOnly = false;
  bool _isUploading = false;

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
          keys: const ['thumbnailUrl', 'thumnailUrl', 'thumnailImageUrl'],
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
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      barrierColor: Colors.transparent,
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
      } else if (names.isEmpty) {
        label = '그룹 선택';
      } else {
        final int extra = names.length - 1;
        label = extra > 0 ? '${names.first} 외 $extra' : names.first.toString();
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
      // 업로드 시작 - 로딩 상태 표시
      setState(() {
        _isUploading = true;
      });

      final Map<String, dynamic> payload = await _buildFinalJson();
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
            onImagesSelected: (files) {
              if (files.isEmpty) return;
              setState(() {
                //사실 여기서 이미지 선택후 서버
                _exportedThumbnailImageUrl = files.first.path;
              });
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardRadius = 5.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const ui.Color.fromARGB(182, 144, 144, 144),
        elevation: 0,
        title: const Text('', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: TextButton(
              onPressed:
                  _isUploading
                      ? null
                      : () {
                        _publish();
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
                                Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '발행 중...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      )
                      : Text(
                        '등록',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 배경 블러 + 반투명
          Positioned.fill(
            child: GestureDetector(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: const ui.Color.fromARGB(182, 144, 144, 144),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '미리보기',
                        style: TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 10),
                      AspectRatio(
                        aspectRatio: 3 / 4,
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
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      cardRadius,
                                    ),
                                    child: Container(
                                      color: AppColors.darkSurface,
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: Image.network(
                                              _exportedThumbnailImageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (c, e, s) => Container(
                                                    color:
                                                        AppColors.darkSurface,
                                                    child: const Center(
                                                      child: Icon(
                                                        Icons.image,
                                                        color: Colors.white54,
                                                      ),
                                                    ),
                                                  ),
                                            ),
                                          ),
                                          Positioned.fill(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(
                                                  0.0,
                                                ),
                                              ),
                                            ),
                                          ),
                                          // 스티커들
                                          ..._stickers.map(
                                            (s) => _DraggableSticker(
                                              sticker: s,
                                              enabled: _editMode,
                                            ),
                                          ),
                                          Positioned(
                                            top: 12,
                                            left: 10,
                                            child: _buildProfileInfo(),
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
                      const SizedBox(height: 15),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 30.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _excerpt,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 30),
                    ],
                  ),
                ),
                Spacer(),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 10.0,
                  ),
                  child: ElevatedButton(
                    onPressed: _openVisibilitySheet,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: const Color.fromARGB(255, 70, 70, 70),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_audienceButtonText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 255, 255, 255),
              borderRadius: BorderRadius.circular(300),
              border: Border.all(
                color: const Color.fromARGB(255, 202, 202, 202),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(300),
              child: Image.network(
                "https://thumbnews.nateimg.co.kr/view610///news.nateimg.co.kr/orgImg/pt/2025/06/12/202506122116776778_684ac5398c368.jpg",
                fit: BoxFit.cover,
                width: 33,
                height: 33,
              ),
            ),
          ),
          SizedBox(width: 4),
          Container(
            margin: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "affection-jk",
                  style: TextStyle(
                    color: const Color.fromARGB(255, 225, 225, 225),
                    fontSize: 14,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w600,
                    height: 0.9,
                  ),
                ),
                Text(
                  "@affection-jk",
                  style: TextStyle(
                    color: const Color.fromARGB(255, 255, 255, 255),
                    fontSize: 14,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
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
  }

  @override
  Widget build(BuildContext context) {
    final groupProv = context.watch<GroupProvider>();
    final List<Group> groups = const [];
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
                color: Colors.white24,
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
                        leading: const CircleAvatar(
                          radius: 30,
                          backgroundColor: AppColors.darkBorder,
                          child: Icon(Icons.public, color: Colors.white),
                        ),
                        title: const Text(
                          '전체 공개',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: const Text(
                          '모든 사용자에게 공개',
                          style: TextStyle(color: Colors.white70),
                        ),
                        trailing: Icon(
                          checked
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: checked ? Colors.white : Colors.white24,
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
                        leading: const CircleAvatar(
                          radius: 30,
                          backgroundColor: AppColors.darkBorder,
                          child: Icon(Icons.lock, color: Colors.white),
                        ),
                        title: const Text(
                          '나만 보기',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: const Text(
                          '본인만 볼 수 있음',
                          style: TextStyle(color: Colors.white70),
                        ),
                        trailing: Icon(
                          checked
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: checked ? Colors.white : Colors.white24,
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
                        backgroundColor: AppColors.darkBorder,
                        child: Text(g.name.substring(0, 1)),
                      ),
                      title: Text(
                        g.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        g.description,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: Icon(
                        checked
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: checked ? Colors.white : Colors.white24,
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
                  final names =
                      _displayGroups(const [], false)
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
    if (isLoading) return original;
    final List<Group> result = List<Group>.from(original);
    // UI 테스트용: 최소 5개까지 데모 그룹으로 채우기
    if (result.length < 5) {
      final now = DateTime.now();
      final owner = User(id: 0, username: 'me', alias: 'me');
      final demo = [
        Group(
          id: 1001,
          name: '친구들',
          description: '지인 모임',
          ownerId: 'me',
          owner: owner,
          createdAt: now,
        ),
        Group(
          id: 1002,
          name: '동네런닝',
          description: '러닝 크루',
          ownerId: 'me',
          owner: owner,
          createdAt: now,
        ),
        Group(
          id: 1003,
          name: '회사동료',
          description: '팀/동료',
          ownerId: 'me',
          owner: owner,
          createdAt: now,
        ),
        Group(
          id: 1004,
          name: '가족',
          description: '패밀리',
          ownerId: 'me',
          owner: owner,
          createdAt: now,
        ),
        Group(
          id: 1005,
          name: '비공개클럽',
          description: '초대 전용',
          ownerId: 'me',
          owner: owner,
          createdAt: now,
        ),
      ];
      for (final g in demo) {
        if (result.length >= 5) break;
        if (!result.any((x) => x.name == g.name)) {
          result.add(g);
        }
      }
    }
    return result;
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
