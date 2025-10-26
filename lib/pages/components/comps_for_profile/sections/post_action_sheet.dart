import 'package:doppy/data/models/post_data.dart';
import 'package:flutter/material.dart';

class PostActionSheet {
  static void show(
    BuildContext context, {
    required PostData post,
    required VoidCallback onDelete,
    required VoidCallback onMoveCategory,
    required VoidCallback onChangeAccessLevel,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHandle(),
                  _buildMenuItem(
                    context,
                    icon: Icons.delete_outline,
                    title: '삭제',
                    onTap: () {
                      Navigator.pop(context);
                      onDelete();
                    },
                  ),
                  Divider(height: 1),
                  _buildMenuItem(
                    context,
                    icon: Icons.folder_outlined,
                    title: '카테고리 이동',
                    onTap: () {
                      Navigator.pop(context);
                      onMoveCategory();
                    },
                  ),
                  Divider(height: 1),
                  _buildMenuItem(
                    context,
                    icon: Icons.lock_outline,
                    title: '공개범위 변경',
                    onTap: () {
                      Navigator.pop(context);
                      onChangeAccessLevel();
                    },
                  ),
                  SizedBox(height: 12),
                ],
              ),
            ),
          ),
    );
  }

  static Widget _buildHandle() {
    return Builder(
      builder:
          (context) => Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
    );
  }

  static Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(leading: Icon(icon), title: Text(title), onTap: onTap);
  }
}
