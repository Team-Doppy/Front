import 'package:flutter/foundation.dart';
import 'military_info_model.dart';
import 'girlfriend_request_model.dart';

class User {
  final int? id; // ✅ 서버 user id (API 명세: recipientUserId는 Long 타입)
  final String username;
  final String? role;
  final String? alias; // alias 필드 추가
  final String? pairAlias; // 🎯 커플 애칭 (짝궁 이름)
  final String? profileImageUrl;
  final List<String>? links; // 🎯 프로필 링크 목록
  final Map<String, String>? linkTitles; // 🎯 링크 타이틀 (URL -> 타이틀)
  final Map<String, String>? linkThumbnails; // 🎯 링크 썸네일 (URL -> thumbnailUrl)
  final int? friendCount;
  final bool? onboardingCompleted; // 🎯 서버에서 온보딩 완료 여부
  final MilitaryInfo? militaryInfo; // 🎯 군인 정보 (군도피 모드)
  final User? connectedMilitaryUser; // 🎯 곰신일 때 연결된 군인(남친) 정보
  final User? connectedToMeByUser; // 🎯 군인/입대예정일 때 나를 연결한 곰신 정보
  final GirlfriendRequest? girlfriendRequest; // 🎯 곰신 요청 정보 (상태 포함)

  User({
    this.id, // ✅ 서버 user id
    required this.username,
    this.role,
    this.alias,
    this.pairAlias,
    this.profileImageUrl,
    this.links,
    this.linkTitles,
    this.linkThumbnails,
    this.friendCount,
    this.onboardingCompleted,
    this.militaryInfo,
    this.connectedMilitaryUser,
    this.connectedToMeByUser,
    this.girlfriendRequest,
  });

  /// MilitaryInfo 파싱을 안전하게 처리 (에러 발생 시 null 반환)
  /// [isConnectedMilitaryUser]: connectedMilitaryUser의 militaryInfo인 경우 true
  static MilitaryInfo? _parseMilitaryInfoSafely(
    Map<String, dynamic> json, {
    bool isConnectedMilitaryUser = false,
  }) {
    try {
      // ✅ connectedMilitaryUser의 militaryInfo는 userType이 없을 수 있으므로 명시적으로 설정
      if (isConnectedMilitaryUser && json['userType'] == null) {
        json = Map<String, dynamic>.from(json);
        json['userType'] = 'military'; // 연결된 남친은 항상 군인
      }
      return MilitaryInfo.fromJson(json);
    } catch (e, stackTrace) {
      debugPrint('❌ [User] MilitaryInfo 파싱 실패: $e');
      debugPrint('❌ [User] Stack trace: $stackTrace');
      debugPrint('❌ [User] JSON 데이터: $json');
      // 서버 데이터가 불완전할 수 있으므로 null 반환
      return null;
    }
  }

