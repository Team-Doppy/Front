import 'package:flutter/material.dart';

class PostDecoderUtil {
  static Widget buildContentViewer(Map<String, dynamic> content) {
    final blocks = (content['blocks'] as List?) ?? [];
    final editor = (content['editor'] as Map?)?.cast<String, dynamic>() ?? {};
    final grid = (content['grid'] as Map?)?.cast<String, dynamic>() ?? {};

    // 🎯 그리드 정보 읽기
    final columns = (grid['columns'] as num?)?.toDouble() ?? 21.0;
    final editorScreenWidth =
        (editor['screenWidth'] as num?)?.toDouble() ?? 420.0;
    final editorGridSize = (editor['gridSize'] as num?)?.toDouble() ?? 20.0;

    print(
      '🎯 Grid Info: columns=$columns, editorScreenWidth=$editorScreenWidth, editorGridSize=$editorGridSize',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final currentScreenWidth = constraints.maxWidth;
        final currentGridSize =
            currentScreenWidth / columns; // 🔥 현재 화면의 그리드 크기

        print(
          '🖼️ Grid Scale: current=${currentScreenWidth.toStringAsFixed(1)} (${currentGridSize.toStringAsFixed(2)}/grid)',
        );

        // 🎯 안전한 SingleChildScrollView + Column 방식으로 변경
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:
                blocks.map<Widget>((block) {
                  final blockMap = (block as Map).cast<String, dynamic>();
                  final type = blockMap['type'] as String? ?? '';

                  if (type == 'paragraph') {
                    final para =
                        (blockMap['paragraph'] as Map?)
                            ?.cast<String, dynamic>() ??
                        {};
                    final align = (para['text_align'] ?? 'left') as String;
                    final rich = (para['rich_text'] as List?) ?? [];

                    // 빈 텍스트는 건너뛰기
                    if (rich.isEmpty) return const SizedBox(height: 8);

                    final spans = _toTextSpans(rich);
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      alignment: _toAlignment(align),
                      child: RichText(
                        text: TextSpan(children: spans),
                        textAlign: _toTextAlign(align),
                      ),
                    );
                  }

                  if (type == 'image') {
                    final layout =
                        (blockMap['layout'] as Map?)?.cast<String, dynamic>() ??
                        {};
                    final pos =
                        (layout['position'] as Map?)?.cast<String, dynamic>() ??
                        {};
                    final size =
                        (layout['size'] as Map?)?.cast<String, dynamic>() ?? {};
                    final image =
                        (blockMap['image'] as Map?)?.cast<String, dynamic>() ??
                        {};

                    double gridX = (pos['gridX'] as num?)?.toDouble() ?? 0.0;
                    double gridW = (size['gridW'] as num?)?.toDouble() ?? 1.0;
                    double gridH = (size['gridH'] as num?)?.toDouble() ?? 1.0;
                    double pxW = (size['pxW'] as num?)?.toDouble() ?? 400.0;
                    double pxH = (size['pxH'] as num?)?.toDouble() ?? 300.0;

                    final maxLeftCols = (columns - gridW).clamp(0.0, columns);
                    gridX = gridX.clamp(0.0, maxLeftCols);
                    final left = gridX * currentGridSize;

                    // 폭 계산 (에디터 gridSize와 현재 gridSize 비율 고려)
                    double width;
                    if (editorGridSize > 0 && pxW > 0) {
                      width = pxW * (currentGridSize / editorGridSize);
                    } else {
                      width = gridW * currentGridSize;
                    }

                    // 높이 계산 (원본 비율 우선 유지)
                    double height;
                    if (pxW > 0 && pxH > 0) {
                      height = width * (pxH / pxW); // 원본 비율 기준
                    } else if (gridH > 0) {
                      height = gridH * currentGridSize;
                    } else {
                      height = width * 9 / 16; // 최후 fallback 비율
                    }

                    final url = image['url'] as String? ?? '';
                    final alt = image['alt'] as String? ?? '이미지';

                    return Container(
                      width: double.infinity,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: EdgeInsets.only(left: left),
                          width: width,
                          height: height,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _buildImage(url, alt),
                          ),
                        ),
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                }).toList(),
          ),
        );
      },
    );
  }

  static Widget _buildImage(String url, String alt) {
    if (url.isEmpty) {
      return Container(
        color: Colors.grey.shade300,
        child: const Center(child: Icon(Icons.image, color: Colors.grey)),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) {
        return Container(
          color: Colors.grey.shade300,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image, color: Colors.grey),
                const SizedBox(height: 4),
                Text(
                  alt,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🎯 텍스트 스팬 변환 (안전한 방식)
  static List<InlineSpan> _toTextSpans(List rich) {
    return rich.map<InlineSpan>((item) {
      final m = (item as Map).cast<String, dynamic>();

      // 🔥 새로운 구조: type과 text 분리
      final textData = (m['text'] as Map?)?.cast<String, dynamic>() ?? {};
      final content = textData['content'] as String? ?? '';

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

  // 🎯 기존 buildContentBlocks는 하위 호환성을 위해 유지
  static List<Widget> buildContentBlocks(Map<String, dynamic> content) {
    return [buildContentViewer(content)];
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
