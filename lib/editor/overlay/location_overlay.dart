import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocationOverlay extends StatefulWidget {
  final void Function(double lat, double lng, String title, String address)
  onSelect;
  const LocationOverlay({super.key, required this.onSelect});

  @override
  State<LocationOverlay> createState() => _LocationOverlayState();
}

class _LocationOverlayState extends State<LocationOverlay> {
  final TextEditingController _search = TextEditingController();
  bool _loading = false;
  List<_Place> _results = const [];
  final Duration _debounce = const Duration(milliseconds: 250);
  DateTime? _lastQueryAt;

  @override
  void initState() {
    super.initState();
    _results = const [
      _Place('서울 시청', '서울 중구 세종대로 110', 37.5665, 126.9780),
      _Place('남산타워', '서울 용산구 용산동2가 산1-3', 37.5512, 126.9882),
      _Place('한강공원', '서울 영등포구 여의도동', 37.5283, 126.9326),
    ];
  }

  Widget _placeTile(_Place p) {
    return GestureDetector(
      onTap: () {
        widget.onSelect(p.lat, p.lng, p.title, p.address);
        Navigator.of(context).maybePop();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                const Icon(Icons.place, color: Colors.white70, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.address,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.add, color: Colors.white70, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            // Blur + Dim
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color: const Color.fromARGB(182, 144, 144, 144),
                ),
              ),
            ),

            // Close (left top)
            Positioned(
              top: 12,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),

            // Search bar (glass)
            Positioned(
              top: 50,
              left: 16,
              right: 16,
              child: _glass(
                child: Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        cursorColor: Colors.white,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: '장소 검색 (예: 카페, 공원, 서울시청)',
                          hintStyle: TextStyle(color: Colors.white54),
                          isDense: true,
                        ),
                        onChanged: _onQueryChanged,
                        onSubmitted: (_) => _onQueryChanged(_search.text),
                      ),
                    ),
                    if (_loading)
                      const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),

            // Map preview placeholder (for future Google Maps)
            Positioned(
              top: 120,
              left: 16,
              right: 16,
              height: 220,
              child: _glass(
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '지도가 여기에 표시됩니다 (Google Maps 연동 예정)',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),

            // Results list
            Positioned.fill(
              top: 320,
              left: 0,
              right: 0,
              bottom: 100,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemBuilder: (_, i) => _placeTile(_results[i]),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: _results.length,
              ),
            ),

            // Confirm button
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed:
                      _results.isEmpty
                          ? null
                          : () {
                            final p = _results.first;
                            widget.onSelect(p.lat, p.lng, p.title, p.address);
                            Navigator.of(context).maybePop();
                          },
                  child: const Text(
                    '이 위치 사용',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glass({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: child,
        ),
      ),
    );
  }

  void _onQueryChanged(String q) {
    final now = DateTime.now();
    _lastQueryAt = now;
    setState(() => _loading = true);
    Future.delayed(_debounce, () async {
      if (!mounted || _lastQueryAt != now) return;
      final qq = q.trim();
      if (qq.isEmpty) {
        setState(() {
          _loading = false;
          _results = const [];
        });
        return;
      }
      try {
        final list = await _fetchAutocomplete(qq);
        if (!mounted || _lastQueryAt != now) return;
        setState(() {
          _results = list;
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _loading = false);
      }
    });
  }

  // Google Places Autocomplete (REST)
  Future<List<_Place>> _fetchAutocomplete(String input) async {
    final key = const String.fromEnvironment('PLACES_KEY');
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {'input': input, 'language': 'ko', 'types': 'establishment', 'key': key},
    );
    final res = await NetworkAssetBundle(uri).load("");
    final body = const Utf8Decoder().convert(res.buffer.asUint8List());
    final map = _parseJson(body);
    final preds =
        (map['predictions'] as List?)?.cast<Map<String, dynamic>>() ??
        <Map<String, dynamic>>[];
    // description만 먼저 사용, 상세는 탭 시 조회
    return preds.map((m) => _Place(m['description'] ?? '', '', 0, 0)).toList();
  }

  Future<_Place?> _fetchDetail(String placeId) async {
    final key = const String.fromEnvironment('PLACES_KEY');
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
          'place_id': placeId,
          'fields': 'geometry/location,name,formatted_address',
          'language': 'ko',
          'key': key,
        });
    final res = await NetworkAssetBundle(uri).load("");
    final body = const Utf8Decoder().convert(res.buffer.asUint8List());
    final map = _parseJson(body);
    final r = (map['result'] as Map?) ?? {};
    final g = (r['geometry'] as Map?)?['location'] as Map?;
    if (g == null) return null;
    final lat = (g['lat'] as num).toDouble();
    final lng = (g['lng'] as num).toDouble();
    return _Place(r['name'] ?? '', r['formatted_address'] ?? '', lat, lng);
  }

  Map<String, dynamic> _parseJson(String s) {
    return jsonDecode(s) as Map<String, dynamic>;
  }
}

class _Place {
  final String title;
  final String address;
  final double lat;
  final double lng;
  const _Place(this.title, this.address, this.lat, this.lng);
}
