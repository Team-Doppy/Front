import 'package:flutter/material.dart';
import '../../data/services/group_service.dart';
import '../../data/models/group_model.dart';

// 그룹 편집 화면
class GroupEditScreen extends StatefulWidget {
  final Group group;

  const GroupEditScreen({Key? key, required this.group}) : super(key: key);

  @override
  State<GroupEditScreen> createState() => _GroupEditScreenState();
}

class _GroupEditScreenState extends State<GroupEditScreen> {
  // API 서비스
  final GroupService _groupService = GroupService();

  // 텍스트 컨트롤러
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // 로딩 상태
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 기존 값으로 초기화
    _nameController.text = widget.group.name;
    _descriptionController.text = widget.group.description;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // 그룹 수정
  Future<void> _updateGroup() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('그룹 이름을 입력해주세요')));
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      print('🔍 [GroupEditScreen] 그룹 수정 시작');

      await _groupService.updateGroup(
        widget.group.id,
        _nameController.text.trim(),
        _descriptionController.text.trim(),
      );

      print('✅ [GroupEditScreen] 그룹 수정 성공');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('그룹이 성공적으로 수정되었습니다')));

        Navigator.pop(context, true); // 수정 완료 표시
      }
    } catch (e) {
      print('❌ [GroupEditScreen] 그룹 수정 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('그룹 수정에 실패했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 그룹 삭제
  Future<void> _deleteGroup() async {
    // 삭제 확인 다이얼로그
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('그룹 삭제'),
          content: Text(
            '정말로 "${widget.group.name}" 그룹을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      setState(() {
        _isLoading = true;
      });

      print('🔍 [GroupEditScreen] 그룹 삭제 시작');

      await _groupService.deleteGroup(widget.group.id);

      print('✅ [GroupEditScreen] 그룹 삭제 성공');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('그룹이 성공적으로 삭제되었습니다')));
        Navigator.pop(context, 'deleted'); // 삭제 완료 표시
      }
    } catch (e) {
      print('❌ [GroupEditScreen] 그룹 삭제 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('그룹 삭제에 실패했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '그룹 편집',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _updateGroup,
            child:
                _isLoading
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text(
                      '저장',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 그룹 이름 입력
            const Text(
              '그룹 이름',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: '그룹 이름을 입력하세요',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 그룹 설명 입력
            const Text(
              '그룹 설명',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '그룹에 대한 설명을 입력하세요',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // 그룹 삭제 버튼
            const Text(
              '위험한 작업',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '그룹을 삭제하면 모든 멤버와 데이터가 영구적으로 제거됩니다.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isLoading ? null : _deleteGroup,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('그룹 삭제', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
