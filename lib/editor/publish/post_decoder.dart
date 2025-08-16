import 'package:flutter/material.dart';

class PostDecoderUtil {
  static List<Widget> buildContentBlocks(Map<String, dynamic> content) {
    final blocks = (content['blocks'] as List?) ?? [];
    return blocks.map<Widget>((block) {
      final type = block['type'];
      if (type == 'paragraph') {
        final para = block['paragraph'] as Map<String, dynamic>;
        final rich = (para['rich_text'] as List?) ?? [];
        final align = para['text_align'] ?? 'left';
        return Container(
          alignment: _toAlignment(align),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: RichText(
            text: TextSpan(
              children:
              rich.map<TextSpan>((item) {
                final m = (item as Map).cast<String, dynamic>();
                final content =
                    ((m['text'] as Map)['content'] as String?) ?? '';
                final ann =
                    (m['annotations'] as Map?)?.cast<String, dynamic>() ??
                        {};
                return TextSpan(
                  text: content,
                  style: TextStyle(
                    fontWeight:
                    ann['bold'] == true
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontStyle:
                    ann['italic'] == true
                        ? FontStyle.italic
                        : FontStyle.normal,
                    decoration: TextDecoration.combine([
                      if (ann['underline'] == true)
                        TextDecoration.underline,
                      if (ann['strikethrough'] == true)
                        TextDecoration.lineThrough,
                    ]),
                    color:
                    ann['color'] != null
                        ? _hex(ann['color'])
                        : Colors.black,
                    fontSize: (ann['font_size'] as num?)?.toDouble() ?? 16,
                  ),
                );
              }).toList(),
            ),
            textAlign: _toTextAlign(align),
          ),
        );
      } else if (type == 'image') {
        final image = block['image'] as Map<String, dynamic>;
        final url = image['url'] ?? '';
        final alt = image['alt'] ?? '이미지';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child:
          (url.startsWith('http://') || url.startsWith('https://'))
              ? Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder:
                (c, e, s) => Center(
              child: Text(
                alt,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
              : Image.asset(
            url,
            fit: BoxFit.contain,
            errorBuilder:
                (c, e, s) => Center(
              child: Text(
                alt,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
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