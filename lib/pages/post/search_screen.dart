import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';
import '../components/custom_bottom_navigation_bar.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// ===== 데이터 모델 =====
class AccountItem {
  final String nickname;
  final String userId;
  final int neighbors;

  const AccountItem({
    required this.nickname,
    required this.userId,
    required this.neighbors,
  });
}

class PostItemData {
  final String title;
  final String author;
  final String preview;
  final String imageUrl;
  final int likes;

  const PostItemData({
    required this.title,
    required this.author,
    required this.preview,
    required this.imageUrl,
    required this.likes,
  });
}

/// ===== 메인 화면 =====
class _SearchScreenState extends State<SearchScreen> {
  // 네비/정렬
  int _bottomIndex = 1;
  String _accountSort = '계정 이름';
  String _postSort = '인기순';

  // 선택 표시
  int? _selectedAccountIndex;
  int? _selectedPostIndex;

  // 검색 상태
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  Timer? _debounce;

  // 더미 데이터
  late final List<AccountItem> _allAccounts = [
    const AccountItem(nickname: '여행러 민준', userId: '@travel_mj', neighbors: 40),
    const AccountItem(
      nickname: '사진찍는 수진',
      userId: '@photo_sujin',
      neighbors: 32,
    ),
    const AccountItem(
      nickname: '코딩하는도치',
      userId: '@coder_dochi',
      neighbors: 27,
    ),
    const AccountItem(
      nickname: '제주살이 현우',
      userId: '@jeju_hyunwoo',
      neighbors: 21,
    ),
    const AccountItem(nickname: '푸른하늘', userId: '@blue_sky', neighbors: 45),
    const AccountItem(nickname: '밤양갱', userId: '@bamyanggeng', neighbors: 29),
    const AccountItem(nickname: '고양이집사', userId: '@catlover', neighbors: 33),
    const AccountItem(
      nickname: '강아지훈련사',
      userId: '@dog_trainer',
      neighbors: 39,
    ),
    const AccountItem(nickname: '수취영', userId: '@suchiyoung', neighbors: 28),
    const AccountItem(nickname: '영화광 민지', userId: '@cine_minji', neighbors: 34),
    const AccountItem(nickname: '러닝하는 준호', userId: '@runner_jh', neighbors: 18),
    const AccountItem(
      nickname: '책읽는 보라',
      userId: '@reader_bora',
      neighbors: 24,
    ),
    const AccountItem(nickname: '디자인 우주', userId: '@ux_woozoo', neighbors: 36),
    const AccountItem(nickname: '푸드파이터', userId: '@foodie', neighbors: 31),
    const AccountItem(nickname: '사진러버', userId: '@photo_love', neighbors: 26),
    const AccountItem(nickname: '여행기록가', userId: '@travel_log', neighbors: 41),
    const AccountItem(nickname: '음악하는나무', userId: '@music_tree', neighbors: 22),
    const AccountItem(
      nickname: '도피 doppy',
      userId: '@doppy_official',
      neighbors: 99,
    ),
    const AccountItem(nickname: '일기장', userId: '@diary', neighbors: 15),
    const AccountItem(nickname: '서핑하는 유나', userId: '@surf_yuna', neighbors: 25),
    for (int i = 1; i <= 10; i++)
      AccountItem(
        nickname: '이웃 $i',
        userId: '@user$i',
        neighbors: 20 + (i % 10),
      ),
  ];

