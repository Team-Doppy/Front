import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';

class LinkOverlay extends StatefulWidget {
  const LinkOverlay({super.key, required this.onSubmit});

  final void Function({
    required String url,
    String? title,
    String? description,
    String? thumbnailUrl,
  })
  onSubmit;

  @override
  State<LinkOverlay> createState() => _LinkOverlayState();
}

class _LinkOverlayState extends State<LinkOverlay> {
  final _url = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  String? _pTitle;
  String? _pDesc;
  String? _pThumb;

  double _dragStartY = 0.0;
  double _dragStartX = 0.0;
  bool _isDragging = false;

  final List<_LinkItem> _items = <_LinkItem>[]; // 여러 링크 큐
  List<String> _suggestions = <String>[]; // URL 추천 목록

  // 유명 사이트 목록 (미국 사이트 위주)
  static const List<Map<String, String>> _popularSites = [
    {'name': 'YouTube', 'url': 'https://www.youtube.com'},
    {'name': 'Google', 'url': 'https://www.google.com'},
    {'name': 'Instagram', 'url': 'https://www.instagram.com'},
    {'name': 'Twitter/X', 'url': 'https://twitter.com'},
    {'name': 'Facebook', 'url': 'https://www.facebook.com'},
    {'name': 'Reddit', 'url': 'https://www.reddit.com'},
    {'name': 'Amazon', 'url': 'https://www.amazon.com'},
    {'name': 'Netflix', 'url': 'https://www.netflix.com'},
    {'name': 'Spotify', 'url': 'https://www.spotify.com'},
    {'name': 'LinkedIn', 'url': 'https://www.linkedin.com'},
    {'name': 'GitHub', 'url': 'https://www.github.com'},
    {'name': 'Wikipedia', 'url': 'https://www.wikipedia.org'},
    {'name': 'Pinterest', 'url': 'https://www.pinterest.com'},
    {'name': 'TikTok', 'url': 'https://www.tiktok.com'},
    {'name': 'Twitch', 'url': 'https://www.twitch.tv'},
    {'name': 'Discord', 'url': 'https://discord.com'},
    {'name': 'Medium', 'url': 'https://medium.com'},
    {'name': 'Stack Overflow', 'url': 'https://stackoverflow.com'},
    {'name': 'Apple', 'url': 'https://www.apple.com'},
    {'name': 'Microsoft', 'url': 'https://www.microsoft.com'},
    {'name': 'Hulu', 'url': 'https://www.hulu.com'},
    {'name': 'Disney+', 'url': 'https://www.disneyplus.com'},
    {'name': 'PayPal', 'url': 'https://www.paypal.com'},
    {'name': 'eBay', 'url': 'https://www.ebay.com'},
    {'name': 'Craigslist', 'url': 'https://www.craigslist.org'},
    {'name': 'Etsy', 'url': 'https://www.etsy.com'},
    {'name': 'Airbnb', 'url': 'https://www.airbnb.com'},
    {'name': 'Uber', 'url': 'https://www.uber.com'},
    {'name': 'Dropbox', 'url': 'https://www.dropbox.com'},
    {'name': 'Zoom', 'url': 'https://zoom.us'},
    {'name': 'CNN', 'url': 'https://www.cnn.com'},
    {'name': 'BBC', 'url': 'https://www.bbc.com'},
    {'name': 'The New York Times', 'url': 'https://www.nytimes.com'},
    {'name': 'Washington Post', 'url': 'https://www.washingtonpost.com'},
    {'name': 'The Wall Street Journal', 'url': 'https://www.wsj.com'},
    // 한국 사이트
    {'name': '네이버', 'url': 'https://www.naver.com'},
    {'name': '다음', 'url': 'https://www.daum.net'},
    {'name': '네이버 블로그', 'url': 'https://blog.naver.com'},
    {'name': '티스토리', 'url': 'https://www.tistory.com'},
    {'name': '벨로그', 'url': 'https://velog.io'},
  ];

