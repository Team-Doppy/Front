import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../components/custom_bottom_navigation_bar.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  int _selectedIndex = 1;
  String _accountSort = '계정 이름';
  String _postSort = '인기순';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // 계정 / 게시글
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // ── 상단 로고 + 검색창 ─────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/doppy_logo.png',
                      width: 32,
                      height: 32,
                    ),
                    const SizedBox(width: 12),

                    // 실제 TextField 로 교체
                    SizedBox(
                      width: 325,
                      height: 40,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: '검색',
                          hintStyle: AppTextStyles.withColor(
                            AppTextStyles.withWeight(
                              AppTextStyles.bodyLarge,
                              FontWeight.w500,
                            ),
                            const Color(0xFF989898),
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 22,
                            color: Color(0xFF989898),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          isDense: true,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF989898),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        // 여기에 onChanged 로 검색 로직 연결 가능
                      ),
                    ),
                  ],
                ),
              ),

              // ── 탭바 (계정 / 게시글) ────────────────────────
              TabBar(
                indicatorColor: Colors.black,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.black54,
                labelStyle: AppTextStyles.withWeight(
                  AppTextStyles.headlineMedium,
                  FontWeight.w700,
                ),
                unselectedLabelStyle: AppTextStyles.withWeight(
                  AppTextStyles.headlineMedium,
                  FontWeight.w500,
                ),
                tabs: const [Tab(text: '계정'), Tab(text: '게시글')],
              ),

              // ── 탭별 콘텐츠 ─────────────────────────────────
              Expanded(
                child: TabBarView(
                  children: [
                    // ── 계정 탭 ───────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 드롭다운 (계정 이름)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: DropdownButton<String>(
                            value: _accountSort,
                            items:
                                ['계정 이름']
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
                              if (v != null) setState(() => _accountSort = v);
                            },
                            underline: const SizedBox.shrink(),
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        // 계정 리스트
                        Expanded(
                          child: ListView.builder(
                            itemCount: 30,
                            itemBuilder:
                                (context, index) => const AccountListItem(
                                  nickname: '이웃 1',
                                  userId: '@userID',
                                  neighborCount: '이웃 23명',
                                ),
                          ),
                        ),
                      ],
                    ),

                    // ── 게시글 탭 ───────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 드롭다운 (인기순)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: DropdownButton<String>(
                            value: _postSort,
                            items:
                                ['인기순']
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
                              if (v != null) setState(() => _postSort = v);
                            },
                            underline: const SizedBox.shrink(),
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        // 게시글 리스트
                        Expanded(
                          child: ListView.builder(
                            itemCount: 10,
                            itemBuilder:
                                (context, index) => PostListItem(index: index),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── 커스텀 바텀 네비게이션 바 ───────────────────
        bottomNavigationBar: CustomBottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
        ),
      ),
    );
  }
}

/// 계정 리스트 아이템
class AccountListItem extends StatelessWidget {
  final String nickname;
  final String userId;
  final String neighborCount;

  const AccountListItem({
    super.key,
    required this.nickname,
    required this.userId,
    required this.neighborCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Stack(
        children: [
          // 우측 메뉴 아이콘
          Positioned(
            right: 0,
            top: 5,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: const Icon(Icons.more_vert),
            ),
          ),
          // 프로필 아이콘
          Positioned(
            left: 0,
            top: 0,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Image.asset(
                'assets/images/profile_icon.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          // 닉네임
          Positioned(
            left: 57,
            top: 6,
            child: Text(
              nickname,
              style: AppTextStyles.withWeight(
                AppTextStyles.withSize(AppTextStyles.bodyMedium, 15),
                FontWeight.w600,
              ).copyWith(color: Colors.black),
            ),
          ),
          // 유저아이디
          Positioned(
            left: 99,
            top: 8,
            child: Text(
              userId,
              style: AppTextStyles.withWeight(
                AppTextStyles.withSize(AppTextStyles.bodySmall, 11),
                FontWeight.w600,
              ).copyWith(color: Colors.black),
            ),
          ),
          // 이웃 수
          Positioned(
            left: 57,
            top: 27,
            child: Text(
              neighborCount,
              style: AppTextStyles.withSize(
                AppTextStyles.labelSmall,
                10,
              ).copyWith(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}

/// 게시글 리스트 아이템
class PostListItem extends StatelessWidget {
  final int index;
  const PostListItem({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    final title = '모태솔로지만연애를해야할까///';
    final author = '수취영';
    final preview = '안녕하세요. 오늘은 모태솔로지만연애하고싶어여 귀곡반도왔어요…';
    final imageUrl = 'https://picsum.photos/144/108?random=$index';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          // 썸네일 이미지
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
          // 텍스트 영역
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 제목
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
                // 작성자
                SizedBox(
                  height: 14,
                  child: Text(
                    author,
                    style: AppTextStyles.withWeight(
                      AppTextStyles.withSize(AppTextStyles.bodySmall, 10),
                      FontWeight.w500,
                    ).copyWith(color: const Color(0xFF5B5757)),
                  ),
                ),
                const SizedBox(height: 4),
                // 미리보기
                SizedBox(
                  height: 12,
                  child: Text(
                    preview,
                    style: AppTextStyles.withWeight(
                      AppTextStyles.withSize(AppTextStyles.bodySmall, 8),
                      FontWeight.w400,
                    ).copyWith(color: const Color(0xFF515151)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
