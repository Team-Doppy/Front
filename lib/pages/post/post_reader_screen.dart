import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/component/row_image_component.dart'
    show ImageRowNode, RowImageComponentBuilder;
// 읽기 전용에서는 에디터 전용 컴포넌트를 사용하지 않음
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/location_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/drag_service.dart';

/// 읽기 전용: 작성 화면에서 Export된 Map을 받아 그대로 복원하여 보여준다.
class PostReaderScreen extends StatefulWidget {
  const PostReaderScreen({super.key, required this.exported, this.heroTag});
  final Map<String, dynamic> exported;
  final String? heroTag; // 홈 썸네일과 자연스러운 연결(Hero)

  @override
  State<PostReaderScreen> createState() => _PostReaderScreenState();
}

class _PostReaderScreenState extends State<PostReaderScreen>
    with SingleTickerProviderStateMixin {
  late final MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late final Editor _editor;
  late final EditorService _editorService;
  late final DragService _dragService;
  late final FocusNode _readOnlyFocus;
  final ScrollController _outerScroll = ScrollController(); // single scroll
  final GlobalKey _layoutKey = GlobalKey();
  static final GlobalKey _stackKey = GlobalKey();

  late final AnimationController _intro;
  late final Animation<double> _introCurve;
  // 상단 이미지는 SliverPersistentHeader에서 shrinkOffset 기반으로 오버레이 처리

  @override
  void initState() {
    super.initState();
    _document = _rebuildDocument(widget.exported);
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
    );
    _editorService = EditorService(editor: _editor, document: _document);
    _dragService = DragService(
      editorService: _editorService,
      scrollController: _outerScroll,
    );
    _readOnlyFocus = FocusNode(canRequestFocus: false);
    try {
      _composer.clearSelection();
    } catch (_) {}

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _introCurve = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    _intro.forward();

    // overlay는 header delegate에서 처리
  }

  @override
  void dispose() {
    _intro.dispose();
    _readOnlyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stickers = (widget.exported['stickers'] as List?) ?? const [];

    // 썸네일 우선순위: URL 키들 → base64 → 자산
    final String? thumbnailUrl = widget.exported['thumbnailImageUrl'];

    final double topHeight = MediaQuery.of(context).size.width * 3 / 4;

    return Scaffold(
      backgroundColor: AppColors.darkSurface,
      body: Stack(
        key: _stackKey,
        children: [
          CustomScrollView(
            controller: _outerScroll,
            slivers: [
              SliverPersistentHeader(
                pinned: false,
                floating: false,
                delegate: _ReaderHeaderDelegate(
                  heroTag: widget.heroTag,
                  url: thumbnailUrl,

                  assetFallback: 'assets/images/feed2.png',
                  maxHeight: topHeight,
                  intro: _introCurve,
                  buildTopImage: _buildTopImage,
                ),
              ),
              // SuperEditor는 슬리버 기반 렌더러이므로 slivers에 직접 배치
              SliverToBoxAdapter(child: SizedBox(height: 100)),
              SuperEditor(
                editor: _editor,
                stylesheet: buildCustomStylesheet(),
                selectionStyle: SelectionStyles(
                  selectionColor: const ui.Color.fromARGB(
                    255,
                    255,
                    255,
                    255,
                  ).withOpacity(0.3),
                ),
                componentBuilders: [
                  SingleImageComponentBuilder(dragService: _dragService),
                  RowImageComponentBuilder(dragService: _dragService),
                  LinkComponentBuilder(),
                  LocationComponentBuilder(dragService: _dragService),
                  MentionComponentBuilder(dragService: _dragService),
                  ...defaultComponentBuilders,
                ],
                documentLayoutKey: _layoutKey,
                focusNode: _readOnlyFocus,
                gestureMode: DocumentGestureMode.mouse,
              ),
            ],
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _outerScroll,
              builder: (context, _) {
                return IgnorePointer(
                  ignoring: true,
                  child: _ReadOnlyStickers(
                    stickers: stickers,
                    layoutKey: _layoutKey,
                    stackKey: _stackKey,
                    scrollController: _outerScroll,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopImage({
    required String? heroTag,
    required String? url,
    required String assetFallback,
  }) {
    Widget image;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http')) {
        image = Image.network(url, fit: BoxFit.cover);
      } else {
        image = Image.asset(url, fit: BoxFit.cover);
      }
    } else {
      image = Image.asset(assetFallback, fit: BoxFit.cover);
    }

    if (heroTag != null && heroTag.isNotEmpty) {
      return Hero(tag: heroTag, child: image);
    }
    return image;
  }

  MutableDocument _rebuildDocument(Map<String, dynamic> data) {
    final nodes = (data['document']?['nodes'] as List?) ?? const [];
    final rebuilt = <DocumentNode>[];
    for (final raw in nodes) {
      final m = (raw as Map).cast<String, dynamic>();
      final id = (m['id'] ?? '').toString();
      final type = (m['type'] ?? '').toString();
      switch (type) {
        case 'paragraph':
          final text = (m['text'] ?? '').toString();
          final align = (m['align'] ?? 'center').toString();
          final isTitle = m['isTitle'] == true;
          final spans = (m['spans'] as List?) ?? const [];
          final attributed = _buildAttributedText(text, spans);
          final meta = <String, dynamic>{'textAlign': align};
          if (isTitle) meta['isTitle'] = true;
          rebuilt.add(ParagraphNode(id: id, text: attributed, metadata: meta));
          break;
        case 'image':
          rebuilt.add(
            ImageNode(
              id: id,
              imageUrl: (m['url'] ?? '').toString(),
              altText: (m['altText'] ?? '').toString(),
            ),
          );
          break;
        case 'imageRow':
          rebuilt.add(
            ImageRowNode(
              id: id,
              imageUrls:
                  ((m['urls'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
              spacing: (m['spacing'] as num?)?.toDouble() ?? 4.0,
            ),
          );
          break;
        case 'link':
          rebuilt.add(
            LinkNode(
              id: id,
              url: (m['url'] ?? '').toString(),
              title: (m['title'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
              thumbnailUrl: (m['thumbnailUrl'] ?? '').toString(),
            ),
          );
          break;
        case 'location':
          rebuilt.add(
            LocationNode(
              id: id,
              lat: (m['lat'] as num?)?.toDouble() ?? 0,
              lng: (m['lng'] as num?)?.toDouble() ?? 0,
              title: (m['title'] ?? '').toString(),
              address: (m['address'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
            ),
          );
          break;
        case 'mention':
          rebuilt.add(
            MentionNode(
              id: id,
              usernames:
                  ((m['usernames'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
            ),
          );
          break;
        default:
          // 알 수 없는 노드는 문단으로 폴백
          rebuilt.add(ParagraphNode(id: id, text: AttributedText('[${type}]')));
      }
    }
    return MutableDocument(nodes: rebuilt);
  }

  AttributedText _buildAttributedText(String text, List spans) {
    final attributed = AttributedText(text);
    for (final s in spans) {
      final m = (s as Map).cast<String, dynamic>();
      final start = (m['start'] as num?)?.toInt() ?? 0;
      final end = (m['end'] as num?)?.toInt() ?? start;
      final ann = (m['attrs'] as Map?)?.cast<String, dynamic>() ?? {};
      final atts = <Attribution>{};
      if (ann['bold'] == true) atts.add(boldAttribution);
      if (ann['italic'] == true) atts.add(italicsAttribution);
      if (ann['underline'] == true) atts.add(underlineAttribution);
      if (ann['strikethrough'] == true) atts.add(strikethroughAttribution);
      final fs = (ann['font_size'] as num?)?.toDouble();
      if (fs != null) atts.add(FontSizeAttribution(fs));
      final colorHex = ann['color'] as String?;
      if (colorHex != null && colorHex.isNotEmpty) {
        atts.add(ColorAttribution(_parseHexColor(colorHex)));
      }
      for (final a in atts) {
        attributed.addAttribution(a, SpanRange(start, end - 1));
      }
    }
    return attributed;
  }

  ui.Color _parseHexColor(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    return ui.Color(int.parse(v, radix: 16));
  }
}

class _ReadOnlyStickers extends StatelessWidget {
  const _ReadOnlyStickers({
    required this.stickers,
    required this.layoutKey,
    required this.stackKey,
    required this.scrollController,
  });
  final List stickers;
  final GlobalKey layoutKey;
  final GlobalKey stackKey;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final children = <Widget>[];
        final double scrollY =
            scrollController.hasClients ? scrollController.offset : 0.0;
        for (final s in stickers) {
          final m = (s as Map).cast<String, dynamic>();
          final type = (m['type'] ?? '').toString();
          final z = (m['zIndex'] as num?)?.toInt() ?? 0;
          final rot = (m['rotation'] as num?)?.toDouble() ?? 0.0;
          final scale = (m['scale'] as num?)?.toDouble() ?? 1.0;
          final anchor = (m['anchor'] as Map?)?.cast<String, dynamic>();
          late final Offset absPos;
          late final bool needsScrollCompensation;
          if (anchor != null) {
            absPos = _resolveAnchor(anchor);
            // anchor는 DocumentLayout 기준으로 이미 스크롤을 포함한 스택 로컬 좌표이므로 보정 불필요
            needsScrollCompensation = false;
          } else {
            final pf =
                (m['positionFallback'] as Map?)?.cast<String, dynamic>() ?? {};
            absPos = Offset(
              (pf['xPx'] as num?)?.toDouble() ?? 0.0,
              (pf['yPx'] as num?)?.toDouble() ?? 0.0,
            );
            // 절대좌표 fallback은 문서 좌표(스크롤 포함)로 저장되었으므로 화면 배치 시 스크롤 보정 필요
            needsScrollCompensation = true;
          }

          Widget body;
          if (type == 'text') {
            final content =
                (m['content'] as Map?)?.cast<String, dynamic>() ?? {};
            final text = (content['text'] ?? '').toString();
            final style =
                (content['style'] as Map?)?.cast<String, dynamic>() ?? {};
            body = Text(
              text,
              style: TextStyle(
                color: _toColor(style['color']) ?? Colors.white,
                fontSize: (style['fontSize'] as num?)?.toDouble() ?? 32,
                fontWeight:
                    (style['bold'] == true) ? FontWeight.w800 : FontWeight.w500,
                fontStyle:
                    (style['italic'] == true)
                        ? FontStyle.italic
                        : FontStyle.normal,
                decoration:
                    (style['underline'] == true)
                        ? TextDecoration.underline
                        : TextDecoration.none,
                letterSpacing:
                    (style['letterSpacing'] as num?)?.toDouble() ?? 0,
              ),
            );
          } else if (type == 'emoji') {
            final content = (m['content'] ?? '').toString();
            body = Text(content, style: const TextStyle(fontSize: 40));
          } else if (type == 'image') {
            final content =
                (m['content'] as Map?)?.cast<String, dynamic>() ?? {};
            final dynamic raw = content['bytes'];
            if (raw != null) {
              try {
                final bytes =
                    raw is String ? base64Decode(raw) : raw as Uint8List;
                body = ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 200,
                      maxHeight: 200,
                    ),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                );
              } catch (_) {
                body = Container(
                  width: 140,
                  height: 140,
                  color: Colors.grey[700],
                );
              }
            } else if ((content['url'] ?? '').toString().isNotEmpty) {
              final url = (content['url'] ?? '').toString();
              body = ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 200,
                    maxHeight: 200,
                  ),
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              );
            } else {
              body = Container(
                width: 140,
                height: 140,
                color: Colors.grey[700],
              );
            }
          } else {
            body = const SizedBox.shrink();
          }

          final double topPos =
              needsScrollCompensation ? (absPos.dy - scrollY) : absPos.dy;

          final w = Positioned(
            left: absPos.dx,
            top: topPos,
            child: Transform(
              alignment: Alignment.center,
              transform:
                  Matrix4.identity()
                    ..rotateZ(rot)
                    ..scale(scale),
              child: body,
            ),
          );
          children.add(Stack(key: ValueKey('z_$z'), children: [w]));
        }
        return Stack(children: children);
      },
    );
  }

  Offset _resolveAnchor(Map<String, dynamic> anchor) {
    final nodeId = (anchor['nodeId'] ?? '').toString();
    final relX = (anchor['relX'] as num?)?.toDouble() ?? 0.5;
    final relY = (anchor['relY'] as num?)?.toDouble() ?? 0.0;

    final layout = layoutKey.currentState as DocumentLayout?;
    final stackBox = stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (layout == null || stackBox == null) return const Offset(0, 0);
    try {
      final rect = layout.getRectForSelection(
        DocumentPosition(
          nodeId: nodeId,
          nodePosition: const UpstreamDownstreamNodePosition.upstream(),
        ),
        DocumentPosition(
          nodeId: nodeId,
          nodePosition: const UpstreamDownstreamNodePosition.downstream(),
        ),
      );
      if (rect == null) return const Offset(0, 0);
      final topLeftInStack = stackBox.globalToLocal(rect.topLeft);
      final x = topLeftInStack.dx + relX * rect.width;
      final y = topLeftInStack.dy + relY * rect.height;
      return Offset(x, y);
    } catch (_) {
      return const Offset(0, 0);
    }
  }

  Color? _toColor(dynamic v) {
    if (v is String && v.startsWith('#')) {
      var hex = v.substring(1);
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    }
    return null;
  }
}

class _ReaderHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String? heroTag;
  final String? url;
  final String assetFallback;
  final double maxHeight;
  final Animation<double> intro;
  final Widget Function({
    required String? heroTag,
    required String? url,
    required String assetFallback,
  })
  buildTopImage;

  _ReaderHeaderDelegate({
    required this.heroTag,
    required this.url,
    required this.assetFallback,
    required this.maxHeight,
    required this.intro,
    required this.buildTopImage,
  });

  @override
  double get minExtent => 0;

  @override
  double get maxExtent => this.maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double visible = (maxExtent - shrinkOffset).clamp(0.0, maxExtent);
    final double overlay = (shrinkOffset / maxExtent).clamp(0.0, 1.0) * 0.15;
    final scale = 0.94 + 0.06 * intro.value;
    final translateY = (1 - intro.value) * 10;
    return SizedBox(
      height: visible,
      width: double.infinity,
      child: Transform.translate(
        offset: Offset(0, translateY),
        child: Transform.scale(
          scale: scale,
          child: Stack(
            fit: StackFit.expand,
            children: [
              buildTopImage(
                heroTag: heroTag,
                url: url,
                assetFallback: assetFallback,
              ),
              Container(color: Colors.black.withOpacity(overlay)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ReaderHeaderDelegate oldDelegate) {
    return oldDelegate.url != url ||
        oldDelegate.maxHeight != maxHeight ||
        oldDelegate.heroTag != heroTag;
  }
}
