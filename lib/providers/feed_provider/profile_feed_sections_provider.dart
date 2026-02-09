import 'package:flutter/foundation.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/utils/network_utils.dart';

/// "전체 탭" 전용: phase별 섹션(각 6개 + hasMore) 조회 Provider
class ProfileFeedSectionsProvider extends ChangeNotifier {
  final BlogService _blogService = BlogService();

  bool _isLoading = false;
  NetworkError? _networkError;

  String? _username;
  Map<String, dynamic>? _userInfo;
  Map<String, List<Map<String, dynamic>>>? _systemCategoryMappings;
  List<Map<String, dynamic>> _sections = <Map<String, dynamic>>[];

  bool get isLoading => _isLoading;
  NetworkError? get networkError => _networkError;
  String? get username => _username;
  Map<String, dynamic>? get userInfo => _userInfo;
  Map<String, List<Map<String, dynamic>>>? get systemCategoryMappings =>
      _systemCategoryMappings;
  List<Map<String, dynamic>> get sections => List.unmodifiable(_sections);

  Future<void> loadSections({
    required String username,
    bool force = false,
  }) async {
    if (_isLoading) return;
    if (!force && _username == username && _sections.isNotEmpty) return;

    _isLoading = true;
    _networkError = null;
    _username = username;
    notifyListeners();

    try {
      debugPrint('[ProfileFeedSectionsProvider] 섹션 로드 시작: username=$username');
      final data = await _blogService.getProfileFeedSections(username);
      debugPrint(
        '[ProfileFeedSectionsProvider] API 응답 받음: keys=${data.keys.toList()}',
      );

      _userInfo = data['userInfo'] as Map<String, dynamic>?;

      // systemCategoryMappings (본인 피드일 때만)
      final mappings = data['systemCategoryMappings'];
      if (mappings is Map<String, dynamic>) {
        final parsed = <String, List<Map<String, dynamic>>>{};
        for (final entry in mappings.entries) {
          if (entry.value is List) {
            parsed[entry.key] =
                (entry.value as List)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
          }
        }
        _systemCategoryMappings = parsed;
      } else {
        _systemCategoryMappings = null;
      }

      final rawSections = data['sections'];
      if (rawSections is List) {
        _sections =
            rawSections
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
        debugPrint(
          '[ProfileFeedSectionsProvider] 섹션 로드 완료: ${_sections.length}개',
        );
        for (int i = 0; i < _sections.length; i++) {
          final section = _sections[i];
          final posts = section['posts'] as List? ?? [];
          debugPrint(
            '[ProfileFeedSectionsProvider] 섹션 $i: phase=${section['phase']}, posts=${posts.length}개, hasMore=${section['hasMore']}',
          );
        }
      } else {
        _sections = <Map<String, dynamic>>[];
        debugPrint(
          '[ProfileFeedSectionsProvider] 섹션이 비어있음 (rawSections가 List가 아님)',
        );
      }
    } catch (e) {
      debugPrint('[ProfileFeedSectionsProvider] 섹션 로드 실패: $e');
      _networkError = NetworkUtils.parseError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 섹션(phase) 표시 순서 저장 (본인만)
  /// PUT /api/profile/feed/section-order
  Future<void> saveSectionOrder(List<String> phaseOrder) async {
    try {
      debugPrint('[ProfileFeedSectionsProvider] 섹션 순서 저장 시작: $phaseOrder');

      await _blogService.saveProfileFeedSectionOrder(phaseOrder);
      debugPrint('[ProfileFeedSectionsProvider] 섹션 순서 저장 성공');

      // 저장 후 섹션 순서를 로컬에서도 업데이트
      _reorderSectionsLocally(phaseOrder);
      notifyListeners();
    } catch (e) {
      debugPrint('[ProfileFeedSectionsProvider] 섹션 순서 저장 실패: $e');
      _networkError = NetworkUtils.parseError(e);
      notifyListeners();
      rethrow;
    }
  }

  /// 섹션 순서를 로컬에서 재정렬 (phaseOrder 기준)
  void _reorderSectionsLocally(List<String> phaseOrder) {
    if (phaseOrder.isEmpty || _sections.isEmpty) return;

    // phaseOrder에 있는 섹션들을 순서대로 정렬
    final orderedSections = <Map<String, dynamic>>[];
    final phaseSet = phaseOrder.toSet();

    // phaseOrder에 있는 섹션들을 순서대로 추가
    for (final phase in phaseOrder) {
      final section = _sections.firstWhere(
        (s) => (s['phase'] as String?) == phase,
        orElse: () => <String, dynamic>{},
      );
      if (section.isNotEmpty) {
        orderedSections.add(section);
      }
    }

    // phaseOrder에 없는 섹션들을 맨 뒤에 추가
    for (final section in _sections) {
      final phase = section['phase'] as String?;
      if (phase != null && !phaseSet.contains(phase)) {
        orderedSections.add(section);
      }
    }

    _sections = orderedSections;
  }

  void clear() {
    _isLoading = false;
    _networkError = null;
    _username = null;
    _userInfo = null;
    _systemCategoryMappings = null;
    _sections = <Map<String, dynamic>>[];
    notifyListeners();
  }
}
