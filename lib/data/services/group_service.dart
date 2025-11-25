import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
  Future<void> createGroup(
    String name, {
    String? description, // 🎯 그룹 설명
    String? profileImageUrl, // 🎯 프로필 이미지 URL
  }) async {
    try {
      debugPrint(
        '🔍 [GroupService] 그룹 생성 요청: name=$name, description=$description, profileImageUrl=$profileImageUrl',
      );

      final Map<String, dynamic> data = {
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (profileImageUrl != null && profileImageUrl.isNotEmpty)
          'groupImage': profileImageUrl,
      };

      final response = await _dio.post('/api/groups', data: data);
      debugPrint('📡 [GroupService] 그룹 생성 응답: ${response.statusCode}');

      if (response.statusCode != 200) throw Exception('그룹 생성 실패');
    } catch (e) {
      debugPrint('❌ [GroupService] 그룹 생성 에러: $e');
      if (e is DioException) {
        throw Exception('그룹 생성 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 18. 내가 소유한 그룹 목록 조회 (allFriends 메타데이터 포함)
  /// 반환값:
  /// (groups, allFriendsDisplayOrder, allFriendsImage, allFriendsGroupId,
  ///  totalFriendCount, allFriendsDescription, allFriendsPostCount)
  Future<(List<Group>, int, String?, int?, int?, String?, int?)>
  getMyGroups() async {
    try {
      debugPrint('🔍 [GroupService] 내가 소유한 그룹 목록 조회 시작');

      final response = await _dio.get('/api/groups/owned');
      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 헤더: ${response.headers}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final decoded = response.data;

        List<Group> groups;
        int allFriendsDisplayOrder = 0;
        String? allFriendsImage;
        int? allFriendsGroupId;
        int? totalFriendCount;
        String? allFriendsDescription;
        int? allFriendsPostCount;

        if (decoded is List) {
          // 🎯 리스트 형태인 경우 (구형 API 응답)
          groups =
              decoded.map<Group>((item) {
                // 각 항목이 { "group": { ... } } 형태로 래핑되어 있을 수 있음
                if (item is Map<String, dynamic> && item.containsKey('group')) {
                  return Group.fromJson(item['group'] as Map<String, dynamic>);
                }
                return Group.fromJson(item as Map<String, dynamic>);
              }).toList();
        } else if (decoded is Map<String, dynamic>) {
          // 🎯 객체 형태인 경우 (신형 API 응답)
          final dynamic groupsData =
              decoded['groups'] ??
              decoded['data'] ??
              decoded['content'] ??
              decoded['items'] ??
              decoded['results'];
          if (groupsData is List) {
            groups =
                groupsData.map<Group>((item) {
                  // 각 항목이 { "group": { ... } } 형태로 래핑되어 있을 수 있음
                  if (item is Map<String, dynamic> &&
                      item.containsKey('group')) {
                    return Group.fromJson(
                      item['group'] as Map<String, dynamic>,
                    );
                  }
                  return Group.fromJson(item as Map<String, dynamic>);
                }).toList();
          } else {
            debugPrint(
              '⚠️ [GroupService] 예상치 못한 응답 구조입니다. groups 배열을 찾지 못했습니다.',
            );
            groups = <Group>[];
          }

          // 🎯 allFriends 메타데이터 추출
          allFriendsDisplayOrder =
              (decoded['allFriendsDisplayOrder'] as num?)?.toInt() ?? 0;
          allFriendsImage =
              decoded['allFriendsImageUrl']?.toString() ??
              decoded['allFriendsImage']?.toString();
          final allFriendsGroupIdValue = decoded['allFriendsGroupId'];
          if (allFriendsGroupIdValue != null) {
            allFriendsGroupId =
                (allFriendsGroupIdValue as num?)?.toInt() ??
                (allFriendsGroupIdValue is int ? allFriendsGroupIdValue : null);
          }
          // 🎯 totalFriendCount 파싱
          totalFriendCount = (decoded['totalFriendCount'] as num?)?.toInt();
          // 🎯 allFriendsDescription 파싱
          allFriendsDescription = decoded['allFriendsDescription']?.toString();
          // 🎯 allFriendsPostCount 파싱 (전체 친구 그룹에 공유된 포스트 수)
          allFriendsPostCount =
              (decoded['allFriendsPostCount'] as num?)?.toInt();
        } else {
          debugPrint('⚠️ [GroupService] 알 수 없는 응답 형태입니다.');
          groups = <Group>[];
        }

        debugPrint('✅ [GroupService] 변환된 그룹 수: ${groups.length}');
        return (
          groups,
          allFriendsDisplayOrder,
          allFriendsImage,
          allFriendsGroupId,
          totalFriendCount,
          allFriendsDescription,
          allFriendsPostCount,
        );
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('내가 소유한 그룹 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 내가 소유한 그룹 목록 조회 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      } else if (e is FormatException) {
        debugPrint('❌ [GroupService] JSON 파싱 오류: $e');
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
      debugPrint('🔍 [GroupService] 그룹 멤버 목록 조회 시작 - 그룹ID: $groupId');

      final response = await _dio.get('/api/groups/$groupId/members');
      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 헤더: ${response.headers}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final decoded = response.data;
        debugPrint('✅ [GroupService] 파싱된 데이터 타입: ${decoded.runtimeType}');

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
            debugPrint(
              '⚠️ [GroupService] 예상치 못한 응답 구조입니다. members 배열을 찾지 못했습니다.',
            );
            members = <GroupMember>[];
          }
        } else {
          debugPrint('⚠️ [GroupService] 알 수 없는 응답 형태입니다.');
          members = <GroupMember>[];
        }

        debugPrint('✅ [GroupService] 변환된 멤버 수: ${members.length}');
        return members;
      } else if (response.statusCode == 403) {
        debugPrint('❌ [GroupService] 권한 없음: 소유자가 아닙니다');
        throw Exception('그룹 멤버 목록 조회 권한이 없습니다: 소유자가 아닙니다');
      } else if (response.statusCode == 404) {
        debugPrint('❌ [GroupService] 그룹을 찾을 수 없음');
        throw Exception('그룹을 찾을 수 없습니다');
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 멤버 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 그룹 멤버 목록 조회 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      } else if (e is FormatException) {
        debugPrint('❌ [GroupService] JSON 파싱 오류: $e');
      }
      rethrow;
    }
  }

  /// 22. 그룹에 멤버 추가
  Future<void> addMemberToGroup(int groupId, String userId) async {
    try {
      debugPrint(
        '🔍 [GroupService] 그룹 멤버 추가 시작 - 그룹ID: $groupId, 사용자ID: $userId',
      );

      final response = await _dio.post(
        '/api/groups/$groupId/members',
        data: {'userId': userId},
      );

      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        debugPrint('✅ [GroupService] 그룹 멤버 추가 성공');
        return;
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 멤버 추가 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 그룹 멤버 추가 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 23. 그룹에 여러 멤버 일괄 추가 (배치)
  /// POST /api/groups/{groupId}/members/batch
  /// Body: ["username1", "username2", "username3"]
  Future<void> addMultipleMembersToGroup(
    int groupId,
    List<String> usernames,
  ) async {
    try {
      debugPrint(
        '🔍 [GroupService] 그룹 멤버 일괄 추가 시작 - 그룹ID: $groupId, 사용자 수: ${usernames.length}',
      );
      debugPrint('🔍 [GroupService] 요청할 usernames: $usernames');

      final response = await _dio.post(
        '/api/groups/$groupId/members/batch',
        data: usernames, // username 배열을 JSON 배열로 직렬화하여 body로 전달
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        debugPrint('✅ [GroupService] 그룹 멤버 일괄 추가 성공');
        return;
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 멤버 일괄 추가 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 그룹 멤버 일괄 추가 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
        debugPrint('❌ [GroupService] 요청 URL: ${e.requestOptions.path}');
        debugPrint('❌ [GroupService] 요청 메서드: ${e.requestOptions.method}');
        debugPrint('❌ [GroupService] 요청 데이터: ${e.requestOptions.data}');
      }
      rethrow;
    }
  }

  /// 22. 그룹 삭제
  Future<void> deleteGroup(int groupId) async {
    try {
      debugPrint('🔍 [GroupService] 그룹 삭제 시작 - 그룹ID: $groupId');

      final response = await _dio.delete('/api/groups/$groupId');

      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        debugPrint('✅ [GroupService] 그룹 삭제 성공');
        return;
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 삭제 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 그룹 삭제 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 24. 그룹에서 멤버 제거
  Future<void> removeMemberFromGroup(int groupId, String userId) async {
    try {
      debugPrint(
        '🔍 [GroupService] 그룹 멤버 제거 시작 - 그룹ID: $groupId, 사용자ID: $userId',
      );

      final response = await _dio.delete(
        '/api/groups/$groupId/members/$userId',
      );

      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        debugPrint('✅ [GroupService] 그룹 멤버 제거 성공');
        return;
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 멤버 제거 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 그룹 멤버 제거 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 25. 그룹에서 여러 멤버 일괄 제거 (배치)
  /// DELETE /api/groups/{groupId}/members/batch
  /// Body: ["username1", "username2", "username3"]
  Future<void> removeMembersFromGroupBatch(
    int groupId,
    List<String> usernames,
  ) async {
    try {
      debugPrint(
        '🔍 [GroupService] 그룹 멤버 일괄 제거 시작 - 그룹ID: $groupId, 사용자 수: ${usernames.length}',
      );
      debugPrint('🔍 [GroupService] 요청할 usernames: $usernames');

      // 🎯 DELETE 메서드에 body를 전달할 때는 options를 사용
      final response = await _dio.delete(
        '/api/groups/$groupId/members/batch',
        data: usernames, // username 배열을 JSON 배열로 직렬화하여 body로 전달
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        debugPrint('✅ [GroupService] 그룹 멤버 일괄 제거 성공');
        return;
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 멤버 일괄 제거 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 그룹 멤버 일괄 제거 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
        debugPrint('❌ [GroupService] 요청 URL: ${e.requestOptions.path}');
        debugPrint('❌ [GroupService] 요청 메서드: ${e.requestOptions.method}');
        debugPrint('❌ [GroupService] 요청 데이터: ${e.requestOptions.data}');
      }
      rethrow;
    }
  }

  /// 26. 전체 친구 그룹 수정 (설명, 이미지만)
  Future<Map<String, dynamic>> updateAllFriendsGroup({
    String? description,
    String? groupImage,
  }) async {
    try {
      debugPrint('🔍 [GroupService] 전체 친구 그룹 수정 시작');
      debugPrint('🔍 [GroupService] 새 설명: $description, 이미지: $groupImage');

      final Map<String, dynamic> body = {};
      // 🎯 description 처리: null이 아니면 빈 문자열 포함하여 그대로 전송
      if (description != null) {
        body['description'] = description; // 빈 문자열 포함하여 그대로 전송
      }
      // description이 null이면 필드 생략 (변경하지 않음)

      // 🎯 이미지 처리: 빈 문자열이면 빈 문자열로 전송 (기본 이미지), 값이 있으면 포함
      if (groupImage != null) {
        body['groupImage'] = groupImage; // 빈 문자열 포함하여 그대로 전송
      }
      // groupImage가 null이면 필드 생략 (변경하지 않음)

      final response = await _dio.put('/api/groups/all-friends', data: body);

      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final responseData = response.data;
        debugPrint('✅ [GroupService] 전체 친구 그룹 수정 성공');
        return responseData;
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('전체 친구 그룹 수정 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 전체 친구 그룹 수정 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 3. 그룹 수정 (이름, 설명, 이미지)
  Future<Map<String, dynamic>> updateGroup(
    int groupId,
    String name,
    String description, {
    String? profileImageUrl, // 🎯 프로필 이미지 URL
  }) async {
    try {
      debugPrint('🔍 [GroupService] 그룹 수정 시작 - 그룹ID: $groupId');
      debugPrint(
        '🔍 [GroupService] 새 이름: $name, 새 설명: $description, 이미지: $profileImageUrl',
      );

      final Map<String, dynamic> body = {
        'name': name,
        'description': description,
      };

      // 🎯 이미지 URL 처리: 빈 문자열이면 빈 문자열로 전송 (기본 이미지), 값이 있으면 포함
      if (profileImageUrl != null) {
        body['groupImage'] = profileImageUrl; // 빈 문자열 포함하여 그대로 전송
      }
      // profileImageUrl이 null이면 필드 생략 (변경하지 않음)

      final response = await _dio.put('/api/groups/$groupId', data: body);

      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final responseData = response.data;
        debugPrint('✅ [GroupService] 그룹 수정 성공');
        return responseData;
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 수정 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 그룹 수정 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 25. 그룹 정보 조회
  Future<Group> getGroup(int groupId) async {
    try {
      debugPrint('🔍 [GroupService] 그룹 정보 조회 시작 - 그룹ID: $groupId');

      final response = await _dio.get('/api/groups/$groupId');
      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data;
        debugPrint('✅ [GroupService] 파싱된 데이터: $data');

        final group = Group.fromJson(data['group'] ?? data);
        debugPrint('✅ [GroupService] 그룹 정보 조회 성공');
        return group;
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 정보 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 그룹 정보 조회 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 26. 그룹 순서 변경 (드래그 앤 드롭)
  ///
  /// [groups] - 그룹 순서 정보 리스트
  /// 각 항목: { "groupId": 1, "displayOrder": 0 }
  ///
  /// 응답: 변경된 그룹 목록 (displayOrder 반영)
  Future<List<Group>> reorderGroups(List<Map<String, dynamic>> groups) async {
    try {
      debugPrint('🔍 [GroupService] 그룹 순서 변경 시작 - 그룹 수: ${groups.length}');

      final response = await _dio.patch(
        '/api/groups/reorder',
        data: {'groups': groups},
      );

      debugPrint('📡 [GroupService] API 응답 상태: ${response.statusCode}');
      debugPrint('📡 [GroupService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final decoded = response.data;
        List<Group> reorderedGroups;

        if (decoded is List) {
          reorderedGroups =
              decoded.map<Group>((item) {
                if (item is Map<String, dynamic> && item.containsKey('group')) {
                  return Group.fromJson(item['group'] as Map<String, dynamic>);
                }
                return Group.fromJson(item as Map<String, dynamic>);
              }).toList();
        } else if (decoded is Map<String, dynamic>) {
          final dynamic groupsData =
              decoded['groups'] ??
              decoded['data'] ??
              decoded['content'] ??
              decoded['items'] ??
              decoded['results'];
          if (groupsData is List) {
            reorderedGroups =
                groupsData.map<Group>((item) {
                  if (item is Map<String, dynamic> &&
                      item.containsKey('group')) {
                    return Group.fromJson(
                      item['group'] as Map<String, dynamic>,
                    );
                  }
                  return Group.fromJson(item as Map<String, dynamic>);
                }).toList();
          } else {
            debugPrint(
              '⚠️ [GroupService] 예상치 못한 응답 구조입니다. groups 배열을 찾지 못했습니다.',
            );
            reorderedGroups = <Group>[];
          }
        } else {
          debugPrint('⚠️ [GroupService] 알 수 없는 응답 형태입니다.');
          reorderedGroups = <Group>[];
        }

        debugPrint(
          '✅ [GroupService] 그룹 순서 변경 성공 - ${reorderedGroups.length}개 그룹',
        );
        return reorderedGroups;
      } else {
        debugPrint(
          '❌ [GroupService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('그룹 순서 변경 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [GroupService] 그룹 순서 변경 중 예외 발생: $e');
      if (e is DioException) {
        debugPrint(
          '❌ [GroupService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }
}
