import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_text_styles.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final List<PostData> _posts;

  @override
  void initState() {
    super.initState();
    _posts = PostDataProvider.getSamplePosts();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // 앱바 - 항상 표시
            Container(
              height: 42,
              color: AppColors.darkBackground,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Consumer<AuthProvider>(
                        builder: (context, auth, child) {
                          final username = auth.username ?? '사용자';
                          return Text(
                            '@$username',
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                    ),
                    Stack(
                      children: [
                        Icon(
                          Icons.notifications,
                          color: AppColors.darkTextPrimary,
                          size: 23,
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 238, 0, 0),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // 포스트 리스트 - 남은 공간 모두 사용
            Expanded(
              child: PostList(containerWidth: screenWidth, posts: _posts),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 0,
        onTap: (_) {},
      ),
    );
  }
}