  @override
  void initState() {
    super.initState();
    // 초기 상태에서 유명 사이트 추천 표시
    _suggestions = _popularSites.map((site) => site['url']!).toList();
    _focusNode.addListener(() {
      // 포커스 변화 시 UI 갱신 (추천/리스트 토글)
      if (mounted) {
        // 포커스를 받았을 때 추천 목록이 비어있으면 초기 추천 목록으로 설정
        if (_focusNode.hasFocus && _suggestions.isEmpty && _url.text.isEmpty) {
          _suggestions = _popularSites.map((site) => site['url']!).toList();
          // 다음 프레임에서 상태 업데이트하여 깜빡임 방지
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
          return;
        }
        // 포커스를 잃었을 때 입력이 비어있으면 추천 목록 초기화
        if (!_focusNode.hasFocus && _url.text.isEmpty) {
          _suggestions = _popularSites.map((site) => site['url']!).toList();
        }
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _focusNode.dispose();

    super.dispose();
  }

  void _closeOverlay() {
    // 애니메이션 없이 즉시 닫기 (흰색 깜빡임 방지)
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        systemOverlayStyle: null,
        title: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: TextField(
            cursorColor: AppColors.darkTextPrimary,
            controller: _url,
            autofocus: true,
            focusNode: _focusNode,

            style: TextStyle(color: AppColors.darkTextPrimary, fontSize: 18),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              hintText: context.tr('search_link'),
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              suffixIcon:
                  _url.text.isNotEmpty
                      ? TextButton(
                        onPressed: () {
                          _focusNode.unfocus();
                          _enqueueUrl(_url.text.trim());
                        },
                        child: Text(
                          '추가',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                          ),
                        ),
                      )
                      : Icon(
                        Icons.search,
                        color: Colors.white.withOpacity(0.6),
                        size: 22,
                      ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 16,
              ),
              isDense: true,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide.none,
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              _onUrlChanged(value);
              _updateSuggestions(value);
            },
            onSubmitted: (value) {
              _enqueueUrl(value.trim());
            },
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () => _closeOverlay(),
            child: Icon(
              Icons.close,
              color: Colors.white.withOpacity(0.7),
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: GestureDetector(
        onPanStart: (details) {
          _dragStartY = details.globalPosition.dy;
          _dragStartX = details.globalPosition.dx;
          _isDragging = true;
        },
        onPanUpdate: (details) {
          if (!_isDragging) return;

          final currentY = details.globalPosition.dy;
          final currentX = details.globalPosition.dx;
          final deltaY = currentY - _dragStartY;
          final deltaX = (currentX - _dragStartX).abs();

          // 아래로 50px 이상 드래그하면 바로 닫기
          if (deltaY > 50) {
            _isDragging = false;
            _closeOverlay();
            return;
          }

          // 좌우로 50px 이상 드래그하면 바로 닫기
          if (deltaX > 50) {
            _isDragging = false;
            _closeOverlay();
            return;
          }
        },
        onPanEnd: (details) {
          if (!_isDragging) return;

          // 드래그 속도에 따라 오버레이 닫기
          final velocity = details.velocity.pixelsPerSecond;
          if (velocity.dy.abs() > velocity.dx.abs()) {
            // 세로 드래그 (아래로)
            if (velocity.dy > 200) {
              _closeOverlay();
            }
          } else {
            // 가로 드래그 (좌우)
            if (velocity.dx.abs() > 200) {
              _closeOverlay();
            }
          }
          _isDragging = false;
        },
        child: Stack(
          children: [
            // 배경 블러 + 반투명
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  // 배경 탭 시 포커스 해제
                  _focusNode.unfocus();
                },
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    color: const ui.Color.fromARGB(235, 45, 45, 45),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child:
                            _focusNode.hasFocus
                                ? _buildSuggestions()
                                : _items.isNotEmpty
                                ? _buildItemsList()
                                : Center(
                                  key: const ValueKey('empty'),
                                  child: Text(
                                    '링크를 추가해주세요',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_items.isNotEmpty && !_focusNode.hasFocus)
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50),
                    backgroundColor:
                        _items.isEmpty ? null : AppColors.darkTextPrimary,
                    foregroundColor:
                        _items.isEmpty ? null : AppColors.darkBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed:
                      _items.isEmpty
                          ? null
                          : () {
                            _focusNode.unfocus();
                            for (final it in _items) {
                              widget.onSubmit(
                                url: it.url,
                                title: it.title,
                                description: it.description,
                                thumbnailUrl: it.thumbnailUrl,
                              );
                            }
                            Navigator.of(context).pop();
                          },
                  child: Text(
                    _items.isEmpty ? '' : '추가하기 (${_items.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onUrlChanged(String value) {
    final input = value.trim();

    // 입력이 변경되면 즉시 메타데이터 초기화 (유효하지 않은 URL일 수 있음)
    if (input.isEmpty || !_isValidUrl(input)) {
      setState(() {
        _pTitle = null;
        _pDesc = null;
        _pThumb = null;
      });
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final trimmedInput = input.trim();
      if (trimmedInput.isEmpty) {
        setState(() {
          _pTitle = null;
          _pDesc = null;
          _pThumb = null;
        });
        return;
      }

      // URL이 완전한 형태일 때만 메타데이터 가져오기
      if (_isValidUrl(trimmedInput)) {
        await _fetchMeta(trimmedInput);
      } else {
        // URL이 완전하지 않으면 메타데이터 초기화
        setState(() {
          _pTitle = null;
          _pDesc = null;
          _pThumb = null;
        });
      }
    });
  }

  // URL이 완전한 형태인지 확인 (도메인과 프로토콜이 있는지)
  bool _isValidUrl(String input) {
    if (input.isEmpty) return false;
    final trimmed = input.trim().toLowerCase();

    // http:// 또는 https://로 시작하는지 확인
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return false;
    }

    // 도메인 패턴 확인 (.com, .kr 등이 있는지)
    final hasDomain = RegExp(
      r'\.(com|kr|net|org|co\.kr|io|dev|me|tv|gov|edu|co|uk|jp|cn|info|biz|name|mobi|asia|tel|jobs|travel|xxx|pro|museum|aero|coop|int|mil|post|geo|cat|xxx|arpa|test|local)$',
      caseSensitive: false,
    ).hasMatch(trimmed);

    // 최소한 도메인 형태는 있어야 함 (예: https://example.com)
    if (!hasDomain) {
      // IP 주소 패턴도 허용
      final hasIp = RegExp(r'\d+\.\d+\.\d+\.\d+').hasMatch(trimmed);
      if (!hasIp) {
        return false;
      }
    }

    // 기본 URL 패턴 검증 (최소한 http://domain 형태)
    return RegExp(r'^https?://[a-zA-Z0-9.-]+').hasMatch(trimmed);
  }

  void _updateSuggestions(String input) {
    final trimmed = input.trim().toLowerCase();
    final suggestions = <String>[];

    // 입력이 비어있으면 유명 사이트만 표시
    if (trimmed.isEmpty) {
      setState(() {
        _suggestions = _popularSites.map((site) => site['url']!).toList();
      });
      return;
    }

    // URL 패턴 감지 및 자동 완성
    final hasHttp =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');
    final hasDomain = RegExp(
      r'\.(com|kr|net|org|co\.kr|io|dev|me|tv|gov|edu)$',
      caseSensitive: false,
    ).hasMatch(trimmed);

    // 유명 사이트와 매칭
    for (final site in _popularSites) {
      final siteName = site['name']!.toLowerCase();
      final siteUrl = site['url']!.toLowerCase();

      if (siteName.contains(trimmed) || siteUrl.contains(trimmed)) {
        suggestions.add(site['url']!);
      }
    }

    // URL 패턴 자동 완성
    if (!hasHttp && !hasDomain) {
      // 도메인 패턴 감지: youtube, naver, google 등
      if (RegExp(r'^[a-zA-Z0-9-]+\.[a-zA-Z]{2,}$').hasMatch(trimmed)) {
        // 이미 도메인 형태면 https:// 추가
        suggestions.add('https://$trimmed');
      } else if (RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(trimmed)) {
        // 단어만 입력된 경우 .com 추가
        suggestions.add('https://www.$trimmed.com');
        suggestions.add('https://$trimmed.com');

        // 한국 사이트 .kr 추가
        suggestions.add('https://www.$trimmed.kr');
        suggestions.add('https://$trimmed.kr');
      }
    } else if (hasHttp && !hasDomain) {
      // http/https는 있지만 도메인이 완전하지 않은 경우
      final withoutProtocol = trimmed.replaceFirst(RegExp(r'^https?://'), '');
      if (RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(withoutProtocol)) {
        suggestions.add('https://$withoutProtocol');
        if (!withoutProtocol.contains('www.')) {
          suggestions.add('https://www.$withoutProtocol');
        }
      }
    } else if (!hasHttp && hasDomain) {
      // 도메인은 있지만 프로토콜이 없는 경우
      suggestions.add('https://$trimmed');
      if (!trimmed.contains('www.')) {
        suggestions.add('https://www.$trimmed');
      }
    }

    // 중복 제거 및 정렬
    final uniqueSuggestions = suggestions.toSet().toList();
    uniqueSuggestions.sort();

    setState(() {
      _suggestions = uniqueSuggestions.take(5).toList(); // 최대 5개만 표시
    });
  }

  Widget _buildSuggestions() {
    if (_suggestions.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('empty_suggestions'));
    }

    return Container(
      key: const ValueKey('suggestions'),

      child: ListView.separated(
        shrinkWrap: false,
        itemCount: _suggestions.length.clamp(0, 7),
        separatorBuilder:
            (_, __) => Divider(
              height: 1,
              color: const ui.Color.fromARGB(255, 0, 0, 0).withOpacity(0.0),
            ),
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];
          // 유명 사이트인지 확인하여 이름 표시
          final siteInfo = _popularSites.firstWhere(
            (site) => site['url']!.toLowerCase() == suggestion.toLowerCase(),
            orElse: () => {'name': '', 'url': suggestion},
          );
          final displayName =
              siteInfo['name']?.isNotEmpty == true
                  ? '${siteInfo['name']} - $suggestion'
                  : suggestion;

          return InkWell(
            onTap: () {
              _focusNode.unfocus();
              _url.text = suggestion;
              _url.selection = TextSelection.fromPosition(
                TextPosition(offset: suggestion.length),
              );
              _enqueueUrl(suggestion);
              setState(() {
                _suggestions.clear();
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _fetchMeta(String rawUrl, {_LinkItem? target}) async {
    final url = _normalizeUrl(rawUrl);
    if (url == null) return;
    if (target == null) {
    } else {
      setState(() => target.fetching = true);
    }
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(Uri.parse(url));
      req.followRedirects = true;
      final res = await req.close();
      if (res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.value(HttpHeaders.locationHeader) != null) {
        final redirected = res.headers.value(HttpHeaders.locationHeader)!;
        final rreq = await client.getUrl(Uri.parse(redirected));
        final rres = await rreq.close();
        final html = await utf8.decodeStream(rres);
        _applyParsedMeta(html, target: target);
      } else {
        final html = await utf8.decodeStream(res);
        _applyParsedMeta(html, target: target);
      }
    } catch (_) {
    } finally {
      if (!mounted) return;
      if (target == null) {
      } else {
        setState(() => target.fetching = false);
      }
    }
  }

  void _applyParsedMeta(String html, {_LinkItem? target}) {
    String? ogTitle = _firstMatch(
      html,
      RegExp(
        r'meta[^>]+property=[\"\"]og:title[\"\"][^>]+content=[\"\"]([^\"\"]+)',
      ),
    );
    String? ogDesc = _firstMatch(
      html,
      RegExp(
        r'meta[^>]+property=[\"\"]og:description[\"\"][^>]+content=[\"\"]([^\"\"]+)',
      ),
    );
    String? ogImage = _firstMatch(
      html,
      RegExp(
        r'meta[^>]+property=[\"\"]og:image[\"\"][^>]+content=[\"\"]([^\"\"]+)',
      ),
    );
    ogTitle ??= _firstMatch(
      html,
      RegExp(r'<title>(.*?)<\/title>', caseSensitive: false, dotAll: true),
    );
    if (target == null) {
      setState(() {
        _pTitle = ogTitle ?? _pTitle;
        _pDesc = ogDesc ?? _pDesc;
        _pThumb = ogImage ?? _pThumb;
      });
    } else {
      final bool hasMeta =
          (ogTitle != null && ogTitle.isNotEmpty) ||
          (ogDesc != null && ogDesc.isNotEmpty) ||
          (ogImage != null && ogImage.isNotEmpty);

      setState(() {
        target.title = ogTitle ?? target.title;
        target.description = ogDesc ?? target.description;
        target.thumbnailUrl = ogImage ?? target.thumbnailUrl;
        target.fetching = false;
        target.metaLoaded = true;
        target.hasMeta = hasMeta;
      });

      if (mounted && !hasMeta && !target.warned) {
        target.warned = true;
        ErrorHandler.showInfo(context, '링크가 올바르지 않을 수 있어요.');
      }
    }
  }

  String? _firstMatch(String html, RegExp re) {
    final m = re.firstMatch(html);
    if (m == null) return null;
    return m.groupCount >= 1 ? m.group(1) : null;
  }

  String? _normalizeUrl(String input) {
    String u = input.trim();
    if (u.isEmpty) return null;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    return u;
  }

  void _enqueueUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    // 중복 제거
    final exists = _items.any((e) => e.url == trimmed);
    if (exists) return;
    final item = _LinkItem(url: trimmed);
    // 추가 직후 포커스 해제 (키보드 내림)
    try {
      _focusNode.unfocus();
    } catch (_) {}
    setState(() {
      _items.insert(0, item);
      _url.clear();
      _pTitle = null;
      _pDesc = null;
      _pThumb = null;
    });
    _fetchMeta(trimmed, target: item);
  }

  Widget _buildItemsList() {
    if (_items.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('empty_items'));
    }
    return ListView.separated(
      key: const ValueKey('items_list'),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final it = _items[index];
        return Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child:
                    it.thumbnailUrl.isNotEmpty
                        ? Image.network(
                          it.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) =>
                                  const Icon(Icons.link, color: Colors.white54),
                        )
                        : const Icon(Icons.link, color: Colors.white54),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.title.isNotEmpty ? it.title : it.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (it.description.isNotEmpty)
                      Text(
                        it.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),

                    if (it.url.isNotEmpty)
                      Text(
                        it.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (it.fetching)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _items.removeAt(index)),
                child: const Text(
                  '취소',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LinkItem {
  _LinkItem({required this.url});
  final String url;
  String title = '';
  String description = '';
  String thumbnailUrl = '';
  bool fetching = true;
  bool metaLoaded = false; // 메타데이터 로드 완료 여부
  bool hasMeta = false; // 제목/설명/썸네일 중 하나라도 존재 여부
  bool warned = false; // 스낵바 경고 중복 방지
}
