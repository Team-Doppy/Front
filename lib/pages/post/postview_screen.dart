import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/editor/bottom_navigation.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:doppy/editor/publish/post_decoder.dart';
import 'package:flutter_svg/svg.dart';

class PostviewScreen extends StatelessWidget {
  final int? postId;
  final Map<String, dynamic>? postJson; // 글쓰기 후 바로 올 때 전달받는 JSON
  const PostviewScreen({Key? key, this.postId, this.postJson})
    : super(key: key);

  Future<Map<String, dynamic>> fetchPost() async {
    if (postJson != null) return postJson!;

    if (postId != null) {
      final token = await AuthService().getToken();
      final url = Uri.parse('${ApiServiceBase.baseUrl}/api/posts/$postId');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('블로그 데이터를 불러오지 못했습니다. (${response.statusCode})');
      }
    }
    throw Exception('postId가 없습니다.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: fetchPost(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: PostErrorView(
              error: snapshot.error,
              onRetry: () {
                (context as Element).reassemble();
              },
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: Text('데이터가 없습니다.')),
          );
        }
        final post = snapshot.data!;
        final contentJson = post["content"];
        print(contentJson);
        return Scaffold(
          backgroundColor: Colors.white,
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              _Thumbnail(post: post),
              _Content(post: post),
              SizedBox(height: 16),
              ...PostDecoderUtil.buildContentBlocks(contentJson),
              SizedBox(height: 35),
              _InteractionButtons(),
              _CommentList(),
            ],
          ),
          bottomNavigationBar: CustomBottomNavigationBar(
            currentIndex: 3,
            onTap: (_) {},
          ),
        );
      },
    );
  }
}

class PostErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;
  const PostErrorView({Key? key, this.error, this.onRetry}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: const Color.fromARGB(255, 190, 190, 190),
            size: 56,
          ),
          const SizedBox(height: 18),
          Text(
            '게시글을 불러올 수 없습니다.',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '존재하지 않거나 삭제된 게시글이거나,\n일시적인 네트워크 오류일 수 있습니다.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: Icon(Icons.refresh),
            label: Text('다시 시도'),
            style: ElevatedButton.styleFrom(
              minimumSize: Size(230, 50),
              backgroundColor: const Color.fromARGB(255, 190, 190, 190),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final Map<String, dynamic> post;
  const _Thumbnail({required this.post});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomLeft,
      children: [
        // 썸네일 이미지
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            child: Image.asset(
              'assets/images/feed5.jpg', //TODO: 백 연동
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
            style: AppTextStyles.headlineLarge.copyWith(
              color: AppColors.darkTextPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  final Map<String, dynamic> post;
  const _Content({required this.post});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          /*
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(
              "affection-jh",
              style: AppTextStyles.headlineMedium.copyWith(
                color: AppColors.lightTextPrimary,
              ),
            ),
            subtitle: Text(
              "작성일: 2025-08-16",
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
          // 제목
          */
          Row(
            children: [
              Text(
                '그 자리에, 그 시간에', //TODO: 텍스트 길이 제한 걸기
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.lightTextPrimary,
                ), // 폰트 두께 조정
              ),
            ],
          ),
          const SizedBox(height: 4),
          if ((post["tags"] as List).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              child: Wrap(
                spacing: 8,
                children:
                    (post["tags"] as List)
                        .map<Widget>((tag) => _TagChip(tag.toString()))
                        .toList(),
              ),
            ),
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
          InkWell(
            onTap: () {
              // TODO: 좋아요 기능, !liked로 상태 변경
            },
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/icons/ic_heart_outlined.svg',
                  width: 24,
                  height: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  '123', //TODO: likes 값 넣기, 1K, 2.3K 등 처리
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.lightTextPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          InkWell(
            onTap: () {
              // TODO: 댓글 기능
            },
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/icons/ic_comment.svg',
                  width: 24,
                  height: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  '45', //TODO: comments 값 넣기
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.lightTextPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(), // 오른쪽으로 밀어내기
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/ic_share.svg',
              width: 24,
              height: 24,            ),
            onPressed: () {
              // TODO: 공유 기능
            },
          ),
        ],
      ),
    );
  }
}

class _CommentList extends StatelessWidget {
  const _CommentList();

  @override
  Widget build(BuildContext context) {
    final comments = List.generate(
      5,
      (index) => {
        'author': 'user${index + 1}',
        'content': '이것은 ${index + 1}번째 댓글입니다. 좋은 글 잘 봤어요!',
        'date': '2025.08.0${index + 1}',
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...comments.map((comment) => _CommentItem(comment: comment)).toList(),
        ],
      ),
    );
  }
}

class _CommentItem extends StatelessWidget {
  final Map<String, dynamic> comment;
  const _CommentItem({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 252, 252, 252),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color.fromARGB(255, 234, 234, 234),
            child: Icon(Icons.person, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment['author'],
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      comment['date'],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment['content'],
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.black87,
                    fontSize: 15,
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

class _TagChip extends StatelessWidget {
  final String tag;
  const _TagChip(this.tag, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        '#$tag',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.lightTextPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: AppColors.lightBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          width: 0.5,
          color: const Color.fromARGB(255, 199, 199, 199).withOpacity(0.2),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    );
  }
}
