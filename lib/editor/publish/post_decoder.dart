import 'package:flutter/material.dart';

/// - 아래 영역에 그리드 기반 레이아웃으로 렌더링합니다.
class PostDecoder extends StatefulWidget {
  final Map<String, dynamic>? initialJson;
  const PostDecoder({super.key, this.initialJson});

  @override
  State<PostDecoder> createState() => _PostDecoderState();
}

class _PostDecoderState extends State<PostDecoder> {
  final TextEditingController _controller = TextEditingController();
  Map<String, dynamic>? _model;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialJson != null) {
      _model = widget.initialJson;
      _controller.text = const JsonEncoder.withIndent(
        '  ',
      ).convert(widget.initialJson);
    }
  }

  void _render() {
    setState(() {
      _error = null;
      _model = null;
    });

    try {
      final text = _controller.text.trim();
      if (text.isEmpty) {
        setState(() => _error = 'JSON을 붙여넣어 주세요.');
        return;
      }
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      setState(() => _model = decoded);
    } catch (e) {
      setState(() => _error = 'JSON 파싱 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: '여기에 JSON을 붙여넣으세요',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  ElevatedButton(onPressed: _render, child: const Text('렌더')),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _controller.clear();
                        _model = null;
                        _error = null;
                      });
                    },
                    child: const Text('초기화'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          ),
        const SizedBox(height: 8),
        Container(
          color: Colors.white,
          child:
              _model == null
                  ? const Center(
                    child: Text(
                      'JSON을 붙여넣고 렌더를 눌러보세요',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                  : GridDocumentViewer(model: _model!),
        ),
      ],
    );
  }
}

