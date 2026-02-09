import 'dart:ui';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/pages/screens/post_mode_selection_screen.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/my_friends_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:doppy/providers/military_grid_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/letter_provider.dart';
import 'package:doppy/data/models/military_grid_model.dart';
import 'package:doppy/pages/components/military_grid_widget.dart';
import 'package:doppy/l10n/military_grid_messages.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/search_video_widgets.dart';
import 'package:doppy/image/utils/read_image_cache_manager.dart';
import 'package:doppy/utils/route_observer.dart';
import 'package:doppy/pages/screens/pre_enlistment_goals_screen.dart';
import 'package:doppy/data/models/girlfriend_request_model.dart';
import 'package:doppy/editor/overlay/letter_recipient_selection_overlay.dart';

// =============================================================================
// ✅ 섹션 간격 상수
// =============================================================================

/// 홈 화면 섹션 간격 상수
class HomeSectionSpacing {
  HomeSectionSpacing._();

  // 주요 섹션 간격
  static const double sectionXLarge =
      80.0; // 매우 큰 섹션 간격 (FillSection과 ListSection 사이)
  static const double sectionLarge = 70.0; // 큰 섹션 간격 (같은 타입 섹션들 사이)
  static const double sectionMedium = 24.0; // 중간 섹션 간격
  static const double sectionSmall = 16.0; // 작은 섹션 간격
  static const double sectionXSmall = 12.0; // 매우 작은 섹션 간격
  static const double sectionXXSmall = 10.0; // 가장 작은 섹션 간격
  static const double sectionTiny = 4.0; // 미세 간격

  // 특수 간격
  static const double greetingBottom = 24.0; // 환영 인사 아래 간격
  static const double gridBottom =
      40.0; // 그리드 아래 간격 (FillSection과 ListSection 사이와 동일)
  static const double gridTop =
      0.0; // 그리드 아래 간격 (FillSection과 ListSection 사이와 동일)
  static const double bannerBottom = 24.0; // 배너 아래 간격
  static const double postCardHeaderBottom = 12.0; // 포스트 카드 헤더 아래 간격
  static const double postCardTitleBottom = 4.0; // 포스트 카드 제목 아래 간격
  static const double friendItemSpacing = 18.0; // 친구 아이템 간격 (가로)
  static const double friendItemBottom = 10.0; // 친구 아이템 아래 간격
}

// =============================================================================
// ✅ 홈 섹션 조립 유틸 (간격을 한 곳에서만 관리)
// =============================================================================

class HomeSectionItem {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const HomeSectionItem({required this.child, this.padding = EdgeInsets.zero});
}

/// ✅ FillSection 계열 위젯인지 확인
bool _isFillSection(Widget widget) {
  // FillSection 직접 사용
  if (widget is FillSection) return true;

  // FillSection을 사용하는 섹션들
  if (widget is GirlfriendRequestAcceptSection) return true;
  // GirlfriendWriteCTASection은 이제 일반 CTA 카드이므로 FillSection 아님
  if (widget is PromotionReportCTASection) return true;
  if (widget is PostFillSection) return true;
  if (widget is SupportPostsSection) return true;

  // PreEnlistmentCTASection은 배경 이미지 있을 때만 FillSection
  // 하지만 간단하게 항상 FillSection으로 처리 (배경 없으면 낮은 배너지만)
  if (widget is PreEnlistmentCTASection) return true;

  // Padding으로 감싸진 경우 재귀 확인
  if (widget is Padding) {
    return _isFillSection(widget.child!);
  }

  // GestureDetector로 감싸진 경우 재귀 확인
  if (widget is GestureDetector) {
    return _isFillSection(widget.child!);
  }

  return false;
}

/// ✅ CTA 카드 위젯인지 확인
bool _isCTACard(Widget widget) {
  if (widget is ThisWeekWriteButton) return true;
  if (widget is GirlfriendWriteCTASection) return true;
  if (widget is PlaceholderGirlfriendWriteCTASection) return true;
  if (widget is SocialMemoryWriteButton) return true;

  // Padding으로 감싸진 경우 재귀 확인
  if (widget is Padding) {
    return _isCTACard(widget.child!);
  }

  // GestureDetector로 감싸진 경우 재귀 확인
  if (widget is GestureDetector) {
    final child = widget.child;
    if (child != null) {
      return _isCTACard(child);
    }
  }

  return false;
}

class HomeSectionList extends StatelessWidget {
  final List<HomeSectionItem> items;
  final double defaultGap; // ✅ 기본 간격 (FillSection이 아닌 섹션들 사이)

  const HomeSectionList({
    super.key,
    required this.items,
    this.defaultGap = HomeSectionSpacing.sectionLarge, // ✅ 기본 간격을 더 크게 (70px)
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final child = Padding(padding: item.padding, child: item.child);
      children.add(child);

      // 마지막 아이템이 아니면 간격 추가
      if (i < items.length - 1) {
        // ✅ StreamBuilder는 간격 계산에서 제외 (건너뛰기)
        if (item.child is StreamBuilder) {
          continue;
        }

        // ✅ item.child를 직접 체크 (타입 기반)
        final currentIsFill = _isFillSection(item.child);

        // ✅ 다음 실제 위젯 찾기 (StreamBuilder 같은 조건부 위젯 건너뛰기)
        Widget? nextWidget;
        int nextIndex = i + 1;
        while (nextIndex < items.length) {
          final nextItem = items[nextIndex];
          // StreamBuilder는 건너뛰고 실제 위젯 찾기
          if (nextItem.child is! StreamBuilder) {
            nextWidget = nextItem.child;
            break;
          }
          nextIndex++;
        }

        // ✅ 다음 위젯이 있으면 간격 계산
        if (nextWidget != null) {
          final nextIsFill = _isFillSection(nextWidget);
          final currentIsCTA = _isCTACard(item.child);
          final nextIsCTA = _isCTACard(nextWidget);

          // ✅ 간격 계산
          double gap;
          if ((currentIsFill && nextIsFill) || (currentIsCTA && nextIsCTA)) {
            // FillSection끼리 또는 CTA끼리 인접: 4px
            gap = HomeSectionSpacing.sectionTiny;
          } else if ((currentIsCTA && nextIsFill) ||
              (currentIsFill && nextIsCTA)) {
            // CTA와 FillSection이 인접: 20px
            gap = 20.0;
          } else {
            // 그 외: 기본 간격
            gap = defaultGap;
          }

          children.add(SizedBox(height: gap));
        } else {
          // 다음 위젯이 없으면 기본 간격만 추가
          children.add(SizedBox(height: defaultGap));
        }
      }
    }

    // ✅ 마지막 위젯이 잘리지 않도록 하단 패딩 추가
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...children,
        SizedBox(
          height: MediaQuery.of(context).padding.bottom + 100,
        ), // 바텀바 + 여유 공간
      ],
    );
  }
}

// =============================================================================
// 7일 제한 배너 카드 제거됨 - 과거 기록 제한 없음

// =============================================================================
// ✅ 헬퍼 함수: 볼드 서브스트링 지원 텍스트
// =============================================================================

