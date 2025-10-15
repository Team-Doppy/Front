import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
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

  Timer? _debounce;
  bool _fetching = false;
  String? _pTitle;
  String? _pDesc;
  String? _pThumb;

  final List<_LinkItem> _items = <_LinkItem>[]; // 여러 링크 큐

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _url.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(182, 96, 96, 96),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close, color: Colors.white, size: 22),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: TextField(
            cursorColor: AppColors.darkTextPrimary,
            controller: _url,
            autofocus: true,
            focusNode: FocusNode(),

            style: TextStyle(color: AppColors.darkTextPrimary, fontSize: 18),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              hintText: '링크 검색하기',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              suffixIcon:
                  _url.text.isNotEmpty
                      ? TextButton(
                        onPressed: () {
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
            },
            onSubmitted: (value) {
              _enqueueUrl(value.trim());
            },
          ),
        ),
      ),
      body: Stack(
        children: [
          // 배경 블러 + 반투명
          Positioned.fill(
            child: GestureDetector(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(color: const Color.fromARGB(182, 96, 96, 96)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 10, width: double.infinity),
                _buildLivePreview(),
                Expanded(child: _buildItemsList()),
                if (_items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
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
                                {
                                  for (final it in _items) {
                                    widget.onSubmit(
                                      url: it.url,
                                      title: it.title,
                                      description: it.description,
                                      thumbnailUrl: it.thumbnailUrl,
                                    );
                                  }
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
        ],
      ),
    );
  }

  Widget _buildLivePreview() {
    if (_url.text.trim().isEmpty &&
        _pTitle == null &&
        _pDesc == null &&
        _pThumb == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 큰 썸네일
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child:
                  (_pThumb ?? '').isNotEmpty
                      ? Image.network(
                        _pThumb!,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => Container(
                              color: const Color(0xFF2A2A2A),
                              child: const Center(
                                child: Icon(Icons.link, color: Colors.white54),
                              ),
                            ),
                      )
                      : Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Center(
                          child: Icon(Icons.link, color: Colors.white54),
                        ),
                      ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 제목
                if ((_pTitle ?? '').isNotEmpty)
                  Text(
                    _pTitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 6),
                // 설명
                if ((_pDesc ?? '').isNotEmpty)
                  Text(
                    _pDesc!,
                    maxLines: 3,

                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                if ((_pDesc ?? '').isNotEmpty) const SizedBox(height: 6),
                Text(
                  _url.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                if (_fetching) const SizedBox(height: 8),
                if (_fetching)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _onUrlChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final input = value.trim();
      if (input.isEmpty) {
        setState(() {
          _pTitle = null;
          _pDesc = null;
          _pThumb = null;
        });
        return;
      }
      await _fetchMeta(input);
    });
  }

  Future<void> _fetchMeta(String rawUrl, {_LinkItem? target}) async {
    final url = _normalizeUrl(rawUrl);
    if (url == null) return;
    if (target == null) {
      setState(() => _fetching = true);
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
      // 무시: 사용자가 수동 입력 가능
    } finally {
      if (!mounted) return;
      if (target == null) {
        setState(() => _fetching = false);
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
      setState(() {
        target.title = ogTitle ?? target.title;
        target.description = ogDesc ?? target.description;
        target.thumbnailUrl = ogImage ?? target.thumbnailUrl;
      });
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
    if (_items.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
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
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (it.description.isNotEmpty)
                      Text(
                        it.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
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
                child: const Icon(Icons.close, color: Colors.white38, size: 18),
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
}