/// 그리드 기반 JSON → 뷰 렌더러
class GridDocumentViewer extends StatelessWidget {
  final Map<String, dynamic> model;
  const GridDocumentViewer({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final blocks = (model['blocks'] as List).cast<dynamic>();
    final columns = _readColumns(model);

    // 에디터와 동일한 컨텐츠 폭 기준으로 그리드 크기 계산
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth =
        screenWidth; // 에디터는 SystemConstants.documentMargin 제거했으므로 전체 폭 사용
    final gridSize = contentWidth / columns;

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: blocks.length,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemBuilder: (context, i) {
        final b = (blocks[i] as Map).cast<String, dynamic>();
        final type = b['type'] as String? ?? '';
        if (type == 'paragraph') {
          final p = (b['paragraph'] as Map?)?.cast<String, dynamic>() ?? {};
          final align = (p['text_align'] ?? 'center') as String;
          final rich = (p['rich_text'] as List<dynamic>? ?? []);
          final spans = _toTextSpans(rich);
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: _toAlignment(align),
            child: RichText(
              text: TextSpan(children: spans),
              textAlign: _toTextAlign(align),
            ),
          );
        }

        if (type == 'image') {
          final layout = (b['layout'] as Map?)?.cast<String, dynamic>() ?? {};
          final pos =
              (layout['position'] as Map?)?.cast<String, dynamic>() ?? {};
          final size = (layout['size'] as Map?)?.cast<String, dynamic>() ?? {};

          double gridX = ((pos['gridX'] as num?) ?? 0).toDouble();
          double gridW = ((size['gridW'] as num?) ?? 0).toDouble();
          double gridH = ((size['gridH'] as num?) ?? 0).toDouble();
          double pxW = (size['pxW'] as num?)?.toDouble() ?? 0;
          double pxH = (size['pxH'] as num?)?.toDouble() ?? 0;

          // 좌우 클램프 및 NaN 방지
          final maxLeftCols = (columns - gridW).clamp(0.0, columns);
          if (!gridX.isFinite) gridX = 0;
          gridX = gridX.clamp(0.0, maxLeftCols);

          final left = gridX * gridSize;
          // 그리드 기반 크기 계산 (에디터와 동일한 방식)
          double width = gridW * gridSize;
          double height = gridH * gridSize;

          // 원본 비율이 있으면 그리드 크기 내에서 비율 유지
          if (pxW > 0 && pxH > 0 && gridW > 0 && gridH > 0) {
            final aspectRatio = pxH / pxW;
            final gridAspectRatio = gridH / gridW;

            // 원본 비율과 그리드 비율이 다르면 그리드에 맞게 조정
            if ((aspectRatio - gridAspectRatio).abs() > 0.1) {
              if (aspectRatio > gridAspectRatio) {
                // 세로가 더 긴 경우: 높이를 그리드에 맞추고 너비 조정
                height = gridH * gridSize;
                width = height / aspectRatio;
              } else {
                // 가로가 더 긴 경우: 너비를 그리드에 맞추고 높이 조정
                width = gridW * gridSize;
                height = width * aspectRatio;
              }
            }
          }

          // 원본 비율이 우선이므로 추가 보정은 제거
          return Padding(
            padding: EdgeInsets.only(
              left: left,
              right: screenWidth - left - width,
              top: 8,
              bottom: 8,
            ),
            child: SizedBox(
              width: width,
              height: height,
              child: _ImageFast(
                url:
                    ((b['image'] as Map?)?.cast<String, dynamic>() ?? {})['url']
                        as String? ??
                    '',
              ),
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  static double _readColumns(Map<String, dynamic> model) {
    final grid = (model['grid'] as Map?)?.cast<String, dynamic>();
    if (grid == null) return 40; // 기본값
    final cols = grid['columns'];
    if (cols is num) return cols.toDouble();
    return 40;
  }

  static double _readWriterGridSizePx(Map<String, dynamic> model) {
    final grid = (model['grid'] as Map?)?.cast<String, dynamic>();
    if (grid == null) return 0;
    final v = grid['writerGridSizePx'];
    if (v is num) return v.toDouble();
    return 0;
  }

  static List<InlineSpan> _toTextSpans(List rich) {
    return rich.map<InlineSpan>((item) {
      final m = (item as Map).cast<String, dynamic>();
      final content = ((m['text'] as Map)['content'] as String?) ?? '';
      final ann = (m['annotations'] as Map?)?.cast<String, dynamic>() ?? {};
      final style = TextStyle(
        fontWeight: ann['bold'] == true ? FontWeight.bold : FontWeight.normal,
        fontStyle: ann['italic'] == true ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (ann['underline'] == true) TextDecoration.underline,
          if (ann['strikethrough'] == true) TextDecoration.lineThrough,
        ]),
        color: ann['color'] != null ? _hex(ann['color']) : Colors.black,
        fontSize: (ann['font_size'] as num?)?.toDouble() ?? 16,
      );
      return TextSpan(text: content, style: style);
    }).toList();
  }

  static Alignment _toAlignment(String align) {
    switch (align) {
      case 'left':
        return Alignment.centerLeft;
      case 'right':
        return Alignment.centerRight;
      default:
        return Alignment.center;
    }
  }

  static TextAlign _toTextAlign(String align) {
    switch (align) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.center;
    }
  }

  static Color _hex(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    return Color(int.parse(v, radix: 16));
  }
}

/// 네트워크 이미지를 최대한 빠르게 보여주기 위한 위젯
/// - 작은 placeHolder로 먼저 그린 뒤, 이미지 로딩 완료 시 페이드 인
class _ImageFast extends StatelessWidget {
  final String url;

  const _ImageFast({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(color: Colors.grey.shade300);
    }

    // 디바이스 픽셀 비율에 따른 고화질 이미지 크기 계산
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final highQualitySize = (800 * devicePixelRatio).round();

    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high, // 고품질 렌더링
      // 이미지 품질 향상을 위한 추가 설정
      gaplessPlayback: true, // 이미지 전환 시 깜빡임 방지
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return Container(color: Colors.grey.shade200);
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          alignment: Alignment.center,
          color: Colors.grey.shade200,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (context, error, stack) {
        return Container(color: Colors.grey.shade300);
      },
      // 고화질 이미지를 위한 캐시 크기 증가
      cacheHeight: highQualitySize,
      cacheWidth: highQualitySize,
    );
  }
}