import 'package:flutter/material.dart';

class CategoryModel {
  CategoryModel({required this.id, required this.name, List<String>? postIds})
    : postIds = postIds ?? <String>[];

  final String id;
  String name;
  final List<String> postIds;
}

class CategoryProvider extends ChangeNotifier {
  // 싱글턴 패턴
  static final CategoryProvider _instance = CategoryProvider._internal();
  factory CategoryProvider({bool readOnly = false}) {
    _instance._isReadOnly = readOnly;
    return _instance;
  }
  CategoryProvider._internal();

  bool _isReadOnly = false;
  final List<CategoryModel> _categories = <CategoryModel>[];
  final Map<String, String> _postIdToCategoryId = <String, String>{};

  // 선택 상태 관리
  BaseFilter _selectedBase = BaseFilter.all;
  String? _selectedCategoryId; // 사용자가 만든 카테고리 선택 시

  bool get isReadOnly => _isReadOnly;
  set isReadOnly(bool v) {
    if (_isReadOnly == v) return;
    _isReadOnly = v;
    notifyListeners();
  }

  List<CategoryModel> get categories => List.unmodifiable(_categories);

  BaseFilter get selectedBase => _selectedBase;
  String? get selectedCategoryId => _selectedCategoryId;

  String get selectedLabel {
    if (_selectedCategoryId != null) {
      final cat = _categories.firstWhere(
        (c) => c.id == _selectedCategoryId,
        orElse: () => CategoryModel(id: '', name: ''),
      );
      if (cat.id.isNotEmpty) return cat.name;
    }
    switch (_selectedBase) {
      case BaseFilter.all:
        return '전체';
      case BaseFilter.private:
        return '나만보기';
      case BaseFilter.groups:
        return '그룹공유';
      case BaseFilter.public:
        return '전체공개';
    }
  }

  void selectBase(BaseFilter base) {
    if (_selectedBase == base && _selectedCategoryId == null) return;
    _selectedCategoryId = null;
    _selectedBase = base;
    print(
      '[CategoryProvider] selectBase -> $_selectedBase (instance: ${this.hashCode})',
    );
    notifyListeners();
  }

  void selectCategory(String categoryId) {
    if (_selectedCategoryId == categoryId) return;
    _selectedCategoryId = categoryId;
    print(
      '[CategoryProvider] selectCategory -> $categoryId (instance: ${this.hashCode})',
    );
    notifyListeners();
  }

  void createCategory(String name) {
    if (_isReadOnly) return;
    final id = 'cat_${DateTime.now().microsecondsSinceEpoch}';
    _categories.add(CategoryModel(id: id, name: name));
    notifyListeners();
  }

  void renameCategory(String categoryId, String newName) {
    if (_isReadOnly) return;
    final idx = _categories.indexWhere((c) => c.id == categoryId);
    if (idx == -1) return;
    _categories[idx].name = newName;
    notifyListeners();
  }

  void removeCategory(String categoryId) {
    if (_isReadOnly) return;
    _categories.removeWhere((c) => c.id == categoryId);
    // 해당 카테고리에 매핑된 포스트 해제
    _postIdToCategoryId.removeWhere((_, cid) => cid == categoryId);
    if (_selectedCategoryId == categoryId) {
      _selectedCategoryId = null; // 삭제 시 기본 탭으로
      _selectedBase = BaseFilter.all;
    }
    notifyListeners();
  }

  void moveWithinCategory({
    required String categoryId,
    required String postId,
    required int targetIndex,
  }) {
    if (_isReadOnly) return;
    final cat = _categories.firstWhere(
      (c) => c.id == categoryId,
      orElse: () => CategoryModel(id: '', name: ''),
    );
    if (cat.id.isEmpty) return;
    final curIdx = cat.postIds.indexOf(postId);
    if (curIdx == -1) return;
    final int clamped = _clampIndex(targetIndex, 0, cat.postIds.length);
    if (clamped == curIdx || clamped == curIdx + 1) return;
    cat.postIds.removeAt(curIdx);
    cat.postIds.insert(clamped > curIdx ? clamped - 1 : clamped, postId);
    notifyListeners();
  }