  late final List<PostItemData> _allPosts = [
    const PostItemData(
      title: '도피(doppy)로 기록하는 나의 일상',
      author: '푸른하늘',
      preview: '고정된 템플릿 없이 자유롭게 기록한 한 주의 일기.',
      imageUrl: 'https://picsum.photos/144/108?random=1',
      likes: 120,
    ),
    const PostItemData(
      title: '여행 준비 체크리스트 30가지',
      author: '여행러 민준',
      preview: '항공권, 숙소, eSIM, 환전, 보험까지 한 번에.',
      imageUrl: 'https://picsum.photos/144/108?random=2',
      likes: 320,
    ),
    const PostItemData(
      title: '사진 구도 10분 핵심',
      author: '사진찍는 수진',
      preview: '삼분할, 리드라인, 대칭. 초보도 바로 적용 가능.',
      imageUrl: 'https://picsum.photos/144/108?random=3',
      likes: 270,
    ),
    const PostItemData(
      title: 'Flutter로 감정 기록 앱 만들기',
      author: '코딩하는도치',
      preview: '탭, 달력 UI, 로컬 이미지 관리 팁 정리.',
      imageUrl: 'https://picsum.photos/144/108?random=4',
      likes: 410,
    ),
    const PostItemData(
      title: '제주살이 한 달 후기',
      author: '제주살이 현우',
      preview: '장단점, 예상비용, 지역별 추천.',
      imageUrl: 'https://picsum.photos/144/108?random=5',
      likes: 190,
    ),
    const PostItemData(
      title: '강아지 분리불안 훈련 루틴',
      author: '강아지훈련사',
      preview: '짧은 외출부터 점진적 거리두기, 보상 타이밍.',
      imageUrl: 'https://picsum.photos/144/108?random=6',
      likes: 450,
    ),
    const PostItemData(
      title: '최애 고양이 사료 비교',
      author: '고양이집사',
      preview: '원료, 기호성, 알레르기 유발성분 체크.',
      imageUrl: 'https://picsum.photos/144/108?random=7',
      likes: 210,
    ),
    const PostItemData(
      title: '도피(doppy) 시작 가이드',
      author: '도피 doppy',
      preview: '하고 싶은 말을, 하고 싶은 방식으로.',
      imageUrl: 'https://picsum.photos/144/108?random=8',
      likes: 999,
    ),
    for (int i = 1; i <= 8; i++)
      PostItemData(
        title: '테스트 포스트 $i',
        author: '이웃 $i',
        preview: '샘플 프리뷰 텍스트 $i 입니다.',
        imageUrl: 'https://picsum.photos/144/108?random=${15 + i}',
        likes: 50 + i * 7,
      ),
  ];

  // 표시 목록(검색/정렬 반영본)
  late List<AccountItem> _accounts = [];
  late List<PostItemData> _posts = [];

