import 'package:flutter/material.dart';

/// 앱 번역 클래스
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  /// context에서 AppLocalizations 가져오기
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  /// 지원하는 언어 목록
  static const List<Locale> supportedLocales = [
    Locale('ko', 'KR'), // 한국어
    Locale('en', 'US'), // 영어
  ];

  /// 번역 맵
  static final Map<String, Map<String, String>> _localizedValues = {
    'ko': {
      // 공통
      'app_name': 'Doppy',
      'ok': '확인',
      'cancel': '취소',
      'save': '저장',
      'delete': '삭제',
      'edit': '수정',
      'back': '뒤로',
      'close': '닫기',
      'loading': '로딩 중...',
      'error': '오류',
      'success': '성공',
      'yes': '예',
      'no': '아니오',

      // 설정 화면
      'settings': '설정',
      'notification_settings': '알림 설정',
      'language_settings': '언어 설정',
      'theme_settings': '테마 설정',
      'favorites': '찜한 항목',
      'terms_of_service': '이용약관',
      'logout': '로그아웃',
      'logout_confirm': '로그아웃 하시겠습니까?',

      // 언어 선택
      'select_language': '언어 선택',
      'korean': '한국어',
      'english': 'English',
      'current_language': '현재 언어',

      // 피드
      'feed': '피드',
      'home': '홈',
      'search': '검색',
      'profile': '프로필',
      'notifications': '알림',
      'friends_posts': '친구글',
      'all_posts': '전체글',
      'search_placeholder': '무엇이든 검색해보세요',
      'search_hint': '검색',
      'no_results': '결과가 없습니다',
      'no_search_results': '검색 결과가 없습니다',
      'no_search_results_short': '검색 결과가 없어요',
      'no_results_for_query': '에 대한 결과가 없어요',
      'search_groups_friends': '그룹이나 친구를 검색해보세요',
      'load_failed': '불러올 수 없습니다',
      'friends_posts_load_failed': '친구글을 불러올 수 없습니다',
      'all_posts_load_failed': '전체글을 불러올 수 없습니다',
      'retry': '다시 시도',
      'users': '사용자',
      'contents': '콘텐츠',
      'recent_searches': '최근 검색',
      'clear_history': '검색 기록 삭제',
      'no_search_history': '최근 검색 기록이 없습니다',
      'searching': '검색 중...',
      'load_more': '더 보기',

      // 포스트
      'post': '포스트',
      'new_post': '새 포스트',
      'edit_post': '포스트 수정',
      'delete_post': '포스트 삭제',
      'delete_post_confirm': '이 포스트를 삭제하시겠습니까?',
      'like': '좋아요',
      'comment': '댓글',
      'comments': '댓글',
      'share': '공유',
      'views': '조회',

      // 글쓰기/수정
      'write_post': '글쓰기',
      'edit_mode': '수정하기',
      'title_hint': '제목을 입력하세요',
      'content_hint': '내용을 입력하세요',
      'publish': '게시',
      'next': '다음',
      'previous': '이전',
      'complete': '완료',
      'save_draft': '임시저장',
      'load_draft': '임시저장 불러오기',
      'draft_saved': '임시저장되었습니다',
      'discard_or_save_title': '작성 취소',
      'discard_or_save_message': '작성 중인 내용을 임시저장할까요?',
      'save_and_exit': '임시저장',
      'discard_without_save': '저장 안 함',
      'enter_title_first': '제목을 입력해주세요',
      'enter_content_first': '내용을 작성해주세요',
      'title_and_body_required': '제목과 본문을 입력해주세요.',
      'title_required': '제목을 입력해주세요.',
      'body_required': '본문을 입력해주세요.',
      'title_required_for_draft': '제목을 입력해야 임시저장할 수 있습니다.',
      'title_required_for_edit': '제목을 입력해야 수정할 수 있습니다.',
      'wait_for_media_upload': '업로드 대기',
      'media_still_uploading': '아직 업로드가 완료되지 않은 미디어가 있어요. 잠시만 기다려주세요.',
      'select_category': '카테고리 선택',
      'select_visibility': '공개 범위 선택',
      'visibility_public': '전체공개',
      'visibility_friends': '친구공개',
      'visibility_private': '나만보기',
      'visibility_group': '그룹공개',
      'select_thumbnail': '썸네일 선택',
      'uploading': '업로드 중...',
      'upload_complete': '업로드 완료',
      'confirm': '확인',
      'warning': '경고',
      'uploading_warning': '업로드 중인 미디어가 있습니다',
      'wait_for_upload': '업로드가 완료될 때까지 기다려주세요',
      'file_too_large_title': '파일이 너무 큽니다',
      'video_size_limit': '최대 100MB까지만 업로드 가능합니다',
      'image_size_limit': '최대 10MB까지만 업로드 가능합니다',
      'no_group_warning': '가입한 그룹이 없습니다',
      'create_group_first': '그룹을 먼저 생성해주세요',
      'edit_thumbnail': '썸네일 편집',
      'change_thumbnail': '썸네일 변경',
      'modify_complete': '수정 완료',
      'cancel_edit_title': '수정 취소',
      'cancel_edit_message': '수정 중인 내용이 사라집니다.\n정말 취소하시겠습니까?',
      'continue_editing': '계속 수정',
      'discard_draft_title': '작성 취소',
      'discard_draft_message': '작성 중인 내용이 사라집니다.\n정말 취소하시겠습니까?',
      'continue_writing': '계속 작성',
      'already_selected_category': '이미 선택된 카테고리예요',
      'category_changed': '카테고리가 변경되었습니다',
      'already_private': '이미 나만보기예요',
      'visibility_changed_private': '공개범위가 나만보기로 변경되었습니다',
      'visibility_changed_public': '공개범위가 전체공개로 변경되었습니다',
      'visibility_changed_friends': '공개범위가 친구공개로 변경되었습니다',
      'visibility_changed_group': '공개범위가 그룹공개로 변경되었습니다',
      'select_image': '이미지 선택',
      'select_video': 'short clip 선택',
      'tap_to_select_thumbnail': '눌러서 썸네일을 선택해주세요',
      'edit_thumbnail': '편집하기',
      'uploading_title': '업로드 중',
      'uploading_message': '아직 업로드 중입니다.\n취소하고 나가시겠어요?',
      'cancel_and_exit': '취소하고 나가기',
      'continue_upload': '계속 업로드',
      'has_changes_title': '변경사항이 있습니다',
      'has_changes_message': '썸네일 변경사항을 두고 나가시겠어요?',
      'exit': '나가기',
      'done': '완료',

      // 프로필
      'my_friends': '내 친구들',
      'share_profile': '프로필 공유',
      'follow': '팔로우',
      'following': '팔로잉',
      'followers': '팔로워',
      'posts_count': '게시물',
      'edit_profile': '프로필 편집',
      'all_friends': '전체 친구',
      'friend_requests': '친구 요청',
      'sent_requests': '보낸 요청',
      'received_requests': '받은 요청',
      'accept': '수락',
      'reject': '거절',
      'add_friend': '친구 추가',
      'remove_friend': '친구 삭제',
      'block_user': '차단하기',
      'report_user': '신고하기',
      'create_group': '그룹 생성',
      'add_group': '그룹 추가',
      'add_new_group_description': '새로운 그룹을 추가합니다',
      'manage_groups': '그룹 관리',
      'group_name': '그룹 이름',
      'group_description': '그룹 설명',
      'add_members': '멤버 추가',
      'remove_member': '멤버 삭제',
      'other_posts_by': '의 다른 글',

      // 댓글
      'write_comment': '댓글을 입력하세요',
      'reply': '답글',
      'edit_comment': '댓글 수정',
      'delete_comment': '댓글 삭제',

      // 인증
      'login': '로그인',
      'signup': '회원가입',
      'username': '사용자명',
      'password': '비밀번호',
      'email': '이메일',

      // 에러 메시지
      'network_error': '네트워크 오류가 발생했습니다',
      'unknown_error': '알 수 없는 오류가 발생했습니다',
      'file_too_large': '파일이 너무 큽니다',
      'upload_failed': '업로드 실패',
    },
    'en': {
      // Common
      'app_name': 'Doppy',
      'ok': 'OK',
      'cancel': 'Cancel',
      'save': 'Save',
      'delete': 'Delete',
      'edit': 'Edit',
      'back': 'Back',
      'close': 'Close',
      'loading': 'Loading...',
      'error': 'Error',
      'success': 'Success',
      'yes': 'Yes',
      'no': 'No',

      // Settings Screen
      'settings': 'Settings',
      'notification_settings': 'Notification Settings',
      'language_settings': 'Language Settings',
      'theme_settings': 'Theme Settings',
      'favorites': 'Favorites',
      'terms_of_service': 'Terms of Service',
      'logout': 'Logout',
      'logout_confirm': 'Are you sure you want to logout?',

      // Language Selection
      'select_language': 'Select Language',
      'korean': '한국어',
      'english': 'English',
      'current_language': 'Current Language',

      // Feed
      'feed': 'Feed',
      'home': 'Home',
      'search': 'Search',
      'profile': 'Profile',
      'notifications': 'Notifications',
      'friends_posts': 'Friends',
      'all_posts': 'All Posts',
      'search_placeholder': 'Search anything...',
      'search_hint': 'Search',
      'no_results': 'No results found',
      'no_search_results': 'No search results',
      'no_search_results_short': 'No search results',
      'no_results_for_query': ' - No results found',
      'search_groups_friends': 'Search for groups or friends',
      'load_failed': 'Failed to load',
      'friends_posts_load_failed': 'Failed to load friends posts',
      'all_posts_load_failed': 'Failed to load all posts',
      'retry': 'Retry',
      'users': 'Users',
      'contents': 'Contents',
      'recent_searches': 'Recent Searches',
      'clear_history': 'Clear History',
      'no_search_history': 'No search history',
      'searching': 'Searching...',
      'load_more': 'Load More',

      // Post
      'post': 'Post',
      'new_post': 'New Post',
      'edit_post': 'Edit Post',
      'delete_post': 'Delete Post',
      'delete_post_confirm': 'Are you sure you want to delete this post?',
      'like': 'Like',
      'comment': 'Comment',
      'comments': 'Comments',
      'share': 'Share',
      'views': 'Views',

      // Write/Edit Post
      'write_post': 'Write Post',
      'edit_mode': 'Edit',
      'title_hint': 'Enter title',
      'content_hint': 'Enter content',
      'publish': 'Publish',
      'next': 'Next',
      'previous': 'Previous',
      'complete': 'Complete',
      'save_draft': 'Save Draft',
      'load_draft': 'Load Draft',
      'draft_saved': 'Draft saved',
      'discard_or_save_title': 'Discard Draft',
      'discard_or_save_message': 'Do you want to save your draft?',
      'save_and_exit': 'Save Draft',
      'discard_without_save': 'Don\'t Save',
      'enter_title_first': 'Enter Title First',
      'enter_content_first': 'Enter Content First',
      'title_and_body_required': 'Please enter title and body.',
      'title_required': 'Please enter title.',
      'body_required': 'Please enter body.',
      'title_required_for_draft': 'A title is required to save draft.',
      'title_required_for_edit': 'A title is required to edit.',
      'wait_for_media_upload': 'Upload in Progress',
      'media_still_uploading': 'Media is still uploading. Please wait.',
      'select_category': 'Select Category',
      'select_visibility': 'Select Visibility',
      'visibility_public': 'Public',
      'visibility_friends': 'Friends Only',
      'visibility_private': 'Private',
      'visibility_group': 'Group',
      'select_thumbnail': 'Select Thumbnail',
      'uploading': 'Uploading...',
      'upload_complete': 'Upload Complete',
      'confirm': 'Confirm',
      'warning': 'Warning',
      'uploading_warning': 'Media is uploading',
      'wait_for_upload': 'Please wait for upload to complete',
      'file_too_large_title': 'File too large',
      'video_size_limit': 'Maximum 100MB allowed',
      'image_size_limit': 'Maximum 10MB allowed',
      'no_group_warning': 'No groups joined',
      'create_group_first': 'Please create a group first',
      'edit_thumbnail': 'Edit Thumbnail',
      'change_thumbnail': 'Change Thumbnail',
      'modify_complete': 'Modification Complete',
      'cancel_edit_title': 'Cancel Edit',
      'cancel_edit_message':
          'Your changes will be lost.\nAre you sure you want to cancel?',
      'continue_editing': 'Continue Editing',
      'discard_draft_title': 'Discard Draft',
      'discard_draft_message':
          'Your draft will be lost.\nAre you sure you want to discard?',
      'continue_writing': 'Continue Writing',
      'already_selected_category': 'This category is already selected',
      'category_changed': 'Category has been changed',
      'already_private': 'Already set to private',
      'visibility_changed_private': 'Visibility changed to private',
      'visibility_changed_public': 'Visibility changed to public',
      'visibility_changed_friends': 'Visibility changed to friends only',
      'visibility_changed_group': 'Visibility changed to group',
      'select_image': 'Select Image',
      'select_video': 'Select Short Clip',
      'tap_to_select_thumbnail': 'Tap to select thumbnail',
      'edit_thumbnail': 'Edit',
      'uploading_title': 'Uploading',
      'uploading_message':
          'Upload is in progress.\nDo you want to cancel and exit?',
      'cancel_and_exit': 'Cancel and Exit',
      'continue_upload': 'Continue Upload',
      'has_changes_title': 'You have changes',
      'has_changes_message': 'Do you want to exit without saving changes?',
      'exit': 'Exit',
      'done': 'Done',

      // Profile
      'my_friends': 'My Friends',
      'share_profile': 'Share Profile',
      'follow': 'Follow',
      'following': 'Following',
      'followers': 'Followers',
      'posts_count': 'Posts',
      'edit_profile': 'Edit Profile',
      'all_friends': 'All Friends',
      'friend_requests': 'Friend Requests',
      'sent_requests': 'Sent Requests',
      'received_requests': 'Received Requests',
      'accept': 'Accept',
      'reject': 'Reject',
      'add_friend': 'Add Friend',
      'remove_friend': 'Remove Friend',
      'block_user': 'Block User',
      'report_user': 'Report User',
      'create_group': 'Create Group',
      'add_group': 'Add Group',
      'add_new_group_description': 'Add a new group',
      'manage_groups': 'Manage Groups',
      'group_name': 'Group Name',
      'group_description': 'Group Description',
      'add_members': 'Add Members',
      'remove_member': 'Remove Member',
      'other_posts_by': '\'s other posts',

      // Comments
      'write_comment': 'Write a comment',
      'reply': 'Reply',
      'edit_comment': 'Edit Comment',
      'delete_comment': 'Delete Comment',

      // Auth
      'login': 'Login',
      'signup': 'Sign Up',
      'username': 'Username',
      'password': 'Password',
      'email': 'Email',

      // Error Messages
      'network_error': 'Network error occurred',
      'unknown_error': 'An unknown error occurred',
      'file_too_large': 'File is too large',
      'upload_failed': 'Upload failed',
    },
  };

  /// 번역 텍스트 가져오기
  String translate(String key) {
    final translations = _localizedValues[locale.languageCode];
    return translations?[key] ?? key;
  }

  /// 단축 메서드
  String t(String key) => translate(key);
}

/// LocalizationsDelegate
class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['ko', 'en'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

/// Extension for easy access
extension LocalizationExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String tr(String key) {
    try {
      final localizations = Localizations.of<AppLocalizations>(
        this,
        AppLocalizations,
      );
      if (localizations != null) {
        return localizations.translate(key);
      } else {
        print('[LocalizationExtension] localizations is null for key: $key');
      }
    } catch (e) {
      print('[LocalizationExtension] 번역 실패: $key - $e');
    }
    // 폴백: 키 그대로 반환
    return key;
  }
}