/// 제목과 볼드 서브스트링을 받아서 RichText로 반환
/// 볼드가 시작하는 부분에서 줄바꿈
Widget buildTitleWithBoldSubstrings({
  required BuildContext context,
  required String title,
  required List<String> boldSubstrings,
  required TextStyle baseStyle,
  required TextStyle boldStyle,
}) {
  // title을 줄바꿈으로 분리
  var lines = title.split('\n');
  lines = lines.map((line) => line.replaceAll('*', '')).toList();

  if (boldSubstrings.isEmpty) {
    // 볼드가 없으면 첫 2줄만 표시
    final displayLines = lines.take(2).join('\n');
    return Text(
      displayLines,
      style: baseStyle,
      maxLines: 2,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.left,
      softWrap: true,
    );
  }

  // 모든 줄에서 첫 번째 볼드 서브스트링 찾기
  String? firstBoldSubstring;
  int? firstBoldIndex;
  int? boldLineIndex; // 볼드가 있는 줄의 인덱스

  for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
    final line = lines[lineIdx];
    for (final boldSubstring in boldSubstrings) {
      final index = line.indexOf(boldSubstring);

      if (index != -1) {
        firstBoldSubstring = boldSubstring;
        firstBoldIndex = index;
        boldLineIndex = lineIdx;
        break;
      }
    }
    if (firstBoldSubstring != null) break;
  }

  // 볼드가 없으면 첫 2줄만 표시
  if (firstBoldSubstring == null ||
      firstBoldIndex == null ||
      boldLineIndex == null) {
    debugPrint(
      '[buildTitleWithBoldSubstrings] ❌ 볼드 서브스트링을 찾지 못함. lines: $lines, boldSubstrings: $boldSubstrings',
    );
    final displayLines = lines.take(2).join('\n');
    return Text(
      displayLines,
      style: baseStyle,
      maxLines: 2,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.left,
      softWrap: true,
    );
  }

  // 볼드가 있는 줄 처리
  final boldLine = lines[boldLineIndex];
  final beforeBold = boldLine.substring(0, firstBoldIndex);
  final fromBold = boldLine.substring(firstBoldIndex);

  // 각 줄을 처리하여 볼드 적용
  final spans = <TextSpan>[];

  // 볼드가 있는 줄 이전의 모든 줄 추가
  for (int i = 0; i < boldLineIndex; i++) {
    if (i > 0) spans.add(const TextSpan(text: '\n'));
    spans.add(TextSpan(text: lines[i], style: baseStyle));
  }

  // 볼드가 있는 줄: 볼드 이전 부분
  if (boldLineIndex > 0) spans.add(const TextSpan(text: '\n'));
  if (beforeBold.isNotEmpty) {
    spans.add(TextSpan(text: beforeBold, style: baseStyle));
  }

  // 볼드 부분부터 처리
  final secondLineSpans = <TextSpan>[];
  int lastIndex = 0;
  String remainingText = fromBold;

  // 모든 볼드 서브스트링 처리
  for (final boldSubstring in boldSubstrings) {
    final index = remainingText.indexOf(boldSubstring, lastIndex);
    if (index == -1) continue;

    // 볼드 서브스트링 이전 텍스트
    if (index > lastIndex) {
      secondLineSpans.add(
        TextSpan(
          text: remainingText.substring(lastIndex, index),
          style: baseStyle,
        ),
      );
    }

    // 볼드 서브스트링
    secondLineSpans.add(TextSpan(text: boldSubstring, style: boldStyle));
    lastIndex = index + boldSubstring.length;
  }

  // 마지막 남은 텍스트
  if (lastIndex < remainingText.length) {
    secondLineSpans.add(
      TextSpan(text: remainingText.substring(lastIndex), style: baseStyle),
    );
  }

  spans.addAll(secondLineSpans);

  return DefaultTextStyle(
    style: baseStyle,
    maxLines: 2,
    overflow: TextOverflow.clip,
    textAlign: TextAlign.left,
    softWrap: true,
    child: RichText(text: TextSpan(children: spans), textAlign: TextAlign.left),
  );
}

// =============================================================================
// ✅ 군인 홈 위젯 (입대예정 + 이미 군인)
// =============================================================================

/// 군인 홈 메인 위젯 (입대예정 + 이미 군인 모두 포함)
class MilitaryHomeWidget extends StatelessWidget {
  final Phase? selectedPhase;
  final Cell? selectedCell;
  final Function(Phase, Cell)? onCellTap;
  final Function(Phase, Cell, Offset?, Offset?)? onCellLongPress;
  final GlobalKey? gridKey; // ✅ 가이드용 GlobalKey

  const MilitaryHomeWidget({
    super.key,
    this.selectedPhase,
    this.selectedCell,
    this.onCellTap,
    this.onCellLongPress,
    this.gridKey,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer3<MilitaryGridProvider, FriendProvider, UserProvider>(
      builder: (context, gridProvider, friendProvider, userProvider, _) {
        final gridResponse = gridProvider.gridResponse;

        // ✅ 친구 포스트는 FriendProvider에서 가져오기
        final friendPosts = friendProvider.friendPosts;
        final hasFriendPosts = friendPosts.isNotEmpty;

        // ✅ 입대 예정자 여부 확인
        final currentUser = userProvider.currentUser;
        final militaryInfo = currentUser?.militaryInfo;
        final isPreEnlistment =
            militaryInfo?.status == MilitaryStatus.beforeEnlistment;
        final hasGirlfriendRequest = currentUser?.connectedToMeByUser != null;

        // 섹션 리스트 구성
        final sections = <Widget>[];

        // ✅ 입대 예정자 전용: 곰신 요청 수락 UI
        if (isPreEnlistment && hasGirlfriendRequest) {
          sections.add(
            GirlfriendRequestAcceptSection(
              girlfriendRequest: currentUser!.girlfriendRequest!,
            ),
          );
        }

        // ✅ 입대 예정자 전용: "입대 전에 꼭 답해보세요" CTA
        if (isPreEnlistment) {
          sections.add(PreEnlistmentCTASection());
        }

        // ✅ 친구 포스트가 있으면 친구 포스트 섹션 추가
        if (hasFriendPosts) {
          sections.add(
            PostCardSection(
              mode: PostCardSectionMode.unlocked,
              posts: friendPosts.take(5).toList(),
              title: '요새 내 친구들',
              titleBoldSubstrings: ['요새'],
              showAuthorInfo: true,
            ),
          );
        }
        // ✅ 친구 추천 섹션 항상 추가 (친구 포스트와 상관없이)
        sections.add(
          FriendRecommendationSection(
            onFriendTap: (String username) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => UserProfileScreen(
                        otherUser: User(username: username),
                      ),
                ),
              );
            },
            onAddFriendTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (context) => UserSearchBottomSheet(),
              );
            },
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: HomeSectionSpacing.gridTop),

            // ✅ Military Grid
            Container(
              key: gridKey, // ✅ 가이드용 GlobalKey
              child:
                  gridResponse == null
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                      : MilitaryGridWidget(
                        gridResponse: gridResponse,
                        onCellTap: onCellTap,
                        onLongPress: onCellLongPress,
                        selectedCell: selectedCell,
                        isLoading: gridProvider.isLoading,
                        onCellKey: (phase, cell, key) {
                          gridProvider.registerCellKey(phase, cell, key);
                        },
                      ),
            ),

            SizedBox(height: HomeSectionSpacing.sectionLarge),

            // ✅ 입대 예정자 전용: "이번주 남기기" CTA 버튼
            if (isPreEnlistment)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ThisWeekWriteButton(),
              ),

            if (isPreEnlistment)
              SizedBox(height: HomeSectionSpacing.sectionLarge),

            // ✅ 네트워크 오프라인 상태 표시 (그리드 밑에)
            StreamBuilder<bool>(
              stream: NetworkManager.onConnectivityChanged,
              initialData: NetworkManager.isOnline,
              builder: (context, snapshot) {
                final isOnline = snapshot.data ?? NetworkManager.isOnline;
                if (!isOnline) {
                  return _buildOfflineBanner(context);
                }
                return const SizedBox.shrink();
              },
            ),

            // 섹션들 표시
            ...sections,
          ],
        );
      },
    );
  }
}

