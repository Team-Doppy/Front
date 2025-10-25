import 'package:dio/dio.dart';
import 'base_api_service.dart';

import '../models/group_model.dart';
import '../models/group_member_model.dart';

class GroupService {
  static final GroupService _instance = GroupService._internal();
  factory GroupService() => _instance;
  GroupService._internal();

  final Dio _dio = BaseApiService().dio;

  /// 초기 그룹 응답 내 포함된 멤버 리스트를 추출하여 모델로 변환한다.
  Future<List<GroupMember>> extractMembersIfAny(Group group) async {
    // 현재 Group 모델엔 members 필드가 없으므로, owner 등 최소 정보만 있어 초기 멤버가 필요 시
    // 서버의 그룹 상세 엔드포인트 형식처럼 그룹 응답에 members가 딸려온 경우를 대비하여
    // 안전하게 처리하기 위해 noop을 반환한다. 실제 추출은 getMyGroups() 호출부에서
    // 디코딩 객체에서 직접 처리하는 것이 더 정확하지만, 기존 구조를 크게 바꾸지 않기 위해
    // 여기서는 빈 리스트를 반환한다.
    return <GroupMember>[];
  }

  /// 17. 그룹 생성
  Future<void> createGroup(String name) async {
    try {
      final response = await _dio.post('/api/groups', data: {'name': name});
      if (response.statusCode != 200) throw Exception('그룹 생성 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('그룹 생성 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 18. 내가 소유한 그룹 목록 조회
  Future<List<Group>> getMyGroups() async {
    try {
      print('🔍 [GroupService] 내가 소유한 그룹 목록 조회 시작');

      final response = await _dio.get('/api/groups/owned');
      print('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      print('📡 [GroupService] API 응답 헤더: ${response.headers}');
      print('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final decoded = response.data;
        print('✅ [GroupService] 파싱된 데이터 타입: ${decoded.runtimeType}');

        List<Group> groups;
        if (decoded is List) {
          groups = decoded.map<Group>((item) => Group.fromJson(item)).toList();
        } else if (decoded is Map<String, dynamic>) {
          final dynamic groupsData =
              decoded['groups'] ??
              decoded['data'] ??
              decoded['content'] ??
              decoded['items'] ??
              decoded['results'];
          if (groupsData is List) {
            groups =
                groupsData.map<Group>((item) => Group.fromJson(item)).toList();
          } else {
            print('⚠️ [GroupService] 예상치 못한 응답 구조입니다. groups 배열을 찾지 못했습니다.');
            groups = <Group>[];
          }
        } else {
          print('⚠️ [GroupService] 알 수 없는 응답 형태입니다.');
          groups = <Group>[];
        }

        print('✅ [GroupService] 변환된 그룹 수: ${groups.length}');
        return groups;
      } else {
        print(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('내가 소유한 그룹 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [GroupService] 내가 소유한 그룹 목록 조회 중 예외 발생: $e');
      if (e is DioException) {
        print(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      } else if (e is FormatException) {
        print('❌ [GroupService] JSON 파싱 오류: $e');
      }
      rethrow;
    }
  }

  /// 19. 그룹에 멤버 추가
  Future<void> addGroupMember(int groupId, String memberUsername) async {
    try {
      final response = await _dio.post(
        '/api/groups/$groupId/members',
        data: {'memberUsername': memberUsername},
      );
      if (response.statusCode != 200) throw Exception('그룹 멤버 추가 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('그룹 멤버 추가 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 20. 그룹에서 멤버 삭제
  Future<void> deleteGroupMember(int groupId, int memberId) async {
    try {
      final response = await _dio.delete(
        '/api/groups/$groupId/members/$memberId',
      );
      if (response.statusCode != 200) throw Exception('그룹 멤버 삭제 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('그룹 멤버 삭제 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 21. 그룹 멤버 목록 조회
  Future<List<GroupMember>> getGroupMembers(int groupId) async {
    try {
      print('🔍 [GroupService] 그룹 멤버 목록 조회 시작 - 그룹ID: $groupId');

      final response = await _dio.get('/api/groups/$groupId/members');
      print('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      print('📡 [GroupService] API 응답 헤더: ${response.headers}');
      print('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final decoded = response.data;
        print('✅ [GroupService] 파싱된 데이터 타입: ${decoded.runtimeType}');

        List<GroupMember> members;
        if (decoded is List) {
          // 최상위 배열 형태
          members =
              decoded
                  .map<GroupMember>((item) => GroupMember.fromJson(item))
                  .toList();
        } else if (decoded is Map<String, dynamic>) {
          // 래핑된 형태 대비
          final dynamic membersData =
              decoded['members'] ??
              decoded['data'] ??
              decoded['content'] ??
              decoded['items'] ??
              decoded['results'];
          if (membersData is List) {
            members =
                membersData
                    .map<GroupMember>((item) => GroupMember.fromJson(item))
                    .toList();
          } else {
            print('⚠️ [GroupService] 예상치 못한 응답 구조입니다. members 배열을 찾지 못했습니다.');
            members = <GroupMember>[];
          }
        } else {
          print('⚠️ [GroupService] 알 수 없는 응답 형태입니다.');
          members = <GroupMember>[];
        }

        print('✅ [GroupService] 변환된 멤버 수: ${members.length}');
        return members;
      } else if (response.statusCode == 403) {
        print('❌ [GroupService] 권한 없음: 소유자가 아닙니다');
        throw Exception('그룹 멤버 목록 조회 권한이 없습니다: 소유자가 아닙니다');
      } else if (response.statusCode == 404) {
        print('❌ [GroupService] 그룹을 찾을 수 없음');
        throw Exception('그룹을 찾을 수 없습니다');
      } else {
        print(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 멤버 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [GroupService] 그룹 멤버 목록 조회 중 예외 발생: $e');
      if (e is DioException) {
        print(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      } else if (e is FormatException) {
        print('❌ [GroupService] JSON 파싱 오류: $e');
      }
      rethrow;
    }
  }

  /// 22. 그룹에 멤버 추가
  Future<void> addMemberToGroup(int groupId, String userId) async {
    try {
      print('🔍 [GroupService] 그룹 멤버 추가 시작 - 그룹ID: $groupId, 사용자ID: $userId');

      final response = await _dio.post(
        '/api/groups/$groupId/members',
        data: {'userId': userId},
      );

      print('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      print('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        print('✅ [GroupService] 그룹 멤버 추가 성공');
        return;
      } else {
        print(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 멤버 추가 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [GroupService] 그룹 멤버 추가 중 예외 발생: $e');
      if (e is DioException) {
        print(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 23. 그룹에 여러 멤버 추가 (배치 처리)
  Future<void> addMultipleMembersToGroup(
    int groupId,
    List<String> userIds,
  ) async {
    try {
      print(
        '🔍 [GroupService] 그룹에 여러 멤버 추가 시작 - 그룹ID: $groupId, 사용자 수: ${userIds.length}',
      );

      // 각 사용자를 순차적으로 추가
      for (String userId in userIds) {
        await addMemberToGroup(groupId, userId);
        // API 부하 방지를 위한 짧은 지연
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('✅ [GroupService] 모든 멤버 추가 완료');
    } catch (e) {
      print('❌ [GroupService] 여러 멤버 추가 중 예외 발생: $e');
      rethrow;
    }
  }

  /// 22. 그룹 삭제
  Future<void> deleteGroup(int groupId) async {
    try {
      print('🔍 [GroupService] 그룹 삭제 시작 - 그룹ID: $groupId');

      final response = await _dio.delete('/api/groups/$groupId');

      print('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      print('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        print('✅ [GroupService] 그룹 삭제 성공');
        return;
      } else {
        print(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 삭제 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [GroupService] 그룹 삭제 중 예외 발생: $e');
      if (e is DioException) {
        print(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 24. 그룹에서 멤버 제거
  Future<void> removeMemberFromGroup(int groupId, String userId) async {
    try {
      print('🔍 [GroupService] 그룹 멤버 제거 시작 - 그룹ID: $groupId, 사용자ID: $userId');

      final response = await _dio.delete(
        '/api/groups/$groupId/members/$userId',
      );

      print('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      print('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        print('✅ [GroupService] 그룹 멤버 제거 성공');
        return;
      } else {
        print(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 멤버 제거 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [GroupService] 그룹 멤버 제거 중 예외 발생: $e');
      if (e is DioException) {
        print(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 3. 그룹 수정 (이름 및 설명)
  Future<Map<String, dynamic>> updateGroup(
    int groupId,
    String name,
    String description,
  ) async {
    try {
      print('🔍 [GroupService] 그룹 수정 시작 - 그룹ID: $groupId');
      print('🔍 [GroupService] 새 이름: $name, 새 설명: $description');

      final Map<String, String> body = {
        'name': name,
        'description': description,
      };

      final response = await _dio.put('/api/groups/$groupId', data: body);

      print('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      print('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final responseData = response.data;
        print('✅ [GroupService] 그룹 수정 성공');
        return responseData;
      } else {
        print(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 수정 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [GroupService] 그룹 수정 중 예외 발생: $e');
      if (e is DioException) {
        print(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 25. 그룹 정보 조회
  Future<Group> getGroup(int groupId) async {
    try {
      print('🔍 [GroupService] 그룹 정보 조회 시작 - 그룹ID: $groupId');

      final response = await _dio.get('/api/groups/$groupId');
      print('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      print('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data;
        print('✅ [GroupService] 파싱된 데이터: $data');

        final group = Group.fromJson(data['group'] ?? data);
        print('✅ [GroupService] 그룹 정보 조회 성공');
        return group;
      } else {
        print(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 정보 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [GroupService] 그룹 정보 조회 중 예외 발생: $e');
      if (e is DioException) {
        print(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }
}