  void assignToCategory({
    required String categoryId,
    required String postId,
    required int targetIndex,
  }) {
    if (_isReadOnly) return;
    // 기존 카테고리에서 제거
    final prevCatId = _postIdToCategoryId[postId];
    if (prevCatId != null) {
      final prev = _categories.firstWhere(
        (c) => c.id == prevCatId,
        orElse: () => CategoryModel(id: '', name: ''),
      );
      if (prev.id.isNotEmpty) {
        prev.postIds.remove(postId);
      }
    }
    _postIdToCategoryId[postId] = categoryId;
    final cat = _categories.firstWhere(
      (c) => c.id == categoryId,
      orElse: () => CategoryModel(id: '', name: ''),
    );
    if (cat.id.isEmpty) return;
    final int clamped = _clampIndex(targetIndex, 0, cat.postIds.length);
    cat.postIds.insert(clamped, postId);
    notifyListeners();
  }

  String? categoryIdOf(String postId) => _postIdToCategoryId[postId];

  // 카테고리 순서 변경 (로컬)
  void reorderCategories(List<String> orderedIds) {
    if (_isReadOnly) return;
    final Map<String, CategoryModel> map = {
      for (final c in _categories) c.id: c,
    };
    final List<CategoryModel> next = <CategoryModel>[];
    for (final id in orderedIds) {
      final c = map.remove(id);
      if (c != null) next.add(c);
    }
    next.addAll(map.values);
    _categories
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  // 카테고리 내 포스트 순서 변경 (로컬)
  void reorderPostsInCategory(String categoryId, List<String> orderedIds) {
    if (_isReadOnly) return;
    final cat = _categories.firstWhere(
      (c) => c.id == categoryId,
      orElse: () => CategoryModel(id: '', name: ''),
    );
    if (cat.id.isEmpty) return;
    final Set<String> seen = <String>{};
    final List<String> next = <String>[];
    for (final id in orderedIds) {
      if (cat.postIds.contains(id) && !seen.contains(id)) {
        next.add(id);
        seen.add(id);
      }
    }
    for (final id in cat.postIds) {
      if (!seen.contains(id)) next.add(id);
    }
    cat.postIds
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  // 카테고리에서 포스트 제거 (미분류 처리: 매핑만 제거)
  void unassignFromCategory(String categoryId, String postId) {
    if (_isReadOnly) return;
    final cat = _categories.firstWhere(
      (c) => c.id == categoryId,
      orElse: () => CategoryModel(id: '', name: ''),
    );
    if (cat.id.isEmpty) return;
    cat.postIds.remove(postId);
    _postIdToCategoryId.remove(postId);
    notifyListeners();
  }

  // 특정 포스트를 다른 카테고리로 이동 (targetCategoryId == null 이면 미분류)
  void movePostToCategory({
    required String postId,
    String? targetCategoryId,
    required int targetPosition,
  }) {
    if (_isReadOnly) return;
    final prevCatId = _postIdToCategoryId[postId];
    if (prevCatId != null) {
      final prev = _categories.firstWhere(
        (c) => c.id == prevCatId,
        orElse: () => CategoryModel(id: '', name: ''),
      );
      if (prev.id.isNotEmpty) prev.postIds.remove(postId);
    }
    if (targetCategoryId == null) {
      _postIdToCategoryId.remove(postId);
      notifyListeners();
      return;
    }
    final cat = _categories.firstWhere(
      (c) => c.id == targetCategoryId,
      orElse: () => CategoryModel(id: '', name: ''),
    );
    if (cat.id.isEmpty) return;
    final int clamped = _clampIndex(targetPosition, 0, cat.postIds.length);
    cat.postIds.insert(clamped, postId);
    _postIdToCategoryId[postId] = targetCategoryId;
    notifyListeners();
  }

  int _clampIndex(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}

enum BaseFilter { all, private, groups, public }
