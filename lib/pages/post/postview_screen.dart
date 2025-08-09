import 'package:flutter/material.dart';
import 'package:doppy/theme/theme.dart';

class PostviewScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: const [
              _TopBar(), // 상단 바
              _AuthorInfo(), // 작성자 정보
              _Thumbnail(), // 썸네일
              _Content(), // 제목, 부제목, 본문
              _InteractionButtons(), // 좋아요, 댓글, 공유
              Divider(),
              _AuthorProfile(), // 작성자 프로필
              _PostList(), // 관련 글 목록
              Divider(),
              _BannerAd(), // 배너 광고
              //TODO: 하단 NavBar 구현?
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.arrow_back),
            iconSize: 30, // 아이콘 크기 조정
          ),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.category), //TODO: 카테고리 토글 구현
            label: Text(
              '일상',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold), // 폰트 스타일 조정
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.menu),
            iconSize: 30, // 아이콘 크기 조정
          ),
        ],
      ),
    );
  }
}

class _AuthorInfo extends StatelessWidget {
  const _AuthorInfo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Row(
        children: [
          // 작성자 프로필 사진
          const CircleAvatar(
            //TODO: 작성자 ProfileScreen으로 링크 추가
            radius: 28, // 프로필 사진 크기 조정 (56px)
            backgroundImage: AssetImage('assets/images/profile.jpg'),
          ),

          const SizedBox(width: 12),

          // 이름 + 작성 시간
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  //TODO: 작성자 ProfileScreen으로 링크 추가
                  'name', //TODO: username 값 넣기
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold), // 폰트 스타일 조정
                ),
                const SizedBox(height: 4),
                Text(
                  '2025.7.29 13:23', //TODO: date값 넣기, 2분 전, 1시간 전 등 처리해주기
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold), // 폰트 스타일 조정
                ),
              ],
            ),
          ),

          // 이웃 요청 버튼 : 삭제, 기타 버튼에 패스
          // TextButton(
          //   onPressed: () {},
          //   child: const Text('+ 이웃 요청'),
          // ),

          // 기타 버튼
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
            iconSize: 30, // 아이콘 크기 조정
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          // 썸네일 이미지
          AspectRatio(
            aspectRatio: 5 / 7,
            child: ClipRRect(
              child: Image.asset(
                'assets/images/thumbnail.jpg', // 경로는 실제 이미지에 맞게 수정
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),

          // 그라데이션 + 주제 텍스트
          Container(
            height: 120, // 그라데이션 높이 조정
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(12),
            child: Text(
              '성시경의 명곡을\n이창섭의 감성으로 재해석하다', //TODO: 텍스트 길이 제한 걸기
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: AppColors.darkTextPrimary,
                    fontWeight: FontWeight.bold, // 폰트 두께 조정
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 제목
          Text(
            '그 자리에, 그 시간에', //TODO: 텍스트 길이 제한 걸기
            style: Theme.of(context)
                .textTheme
                .headlineLarge
                ?.copyWith(fontWeight: FontWeight.bold), // 폰트 두께 조정
          ),
          const SizedBox(height: 4),
          // 부제목
          Text(
            '원곡 성시경, 커버 이창섭',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontSize: 20), // 폰트 크기 조정
          ),

          SizedBox(height: 16),

          // 본문
          Text(
            '살아가는 순간들 마다\n얼마나 많은 일들이\n우연이라는 이름에 빛을 잃었는지\n믿기 힘든 작은 기적들\n\n\n그 자리에 그 시간에\n꼭 운명처럼 우리는 놓여있었던 거죠\n스쳐 지나갔다면 다른 곳을 봤다면\n만일 누군가 만났더라면\n우린 사랑하지 않았을까요\n\n\n사랑하며 순간들 마다\n얼마나 많은 말들이\n이별이라는 끝으로 밀어 넣었는지\n지나서야 깨닫는 일들\n\n\n그 자리에 그 시간에\n헤어질 차례가 되어 놓여졌던 걸까요\n그 말을 참았다면 다른 얘길 했다면\n우린 이별을 피해 갔을 것 같나요\n잃어버린 반지처럼 꼭 찾을 것 같아\n한참을 헤매겠지만 돌이킬 수 없는 일\n\n\n그댈 안아줬다면 울리지 않았다면\n우린 어떻게 되었을까요\n정말 헤어지진 않았을까요',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontSize: 15), // 폰트 크기 조정
          ),

          SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _InteractionButtons extends StatelessWidget {
  const _InteractionButtons();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          _IconTextButton(
            icon: Icons.favorite_border,
            label: '123', //TODO: likes 값 넣기, 1K, 2.3K 등 처리
            onPressed: () {
              // TODO: 좋아요 기능, !liked로 상태 변경
            },
          ),
          const SizedBox(width: 16),
          _IconTextButton(
            icon: Icons.comment_outlined,
            label: '45', //TODO: comments 값 넣기
            onPressed: () {
              // TODO: 댓글 기능
            },
          ),
          const Spacer(), // 오른쪽으로 밀어내기
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              // TODO: 공유 기능
            },
            iconSize: 30, // 아이콘 크기 조정
          ),
        ],
      ),
    );
  }
}

class _IconTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _IconTextButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Icon(icon,
              size: 28, color: Theme.of(context).colorScheme.onSurface), // 아이콘 크기 조정
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold), // 폰트 스타일 조정
          ),
        ],
      ),
    );
  }
}