/// 곰신 홈 메인 위젯
class GirlfriendHomeWidget extends StatefulWidget {
  final Phase? selectedPhase;
  final Cell? selectedCell;
  final Function(Phase, Cell)? onCellTap;
  final Function(Phase, Cell, Offset?, Offset?)? onCellLongPress;

  const GirlfriendHomeWidget({
    super.key,
    this.selectedPhase,
    this.selectedCell,
    this.onCellTap,
    this.onCellLongPress,
  });

  @override
  State<GirlfriendHomeWidget> createState() => _GirlfriendHomeWidgetState();
}

class _GirlfriendHomeWidgetState extends State<GirlfriendHomeWidget>
    with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MilitaryGridProvider, FriendProvider>(
      builder: (context, gridProvider, friendProvider, _) {
        final gridResponse = gridProvider.gridResponse;

        // ✅ 친구 포스트는 FriendProvider에서 가져오기
        final friendPosts = friendProvider.friendPosts;
        final hasFriendPosts = friendPosts.isNotEmpty;

        // 섹션 배치 로직
        final finalSections = <Widget>[];

        // ✅ 친구 포스트가 있으면 친구 포스트 섹션 추가
        if (hasFriendPosts) {
          final friendSection = PostCardSection(
            mode: PostCardSectionMode.unlocked,
            posts: friendPosts.take(5).toList(),
            title: '요새 내 친구들',
            titleBoldSubstrings: ['요새'],
            showAuthorInfo: true,
          );
          finalSections.add(friendSection);
        }

        // ✅ 친구 추천 섹션 항상 추가
        finalSections.add(
          FriendRecommendationSection(
            onFriendTap: (String username) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => UserProfileScreen(
                        otherUser: User(username: username),
                      ),
                ),
              );
            },
            onAddFriendTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (context) => UserSearchBottomSheet(),
              );
            },
          ),
        );

        return Column(
          children: [
            SizedBox(height: HomeSectionSpacing.gridTop),

            // ✅ Military Grid (연결된 군인의 그리드)
            gridResponse == null
                ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
                : MilitaryGridWidget(
                  gridResponse: gridResponse,
                  onCellTap: widget.onCellTap,
                  onLongPress: widget.onCellLongPress,
                  selectedCell: widget.selectedCell,
                  isLoading: gridProvider.isLoading,
                  onCellKey: (phase, cell, key) {
                    gridProvider.registerCellKey(phase, cell, key);
                  },
                ),

            SizedBox(height: HomeSectionSpacing.gridBottom),

            // ✅ 네트워크 오프라인 상태 표시 (그리드 밑에)
            StreamBuilder<bool>(
              stream: NetworkManager.onConnectivityChanged,
              initialData: NetworkManager.isOnline,
              builder: (context, snapshot) {
                final isOnline = snapshot.data ?? NetworkManager.isOnline;
                if (!isOnline) {
                  return _buildOfflineBanner(context);
                }
                return const SizedBox.shrink();
              },
            ),

            // ✅ 추천 섹션들
            ...finalSections,
          ],
        );
      },
    );
  }
}

/// 친구 추천 섹션 (락과 관련없이 항상 표시)
class FriendRecommendationSection extends StatelessWidget {
  final Function(String) onFriendTap;
  final VoidCallback? onAddFriendTap;
  final double bottomSpacing; // ✅ 외부에서 간격을 통제할 수 있도록
  final double bottomPadding; // ✅ 섹션 내부 하단 패딩(기본 24)
  final String? customTitle; // ✅ 커스텀 제목 (여친 화면용)

  const FriendRecommendationSection({
    super.key,
    required this.onFriendTap,
    this.onAddFriendTap,
    this.bottomSpacing = HomeSectionSpacing.sectionLarge,
    this.bottomPadding = HomeSectionSpacing.sectionMedium,
    this.customTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<FriendProvider>(
      builder: (context, friendProvider, _) {
        final recommendations = friendProvider.friendRecommendations;

        if (recommendations.isEmpty) {
          return const SizedBox.shrink();
        }

        final onSurface = Theme.of(context).colorScheme.onSurface;

        final allItems = <Widget>[];
        for (int i = 0; i < recommendations.length; i++) {
          final user = recommendations[i];
          final borderColor = onSurface.withOpacity(0.15);
          final borderWidth = 2.0;
          final isGirlfriend = user.role == 'girlfriend';

          final avatarWidget = Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: ClipOval(
              child: CommonProfileAvatar(
                imageUrl: user.profileImageUrl,
                username: user.username,
                size: 150,
                borderWidth: 0, // 외부 컨테이너에서 border 처리
              ),
            ),
          );

          final friendItem = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => onFriendTap(user.username),
                borderRadius: BorderRadius.circular(999),
                child: avatarWidget,
              ),
              SizedBox(height: HomeSectionSpacing.sectionXXSmall),
              SizedBox(
                width: 160,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isGirlfriend) const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        user.alias ?? user.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: LocaleTypography.style(
                          context: context,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: onSurface.withOpacity(0.9),
                        ),
                      ),
                    ),
                    // ✅ 곰신 역할 배지 (하트 아이콘) - 이름 옆에 표시
                    if (isGirlfriend) ...[
                      const SizedBox(width: 0),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Icon(
                          Icons.favorite,
                          size: 12,
                          color: const Color.fromARGB(255, 255, 129, 120),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          allItems.add(friendItem);
          if (i < recommendations.length - 1 || onAddFriendTap != null) {
            allItems.add(SizedBox(width: HomeSectionSpacing.friendItemSpacing));
          }
        }

        if (onAddFriendTap != null) {
          final addButton = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: onSurface.withOpacity(0.2),
                    width: 2.0,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onAddFriendTap,
                    borderRadius: BorderRadius.circular(999),
                    child: Center(
                      child: Icon(
                        Icons.add,
                        size: 48,
                        color: onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: HomeSectionSpacing.sectionXXSmall),
              SizedBox(
                width: 150,
                child: Text(
                  '친구 추가',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          );
          allItems.add(addButton);
        }

        return Container(
          margin: EdgeInsets.only(bottom: bottomSpacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '아는 사람들인가요?',
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(height: HomeSectionSpacing.sectionMedium),
              SizedBox(
                height: 190,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  children: allItems,
                ),
              ),
              // ✅ 하단 간격: 섹션 자체에서 관리
              SizedBox(height: bottomPadding),
            ],
          ),
        );
      },
    );
  }
}

class GreetingSection extends StatelessWidget {
  final String? greetingKey; // 서버에서 받은 greetingKey
  final bool isLoading; // 🎯 그리드 로딩 중일 때 그리팅 메시지 숨김

