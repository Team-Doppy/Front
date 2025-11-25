import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LinkOverlay extends StatefulWidget {
  const LinkOverlay({
    super.key,
    required this.onSubmit,
    this.autoSubmit = false, // 🎯 링크 추가 시 즉시 제출 (프로필 편집용)
  });

  final void Function({
    required String url,
    String? title,
    String? description,
    String? thumbnailUrl,
  })
  onSubmit;

  final bool autoSubmit; // 🎯 true이면 _enqueueUrl에서 즉시 onSubmit 호출

  @override
  State<LinkOverlay> createState() => _LinkOverlayState();
}

class _LinkOverlayState extends State<LinkOverlay> {
  final _url = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _customTitleController =
      TextEditingController(); // 🎯 사용자 정의 타이틀
  final FocusNode _titleFocusNode = FocusNode();

  Timer? _debounce;
  String? _pTitle;
  String? _pDesc;
  String? _pThumb;
  bool _isFetchingMeta = false; // 메타데이터 가져오는 중인지

  double _dragStartY = 0.0;
  double _dragStartX = 0.0;
  bool _isDragging = false;

  final List<_LinkItem> _items = <_LinkItem>[]; // 여러 링크 큐
  List<String> _suggestions = <String>[]; // URL 추천 목록
  List<String> _linkHistory = <String>[]; // 🎯 링크 추가 기록

