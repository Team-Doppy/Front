import 'dart:async';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/recap/recap_doc.dart';
import 'package:doppy/pages/components/recap/recap_dummy.dart';
import 'package:doppy/pages/components/recap/recap_renderer.dart';
import 'package:doppy/providers/home_recommendation_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RecapContentScreen extends StatefulWidget {
  const RecapContentScreen({
    super.key,
    this.docJson,
    this.audioPlayer,
    this.initialVolume = 1.0,
  });

  final Map<String, dynamic>? docJson;
  final AudioPlayer? audioPlayer; // ✅ 로딩 화면에서 전달받은 오디오 플레이어
  final double initialVolume; // ✅ 초기 볼륨 (페이드인 완료된 상태)

  @override
  State<RecapContentScreen> createState() => _RecapContentScreenState();
}

class _RecapContentScreenState extends State<RecapContentScreen> {
  late final ScrollController _scrollController;
  late final RecapDoc _doc;
  bool _isExpanded = true;
  bool _showAppBar = true; // 앱바 표시 여부
  double _lastScrollOffset = 0.0;
  DateTime? _lastScrollUpdate;
  static const double _expandedHeight = 400.0;
  static const double _scrollThreshold = 4.0; // 미세 스크롤 무시
  static const Color _darkSurface = AppColors.darkSurface;

  AudioPlayer? _audioPlayer;
  StreamSubscription<void>? _playerCompleteSubscription;
  double _audioVolume = 1.0;
  bool _isNavigating = false; // ✅ 뒤로가기 중복 클릭 방지

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    // ✅ 오디오 플레이어 설정
    _audioPlayer = widget.audioPlayer;
    _audioVolume = widget.initialVolume;

    if (_audioPlayer != null) {
      // ✅ 오디오 완료 리스너
      _playerCompleteSubscription = _audioPlayer!.onPlayerComplete.listen((_) {
        if (mounted) {
          _fadeOutAndDisposeAudio();
        }
      });
    }

