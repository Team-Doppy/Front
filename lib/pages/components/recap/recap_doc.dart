import 'package:flutter/foundation.dart';

class RecapDoc {
  final RecapHero hero;
  final List<RecapBlock> blocks;

  RecapDoc({required this.hero, required this.blocks});

  factory RecapDoc.fromJson(Map<String, dynamic> json) {
    debugPrint('[RecapDoc.fromJson] 시작 - json keys: ${json.keys.toList()}');

    final heroJson = (json['hero'] as Map?)?.cast<String, dynamic>() ?? {};
    debugPrint('[RecapDoc.fromJson] heroJson: $heroJson');

    final blocksJson = (json['blocks'] as List? ?? []);
    debugPrint(
      '[RecapDoc.fromJson] blocksJson 타입: ${blocksJson.runtimeType}, 개수: ${blocksJson.length}',
    );

    final blocks =
        blocksJson
            .whereType<Map>()
            .map((e) => RecapBlock.fromJson(e.cast<String, dynamic>()))
            .toList();

    debugPrint('[RecapDoc.fromJson] 파싱된 blocks 개수: ${blocks.length}');

    return RecapDoc(hero: RecapHero.fromJson(heroJson), blocks: blocks);
  }
}

class RecapHero {
  final String title;
  final String? subtitle;
  final String? imageUrl;

  RecapHero({required this.title, this.subtitle, this.imageUrl});

  factory RecapHero.fromJson(Map<String, dynamic> json) {
    return RecapHero(
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
    );
  }
}

enum RecapMotionPreset { soft, hero, punchy }

enum RecapImageAnimation {
  none,
  parallax,
  blurOnScroll,
  scaleOnScroll,
  parallaxBlur,
}

class RecapBlock {
  final String type;
  final RecapMotionPreset motion;
  final Map<String, dynamic> data;

  RecapBlock({required this.type, required this.motion, required this.data});

  factory RecapBlock.fromJson(Map<String, dynamic> json) {
    final type = (json['type']?.toString() ?? 'paragraph').trim();
    final motionStr = (json['motion']?.toString() ?? 'soft').trim();
    final motion = switch (motionStr) {
      'hero' => RecapMotionPreset.hero,
      'punchy' => RecapMotionPreset.punchy,
      _ => RecapMotionPreset.soft,
    };

    // ✅ 렌더러 규약: block.data에는 "data" 페이로드만 들어간다.
    // 예) {type:'h1', motion:'hero', data:{text:'...'}}  -> RecapBlock.data == {text:'...'}
    final payload =
        (json['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return RecapBlock(type: type, motion: motion, data: payload);
  }
}