  // SharedPreferences 키
  static const String _linkHistoryKey = 'link_overlay_history';

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
    _loadLinkHistory();
    _focusNode.addListener(() {
      // 포커스 변화 시 UI 갱신 (추천/리스트 토글)
      if (mounted) {
        // 포커스를 받았을 때 추천 목록이 비어있으면 기록 또는 기본 추천 목록으로 설정
        if (_focusNode.hasFocus && _suggestions.isEmpty && _url.text.isEmpty) {
          _updateSuggestionsForFocus();
          // 다음 프레임에서 상태 업데이트하여 깜빡임 방지
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
          return;
        }
        // 포커스를 잃었을 때 입력이 비어있으면 기록 또는 기본 추천 목록으로 설정
        if (!_focusNode.hasFocus && _url.text.isEmpty) {
          _updateSuggestionsForFocus();
        }
        setState(() {});
      }
    });
  }

  // 🎯 링크 기록 불러오기
  Future<void> _loadLinkHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_linkHistoryKey) ?? <String>[];
      if (mounted) {
        setState(() {
          _linkHistory = history;
          // 기록이 있으면 기록을 먼저 표시, 없으면 기본 링크 표시
          _updateSuggestionsForFocus();
        });
      }
    } catch (e) {
      debugPrint('[LinkOverlay] 링크 기록 불러오기 실패: $e');
      // 실패 시 기본 추천 목록 표시
      if (mounted) {
        setState(() {
          _suggestions = _popularSites.map((site) => site['url']!).toList();
        });
      }
    }
  }

  // 🎯 링크 기록 저장하기 (최대 20개, 중복 제거, 최신순)
  Future<void> _saveLinkHistory(String url) async {
    try {
      // 중복 제거 및 최신순 정렬
      _linkHistory.remove(url); // 기존에 있으면 제거
      _linkHistory.insert(0, url); // 맨 앞에 추가

      // 최대 20개만 유지
      if (_linkHistory.length > 20) {
        _linkHistory = _linkHistory.take(20).toList();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_linkHistoryKey, _linkHistory);
    } catch (e) {
      debugPrint('[LinkOverlay] 링크 기록 저장 실패: $e');
    }
  }

  // 🎯 포커스 상태에 따라 추천 목록 업데이트 (기록 우선)
  void _updateSuggestionsForFocus() {
    if (_linkHistory.isNotEmpty) {
      // 기록이 있으면 기록을 먼저 표시
      _suggestions = List<String>.from(_linkHistory);
    } else {
      // 기록이 없으면 기본 링크 표시
      _suggestions = _popularSites.map((site) => site['url']!).toList();
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _focusNode.dispose();
    _customTitleController.dispose();
    _titleFocusNode.dispose();

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
        backgroundColor: const Color(0xFF2D2D2D).withOpacity(0.9),
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
              // 🎯 autoSubmit일 때 URL이 유효하면 즉시 포커스 해제하여 미리보기 표시
              if (widget.autoSubmit && value.trim().isNotEmpty) {
                final normalized = _normalizeUrl(value.trim());
                if (normalized != null && _isValidUrl(normalized)) {
                  // 다음 프레임에서 포커스 해제 (입력 완료 후)
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _focusNode.hasFocus) {
                      _focusNode.unfocus();
                    }
                  });
                }
              }
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
                child: Container(
                  color: const Color(0xFF2D2D2D).withOpacity(0.9),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(color: Colors.transparent),
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
                            // 🎯 autoSubmit일 때 미리보기 표시 (URL이 있고 정규화 가능할 때)
                            (widget.autoSubmit &&
                                    _url.text.trim().isNotEmpty &&
                                    _normalizeUrl(_url.text.trim()) != null)
                                ? _buildPreviewCard()
                                : _focusNode.hasFocus
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
            // 🎯 autoSubmit일 때 미리보기 하단에 추가 버튼 표시 (URL이 정규화 가능할 때)
            if (widget.autoSubmit &&
                _url.text.trim().isNotEmpty &&
                _normalizeUrl(_url.text.trim()) != null &&
                !_focusNode.hasFocus)
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50),
                    backgroundColor: AppColors.darkTextPrimary,
                    foregroundColor: AppColors.darkBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () async {
                    if (_url.text.trim().isNotEmpty) {
                      // 🎯 URL 정규화하여 기록에 저장
                      final normalizedUrl = _normalizeUrl(_url.text.trim());
                      if (normalizedUrl != null) {
                        await _saveLinkHistory(normalizedUrl);
                      }

                      // 🎯 사용자가 입력한 타이틀이 있으면 사용, 없으면 메타데이터 타이틀 또는 도메인 사용
                      final finalTitle =
                          _customTitleController.text.trim().isNotEmpty
                              ? _customTitleController.text.trim()
                              : (_pTitle?.isNotEmpty == true ? _pTitle : null);

                      widget.onSubmit(
                        url: normalizedUrl ?? _url.text.trim(),
                        title: finalTitle,
                        description: _pDesc,
                        thumbnailUrl: _pThumb,
                      );
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text(
                    '추가',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            // 기존 버튼 (에디터용)
            if (!widget.autoSubmit && _items.isNotEmpty && !_focusNode.hasFocus)
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
                          : () async {
                            _focusNode.unfocus();
                            for (final it in _items) {
                              // 🎯 URL 정규화하여 기록에 저장
                              final normalizedUrl = _normalizeUrl(it.url);
                              if (normalizedUrl != null) {
                                await _saveLinkHistory(normalizedUrl);
                              }

                              widget.onSubmit(
                                url: normalizedUrl ?? it.url,
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
    final normalized = _normalizeUrl(input);
    if (input.isEmpty || normalized == null) {
      setState(() {
        _pTitle = null;
        _pDesc = null;
        _pThumb = null;
        _isFetchingMeta = false;
        _customTitleController.clear(); // 🎯 URL이 변경되면 타이틀도 초기화
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
          _isFetchingMeta = false;
          _customTitleController.clear(); // 🎯 URL이 비어지면 타이틀도 초기화
        });
        return;
      }

      // 정규화된 URL로 메타데이터 가져오기
      final normalizedUrl = _normalizeUrl(trimmedInput);
      if (normalizedUrl != null && _isValidUrl(normalizedUrl)) {
        // 🎯 autoSubmit일 때는 포커스를 해제하여 미리보기 표시
        if (widget.autoSubmit && _focusNode.hasFocus) {
          _focusNode.unfocus();
        }
        setState(() {
          _isFetchingMeta = true;
        });
        await _fetchMeta(normalizedUrl);
        if (mounted) {
          setState(() {
            _isFetchingMeta = false;
            // 메타데이터에서 타이틀이 가져와지면 커스텀 타이틀에 설정
            if (_pTitle != null &&
                _pTitle!.isNotEmpty &&
                _customTitleController.text.isEmpty) {
              _customTitleController.text = _pTitle!;
            }
          });

          // 🎯 autoSubmit일 때 커스텀 제목 필드에 자동 포커스
          if (widget.autoSubmit) {
            // 메타데이터 가져오기 완료 후 포커스 (약간의 딜레이 추가)
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted && _titleFocusNode.canRequestFocus) {
                _titleFocusNode.requestFocus();
              }
            });
          }
        }
      } else {
        // URL이 완전하지 않으면 메타데이터 초기화
        setState(() {
          _pTitle = null;
          _pDesc = null;
          _pThumb = null;
          _isFetchingMeta = false;
          _customTitleController.clear(); // 🎯 URL이 유효하지 않으면 타이틀도 초기화
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

    // 입력이 비어있으면 기록 또는 기본 링크 표시
    if (trimmed.isEmpty) {
      _updateSuggestionsForFocus();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    // 🎯 기록에서 먼저 검색 (입력과 일치하는 기록이 있으면 우선 표시)
    for (final historyUrl in _linkHistory) {
      if (historyUrl.toLowerCase().contains(trimmed)) {
        suggestions.add(historyUrl);
      }
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

    // 🎯 유명 사이트 검색 (기록에 없는 것만)
    for (final site in _popularSites) {
      final siteName = site['name']!.toLowerCase();
      final siteUrl = site['url']!.toLowerCase();

      if ((siteName.contains(trimmed) || siteUrl.contains(trimmed)) &&
          !suggestions.contains(site['url']!)) {
        suggestions.add(site['url']!);
      }
    }

    // URL 패턴 자동 완성 (기록에 없는 것만)
    if (!hasHttp && !hasDomain) {
      // 도메인 패턴 감지: youtube, naver, google 등
      if (RegExp(r'^[a-zA-Z0-9-]+\.[a-zA-Z]{2,}$').hasMatch(trimmed)) {
        // 이미 도메인 형태면 https:// 추가
        final suggested = 'https://$trimmed';
        if (!suggestions.contains(suggested)) {
          suggestions.add(suggested);
        }
      } else if (RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(trimmed)) {
        // 단어만 입력된 경우 .com 추가
        final suggestionsToAdd = [
          'https://www.$trimmed.com',
          'https://$trimmed.com',
          'https://www.$trimmed.kr',
          'https://$trimmed.kr',
        ];
        for (final suggested in suggestionsToAdd) {
          if (!suggestions.contains(suggested)) {
            suggestions.add(suggested);
          }
        }
      }
    } else if (hasHttp && !hasDomain) {
      // http/https는 있지만 도메인이 완전하지 않은 경우
      final withoutProtocol = trimmed.replaceFirst(RegExp(r'^https?://'), '');
      if (RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(withoutProtocol)) {
        final suggested = 'https://$withoutProtocol';
        if (!suggestions.contains(suggested)) {
          suggestions.add(suggested);
        }
        if (!withoutProtocol.contains('www.')) {
          final suggestedWithWww = 'https://www.$withoutProtocol';
          if (!suggestions.contains(suggestedWithWww)) {
            suggestions.add(suggestedWithWww);
          }
        }
      }
    } else if (!hasHttp && hasDomain) {
      // 도메인은 있지만 프로토콜이 없는 경우
      final suggested = 'https://$trimmed';
      if (!suggestions.contains(suggested)) {
        suggestions.add(suggested);
      }
      if (!trimmed.contains('www.')) {
        final suggestedWithWww = 'https://www.$trimmed';
        if (!suggestions.contains(suggestedWithWww)) {
          suggestions.add(suggestedWithWww);
        }
      }
    }

    // 중복 제거 및 정렬 (기록 우선, 그 다음 유명 사이트/자동완성)
    final uniqueSuggestions = suggestions.toSet().toList();
    uniqueSuggestions.sort((a, b) {
      // 기록에 있는 것이 먼저 오도록 정렬
      final aInHistory = _linkHistory.contains(a);
      final bInHistory = _linkHistory.contains(b);
      if (aInHistory && !bInHistory) return -1;
      if (!aInHistory && bInHistory) return 1;
      return a.compareTo(b);
    });

    setState(() {
      _suggestions = uniqueSuggestions.take(10).toList(); // 최대 10개 표시
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
    if (url == null) {
      if (target == null && mounted) {
        setState(() {
          _isFetchingMeta = false;
        });
      }
      return;
    }
    if (target == null) {
      if (mounted) {
        setState(() {
          _isFetchingMeta = true;
        });
      }
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
      if (target == null && mounted) {
        setState(() {
          _isFetchingMeta = false;
        });
      }
    } finally {
      if (!mounted) return;
      if (target == null) {
        setState(() {
          _isFetchingMeta = false;
        });
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
        ErrorHandler.showInfo(context, context.tr('link_may_invalid'));
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
    // http:// 또는 https://로 시작하지 않으면 추가
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      // 이미 도메인 형태인지 확인 (예: example.com)
      if (RegExp(
            r'^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.([a-zA-Z]{2,}|[a-zA-Z]{2,}\.[a-zA-Z]{2,})',
          ).hasMatch(u) ||
          RegExp(r'^\d+\.\d+\.\d+\.\d+').hasMatch(u)) {
        u = 'https://$u';
      } else {
        // 도메인 형태가 아니면 null 반환
        return null;
      }
    }
    // 기본 URL 패턴 검증
    if (!RegExp(
      r'^https?://[^\s/$.?#].[^\s]*$',
      caseSensitive: false,
    ).hasMatch(u)) {
      return null;
    }
    return u;
  }

  void _enqueueUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    // 🎯 URL 정규화하여 기록에 저장
    final normalizedUrl = _normalizeUrl(trimmed);
    if (normalizedUrl != null) {
      await _saveLinkHistory(normalizedUrl);
      // 기록 저장 후 목록 업데이트
      await _loadLinkHistory();
    }

    // 중복 제거
    final exists = _items.any((e) => e.url == trimmed);
    if (exists) return;
    final item = _LinkItem(url: trimmed);
    // 추가 직후 포커스 해제 (키보드 내림)
    try {
      _focusNode.unfocus();
    } catch (_) {}

    // 🎯 autoSubmit이 true이면 미리보기를 보여주고 메타데이터를 가져온 후 추가 (프로필 편집용)
    if (widget.autoSubmit) {
      // 먼저 메타데이터 가져오기
      await _fetchMeta(trimmed);

      // 메타데이터를 가져온 후 미리보기 표시를 위해 상태 업데이트
      // (이미 _fetchMeta에서 _pTitle, _pDesc, _pThumb가 설정됨)

      // 미리보기가 표시되도록 포커스 해제
      if (mounted) {
        _focusNode.unfocus();
        setState(() {
          // 메타데이터에서 타이틀이 가져와지면 커스텀 타이틀에 설정
          if (_pTitle != null &&
              _pTitle!.isNotEmpty &&
              _customTitleController.text.isEmpty) {
            _customTitleController.text = _pTitle!;
          }
          // 미리보기 표시를 위해 URL은 유지
        });

        // 🎯 커스텀 제목 필드에 자동 포커스 (약간의 딜레이 추가)
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _titleFocusNode.canRequestFocus) {
            _titleFocusNode.requestFocus();
          }
        });
      }
      return;
    }

    // 기존 동작 (에디터용)
    setState(() {
      _items.insert(0, item);
      _url.clear();
      _pTitle = null;
      _pDesc = null;
      _pThumb = null;
    });
    _fetchMeta(trimmed, target: item);
  }

  // 🎯 autoSubmit일 때 미리보기 카드 빌드 (리스트 아이템 형태)
  Widget _buildPreviewCard() {
    final url = _url.text.trim();
    if (url.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('empty_preview'));
    }

    // URL 정규화 (표시용)
    String displayUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      displayUrl = 'https://$url';
    }

    // 도메인 추출 (표시용)
    String domain = url;
    try {
      final uri = Uri.parse(displayUrl);
      domain = uri.host.replaceFirst('www.', '');
    } catch (_) {
      domain = url;
    }

    return Padding(
      key: const ValueKey('preview_card'),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 🎯 링크 썸네일 또는 아이콘
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Builder(
                  builder: (context) {
                    // 도메인에서 썸네일 URL 생성 (Google Favicon API)
                    String? thumbnailUrl;
                    try {
                      final uri = Uri.parse(displayUrl);
                      final domainForIcon = uri.host.replaceFirst('www.', '');
                      thumbnailUrl =
                          'https://www.google.com/s2/favicons?domain=$domainForIcon&sz=64';
                    } catch (_) {
                      thumbnailUrl = null;
                    }

                    // 메타데이터에서 썸네일이 있으면 우선 사용
                    if (_pThumb != null && _pThumb!.isNotEmpty) {
                      thumbnailUrl = _pThumb;
                    }

                    if (_isFetchingMeta && thumbnailUrl == null) {
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        ),
                      );
                    }

                    return thumbnailUrl != null
                        ? Image.network(
                          thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.link,
                              color: Colors.white54,
                              size: 28,
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) {
                              return child;
                            }
                            return const Icon(
                              Icons.link,
                              color: Colors.white54,
                              size: 28,
                            );
                          },
                        )
                        : const Icon(
                          Icons.link,
                          color: Colors.white54,
                          size: 28,
                        );
                  },
                ),
              ),
              const SizedBox(width: 16),
              // 링크 정보 (타이틀 편집 가능)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🎯 타이틀 입력 필드 (편집 가능)
                    TextField(
                      controller: _customTitleController,
                      focusNode: _titleFocusNode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: domain,
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      maxLines: 1,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        _titleFocusNode.unfocus();
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
