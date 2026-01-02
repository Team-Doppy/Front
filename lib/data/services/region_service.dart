import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'auth_service.dart';
import 'base_api_service.dart';

/// Region 관리 서비스
/// JWT 토큰의 region 추출 및 업데이트를 담당
class RegionService {
  static final RegionService _instance = RegionService._internal();
  factory RegionService() => _instance;
  RegionService._internal();

  final AuthService _authService = AuthService();
  final BaseApiService _baseApiService = BaseApiService();

  /// JWT 토큰 문자열에서 region 정보 추출 (정적 메서드)
  /// [token] - JWT 토큰 문자열
  /// 반환: 'KR' 또는 'US', 실패 시 null
  static String? getRegionFromTokenString(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        debugPrint('[RegionService] Invalid token format');
        return null;
      }

      // JWT payload 디코딩
      final payload = parts[1];
      // Base64 패딩 추가
      String normalized = base64Url.normalize(payload);
      final decoded = base64Url.decode(normalized);
      final json = jsonDecode(utf8.decode(decoded));

      // region 필드 추출
      final region = json['region']?.toString();
      if (kDebugMode) {
        debugPrint('[RegionService] JWT 토큰에서 region 추출: $region');
      }
      return region;
    } catch (e, stackTrace) {
      debugPrint('[RegionService] 토큰에서 region 추출 실패: $e');
      debugPrint('[RegionService] Stack trace: $stackTrace');
      return null;
    }
  }

  /// JWT 토큰 문자열에서 region 정보 추출 (비동기 버전)
  /// 현재 저장된 토큰에서 region을 추출
  Future<String?> getRegionFromTokenAsync() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('[RegionService] 토큰이 없어서 region 추출 불가');
        return null;
      }

      if (kDebugMode) {
        debugPrint(
          '[RegionService] 토큰에서 region 추출 시도 (토큰 앞 20자: ${token.length > 20 ? token.substring(0, 20) : token}...)',
        );
      }
      final region = getRegionFromTokenString(token);
      if (kDebugMode) {
        debugPrint('[RegionService] 추출된 region: $region');
      }
      return region;
    } catch (e, stackTrace) {
      debugPrint('[RegionService] 토큰에서 region 추출 실패: $e');
      debugPrint('[RegionService] Stack trace: $stackTrace');
      return null;
    }
  }

  /// 사용자 region 업데이트 (언어 변경 시)
  /// 🎯 디버그 모드에서만 지원: 프로덕션에서는 처음 계정별로 한번 결정된 지역이 변하면 안됨
  /// [region] - 'KR' 또는 'US'
  /// 반환: 성공 여부
  Future<bool> updateUserRegion(String region) async {
    // 🎯 프로덕션에서 실수로 호출되는 것을 방지
    if (!kDebugMode) {
      debugPrint('[RegionService] ⚠️ updateUserRegion은 디버그 모드에서만 지원됩니다.');
      return false;
    }

    try {
      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('[RegionService] 토큰이 없습니다');
        return false;
      }

      debugPrint('[RegionService] Region 업데이트 시작: $region');
      debugPrint('[RegionService] Base URL: ${AuthService.baseUrl}');

      debugPrint('[RegionService] 요청 본문: {"region": "$region"}');

      // 🎯 BaseApiService의 dio를 사용하여 자동 토큰 갱신 지원
      final response = await _baseApiService.dio.patch(
        '/api/auth/update-region',
        data: {'region': region},
      );

      debugPrint('[RegionService] Region 업데이트 응답 상태: ${response.statusCode}');
      debugPrint('[RegionService] Region 업데이트 응답 본문: ${response.data}');

      // 🎯 200이 아닌 경우에도 응답 본문 로그 출력
      if (response.statusCode != 200) {
        debugPrint('[RegionService] ⚠️ Region 업데이트 실패 응답: ${response.data}');
      }

      if (response.statusCode == 200) {
        // 🎯 새 토큰 저장
        final responseData = response.data as Map<String, dynamic>;

        if (responseData['success'] == true && responseData['data'] != null) {
          final data = responseData['data'];

          // token (accessToken) - 서버 응답 형식: accessToken
          final token = data['accessToken'] ?? data['token'];
          if (token != null) {
            final newToken = token as String;
            await _authService.saveToken(newToken);
            debugPrint('[RegionService] 새 access token 저장 완료');
            debugPrint(
              '[RegionService] 새 토큰 앞 20자: ${newToken.length > 20 ? newToken.substring(0, 20) : newToken}...',
            );

            // 🎯 저장된 토큰에서 region 확인
            final savedTokenRegion = getRegionFromTokenString(newToken);
            debugPrint(
              '[RegionService] 저장된 새 토큰의 region: $savedTokenRegion (기대: $region)',
            );
            if (savedTokenRegion != region) {
              debugPrint('[RegionService] ⚠️ 경고: 저장된 토큰의 region이 기대값과 다름!');
            }
          }

          // refreshToken
          if (data['refreshToken'] != null) {
            await _authService.saveRefreshToken(data['refreshToken']);
            debugPrint('[RegionService] 새 refresh token 저장 완료');
          }

          // 사용자 정보도 업데이트
          if (data['username'] != null) {
            debugPrint(
              '[RegionService] 사용자: ${data['username']}, Region: ${data['region']}',
            );
          }

          debugPrint('[RegionService] Region 업데이트 성공: $region');
          return true;
        } else {
          debugPrint('[RegionService] Region 업데이트 실패: 응답 구조 오류');
          debugPrint('[RegionService] 응답 데이터: $responseData');
          return false;
        }
      } else {
        debugPrint('[RegionService] Region 업데이트 실패: ${response.statusCode}');
        debugPrint('[RegionService] 에러 메시지: ${response.data}');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('[RegionService] Region 업데이트 오류: $e');
      debugPrint('[RegionService] Stack trace: $stackTrace');
      return false;
    }
  }
}
