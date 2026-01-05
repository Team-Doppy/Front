import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:doppy/image/utils/editor_image_provider.dart';

/// 스티커 오버레이 (리더/에디터 공용)
class PostReaderStickers extends StatefulWidget {
  const PostReaderStickers({
    super.key,
    required this.stickers,
    required this.layoutKey,
    required this.stackKey,
    required this.scrollController,
    this.topInset = 0,
  });

  final List stickers;
  final GlobalKey layoutKey;
  final GlobalKey stackKey;
  final ScrollController scrollController;
  final double topInset;

  @override
  State<PostReaderStickers> createState() => _PostReaderStickersState();
}

class _PostReaderStickersState extends State<PostReaderStickers> {
  // ✅ 스크롤 중 리빌드가 매우 자주 발생하므로, 비용 큰 작업은 캐시한다.
  // - stickers 정렬: 스티커 데이터가 바뀔 때만 재계산
  // - base64Decode: 스티커 id 기준으로 1회만 수행
  List<Map<String, dynamic>> _sorted = const [];
  final Map<String, Uint8List> _decodedBytesByKey = <String, Uint8List>{};

  @override
  void initState() {
    super.initState();
    _rebuildSorted();
  }

  @override
  void didUpdateWidget(covariant PostReaderStickers oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stickers, widget.stickers)) {
      _rebuildSorted();
      // 스티커가 교체되면 캐시도 오래된 데이터가 남을 수 있으므로 정리한다.
      // id 기반 키는 안정적이지만, 안전하게 크기를 제한한다.
      if (_decodedBytesByKey.length > 200) {
        _decodedBytesByKey.clear();
      }
    }
  }

  void _rebuildSorted() {
    final list = <Map<String, dynamic>>[];
    for (final s in widget.stickers) {
      if (s is Map<String, dynamic>) {
        list.add(s);
      } else if (s is Map) {
        list.add(s.cast<String, dynamic>());
      }
    }
    list.sort((a, b) {
      final za = (a['zIndex'] as num?)?.toInt() ?? 0;
      final zb = (b['zIndex'] as num?)?.toInt() ?? 0;
      return za.compareTo(zb);
    });
    _sorted = list;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.scrollController,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final children = <Widget>[];
            final double scrollY =
                widget.scrollController.hasClients
                    ? widget.scrollController.offset
                    : 0.0;

            // ✅ URL 이미지 decodeWidth는 스티커마다 동일하므로 루프 밖에서 1회만 계산
            final screenWidth = constraints.maxWidth;
            final decodeWidth = EditorImageProvider.readingDecodeWidth(
              context,
              screenWidth,
            );

            for (final m in _sorted) {
              final type = (m['type'] ?? '').toString();
              // zIndex는 정렬에만 사용되었으며 여기선 미사용
              final rot = (m['rotation'] as num?)?.toDouble() ?? 0.0;
              double baseScale = (m['scale'] as num?)?.toDouble() ?? 1.0;
              // ✅ PostwriteScreen 방식: positionFallback만 사용 (anchor 해석 제거로 성능 향상)
              // - anchor 해석(_getNodeRect, _resolveAnchor)은 매 프레임마다 localToGlobal/globalToLocal을 호출하여
              //   프레임 드랍과 "출렁거림"을 유발할 수 있음
              // - positionFallback은 이미 문서 좌표로 저장되어 있어서 단순 스케일만 적용하면 됨
              final pf =
                  (m['positionFallback'] as Map?)?.cast<String, dynamic>() ??
                  {};
              final docWidth = (pf['docWidth'] as num?)?.toDouble();
              final currentWidth = constraints.maxWidth;
              final scale =
                  (docWidth != null && docWidth > 0)
                      ? (currentWidth / docWidth)
                      : 1.0;
              final Offset absPos = Offset(
                ((pf['xPx'] as num?)?.toDouble() ?? 0.0) * scale,
                ((pf['yPx'] as num?)?.toDouble() ?? 0.0) * scale,
              );

              // ✅ anchor 기반 스케일 보정은 제거 (성능 우선)
              // - 필요시 나중에 캐시를 추가하여 복원 가능
              double anchorScale = 1.0;

              Widget body;

              // 🎯 PNG 드로잉만 지원 (type == 'image'만 처리)
              if (type == 'image') {
                final content =
                    (m['content'] as Map?)?.cast<String, dynamic>() ?? {};
                final dynamic raw = content['bytes'];
                if (raw != null) {
                  try {
                    final String id = (m['id'] ?? '').toString();
                    // ✅ base64 문자열은 스크롤 중 매 프레임 디코딩하면 매우 무겁다 → 캐시
                    Uint8List bytes;
                    if (raw is String) {
                      final key =
                          id.isNotEmpty
                              ? 'id:$id'
                              : 'b64:${raw.length}_${raw.hashCode}';
                      bytes = _decodedBytesByKey.putIfAbsent(
                        key,
                        () => base64Decode(raw),
                      );
                    } else {
                      bytes = raw as Uint8List;
                    }

                    // 🎯 PNG 드로잉 (고화질 원본)
                    body = RepaintBoundary(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        isAntiAlias: true,
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
                  final width = (content['width'] as num?)?.toDouble();
                  final height = (content['height'] as num?)?.toDouble();

                  // 🎯 PNG 드로잉 (URL + 크기 정보)
                  // ✅ 프리로드와 동일한 EditorImageProvider 사용으로 캐시 히트 보장
                  final imageProviderResult = EditorImageProvider.build(
                    url: url,
                    isEditing: false, // 읽기 모드
                    decodeWidth: decodeWidth,
                  );

                  if (width != null && height != null) {
                    body = RepaintBoundary(
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: Image(
                          image: imageProviderResult.effectiveProvider,
                          fit: BoxFit.fill, // 정확한 크기
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: width,
                              height: height,
                              color: Colors.transparent,
                            );
                          },
                        ),
                      ),
                    );
                  } else {
                    // 레거시: 크기 정보 없음
                    body = RepaintBoundary(
                      child: Image(
                        image: imageProviderResult.effectiveProvider,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 140,
                            height: 140,
                            color: Colors.transparent,
                          );
                        },
                      ),
                    );
                  }
                } else {
                  body = Container(
                    width: 140,
                    height: 140,
                    color: Colors.grey[700],
                  );
                }
              } else {
                // 🎯 text, emoji, drawing 타입은 무시
                continue;
              }

              final double topPos = absPos.dy - scrollY;

              // 최종 스케일: 저장된 스케일 * 앵커 스케일 보정
              final double finalScale = baseScale * anchorScale;

              // ✅ 문서 좌표계에서 Stack 좌표계로 변환: topInset 추가
              // - absPos.dy는 문서 좌표계, scrollY를 빼면 문서 내 상대 위치
              // - topInset(헤더 높이)을 더해서 Stack 내 절대 위치로 변환
              double left = absPos.dx;
              double top = topPos + widget.topInset;
              // ✅ PostwriteScreen 방식: 중심 보정 없음 (좌상단 기준)

              children.add(
                Positioned(
                  left: left,
                  top: top,
                  child: Transform(
                    alignment: Alignment.center,
                    transform:
                        Matrix4.identity()
                          ..rotateZ(rot)
                          ..scale(finalScale),
                    child: body,
                  ),
                ),
              );
            }
            return Stack(children: children);
          },
        );
      },
    );
  }
}

// 🎯 벡터 드로잉 제거됨 (PNG만 지원)