class _AuthorProfile extends StatelessWidget {
  const _AuthorProfile();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 프로필 사진
          const CircleAvatar(
            radius: 28, // 프로필 사진 크기 조정 (56px)
            backgroundImage: AssetImage('assets/images/profile.jpg'),
          ),

          const SizedBox(width: 16),

          // 이름, 아이디, 친구 수
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '홍길동',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold), // 폰트 스타일 조정
                    ),
                    const SizedBox(width: 8), // 이름과 아이디 사이 간격
                    Text(
                      '@hong_gildong',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.bold), // 폰트 스타일 조정
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  '친구 254명',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold), // 폰트 스타일 조정
                ),
              ],
            ),
          ),

          // 친구 추가 버튼 : 삭제, 기타 버튼에 패스
          // TextButton(
          //   onPressed: () {
          //     // TODO: 친구 추가 기능
          //   },
          //   child: Text(
          //     '+ 친구',
          //     style: Theme.of(context)
          //         .textTheme
          //         .bodySmall
          //         ?.copyWith(fontWeight: FontWeight.bold), // 폰트 스타일 조정
          //   ),
          // ),

          // 기타 버튼
          IconButton(
            onPressed: () {
              // TODO: 옵션 메뉴 기능 (이웃 추가, ...)
            },
            icon: const Icon(Icons.more_vert),
            iconSize: 30, // 아이콘 크기 조정
          ),
        ],
      ),
    );
  }
}

class _PostList extends StatelessWidget {
  const _PostList();

  @override
  Widget build(BuildContext context) {
    // 더미 데이터 예시
    final posts = List.generate(
      5,
      (index) => { //TODO: 값 수정하기
        'title': '글 제목 ${index + 1}',
        'date': '2025.08.0${index + 1}',
        'likes': 12 * (index + 1),
        'comments': 5 * (index + 1),
        'thumbnail': 'assets/images/thumb${index + 1}.jpg',
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카테고리 링크
          GestureDetector(
            onTap: () {
              // TODO: 카테고리 이동
            },
            child: Text(
              '#일상 카테고리의 다른 글',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold, // 폰트 스타일 조정
                  ),
            ),
          ),

          const SizedBox(height: 12),

          // 글 카드 목록
          ...posts.asMap().entries.map((entry) {
            final index = entry.key;
            final post = entry.value;
            return Column(
              children: [
                _PostCard(post: post),
                if (index < posts.length - 1) Divider(color: AppColors.getBorder(Theme.of(context).brightness == Brightness.dark)), // 마지막 카드 뒤에는 Divider를 추가하지 않음
              ],
            );
          }).toList(),

          const SizedBox(height: 16),

          // 이전 / 다음 버튼
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                iconSize: 30, // 아이콘 크기 조정
                onPressed: () {
                  // TODO: 이전 페이지
                },
              ),
              const SizedBox(width: 40),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                iconSize: 30, // 아이콘 크기 조정
                onPressed: () {
                  // TODO: 다음 페이지
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;

  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            // TODO: 글 상세 보기 이동
          },
          child: Container(
            height: 90, // 고정 높이 설정
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 텍스트 내용 (제목, 날짜, 좋아요, 댓글)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 제목
                      Text(
                        post['title'],
                        style: Theme
                            .of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight
                            .bold), // 폰트 스타일 조정
                      ),
                      const SizedBox(height: 4), // 제목과 서브타이틀 정보 사이 간격

                      // 날짜, 좋아요, 댓글
                      Row(
                        children: [
                          Text(
                            post['date'],
                            style: Theme
                                .of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                fontWeight: FontWeight.bold), // 폰트 스타일 조정
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.favorite,
                              size: 16,
                              color: Theme
                                  .of(context)
                                  .colorScheme
                                  .error), // 아이콘 크기 조정
                          const SizedBox(width: 4),
                          Text(
                            '${post['likes']}',
                            style: Theme
                                .of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                fontWeight: FontWeight.bold), // 폰트 스타일 조정
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.comment,
                              size: 16,
                              color: Theme
                                  .of(context)
                                  .colorScheme
                                  .onSurface), // 아이콘 크기 조정
                          const SizedBox(width: 4),
                          Text(
                            '${post['comments']}',
                            style: Theme
                                .of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                fontWeight: FontWeight.bold), // 폰트 스타일 조정
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12), // 썸네일과 텍스트 사이 간격
                // 썸네일
                Container(
                  width: 76,
                  height: 74,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/images/card_sample.jpg'), // 실제 이미지 경로로 변경
                      fit: BoxFit.cover,
                    ),
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

class _BannerAd extends StatelessWidget {
  const _BannerAd();

  @override
  Widget build(BuildContext context) {
    // The main container for the ad, with margin.
    return Padding(
      padding: const EdgeInsets.all(16.0),
      // ClipRRect ensures the rounded corners are applied to all children.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5.0),
        child: InkWell( // To make the whole banner clickable
          onTap: () {
            // TODO: 광고 링크 이동
          },
          child: Container(
            height: 180,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/banner_sample.jpg'), // 실제 이미지 경로로 변경
                fit: BoxFit.cover,
              ),
            ),
            child: Stack(
              children: [
                // 2. "광고" label at the top-left corner
                Positioned(
                  top: 8.0,
                  left: 8.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '광고',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold, // 폰트 스타일 조정
                      ),
                    ),
                  ),
                ),

                // 3. Bottom bar with "더 알아보기" text
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 36, // 높이 36으로 변경
                    width: double.infinity,
                    color: Colors.black.withOpacity(0.7),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text(
                          '더 알아보기',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ),
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