  @override
  void initState() {
    super.initState();
    _applySortAndReset();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ===== 검색/정렬 =====
  void _onSearchChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _performSearch();
    });
  }

  void _onSearchSubmitted(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    _performSearch();
  }

  void _performSearch() {
    final q = _query.trim();
    debugPrint('검색 실행: "$q"');

    if (q.isEmpty) {
      _applySortAndReset();
      debugPrint(
        '검색어 없음 → 전체 목록 표시 (accounts=${_accounts.length}, posts=${_posts.length})',
      );
      return;
    }

    final lower = q.toLowerCase();
    List<AccountItem> acc =
        _allAccounts
            .where(
              (a) =>
                  a.nickname.toLowerCase().contains(lower) ||
                  a.userId.toLowerCase().contains(lower),
            )
            .toList();
    List<PostItemData> pst =
        _allPosts
            .where(
              (p) =>
                  p.title.toLowerCase().contains(lower) ||
                  p.author.toLowerCase().contains(lower),
            )
            .toList();

    acc = _sortAccounts(acc);
    pst = _sortPosts(pst);

    setState(() {
      _accounts = acc;
      _posts = pst;
      _selectedAccountIndex = null;
      _selectedPostIndex = null;
    });

    debugPrint('검색 결과: accounts=${acc.length}, posts=${pst.length}');
  }

  void _applySortAndReset() {
    setState(() {
      _accounts = _sortAccounts(List.of(_allAccounts));
      _posts = _sortPosts(List.of(_allPosts));
      _selectedAccountIndex = null;
      _selectedPostIndex = null;
    });
  }

  List<AccountItem> _sortAccounts(List<AccountItem> list) {
    if (_accountSort == '계정 이름') {
      list.sort((a, b) => a.nickname.compareTo(b.nickname));
    }
    return list;
  }

  List<PostItemData> _sortPosts(List<PostItemData> list) {
    if (_postSort == '인기순') {
      list.sort((b, a) => a.likes.compareTo(b.likes)); // desc
    }
    return list;
  }

  void _clearSearch() {
    debugPrint('검색어 초기화');
    _searchController.clear();
    setState(() => _query = '');
    _performSearch();
  }

  // ===== 선택/알림 =====
  void _onTapAccount(int index, AccountItem item) {
    setState(() => _selectedAccountIndex = index);
    final msg = '계정 선택: ${item.nickname} (${item.userId})';
    debugPrint(msg);
    _showSnack(msg);
  }

  void _onTapPost(int index, PostItemData item) {
    setState(() => _selectedPostIndex = index);
    final msg = '게시글 선택: "${item.title}" - ${item.author} (♥${item.likes})';
    debugPrint(msg);
    _showSnack(msg);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                controller: _searchController,
                query: _query,
                onChanged: _onSearchChanged,
                onSubmitted: _onSearchSubmitted,
                onClear: _clearSearch,
              ),
              const _SearchTabBar(),
              Expanded(
                child: TabBarView(
                  children: [
                    _AccountsTab(
                      accounts: _accounts,
                      accountSort: _accountSort,
                      onChangeSort: (v) {
                        setState(() => _accountSort = v);
                        _applySortAndReset();
                        _performSearch();
                        debugPrint('계정 정렬 변경: $_accountSort');
                      },
                      selectedIndex: _selectedAccountIndex,
                      onTapItem: _onTapAccount,
                    ),
                    _PostsTab(
                      posts: _posts,
                      postSort: _postSort,
                      onChangeSort: (v) {
                        setState(() => _postSort = v);
                        _applySortAndReset();
                        _performSearch();
                        debugPrint('게시글 정렬 변경: $_postSort');
                      },
                      selectedIndex: _selectedPostIndex,
                      onTapItem: _onTapPost,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: CustomBottomNavigationBar(
          currentIndex: _bottomIndex,
          onTap: (i) {
            setState(() => _bottomIndex = i);
            debugPrint('BottomNav 탭 변경: index=$i');
          },
        ),
      ),
    );
  }
}

/// ===== 상단 바(로고+검색창) =====
class _TopBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _TopBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Image.asset('assets/images/doppy_logo.png', width: 32, height: 32),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                style: AppTextStyles.bodyLarge.copyWith(color: Colors.black),
                decoration: InputDecoration(
                  hintText: '검색',
                  hintStyle: AppTextStyles.withWeight(
                    AppTextStyles.bodyLarge,
                    FontWeight.w500,
                  ).copyWith(color: const Color(0xFF989898)),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 22,
                    color: Color(0xFF989898),
                  ),
                  suffixIcon:
                      query.isNotEmpty
                          ? IconButton(
                            tooltip: '지우기',
                            onPressed: onClear,
                            icon: const Icon(
                              Icons.clear,
                              color: Color(0xFF989898),
                            ),
                          )
                          : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: Color(0xFF989898), width: 1),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: Colors.black, width: 1.5),
                  ),
                ),
                onChanged: onChanged,
                onSubmitted: onSubmitted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===== 탭바 =====
class _SearchTabBar extends StatelessWidget {
  const _SearchTabBar();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Material(
      color: Colors.transparent, // 배경 투명 (문제 없음)
      child: SizedBox(
        height: 46,
        child: TabBar(
          dividerColor: Colors.transparent, // 기본 하단선 제거
          // 텍스트 스타일 (피그마와 동일 계열)
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black,
          labelStyle: AppTextStyles.withWeight(
            AppTextStyles.headlineMedium,
            FontWeight.w600,
          ),
          unselectedLabelStyle: AppTextStyles.withWeight(
            AppTextStyles.headlineMedium,
            FontWeight.w600,
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 32),
          // 🔹 활성 탭 중앙 기준, 스크린 폭의 37.5% 길이로 고정
          indicator: FixedUnderlineTabIndicator(
            color: Colors.black,
            thickness: 2.0,
            bottomInset: 0.0,
            screenWidth: w,
            fraction: 0.375,
          ),
          tabs: const [Tab(text: '계정'), Tab(text: '게시글')],
        ),
      ),
    );
  }
}