  factory User.fromJson(Map<String, dynamic> json) {
    // 🎯 links 필드 처리 (배열 또는 null)
    List<String>? links;
    if (json['links'] != null) {
      if (json['links'] is List) {
        links =
            (json['links'] as List)
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList();
      } else if (json['links'] is String) {
        // 문자열인 경우 파싱 시도
        final linksStr = json['links'] as String;
        if (linksStr.isNotEmpty) {
          links =
              linksStr
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
        }
      }
    }

    // 🎯 linkTitles 필드 처리 (Map<String, String> 또는 null)
    Map<String, String>? linkTitles;
    if (json['linkTitles'] != null) {
      if (json['linkTitles'] is Map) {
        linkTitles = Map<String, String>.from(
          (json['linkTitles'] as Map).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        );
      }
    }

    // 🎯 linkThumbnails 필드 처리 (Map<String, String> 또는 null)
    Map<String, String>? linkThumbnails;
    if (json['linkThumbnails'] != null) {
      if (json['linkThumbnails'] is Map) {
        linkThumbnails = Map<String, String>.from(
          (json['linkThumbnails'] as Map).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        );
      }
    }

    // 🎯 connectedMilitaryUser 파싱 (곰신일 때 연결된 군인 정보)
    User? connectedMilitaryUser;
    if (json['connectedMilitaryUser'] != null) {
      final connectedUserJson = Map<String, dynamic>.from(
        json['connectedMilitaryUser'] as Map<String, dynamic>,
      );
      debugPrint(
        '[User.fromJson] connectedMilitaryUser 파싱 시작: '
        'username=${connectedUserJson['username']}, '
        'militaryInfo=${connectedUserJson['militaryInfo']}',
      );

      // ✅ connectedMilitaryUser의 militaryInfo에 userType과 status가 없을 수 있으므로 추가
      if (connectedUserJson['militaryInfo'] != null) {
        final militaryInfoJson = Map<String, dynamic>.from(
          connectedUserJson['militaryInfo'] as Map<String, dynamic>,
        );
        if (militaryInfoJson['userType'] == null) {
          militaryInfoJson['userType'] = 'military'; // 연결된 남친은 항상 군인
          debugPrint(
            '[User.fromJson] connectedMilitaryUser.militaryInfo에 userType 추가: military',
          );
        }
        // ✅ status가 없으면 enlistmentDate를 기반으로 추론
        if (militaryInfoJson['status'] == null) {
          if (militaryInfoJson['enlistmentDate'] != null) {
            militaryInfoJson['status'] = 'afterEnlistment'; // 입대일이 있으면 입대 후
            debugPrint(
              '[User.fromJson] connectedMilitaryUser.militaryInfo에 status 추가: afterEnlistment',
            );
          } else if (militaryInfoJson['plannedEnlistmentDate'] != null) {
            militaryInfoJson['status'] = 'beforeEnlistment'; // 예정 입대일만 있으면 입대 전
            debugPrint(
              '[User.fromJson] connectedMilitaryUser.militaryInfo에 status 추가: beforeEnlistment',
            );
          }
        }
        connectedUserJson['militaryInfo'] = militaryInfoJson;
      }

      connectedMilitaryUser = User.fromJson(connectedUserJson);
      debugPrint(
        '[User.fromJson] connectedMilitaryUser 파싱 완료: '
        'username=${connectedMilitaryUser.username}, '
        'militaryInfo=${connectedMilitaryUser.militaryInfo != null ? "있음 (${connectedMilitaryUser.militaryInfo!.status}, rank=${connectedMilitaryUser.militaryInfo!.currentRank})" : "없음"}',
      );
    }

    // 🎯 connectedToMeByUser 파싱 (군인/입대예정일 때 나를 연결한 곰신 정보)
    User? connectedToMeByUser;
    if (json['connectedToMeByUser'] != null) {
      connectedToMeByUser = User.fromJson(
        json['connectedToMeByUser'] as Map<String, dynamic>,
      );
    }

    // 🎯 girlfriendRequest 파싱 (곰신 요청 정보)
    GirlfriendRequest? girlfriendRequest;
    if (json['girlfriendRequest'] != null) {
      try {
        girlfriendRequest = GirlfriendRequest.fromJson(
          json['girlfriendRequest'] as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('[User.fromJson] girlfriendRequest 파싱 실패: $e');
        girlfriendRequest = null;
      }
    }

    return User(
      id: (json['id'] ?? json['userId'] ?? json['user_id']) as int?,
      username: (json['username'] ?? json['userId'] ?? '').toString(),
      role: json['role']?.toString(),
      alias: json['alias']?.toString(),
      pairAlias: json['pairAlias']?.toString(),
      profileImageUrl:
          json['profileImageUrl']?.toString() ?? json['imageUrl']?.toString(),

      links: links,
      linkTitles: linkTitles,
      linkThumbnails: linkThumbnails,
      friendCount: (json['friendCount'] as num?)?.toInt(),
      onboardingCompleted: json['onboardingCompleted'] as bool?,
      militaryInfo: () {
        if (json['militaryInfo'] != null) {
          debugPrint(
            '[User.fromJson] militaryInfo 발견: ${json['militaryInfo']}',
          );
          final parsed = _parseMilitaryInfoSafely(
            json['militaryInfo'] as Map<String, dynamic>,
            isConnectedMilitaryUser: false, // 자신의 militaryInfo
          );
          debugPrint('[User.fromJson] militaryInfo 파싱 결과: $parsed');
          return parsed;
        } else {
          debugPrint('[User.fromJson] militaryInfo가 JSON에 없음');
          return null;
        }
      }(),
      connectedMilitaryUser: connectedMilitaryUser,
      connectedToMeByUser: connectedToMeByUser,
      girlfriendRequest: girlfriendRequest,
    );
  }

  User copyWith({
    int? id, // ✅ 서버 user id
    String? username,
    String? role,
    String? alias,
    String? pairAlias,
    String? profileImageUrl,
    String? selfIntroduction,
    List<String>? links,
    Map<String, String>? linkTitles,
    Map<String, String>? linkThumbnails,
    int? friendCount,
    bool? onboardingCompleted,
    MilitaryInfo? militaryInfo,
    User? connectedMilitaryUser,
    User? connectedToMeByUser,
    GirlfriendRequest? girlfriendRequest,
  }) {
    return User(
      id: id ?? this.id, // ✅ 서버 user id
      username: username ?? this.username,
      role: role ?? this.role,
      alias: alias ?? this.alias,
      pairAlias: pairAlias ?? this.pairAlias,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,

      links: links ?? this.links,
      linkTitles: linkTitles ?? this.linkTitles,
      linkThumbnails: linkThumbnails ?? this.linkThumbnails,
      friendCount: friendCount ?? this.friendCount,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      militaryInfo: militaryInfo ?? this.militaryInfo,
      connectedMilitaryUser:
          connectedMilitaryUser ?? this.connectedMilitaryUser,
      connectedToMeByUser: connectedToMeByUser ?? this.connectedToMeByUser,
      girlfriendRequest: girlfriendRequest ?? this.girlfriendRequest,
    );
  }

  /// JSON으로 변환 (로컬 캐싱용)
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id, // ✅ 서버 user id
      'username': username,
      if (role != null) 'role': role,
      if (alias != null) 'alias': alias,
      if (pairAlias != null) 'pairAlias': pairAlias,
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      if (links != null) 'links': links,
      if (linkTitles != null) 'linkTitles': linkTitles,
      if (linkThumbnails != null) 'linkThumbnails': linkThumbnails,
      if (friendCount != null) 'friendCount': friendCount,
      if (onboardingCompleted != null)
        'onboardingCompleted': onboardingCompleted,
      if (militaryInfo != null) 'militaryInfo': militaryInfo!.toJson(),
      if (connectedMilitaryUser != null)
        'connectedMilitaryUser': connectedMilitaryUser!.toJson(),
      if (connectedToMeByUser != null)
        'connectedToMeByUser': connectedToMeByUser!.toJson(),
      if (girlfriendRequest != null)
        'girlfriendRequest': girlfriendRequest!.toJson(),
    };
  }
}