    // ✅ 리캡을 보고 있는 동안 백그라운드에서 홈 섹션 데이터 미리 로드
    // (홈 화면으로 돌아갔을 때 새로운 데이터가 표시되도록)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = this.context;
      if (context.mounted) {
        try {
          final recommendationProvider =
              context.read<HomeRecommendationProvider>();
          // ✅ 백그라운드에서 실행 (에러는 무시)
          recommendationProvider.loadHomeRecommendations().catchError((e) {
            debugPrint('[RecapContentScreen] 홈 섹션 데이터 미리 로드 실패 (무시): $e');
          });
        } catch (e) {
          debugPrint('[RecapContentScreen] 홈 섹션 데이터 미리 로드 실패 (무시): $e');
        }
      }
    });

    // 🎯 서버 응답 구조 처리: {success, data: {...}} 또는 직접 {hero, blocks} 구조 모두 지원
    Map<String, dynamic> jsonToParse;
    if (widget.docJson != null) {
      // docJson이 전달된 경우
      if (widget.docJson!.containsKey('data') &&
          widget.docJson!['data'] is Map) {
        // {success, data: {...}} 구조인 경우 data 추출
        jsonToParse = widget.docJson!['data'] as Map<String, dynamic>;
        debugPrint('[RecapContentScreen] 서버 응답 구조 감지 - data 추출');
      } else if (widget.docJson!.containsKey('hero') ||
          widget.docJson!.containsKey('blocks')) {
        // 이미 {hero, blocks} 구조인 경우 그대로 사용
        jsonToParse = widget.docJson!;
        debugPrint('[RecapContentScreen] 직접 구조 - 그대로 사용');
      } else {
        // 알 수 없는 구조
        jsonToParse = {};
        debugPrint(
          '[RecapContentScreen] ⚠️ 알 수 없는 구조: ${widget.docJson!.keys.toList()}',
        );
      }
    } else {
      // docJson이 null인 경우 더미 데이터 사용
      jsonToParse = recapDummyJson['data'] as Map<String, dynamic>? ?? {};
      debugPrint('[RecapContentScreen] 더미 데이터 사용');
    }

    _doc = RecapDoc.fromJson(jsonToParse);

    for (int i = 0; i < _doc.blocks.length; i++) {
      debugPrint(
        '[RecapContentScreen] block[$i]: type=${_doc.blocks[i].type}, motion=${_doc.blocks[i].motion}',
      );
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _playerCompleteSubscription?.cancel();
    _fadeOutAndDisposeAudio();
    super.dispose();
  }

  Future<void> _fadeOutAndDisposeAudio() async {
    if (_audioPlayer == null) return;

    try {
      // ✅ 페이드아웃 애니메이션 (0.5초 동안 현재 볼륨 -> 0.0)
      const duration = Duration(milliseconds: 500);
      const steps = 10;
      final stepDuration = duration ~/ steps;
      final volumeStep = _audioVolume / steps;

      for (int i = steps; i >= 0; i--) {
        if (_audioPlayer == null) return;
        _audioVolume = (i * volumeStep).clamp(0.0, 1.0);
        await _audioPlayer!.setVolume(_audioVolume);
        await Future<void>.delayed(stepDuration);
      }

      await _audioPlayer!.stop();
    } catch (e) {
      debugPrint('[RecapContentScreen] 오디오 페이드아웃 실패: $e');
    } finally {
      _playerCompleteSubscription?.cancel();
      await _audioPlayer?.dispose();
      _audioPlayer = null;
    }
  }

  void _onScroll() {
    final double nextOffset = _scrollController.offset;
    final double delta = nextOffset - _lastScrollOffset;

    // 성능 최적화: 스크롤 업데이트 throttling (16ms = 60fps)
    final now = DateTime.now();
    if (_lastScrollUpdate != null &&
        now.difference(_lastScrollUpdate!).inMilliseconds < 16) {
      _lastScrollOffset = nextOffset;
      return;
    }
    _lastScrollUpdate = now;

    // 확장 상태 업데이트
    final isExpanded = nextOffset < (_expandedHeight - 56);
    if (_isExpanded != isExpanded) {
      setState(() => _isExpanded = isExpanded);
    }

    // 앱바 표시/숨김 로직
    bool nextShow = _showAppBar;
    if (delta < -_scrollThreshold) {
      // 위로 스크롤 → 앱바 표시
      nextShow = true;
    } else if (delta > _scrollThreshold) {
      // 아래로 스크롤 → 앱바 숨김
      nextShow = false;
    }

    if (nextShow != _showAppBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _showAppBar = nextShow;
            _lastScrollOffset = nextOffset;
          });
        }
      });
    } else {
      _lastScrollOffset = nextOffset;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hero = _doc.hero;

    return Scaffold(
      backgroundColor: _darkSurface,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            // ✅ 위로 스크롤하면 숨겨지고, 아래로 스크롤하면 나타남
            pinned: _showAppBar,
            floating: false,
            snap: false,
            stretch: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            toolbarHeight: 56, // 앱바 축소 시 최대 높이
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              color: AppColors.darkTextPrimary,
              onPressed: () async {
                // ✅ 뒤로가기 중복 클릭 방지
                if (_isNavigating) return;
                _isNavigating = true;

                try {
                  // ✅ 뒤로가기 시 오디오 페이드아웃
                  await _fadeOutAndDisposeAudio();
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                } catch (e) {
                  debugPrint('[RecapContentScreen] 뒤로가기 실패: $e');
                  // 에러 발생 시에도 플래그는 유지 (중복 방지)
                }
              },
            ),
            expandedHeight: _expandedHeight,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (hero.imageUrl != null && hero.imageUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: hero.imageUrl!,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget:
                          (context, url, error) => Container(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                          ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            Theme.of(context).colorScheme.surface,
                          ],
                        ),
                      ),
                    ),

                  // 하단 그라데이션: hero section에서 darkSurface로 부드럽게 전환
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.4),
                          _darkSurface.withOpacity(0.8),
                          _darkSurface,
                        ],
                        stops: const [0.0, 0.5, 0.85, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverToBoxAdapter(
              child: RecapRenderer(
                doc: _doc,
                scrollController: _scrollController,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverToBoxAdapter(
              child: Container(color: Colors.transparent, height: 100),
            ),
          ),
        ],
      ),
    );
  }
}