/// ===== 계정 탭 =====
class _AccountsTab extends StatelessWidget {
  final List<AccountItem> accounts;
  final String accountSort;
  final ValueChanged<String> onChangeSort;
  final int? selectedIndex;
  final void Function(int index, AccountItem item) onTapItem;

  const _AccountsTab({
    required this.accounts,
    required this.accountSort,
    required this.onChangeSort,
    required this.selectedIndex,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 정렬 + 결과 수
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DropdownButton<String>(
                value: accountSort,
                items:
                    const ['계정 이름']
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v,
                              style: AppTextStyles.withWeight(
                                AppTextStyles.bodyLarge,
                                FontWeight.w600,
                              ).copyWith(color: Colors.black),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) onChangeSort(v);
                },
                underline: const SizedBox.shrink(),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.black,
                ),
              ),
              Text(
                '결과 ${accounts.length}건',
                style: AppTextStyles.withWeight(
                  AppTextStyles.bodySmall,
                  FontWeight.w500,
                ).copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
        // 리스트
        Expanded(
          child:
              accounts.isEmpty
                  ? const _EmptyResult(message: '계정 결과가 없습니다.')
                  : ListView.builder(
                    itemCount: accounts.length,
                    itemBuilder: (context, index) {
                      final item = accounts[index];
                      return _AccountListItem(
                        index: index,
                        nickname: item.nickname,
                        userId: item.userId,
                        neighborCount: '이웃 ${item.neighbors}명',
                        selected: selectedIndex == index,
                        onTap: () => onTapItem(index, item),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

/// ===== 게시글 탭 =====
class _PostsTab extends StatelessWidget {
  final List<PostItemData> posts;
  final String postSort;
  final ValueChanged<String> onChangeSort;
  final int? selectedIndex;
  final void Function(int index, PostItemData item) onTapItem;

  const _PostsTab({
    required this.posts,
    required this.postSort,
    required this.onChangeSort,
    required this.selectedIndex,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 정렬 + 결과 수
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DropdownButton<String>(
                value: postSort,
                items:
                    const ['인기순']
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v,
                              style: AppTextStyles.withWeight(
                                AppTextStyles.bodyLarge,
                                FontWeight.w600,
                              ).copyWith(color: Colors.black),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) onChangeSort(v);
                },
                underline: const SizedBox.shrink(),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.black,
                ),
              ),
              Text(
                '결과 ${posts.length}건',
                style: AppTextStyles.withWeight(
                  AppTextStyles.bodySmall,
                  FontWeight.w500,
                ).copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
        // 리스트
        Expanded(
          child:
              posts.isEmpty
                  ? const _EmptyResult(message: '게시글 결과가 없습니다.')
                  : ListView.builder(
                    itemCount: posts.length,
                    itemBuilder: (context, index) {
                      final item = posts[index];
                      return _PostListItem(
                        index: index,
                        title: item.title,
                        author: item.author,
                        preview: item.preview,
                        imageUrl: item.imageUrl,
                        likes: item.likes,
                        selected: selectedIndex == index,
                        onTap: () => onTapItem(index, item),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

/// ===== 공통: 결과 없음 =====
class _EmptyResult extends StatelessWidget {
  final String message;
  const _EmptyResult({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: AppTextStyles.withWeight(
          AppTextStyles.bodyMedium,
          FontWeight.w500,
        ).copyWith(color: Colors.black54),
      ),
    );
  }
}

/// ===== 컴포넌트: 계정 아이템 =====
class _AccountListItem extends StatelessWidget {
  final int index;
  final String nickname;
  final String userId;
  final String neighborCount;
  final bool selected;
  final VoidCallback onTap;

  const _AccountListItem({
    required this.index,
    required this.nickname,
    required this.userId,
    required this.neighborCount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.black.withOpacity(0.06) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Image.asset(
                    'assets/images/profile_icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            flex: 0,
                            child: Text(
                              nickname,
                              style: AppTextStyles.withWeight(
                                AppTextStyles.withSize(
                                  AppTextStyles.bodyMedium,
                                  15,
                                ),
                                FontWeight.w600,
                              ).copyWith(color: Colors.black),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              userId,
                              style: AppTextStyles.withWeight(
                                AppTextStyles.withSize(
                                  AppTextStyles.bodySmall,
                                  11,
                                ),
                                FontWeight.w600,
                              ).copyWith(color: Colors.black),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        neighborCount,
                        style: AppTextStyles.withSize(
                          AppTextStyles.labelSmall,
                          10,
                        ).copyWith(color: Colors.black54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.more_vert, color: Colors.black),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== 컴포넌트: 게시글 아이템 =====
class _PostListItem extends StatelessWidget {
  final int index;
  final String title;
  final String author;
  final String preview;
  final String imageUrl;
  final int likes;
  final bool selected;
  final VoidCallback onTap;

  const _PostListItem({
    required this.index,
    required this.title,
    required this.author,
    required this.preview,
    required this.imageUrl,
    required this.likes,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.black.withOpacity(0.06) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Container(
                  width: 144,
                  height: 108,
                  decoration: ShapeDecoration(
                    image: DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 20,
                        child: Text(
                          title,
                          style: AppTextStyles.withWeight(
                            AppTextStyles.withSize(AppTextStyles.bodyLarge, 15),
                            FontWeight.w500,
                          ).copyWith(color: Colors.black),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 14,
                        child: Text(
                          '$author · ♥$likes',
                          style: AppTextStyles.withWeight(
                            AppTextStyles.withSize(AppTextStyles.bodySmall, 10),
                            FontWeight.w500,
                          ).copyWith(color: Colors.black54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 32,
                        child: Text(
                          preview,
                          style: AppTextStyles.withWeight(
                            AppTextStyles.withSize(AppTextStyles.bodySmall, 11),
                            FontWeight.w400,
                          ).copyWith(color: Colors.black54),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.check_circle,
                      size: 20,
                      color: Colors.black,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== 커스텀 인디케이터: 화면 너비 37.5% 길이 =====
enum FixedUnderlineAlign { left, center, right }

class FixedUnderlineTabIndicator extends Decoration {
  final Color color;
  final double thickness;
  final double bottomInset;
  final double screenWidth; // 스크린 전체 폭
  final double fraction; // 스크린 폭 대비 비율 (0.375 = 37.5%)

  const FixedUnderlineTabIndicator({
    required this.color,
    required this.screenWidth,
    this.fraction = 0.375,
    this.thickness = 2.0,
    this.bottomInset = 0.0,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _FixedUnderlinePainter(
      color: color,
      thickness: thickness,
      bottomInset: bottomInset,
      indicatorWidth: screenWidth * fraction, // 스크린 기준 길이
    );
  }
}

class _FixedUnderlinePainter extends BoxPainter {
  final Color color;
  final double thickness;
  final double bottomInset;
  final double indicatorWidth;

  _FixedUnderlinePainter({
    required this.color,
    required this.thickness,
    required this.bottomInset,
    required this.indicatorWidth,
  });

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    if (configuration.size == null) return;

    // 현재 "해당 탭"의 영역
    final Rect rect = offset & configuration.size!;
    final double cx = rect.center.dx; // 탭 중앙 x
    final double half = indicatorWidth / 2;

    // 인디케이터 y: 탭 하단에 붙임
    final double y = rect.bottom - bottomInset - thickness / 2;

    // 중앙 정렬: 탭 중앙을 기준으로 좌우로 half
    final double x1 = cx - half;
    final double x2 = cx + half;

    final Paint p =
        Paint()
          ..color = color
          ..strokeWidth = thickness
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.square;

    canvas.drawLine(Offset(x1, y), Offset(x2, y), p);
  }
}