  const GreetingSection({super.key, this.greetingKey, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    // ✅ 높이 고정: 메시지 전환/로딩 중 레이아웃 요동 방지
    return SizedBox(
      height: 70.0,
      child: () {
        if (isLoading || greetingKey == null) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<String?>(
          future: MilitaryGridMessages.getGreetingMessage(greetingKey!),
          builder: (context, snapshot) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child:
                  snapshot.hasData && snapshot.data != null
                      ? Align(
                        key: ValueKey(snapshot.data),
                        alignment: Alignment.centerLeft,
                        child: _buildMessageWidget(context, snapshot.data!),
                      )
                      : const SizedBox.shrink(key: ValueKey('empty')),
            );
          },
        );
      }(),
    );
  }

  /// ✅ 메시지 위젯 빌드 헬퍼 메서드
  Widget _buildMessageWidget(BuildContext context, String message) {
    // 메시지를 줄바꿈으로 분리 (첫 줄: tier 스타일, 둘째 줄: mode 스타일)
    final lines = message.split('\n');
    final firstLine = lines.isNotEmpty ? lines[0] : '';
    final secondLine = lines.length > 1 ? lines[1] : '';

    // 🎯 첫 줄에서 연도 부분 찾기 (예: "2025년은")
    final yearPattern = RegExp(r'(\d{4}년은)');
    final firstLineSpans = <TextSpan>[];

    if (firstLine.isNotEmpty) {
      final baseStyle = LocaleTypography.style(
        context: context,
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w300,
        letterSpacing: -1,
        height: 1.4,
      );

      final boldStyle = LocaleTypography.style(
        context: context,
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
        height: 1.4,
      );

      final matches = yearPattern.allMatches(firstLine);
      if (matches.isEmpty) {
        // 연도 패턴이 없으면 그대로 표시
        firstLineSpans.add(TextSpan(text: firstLine, style: baseStyle));
      } else {
        // 연도 패턴이 있으면 볼드 처리
        int lastIndex = 0;
        for (final match in matches) {
          // 연도 이전 텍스트
          if (match.start > lastIndex) {
            firstLineSpans.add(
              TextSpan(
                text: firstLine.substring(lastIndex, match.start),
                style: baseStyle,
              ),
            );
          }
          // 연도 부분 (볼드)
          firstLineSpans.add(TextSpan(text: match.group(0), style: boldStyle));
          lastIndex = match.end;
        }
        // 연도 이후 텍스트
        if (lastIndex < firstLine.length) {
          firstLineSpans.add(
            TextSpan(text: firstLine.substring(lastIndex), style: baseStyle),
          );
        }
      }
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.left,
      softWrap: true, // 🎯 줄바꿈 활성화
      text: TextSpan(
        children: [
          ...firstLineSpans,
          if (secondLine.isNotEmpty) ...[
            if (firstLineSpans.isNotEmpty) const TextSpan(text: '\n'),
            TextSpan(
              text: secondLine,
              style: LocaleTypography.style(
                context: context,
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PostFillSection extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final VoidCallback? onPostTap;
  final Function(String postId)? onPostTapWithId;
  final String? title;
  final List<String>? titleBoldSubstrings;
  final double? bottomSpacing; // ✅ 하단 간격 동적 제어

  const PostFillSection({
    super.key,
    required this.posts,
    this.onPostTap,
    this.onPostTapWithId,
    this.title,
    this.titleBoldSubstrings,
    this.bottomSpacing, // null이면 기본값 사용
  });

  @override
  State<PostFillSection> createState() => _PostFillSectionState();
}

class _PostFillSectionState extends State<PostFillSection>
    with AutomaticKeepAliveClientMixin {
  late final PageController _pageController;
  late final ValueNotifier<int> _currentPageNotifier;
  late List<Map<String, dynamic>> _uniquePostsCache;

  static int get _kMaxDecodeWidthPx =>
      defaultTargetPlatform == TargetPlatform.android ? 2048 : 3072;

  @override
  bool get wantKeepAlive => true;

  void _openPost(
    BuildContext context,
    Map<String, dynamic> post,
    String postId,
  ) {
    if (widget.onPostTapWithId != null) {
      widget.onPostTapWithId!(postId);
      return;
    }

    try {
      final postData = PostData.fromServerMeta(post);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostReaderScreen(exported: postData.toExportedData()),
        ),
      );
    } catch (e) {
      debugPrint('[PostFillSection] 포스트 열기 실패: $e');
      widget.onPostTap?.call();
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(keepPage: true);
    _currentPageNotifier = ValueNotifier<int>(0);

    _pageController.addListener(() {
      if (!_pageController.hasClients) return;
      final page = _pageController.page?.round() ?? 0;
      if (_currentPageNotifier.value != page) {
        _currentPageNotifier.value = page;
      }
    });

    _uniquePostsCache = _buildUniquePosts(widget.posts);
  }

  @override
  void didUpdateWidget(covariant PostFillSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posts != widget.posts) {
      _uniquePostsCache = _buildUniquePosts(widget.posts);
    }
  }

  @override
  void dispose() {
    _currentPageNotifier.dispose();
    _pageController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _buildUniquePosts(
    List<Map<String, dynamic>> posts,
  ) {
    final seenIds = <String>{};
    final result = <Map<String, dynamic>>[];

    for (final post in posts) {
      final id = post['id']?.toString();
      if (id != null && id.isNotEmpty && seenIds.add(id)) {
        result.add(post);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final title = widget.title ?? '';
    final posts = _uniquePostsCache;

    if (posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          '포스트가 없습니다.',
          style: LocaleTypography.style(
            context: context,
            fontSize: 20,
            fontWeight: FontWeight.w400,
            color: onSurface,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Stack(
          children: [
            /// ---------------- PageView (고정) ----------------
            SizedBox(
              height: 350,
              child: PageView.builder(
                controller: _pageController,
                physics: const ClampingScrollPhysics(),
                padEnds: false,
                allowImplicitScrolling: false,
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  final post = posts[index];
                  final postId = post['id']?.toString() ?? index.toString();

                  return ValueListenableBuilder<int>(
                    valueListenable: _currentPageNotifier,
                    builder: (_, currentPage, __) {
                      return _PostFillPageItem(
                        key: ValueKey('post_fill_$postId'),
                        imageUrl: post['thumbnailImageUrl'] ?? '',
                        postData: post,
                        onTap: () => _openPost(context, post, postId),
                        isActive: index == currentPage,
                      );
                    },
                  );
                },
              ),
            ),

            /// ---------------- Gradient + Title ----------------
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.03),
                        Colors.black.withOpacity(0.2),
                        Colors.black.withOpacity(0.4),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty)
                        Flexible(
                          child:
                              widget.titleBoldSubstrings != null &&
                                      widget.titleBoldSubstrings!.isNotEmpty
                                  ? buildTitleWithBoldSubstrings(
                                    context: context,
                                    title: title,
                                    boldSubstrings: widget.titleBoldSubstrings!,
                                    baseStyle: LocaleTypography.style(
                                      context: context,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.white,
                                    ),
                                    boldStyle: LocaleTypography.style(
                                      context: context,
                                      fontSize: 36,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  )
                                  : Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.clip,
                                    style: LocaleTypography.style(
                                      context: context,
                                      fontSize: 36,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                        ),
                      if (title.isNotEmpty)
                        SizedBox(height: HomeSectionSpacing.sectionTiny),
                    ],
                  ),
                ),
              ),
            ),

            /// ---------------- Indicator (최소 rebuild) ----------------
            Positioned(
              top: 20,
              left: 24,
              child: ValueListenableBuilder<int>(
                valueListenable: _currentPageNotifier,
                builder: (_, currentPage, __) {
                  return Row(
                    children: List.generate(posts.length, (index) {
                      return Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              index == currentPage
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ),
        SizedBox(
          height: widget.bottomSpacing ?? HomeSectionSpacing.sectionLarge,
        ),
      ],
    );
  }
}

class _PostFillPageItem extends StatefulWidget {
  final String imageUrl;
  final Map<String, dynamic> postData;
  final VoidCallback? onTap;
  final bool isActive;

  const _PostFillPageItem({
    super.key,
    required this.imageUrl,
    required this.postData,
    this.onTap,
    required this.isActive,
  });

  @override
  State<_PostFillPageItem> createState() => _PostFillPageItemState();
}

class _PostFillPageItemState extends State<_PostFillPageItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final screenWidth = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final decodeWidthPx = (screenWidth * dpr * 2).round().clamp(
      1,
      _PostFillSectionState._kMaxDecodeWidthPx,
    );

    final url = widget.imageUrl.toLowerCase();
    final isVideo =
        url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.m4v') ||
        url.contains('video');

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child:
            isVideo
                ? ThumbnailVideoPlayer(
                  videoUrl: widget.imageUrl,
                  width: screenWidth,
                  height: 500,
                  autoPlay: widget.isActive,
                )
                : CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  cacheKey: widget.imageUrl,
                  cacheManager: ReadImageCacheManager.instance,
                  fit: BoxFit.cover,
                  memCacheWidth: decodeWidthPx,
                  fadeInDuration: const Duration(milliseconds: 200),
                  fadeOutDuration: const Duration(milliseconds: 200),
                  placeholder:
                      (_, __) => ShimmerBox(width: screenWidth, height: 420),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                ),
      ),
    );
  }
}

enum PostCardSectionMode { unlocked, locked }

class PostCardSection extends StatefulWidget {
  final PostCardSectionMode mode;
  final List<Map<String, dynamic>> posts;

  final String? title;
  final String? subtitle;
  final List<String>? titleBoldSubstrings; // 🎯 볼드 서브스트링 지원
  final Color? titleColor; // ✅ title 색상 커스터마이징

  final bool showAuthorInfo;
  final VoidCallback? onPostTap;
  final Function(String postId)? onPostTapWithId;
  final double bottomSpacing; // ✅ 외부에서 간격을 통제할 수 있도록

  const PostCardSection({
    super.key,
    required this.mode,
    required this.posts,
    this.title,
    this.subtitle,
    this.titleBoldSubstrings,
    this.titleColor,
    this.showAuthorInfo = false,
    this.onPostTap,
    this.onPostTapWithId,
    this.bottomSpacing = HomeSectionSpacing.sectionLarge,
  });

  @override
  State<PostCardSection> createState() => _PostCardSectionState();
}

class _PostCardSectionState extends State<PostCardSection>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController;
  late final ValueNotifier<int> _currentPageNotifier;

  static const int _lockedSlots = 3;
  static const double _unlockedSizeFactor = 0.74;
  static const double _lockedSizeFactor = 0.6;

  double get _sizeFactor =>
      widget.mode == PostCardSectionMode.locked
          ? _lockedSizeFactor
          : _unlockedSizeFactor;

  int get _itemCount =>
      widget.mode == PostCardSectionMode.locked
          ? _lockedSlots
          : widget.posts.length.clamp(0, 5);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _currentPageNotifier = ValueNotifier<int>(0);

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth * _sizeFactor + 6;

    final page = (_scrollController.position.pixels / itemWidth).round().clamp(
      0,
      _itemCount - 1,
    );

    if (_currentPageNotifier.value != page) {
      _currentPageNotifier.value = page;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.posts.isEmpty && widget.mode == PostCardSectionMode.unlocked) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Header(
          title: widget.title,
          subtitle: widget.subtitle,
          titleColor: widget.titleColor,
          titleBoldSubstrings: widget.titleBoldSubstrings,
          count: _itemCount,
          notifier: _currentPageNotifier,
          showIndicator:
              widget.mode == PostCardSectionMode.locked ||
              widget.showAuthorInfo,
        ),
        SizedBox(height: HomeSectionSpacing.sectionSmall),
        _buildList(context),
        SizedBox(height: widget.bottomSpacing),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final height = screenWidth * _sizeFactor * 1.15;

    return SizedBox(
      height: height,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 0), // ✅ 패딩은 각 아이템에서 처리
        itemCount: _itemCount,
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true,
        itemBuilder: (context, index) {
          final isLocked = widget.mode == PostCardSectionMode.locked;
          final isPlaceholder = index >= widget.posts.length;
          final isFirst = index == 0;
          final isLast = index == _itemCount - 1;

          if (isLocked && isPlaceholder) {
            return Container(
              margin: EdgeInsets.only(
                left: isFirst ? 16 : 0,
                right: isLast ? 16 : 6,
              ),
              child: _PlaceholderCard(sizeFactor: _sizeFactor),
            );
          }

          final post = widget.posts[index];
          final postId = post['id']?.toString() ?? index.toString();

          return RepaintBoundary(
            key: ValueKey('post_card_$postId'),
            child: Container(
              margin: EdgeInsets.only(
                left: isFirst ? 16 : 0,
                right: isLast ? 16 : 6,
              ),
              child: _PostCard(
                post: post,
                sizeFactor: _sizeFactor,
                locked: isLocked,
                showAuthorInfo: widget.showAuthorInfo,
                titleBoldSubstrings: widget.titleBoldSubstrings,
                isFirst: isFirst,
                isLast: isLast,
                onTap: () => _onTap(context, index),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onTap(BuildContext context, int index) {
    if (index >= widget.posts.length) return;

    final postId = widget.posts[index]['id']?.toString();
    if (postId == null) return;

    if (widget.onPostTapWithId != null) {
      widget.onPostTapWithId!(postId);
      return;
    }

    try {
      final postData = PostData.fromServerMeta(widget.posts[index]);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostReaderScreen(exported: postData.toExportedData()),
        ),
      );
    } catch (_) {
      widget.onPostTap?.call();
    }
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final double sizeFactor;
  final bool locked;
  final bool showAuthorInfo;
  final List<String>? titleBoldSubstrings; // 🎯 볼드 서브스트링 지원
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const _PostCard({
    required this.post,
    required this.sizeFactor,
    required this.locked,
    required this.showAuthorInfo,
    this.titleBoldSubstrings,
    this.isFirst = false,
    this.isLast = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    final memCacheWidth = (screenWidth *
            sizeFactor *
            dpr *
            (isAndroid ? 1.5 : 2.0))
        .round()
        .clamp(1, isAndroid ? 2048 : 3072);

    final thumbnailUrl = post['thumbnailImageUrl'] as String? ?? '';
    final isVideo = thumbnailUrl.toLowerCase().contains('video');

    // ✅ 첫 번째는 왼쪽만, 마지막은 오른쪽만 라운드 처리
    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(isFirst ? 20 : 0),
      bottomLeft: Radius.circular(isFirst ? 20 : 0),
      topRight: Radius.circular(isLast ? 20 : 0),
      bottomRight: Radius.circular(isLast ? 20 : 0),
    );

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(
          width: screenWidth * sizeFactor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              isVideo
                  ? ThumbnailVideoPlayer(
                    videoUrl: thumbnailUrl,
                    width: screenWidth * sizeFactor,
                    height: screenWidth * sizeFactor * 1.15,
                  )
                  : CachedNetworkImage(
                    imageUrl: thumbnailUrl,
                    cacheKey: thumbnailUrl,
                    cacheManager: ReadImageCacheManager.instance,
                    fit: BoxFit.cover,
                    memCacheWidth: memCacheWidth,
                    fadeInDuration: const Duration(milliseconds: 200),
                    fadeOutDuration: const Duration(milliseconds: 200),
                  ),

              if (locked)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                      ),

                      child: const Center(
                        child: Icon(Icons.check, color: Colors.white, size: 96),
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _PostCardOverlay(
                    post: post,
                    showAuthorInfo: showAuthorInfo,
                    titleBoldSubstrings: titleBoldSubstrings,
                    borderRadius: borderRadius,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostCardOverlay extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool showAuthorInfo;
  final List<String>? titleBoldSubstrings; // 🎯 볼드 서브스트링 지원
  final BorderRadius borderRadius;

  const _PostCardOverlay({
    required this.post,
    required this.showAuthorInfo,
    this.titleBoldSubstrings,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final title = post['title'] as String? ?? '';
    final author = post['author'] as String? ?? '';
    final alias = post['alias'] as String? ?? '';
    final profile = post['authorProfileImageUrl'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: borderRadius.bottomLeft,
          bottomRight: borderRadius.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🎯 buildTitleWithBoldSubstrings 사용하여 통일
          titleBoldSubstrings != null && titleBoldSubstrings!.isNotEmpty
              ? buildTitleWithBoldSubstrings(
                context: context,
                title: title,
                boldSubstrings: titleBoldSubstrings!,
                baseStyle: LocaleTypography.style(
                  context: context,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                boldStyle: LocaleTypography.style(
                  context: context,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              )
              : Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LocaleTypography.style(
                  context: context,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
          if (showAuthorInfo) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                CommonProfileAvatar(
                  imageUrl: profile,
                  username: author,
                  size: 32,
                  borderWidth: 0,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alias.isNotEmpty ? alias : author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LocaleTypography.style(
                      context: context,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Color? titleColor; // ✅ title 색상 커스터마이징
  final List<String>? titleBoldSubstrings; // ✅ 볼드 서브스트링 지원
  final int count;
  final ValueNotifier<int> notifier;
  final bool showIndicator;

  const _Header({
    this.title,
    this.subtitle,
    this.titleColor,
    this.titleBoldSubstrings,
    required this.count,
    required this.notifier,
    this.showIndicator = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    if ((title == null || title!.isEmpty) &&
        (subtitle == null || subtitle!.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          /// LEFT : TITLE / SUBTITLE
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title!.isNotEmpty)
                  titleBoldSubstrings != null && titleBoldSubstrings!.isNotEmpty
                      ? buildTitleWithBoldSubstrings(
                        context: context,
                        title: title!,
                        boldSubstrings: titleBoldSubstrings!,
                        baseStyle: LocaleTypography.style(
                          context: context,
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                          color: titleColor ?? onSurface,
                        ),
                        boldStyle: LocaleTypography.style(
                          context: context,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: titleColor ?? onSurface,
                        ),
                      )
                      : Text(
                        title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LocaleTypography.style(
                          context: context,
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                          color:
                              titleColor ??
                              onSurface, // ✅ titleColor가 있으면 사용, 없으면 기본 색상
                        ),
                      ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  SizedBox(height: HomeSectionSpacing.sectionTiny + 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LocaleTypography.style(
                      context: context,
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),

          /// RIGHT : PAGE INDICATOR
          if (showIndicator && count > 1) ...[
            const SizedBox(width: 12),
            ValueListenableBuilder<int>(
              valueListenable: notifier,
              builder: (context, currentPage, _) {
                final visibleCount = count.clamp(0, 5);

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(visibleCount, (index) {
                    return Container(
                      width: 10,
                      height: 10,
                      margin: EdgeInsets.only(
                        right: index == visibleCount - 1 ? 0 : 4,
                      ),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            currentPage == index
                                ? onSurface
                                : onSurface.withOpacity(0.3),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  final double sizeFactor;

  const _PlaceholderCard({required this.sizeFactor});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder:
                (context, animation, secondaryAnimation) =>
                    const PostModeSelectionScreen(),
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: screenWidth * sizeFactor,
          height: screenWidth * sizeFactor * 1.15,
          color:
              isDark ? AppColors.darkBackground : AppColors.lightSurfaceVariant,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                size: 48,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//곰신 요청 수락 UI 섹션 (CTA 스타일)
class GirlfriendRequestAcceptSection extends StatelessWidget {
  final GirlfriendRequest girlfriendRequest;
  final double height;

  const GirlfriendRequestAcceptSection({
    super.key,
    required this.girlfriendRequest,
    this.height = 420,
  });

  /// 배경 이미지 정보 가져오기
  _BackgroundImageInfo? _getBackgroundImageInfo(BuildContext context) {
    // 1. 곰신 사용자의 프로필 이미지
    final profileImageUrl = girlfriendRequest.requester.profileImageUrl;
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      return _BackgroundImageInfo(url: profileImageUrl, isProfileImage: true);
    }

    // 2. 곰신 사용자의 첫 번째 포스트 이미지 (향후 구현 가능)
    // TODO: 곰신 사용자의 포스트 이미지 가져오기

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final backgroundImageInfo = _getBackgroundImageInfo(context);

    return GestureDetector(
      onTap: () async {
        // ✅ 곰신 요청 수락 API 호출
        final userProvider = context.read<UserProvider>();
        try {
          await userProvider.acceptGirlfriendRequest(
            girlfriendRequest.requestId,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('곰신 요청이 수락되었습니다'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          debugPrint('[GirlfriendRequestAcceptSection] 곰신 요청 수락 실패: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('곰신 요청 수락 실패: ${e.toString()}'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      },
      child: FillSection(
        backgroundImageInfo: backgroundImageInfo,
        fallbackColor: primaryColor,
        height: height,
        content: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '곰신과 함께 할까요?',
                style: LocaleTypography.style(
                  context: context,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '곰신 수락하기!',
                    style: LocaleTypography.style(
                      context: context,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, color: Colors.white, size: 32),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ✅ placeholder CTA 섹션 (connectedMilitaryUser가 null일 때)
class PlaceholderGirlfriendWriteCTASection extends StatelessWidget {
  final MilitaryInfo? militaryInfo;

  const PlaceholderGirlfriendWriteCTASection({super.key, this.militaryInfo});

  /// D+ 날짜 계산
  int _calculateDaysSinceEnlistment() {
    if (militaryInfo == null) return 0;

    DateTime? baseDate;
    if (militaryInfo!.status == MilitaryStatus.beforeEnlistment) {
      // 입대 전: 예정 입대일 기준으로 음수 계산 (선택적)
      baseDate = militaryInfo!.plannedEnlistmentDate;
    } else {
      // 입대 후: 입대일 기준
      baseDate = militaryInfo!.enlistmentDate;
    }

    if (baseDate == null) return 0;

    final now = DateTime.now();
    final difference = now.difference(baseDate);
    return difference.inDays;
  }

  /// 일수를 주차로 환산 (7일 = 1주차)
  int _calculateWeeksSinceEnlistment() {
    final days = _calculateDaysSinceEnlistment();
    if (days <= 0) return 0;
    // 7일 단위로 주차 계산 (1일 이상이면 최소 1주차)
    return ((days - 1) ~/ 7) + 1;
  }

  @override
  Widget build(BuildContext context) {
    final weeksSinceEnlistment = _calculateWeeksSinceEnlistment();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      borderRadius: BorderRadius.circular(20),
      color: isDark ? AppColors.darkBackground : AppColors.lightSurfaceVariant,
      child: InkWell(
        onTap: () {
          // ✅ letter 모드로 이동 (수신인 선택 화면)
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const LetterRecipientSelectionScreen(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 작은 회색 텍스트
                Text(
                  weeksSinceEnlistment > 0
                      ? '곰신커플이 된지 ${weeksSinceEnlistment}주차'
                      : '곰신커플이 된지 -주차',
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                // 큰 굵은 텍스트 + 화살표
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        '군화에게 포스팅하기',
                        style: LocaleTypography.style(
                          context: context,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ 곰신과 연결된 경우: "D+X 내 짝궁과 한마디" CTA 섹션 (일반 카드 스타일)
class GirlfriendWriteCTASection extends StatelessWidget {
  final User girlfriendUser;
  final MilitaryInfo? militaryInfo;

  const GirlfriendWriteCTASection({
    super.key,
    required this.girlfriendUser,
    required this.militaryInfo,
  });

  /// D+ 날짜 계산
  int _calculateDaysSinceEnlistment() {
    if (militaryInfo == null) return 0;

    DateTime? baseDate;
    if (militaryInfo!.status == MilitaryStatus.beforeEnlistment) {
      // 입대 전: 예정 입대일 기준으로 음수 계산 (선택적)
      baseDate = militaryInfo!.plannedEnlistmentDate;
    } else {
      // 입대 후: 입대일 기준
      baseDate = militaryInfo!.enlistmentDate;
    }

    if (baseDate == null) return 0;

    final now = DateTime.now();
    final difference = now.difference(baseDate);
    return difference.inDays;
  }

  /// 일수를 주차로 환산 (7일 = 1주차)
  int _calculateWeeksSinceEnlistment() {
    final days = _calculateDaysSinceEnlistment();
    if (days <= 0) return 0;
    // 7일 단위로 주차 계산 (1일 이상이면 최소 1주차)
    return ((days - 1) ~/ 7) + 1;
  }

  @override
  Widget build(BuildContext context) {
    final weeksSinceEnlistment = _calculateWeeksSinceEnlistment();
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ 현재 사용자 타입 확인
    final userProvider = context.watch<UserProvider>();
    final currentUser = userProvider.currentUser;
    final isGirlfriend =
        currentUser?.militaryInfo?.userType == UserType.girlfriend;

    // ✅ 사용자 타입에 따라 텍스트 결정
    final postingText = isGirlfriend ? '군화에게 포스팅하기' : '곰신에게 포스팅하기';

    return Material(
      borderRadius: BorderRadius.circular(20),
      color: isDark ? AppColors.darkBackground : AppColors.lightSurfaceVariant,
      child: InkWell(
        onTap: () {
          // ✅ support 모드(letter)로 바로 이동 - 자동으로 남친 선택
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => LetterRecipientSelectionScreen(
                    initialRecipientUsername:
                        girlfriendUser.username, // 자동으로 남친 선택
                  ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 작은 회색 텍스트
                Text(
                  '곰신커플이 된지 ${weeksSinceEnlistment}주차',
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                // 큰 굵은 텍스트 + 화살표
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        postingText,
                        style: LocaleTypography.style(
                          context: context,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 배경 이미지 정보
class _BackgroundImageInfo {
  final String url;
  final bool isProfileImage;

  _BackgroundImageInfo({required this.url, required this.isProfileImage});
}

/// ✅ 공통 FillSection 위젯 (재사용 가능)
class FillSection extends StatelessWidget {
  final _BackgroundImageInfo? backgroundImageInfo;
  final Widget content; // 콘텐츠 위젯
  final Color? fallbackColor; // 폴백 색상 (이미지 로드 실패 시)
  final double height;
  final double blurSigma;
  final double profileScale;

  const FillSection({
    super.key,
    this.backgroundImageInfo,
    required this.content,
    this.fallbackColor,
    this.height = 350,
    this.blurSigma = 3,
    this.profileScale = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final decodeWidthPx = (screenWidth * dpr * 2).round().clamp(1, 3072);
    final primaryColor = fallbackColor ?? Theme.of(context).colorScheme.primary;

    return Container(
      margin: EdgeInsets.zero, // ✅ FillSection끼리 붙었을 때는 상위에서 간격 조정
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 배경 이미지 (없으면 그라데이션 폴백)
          if (backgroundImageInfo == null)
            _buildGradientFallback(primaryColor)
          else
            // ✅ 프로필 이미지인 경우 확대해서 원형이 사각형처럼 보이게
            backgroundImageInfo!.isProfileImage
                ? ClipRect(
                  child: Transform.scale(
                    scale: profileScale,
                    child: Center(
                      child: CachedNetworkImage(
                        imageUrl: backgroundImageInfo!.url,
                        cacheKey: backgroundImageInfo!.url,
                        cacheManager: ReadImageCacheManager.instance,
                        fit: BoxFit.cover,
                        memCacheWidth: decodeWidthPx,
                        fadeInDuration: const Duration(milliseconds: 200),
                        fadeOutDuration: const Duration(milliseconds: 200),
                        placeholder:
                            (_, __) =>
                                ShimmerBox(width: screenWidth, height: height),
                        errorWidget:
                            (_, __, ___) =>
                                _buildGradientFallback(primaryColor),
                      ),
                    ),
                  ),
                )
                : CachedNetworkImage(
                  imageUrl: backgroundImageInfo!.url,
                  cacheKey: backgroundImageInfo!.url,
                  cacheManager: ReadImageCacheManager.instance,
                  fit: BoxFit.cover,
                  memCacheWidth: decodeWidthPx,
                  fadeInDuration: const Duration(milliseconds: 200),
                  fadeOutDuration: const Duration(milliseconds: 200),
                  placeholder:
                      (_, __) => ShimmerBox(width: screenWidth, height: height),
                  errorWidget:
                      (_, __, ___) => _buildGradientFallback(primaryColor),
                ),

          // ✅ 블러 효과
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: Container(color: Colors.transparent),
            ),
          ),

          // 그라데이션 오버레이
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
              ),
            ),
          ),

          // 콘텐츠
          content,
        ],
      ),
    );
  }

  /// 그라데이션 폴백 (이미지 로드 실패 시)
  Widget _buildGradientFallback(Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor.withOpacity(0.15),
            primaryColor.withOpacity(0.05),
          ],
        ),
      ),
    );
  }
}

/// ✅ 입대 예정자 전용: "입대 전에 꼭 답해보세요" CTA 섹션
/// PostFillSection 기반으로 배경 이미지 지원
class PreEnlistmentCTASection extends StatelessWidget {
  const PreEnlistmentCTASection({super.key});

  /// 배경 이미지 정보 (URL + 타입)
  _BackgroundImageInfo? _getBackgroundImageInfo(BuildContext context) {
    // 1. 프로필 사진 확인
    final userProvider = context.read<UserProvider>();
    final profileImageUrl = userProvider.currentUser?.profileImageUrl;
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      debugPrint('[PreEnlistmentCTA] 배경 이미지: 프로필 사진 사용');
      return _BackgroundImageInfo(url: profileImageUrl, isProfileImage: true);
    }

    // 2. 첫 번째 포스트 이미지 확인
    final friendProvider = context.read<FriendProvider>();
    final friendPosts = friendProvider.friendPosts;
    if (friendPosts.isNotEmpty) {
      final firstPost = friendPosts.first;
      final thumbnailUrl = firstPost['thumbnailImageUrl'] as String?;
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        debugPrint('[PreEnlistmentCTA] 배경 이미지: 첫 번째 포스트 사용');
        return _BackgroundImageInfo(url: thumbnailUrl, isProfileImage: false);
      }
    }

    // 3. 배경 이미지 없음
    debugPrint('[PreEnlistmentCTA] 배경 이미지: 없음 (배너 모드)');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final backgroundImageInfo = _getBackgroundImageInfo(context);

    // ✅ 배경 이미지가 있으면 FillSection 사용, 없으면 낮은 배너
    if (backgroundImageInfo != null) {
      return GestureDetector(
        onTap: () {
          // ✅ promise 모드로 바로 이동
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => const PostwriteScreen(
                    isEditingMode: false,
                    mode: PostWriteMode.promise,
                  ),
            ),
          );
        },
        child: FillSection(
          backgroundImageInfo: backgroundImageInfo,
          fallbackColor: primaryColor,
          height: 420,
          content: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ✅ 상단: 자물쇠 아이콘 + "입대 전에 꼭 답해보세요!"
                Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '입대 전에 꼭 답해보세요!',
                      style: LocaleTypography.style(
                        context: context,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),

                // ✅ 하단: 제목 + 화살표
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '입대 전에 꼭 답해보세요',
                            style: LocaleTypography.style(
                              context: context,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '입대 전에 꼭 답해보세요',
                            style: LocaleTypography.style(
                              context: context,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 오른쪽: 큰 화살표 (프로필 이미지일 때만 애니메이션)
                    if (backgroundImageInfo.isProfileImage)
                      _AnimatedArrowIndicator()
                    else
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 32,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        margin: EdgeInsets.zero, // ✅ FillSection끼리 붙었을 때는 상위에서 간격 조정
        child: _buildBannerStyle(
          context: context,
          primaryColor: primaryColor,
          onSurface: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
  }
}

/// 배너 스타일 (배경 이미지 없음)
Widget _buildBannerStyle({
  required BuildContext context,
  required Color primaryColor,
  required Color onSurface,
}) {
  bool isDark = Theme.of(context).brightness == Brightness.dark;

  return Material(
    borderRadius: BorderRadius.circular(20),
    color: isDark ? AppColors.darkBackground : AppColors.lightSurfaceVariant,
    child: InkWell(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => PreEnlistmentGoalsScreen()));
      },
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: double.infinity,
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 작은 회색 텍스트
              Text(
                '입대 전에 꼭 답해보세요',
                style: LocaleTypography.style(
                  context: context,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 4),
              // 큰 굵은 텍스트 + 화살표
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      '입대 전에 꼭 답해보세요',
                      style: LocaleTypography.style(
                        context: context,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 16,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 화살표 애니메이션 인디케이터 (오른쪽 화살표만 흔들림)
class _AnimatedArrowIndicator extends StatefulWidget {
  final double size;
  final Color color;

  const _AnimatedArrowIndicator({this.size = 32, this.color = Colors.white});

  @override
  State<_AnimatedArrowIndicator> createState() =>
      _AnimatedArrowIndicatorState();
}

class _AnimatedArrowIndicatorState extends State<_AnimatedArrowIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _animation = Tween<double>(
      begin: -1.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        // ✅ Transform으로 화살표를 좌우로 조금씩 흔들림
        final offsetX = _animation.value * 8.0; // 최대 8px 이동

        return Transform.translate(
          offset: Offset(offsetX, 0),
          child: Icon(
            Icons.arrow_forward_ios,
            color: widget.color,
            size: widget.size,
          ),
        );
      },
    );
  }
}

/// ✅ 오프라인 상태 배너 (그리드 밑에 표시)
Widget _buildOfflineBanner(BuildContext context) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  final l10n = AppLocalizations.of(context);
  return Container(
    margin: const EdgeInsets.only(
      bottom: HomeSectionSpacing.sectionLarge,
      left: 20,
      right: 20,
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            l10n.t('offline_status'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: onSurface,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.t('check_network_connection'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Icon(
            Icons.keyboard_arrow_down,
            color: onSurface.withOpacity(0.4),
            size: 28,
          ),
        ],
      ),
    ),
  );
}

/// ✅ 입대전 홈: "사회에서 추억 남기기" CTA 버튼
class SocialMemoryWriteButton extends StatelessWidget {
  const SocialMemoryWriteButton({super.key});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      borderRadius: BorderRadius.circular(20),
      color: isDark ? AppColors.darkBackground : AppColors.lightSurfaceVariant,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => const PostwriteScreen(
                    isEditingMode: false,
                    mode: PostWriteMode.leaveOrPreEnlistment,
                    emptyStateMessage: '사회에서 추억 남기기',
                    disableAutoFocus: true,
                  ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 작은 회색 텍스트
                Text(
                  '사회에서의 추억',
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                // 큰 굵은 텍스트 + 화살표
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        '사회에서 추억 남기기',
                        style: LocaleTypography.style(
                          context: context,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ThisWeekWriteButton extends StatelessWidget {
  const ThisWeekWriteButton({super.key});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      borderRadius: BorderRadius.circular(20),
      color: isDark ? AppColors.darkBackground : AppColors.lightSurfaceVariant,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PostModeSelectionScreen()),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 작은 회색 텍스트
                Text(
                  '꾸준히 쌓이고 있어요',
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                // 큰 굵은 텍스트 + 화살표
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        '이번 주 기록하기',
                        style: LocaleTypography.style(
                          context: context,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ 입대 후: 받은 Support 글 섹션
class SupportPostsSection extends StatelessWidget {
  final double bottomSpacing;

  const SupportPostsSection({super.key, this.bottomSpacing = 0});

  @override
  Widget build(BuildContext context) {
    return Consumer<LetterProvider>(
      builder: (context, letterProvider, _) {
        // 로딩 중이거나 에러가 있으면 빈 상태
        if (letterProvider.isLoading && letterProvider.recentLetters.isEmpty) {
          return const SizedBox.shrink(); // 로딩 중에는 표시하지 않음
        }

        // 편지가 없으면 빈 상태
        if (letterProvider.recentLetters.isEmpty) {
          return const SizedBox.shrink();
        }

        // 편지 데이터를 PostFillSection 형식으로 변환
        final posts =
            letterProvider.recentLetters.map((letter) {
              // 서버 응답 형식에 맞게 필드 매핑
              return {
                'id': letter['id']?.toString() ?? '',
                'thumbnailImageUrl': letter['thumbnailImageUrl']?.toString(),
                'title': letter['title']?.toString() ?? '',
                'subtitle': letter['subtitle']?.toString() ?? '',
                'author': letter['author']?.toString() ?? '',
                'authorProfileImageUrl':
                    letter['authorProfileImageUrl']?.toString(),
                'createdAt': letter['createdAt']?.toString(),
              };
            }).toList();

        return PostFillSection(posts: posts, bottomSpacing: bottomSpacing);
      },
    );
  }
}

/// ✅ 입대 후: 진급 리포트 보기 CTA (임시 하드코딩)
class PromotionReportCTASection extends StatelessWidget {
  final double bottomSpacing;

  const PromotionReportCTASection({super.key, this.bottomSpacing = 0});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    // ✅ 임시 하드코딩 이미지
    final mockImageUrl =
        'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800';

    return GestureDetector(
      onTap: () {
        // TODO: 진급 리포트 화면으로 이동
        debugPrint('[PromotionReportCTA] 진급 리포트 보기');
      },
      child: Column(
        children: [
          FillSection(
            backgroundImageInfo: _BackgroundImageInfo(
              url: mockImageUrl,
              isProfileImage: false,
            ),
            fallbackColor: primaryColor,

            content: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '이병이 되었어요',
                    style: LocaleTypography.style(
                      context: context,
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '진급 리포트 보기',
                              style: LocaleTypography.style(
                                context: context,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      _AnimatedArrowIndicator(color: Colors.white, size: 24),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (bottomSpacing > 0) SizedBox(height: bottomSpacing),
        ],
      ),
    );
  }
}
