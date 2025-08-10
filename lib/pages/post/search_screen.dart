import 'dart:async';
import 'package:dio/dio.dart';
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
  final String nickname; // 서버는 username만 주므로 UI 편의를 위해 nickname=userId 변형
  final String userId; // '@username'
  final int neighbors; // 서버 응답엔 없으므로 0으로 채움

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

  // 백엔드 설정
  final String _baseUrl = 'https://example.com'; // TODO: 실제 서버 base URL로 교체
  final FriendSearchApi _friendApi = FriendSearchApi();

  // 네트워크 요청 상태
  bool _accountsLoading = false;
  String? _accountsError;
  CancelToken? _accountsCancelToken;

  // 더미 데이터 (게시글은 로컬 유지)
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
  List<AccountItem> _accounts = [];
  List<PostItemData> _posts = [];

  @override
  void initState() {
    super.initState();
    _applySortAndResetInitial(); // 최초엔 전체 게시글만 채움, 계정은 비워둠
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _accountsCancelToken?.cancel('dispose');
    _searchController.dispose();
    super.dispose();
  }

  // ===== 검색/정렬 =====
  void _onSearchChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _performSearch(); // 디바운스 후 실행
    });
  }

  void _onSearchSubmitted(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    _performSearch(); // 즉시 실행
  }

  Future<void> _performSearch() async {
    final q = _query.trim();
    debugPrint('[Search] performSearch | query="$q"');

    if (q.isEmpty) {
      // 빈 검색어: 계정은 비우고, 게시글은 전체/정렬 반영 상태로
      setState(() {
        _accounts = [];
        _posts = _sortPosts(List.of(_allPosts));
        _selectedAccountIndex = null;
        _selectedPostIndex = null;
      });
      debugPrint(
        '[Search] empty query -> clear accounts, show all posts (${_posts.length})',
      );
      return;
    }

    // 1) 계정: 서버 검색
    await _searchAccountsRemote(q);

    // 2) 게시글: 로컬 필터
    _filterPostsLocal(q);

    // 선택 상태 초기화
    setState(() {
      _selectedAccountIndex = null;
      _selectedPostIndex = null;
    });
  }

  Future<void> _searchAccountsRemote(String q) async {
    // 진행 중 요청이 있으면 취소
    _accountsCancelToken?.cancel('new query: $q');
    _accountsCancelToken = CancelToken();

    final token = await _getAuthToken();

    setState(() {
      _accountsLoading = true;
      _accountsError = null;
    });

    final startedAt = DateTime.now();
    debugPrint(
      '[API] friends/search started | q="$q" | t=${startedAt.toIso8601String()}',
    );

    try {
      final usernames = await _friendApi.searchUsers(
        baseUrl: _baseUrl,
        token: token ?? '',
        query: q,
        cancelToken: _accountsCancelToken,
      );

      // 서버가 반환한 username 배열을 화면용 AccountItem으로 변환
      final items =
          usernames
              .map(
                (u) => AccountItem(
                  nickname: u, // 닉네임은 서버 데이터가 없으므로 일단 username
                  userId: '@$u',
                  neighbors: 0, // 서버 응답에 없으므로 0으로 표시
                ),
              )
              .toList();

      // 정렬 규칙 적용
      final sorted = _sortAccounts(items);

      final endedAt = DateTime.now();
      debugPrint(
        '[API] friends/search success | count=${sorted.length} | elapsed=${endedAt.difference(startedAt).inMilliseconds}ms',
      );

      setState(() {
        _accountsLoading = false;
        _accounts = sorted;
      });
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        debugPrint('[API] friends/search canceled: ${e.message}');
        return;
      }
      // 자세한 에러 로깅
      debugPrint(
        '[API][ERROR] friends/search failed | type=${e.type} | status=${e.response?.statusCode}',
      );
      debugPrint('[API][ERROR] message=${e.message}');
      debugPrint('[API][ERROR] data=${e.response?.data}');

      setState(() {
        _accountsLoading = false;
        _accountsError = '계정 검색 실패 (${e.response?.statusCode ?? e.type})';
        _accounts = []; // 실패 시 빈 리스트
      });
      _showSnack(_accountsError!);
    } catch (e) {
      debugPrint('[API][ERROR] friends/search unknown error: $e');
      setState(() {
        _accountsLoading = false;
        _accountsError = '계정 검색 중 알 수 없는 오류';
        _accounts = [];
      });
      _showSnack(_accountsError!);
    }
  }

  void _filterPostsLocal(String q) {
    final lower = q.toLowerCase();
    List<PostItemData> pst =
        _allPosts
            .where(
              (p) =>
                  p.title.toLowerCase().contains(lower) ||
                  p.author.toLowerCase().contains(lower),
            )
            .toList();
    pst = _sortPosts(pst);
    setState(() {
      _posts = pst;
    });
    debugPrint('[Search] posts local filtered | count=${pst.length}');
  }

  void _applySortAndResetInitial() {
    setState(() {
      _accounts = []; // 최초엔 서버 검색 전이므로 비움
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

  Future<String?> _getAuthToken() async {
    // TODO: 실제 토큰 획득 로직으로 교체 (예: secure storage, provider, dio interceptor 등)
    // 예시: return await SecureStorage.read('accessToken');
    debugPrint('[Auth] getAuthToken called');
    return 'YOUR_ACCESS_TOKEN'; // 임시
  }

  void _clearSearch() {
    debugPrint('[Search] clear query');
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
                      loading: _accountsLoading,
                      errorText: _accountsError,
                      onChangeSort: (v) {
                        setState(() => _accountSort = v);
                        _accounts = _sortAccounts(List.of(_accounts));
                        debugPrint('[Sort] account sort -> "$_accountSort"');
                      },
                      selectedIndex: _selectedAccountIndex,
                      onTapItem: _onTapAccount,
                    ),
                    _PostsTab(
                      posts: _posts,
                      postSort: _postSort,
                      onChangeSort: (v) {
                        setState(() => _postSort = v);
                        _posts = _sortPosts(List.of(_posts));
                        debugPrint('[Sort] post sort -> "$_postSort"');
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
      color: Colors.transparent,
      child: SizedBox(
        height: 46,
        child: TabBar(
          dividerColor: Colors.transparent,
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
          indicator: FixedUnderlineTabIndicator(
            color: Colors.black,
            thickness: 2.0,
            bottomInset: 0.0,
            screenWidth: w,
            fraction: 0.375, // 화면 너비의 37.5%
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
  final bool loading;
  final String? errorText;
  final ValueChanged<String> onChangeSort;
  final int? selectedIndex;
  final void Function(int index, AccountItem item) onTapItem;

  const _AccountsTab({
    required this.accounts,
    required this.accountSort,
    required this.loading,
    required this.errorText,
    required this.onChangeSort,
    required this.selectedIndex,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 로딩바
        if (loading) const LinearProgressIndicator(minHeight: 2),

        // 정렬 + 결과 수 / 에러
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
              if (errorText == null)
                Text(
                  '결과 ${accounts.length}건',
                  style: AppTextStyles.withWeight(
                    AppTextStyles.bodySmall,
                    FontWeight.w500,
                  ).copyWith(color: Colors.black54),
                )
              else
                Text(
                  errorText!,
                  style: AppTextStyles.withWeight(
                    AppTextStyles.bodySmall,
                    FontWeight.w600,
                  ).copyWith(color: Colors.red),
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

/// ===== 커스텀 인디케이터: 활성 탭 중앙에, 화면 폭의 37.5% 길이 =====
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

    final Rect rect = offset & configuration.size!;
    final double cx = rect.center.dx; // 현재 탭 중앙
    final double half = indicatorWidth / 2;
    final double y = rect.bottom - bottomInset - thickness / 2;

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

/// ====== API: 친구 검색 ======
/// GET /api/friends/search?username={searchTerm}
/// Authorization: Bearer {token}
class FriendSearchApi {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  Future<List<String>> searchUsers({
    required String baseUrl,
    required String token,
    required String query,
    CancelToken? cancelToken,
  }) async {
    final uri = '$baseUrl/api/friends/search';
    final params = {'username': query};

    // 요청 로그
    debugPrint('[API] → GET $uri');
    debugPrint('[API]   params=$params');
    debugPrint(
      '[API]   headers={"Authorization": "Bearer ***${token.length >= 6 ? token.substring(token.length - 6) : token}"}',
    );

    final sw = Stopwatch()..start();

    final res = await _dio.get<List<dynamic>>(
      uri,
      queryParameters: params,
      cancelToken: cancelToken,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.json,
      ),
    );

    sw.stop();
    debugPrint('[API] ← ${res.statusCode}  (${sw.elapsedMilliseconds}ms)');

    if (res.statusCode == 200 && res.data != null) {
      // 응답 예: [{"username":"testuser2"}]
      final List<dynamic> raw = res.data!;
      final usernames = <String>[];
      for (final item in raw) {
        final u = (item as Map<String, dynamic>)['username']?.toString();
        if (u != null && u.isNotEmpty) usernames.add(u);
      }
      debugPrint('[API] parsed usernames count=${usernames.length}');
      return usernames;
    } else {
      // 비정상 코드 로깅
      debugPrint(
        '[API][WARN] unexpected status: ${res.statusCode}, data=${res.data}',
      );
      return [];
    }
  }
}
