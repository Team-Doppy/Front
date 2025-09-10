import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';

class MentionOverlay extends StatefulWidget {
  final VoidCallback? onClose;
  final void Function(String username)? onSelect;

  const MentionOverlay({super.key, this.onClose, this.onSelect});

  @override
  State<MentionOverlay> createState() => _MentionOverlayState();
}

class _MentionOverlayState extends State<MentionOverlay> {
  final TextEditingController _controller = TextEditingController(text: '@');
  final FocusNode _focusNode = FocusNode();

  // 데모용 추천 사용자 목록 (실제 연결 시 API나 검색 로직 바인딩)
  final List<_UserChip> _suggestions = const [
    _UserChip(username: 'alice', imageUrl: null),
    _UserChip(username: 'bob', imageUrl: null),
    _UserChip(username: 'carol', imageUrl: null),
    _UserChip(username: 'dave', imageUrl: null),
    _UserChip(username: 'erin', imageUrl: null),
    _UserChip(username: 'frank', imageUrl: null),
    _UserChip(username: 'grace', imageUrl: null),
  ];

  @override
  void initState() {
    super.initState();
    // 키보드 자동 표시
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.8),
      body: SafeArea(
        child: Stack(
          children: [
            // 닫기 제스처 (배경 탭)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  widget.onClose?.call();
                  Navigator.of(context).maybePop();
                },
                behavior: HitTestBehavior.opaque,
              ),
            ),
            // 상단 입력 영역 (인스타 느낌 상단 카드 느낌)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),

                    child: Row(
                      children: [
                        Icon(
                          Icons.alternate_email,
                          color: AppColors.darkTextPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 상단 입력 영역 (인스타 느낌 상단 카드 느낌)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),

                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: true,
                            cursorColor: AppColors.darkTextPrimary,
                            style: const TextStyle(
                              color: AppColors.darkTextPrimary,
                              fontSize: 18,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: '@사용자 검색',
                              hintStyle: TextStyle(
                                color: AppColors.darkTextSecondary,
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {});
                            },
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            widget.onClose?.call();
                            Navigator.of(context).maybePop();
                          },
                          child: const Text(
                            '완료',
                            style: TextStyle(
                              color: AppColors.darkTextPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 하단 추천 가로 리스트 (키보드 위로 떠있게)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    itemBuilder: (context, index) {
                      final item = _suggestions[index];
                      return _MentionChip(
                        username: item.username,
                        imageUrl: item.imageUrl,
                        onTap: () {
                          widget.onSelect?.call(item.username);
                          Navigator.of(context).maybePop();
                        },
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemCount: _suggestions.length,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MentionChip extends StatelessWidget {
  final String username;
  final String? imageUrl;
  final VoidCallback onTap;

  const _MentionChip({
    required this.username,
    required this.onTap,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.darkBorder),
              image:
                  imageUrl != null
                      ? DecorationImage(
                        image: NetworkImage(imageUrl!),
                        fit: BoxFit.cover,
                      )
                      : null,
              color: AppColors.darkSurfaceVariant,
            ),
            child:
                imageUrl == null
                    ? const Icon(
                      Icons.person,
                      color: AppColors.darkTextSecondary,
                    )
                    : null,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 70,
            child: Text(
              username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserChip {
  final String username;
  final String? imageUrl;
  const _UserChip({required this.username, this.imageUrl});
}
