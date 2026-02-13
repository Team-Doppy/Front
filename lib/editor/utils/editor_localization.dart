import 'package:flutter/material.dart';

/// 지원하는 언어
enum EditorLocale {
  korean('ko', '한국어'),
  english('en', 'English');

  final String code;
  final String displayName;

  const EditorLocale(this.code, this.displayName);
}

/// 에디터 패키지에서 사용하는 번역 키와 기본 한국어 번역
///
/// 번역 키는 직관적이고 공통 키를 최대한 재사용하도록 구성
/// 패키지화 시 이 번역 키들을 외부 번역 파일에 매핑하여 사용
class EditorTranslations {
  EditorTranslations._();

  /// 현재 언어 설정
  static EditorLocale _currentLocale = EditorLocale.korean;

  /// 현재 언어 설정 가져오기
  static EditorLocale get currentLocale => _currentLocale;

  /// 언어 설정 변경
  static void setLocale(EditorLocale locale) {
    _currentLocale = locale;
  }

  /// 언어 코드로 언어 설정
  static void setLocaleByCode(String code) {
    _currentLocale = EditorLocale.values.firstWhere(
      (locale) => locale.code == code,
      orElse: () => EditorLocale.korean,
    );
  }

  /// 에디터 패키지 번역 맵 (한국어)
  static const Map<String, String> _translationsKo = {
    // ========== 공통 버튼/액션 ==========
    'editor_save': '저장',
    'editor_cancel': '취소',
    'editor_delete': '삭제',
    'editor_exit': '나가기',
    'editor_next': '다음',
    'editor_close': '닫기',
    'close': '닫기',
    'drafts': '임시저장',
    'editor_confirm': '확인',
    'editor_add': '추가',
    'editor_modify': '수정',
    'editor_search': '검색',
    'editor_loading': '로딩 중...',

    // ========== 공통 메시지 ==========
    'editor_error': '오류',
    'editor_error_occurred': '오류가 발생했습니다',
    'editor_success': '성공',
    'editor_notification': '알림',
    'editor_uploading': '업로드 중...',
    'editor_wait': '대기 중...',
    'editor_upload_wait': '업로드가 완료될 때까지 기다려주세요.',

    //=========== 노드 관련 ==========
    'drop_here': '여기에 넣기',

    // ========== 드래프트 관련 ==========
    'editor_draft': '임시저장',
    'editor_drafts': '임시저장 목록',
    'editor_save_draft': '임시저장',
    'editor_load_draft': '임시저장 불러오기',
    'editor_draft_saved': '임시저장되었습니다',
    'editor_draft_save_failed': '임시저장에 실패했습니다',
    'editor_draft_load_failed': '임시저장을 불러오는데 실패했습니다',
    'editor_draft_list_failed': '임시저장 목록을 불러오는데 실패했습니다',
    'editor_no_drafts': '임시저장이 없습니다',
    'editor_delete_draft_confirm_title': '임시저장 삭제',
    'editor_delete_draft_confirm_message': '이 임시저장을 삭제하시겠습니까?',
    'delete_draft_confirm_title': '임시저장 삭제',
    'delete_draft_confirm_message': '이 임시저장을 삭제하시겠습니까?',
    'delete': '삭제',
    'editor_post_delete_confirm_title': '포스트 삭제',
    'editor_post_delete_confirm_message': '포스트가 영구 삭제됩니다.\n삭제하시겠습니까?',

    // ========== 콘텐츠 검증 ==========
    'editor_body_required': '본문을 입력해주세요',
    'editor_title_required': '제목을 입력해주세요',
    'editor_content_required': '내용을 입력해주세요',
    'editor_thumbnail_required': '썸네일을 선택해주세요',

    // ========== 나가기/저장 다이얼로그 ==========
    'editor_discard_or_save_title': '작성중인 글이 있습니다',
    'editor_discard_or_save_message': '변경사항이 저장되지 않습니다',
    'editor_save_and_exit': '임시저장',
    'editor_discard_without_save': '나가기',
    'editor_exit_writing_title': '작성중인 글이 있습니다',
    'editor_exit_writing_message': '작성 중인 내용이 사라질 수 있습니다',
    'editor_continue_writing': '계속 작성하기',
    'editor_cancel_edit_title': '수정을 취소할까요?',
    'editor_cancel_edit_message': '수정 중인 내용이 사라질 수 있습니다',
    'editor_finish_edit': '수정완료',

    // ========== 미디어 업로드 ==========
    'editor_wait_for_media_upload': '미디어 업로드 대기',
    'editor_media_still_uploading': '미디어가 아직 업로드 중입니다',
    'editor_image_uploading': '이미지 업로드 중...',
    'editor_upload_failed': '업로드에 실패했습니다',
    'editor_load_failed': '불러오는데 실패했습니다',
    'editor_image_edit_failed': '이미지 편집에 실패했습니다',
    'editor_selection_limit': '선택 개수 제한을 초과했습니다',

    // ========== 발행/수정 관련 ==========
    'editor_publish': '발행',
    'editor_publish_failed': '게시에 실패했습니다',
    'editor_thumbnail_upload_required': '썸네일 업로드가 필요합니다',
    'editor_modify_complete': '수정 완료',
    'editor_edit_failed': '수정에 실패했습니다',

    // ========== 공개 범위 ==========
    'editor_public': '전체공개',
    'editor_private': '나만보기',
    'editor_friends': '친구공개',

    // ========== 링크 ==========
    'search_link': '링크 검색',
    'editor_search_link': '링크 검색',
    'editor_add_link_please': '링크를 추가해주세요',
    'editor_link_may_invalid': '유효하지 않은 링크일 수 있습니다',

    // ========== 기타 ==========
    'editor_replay': '다시보기',

    // ========== 툴바 ==========
    'editor_link': '링크',
    'editor_divider': '구분선',
    'editor_list_numbered': '번호 리스트',
    'editor_list_bullet': '불릿 리스트',
    'editor_list_checklist': '체크리스트',
    'editor_list_quote': '인용',

    'editor_tag': '태그',
    'editor_default': '기본',

    // ========== 드래프트 ==========
    'editor_no_title': '무제',
    'no_title': '무제',
    'resume_writing_title': '이전에 작성하던 글이 있어요',
    'resume_writing_continue': '이어서 쓰기',
    'resume_writing_new': '새 글 작성',

    // ========== 폰트 카테고리 ==========
    'editor_font_size_mixed': 'Mixed',
    'editor_font_category_all': '전체',
    'editor_font_category_handwriting': '손글씨',
    'editor_font_category_sans_serif': '산세리프',
    'editor_font_default_sans_serif': '기본 산세리프',

    // ========== 에러 메시지 ==========
    'editor_unsupported_file_format':
        '지원하지 않는 파일 형식입니다\nmp4, mov, m4v 형식의 영상만 업로드 가능합니다',
    'editor_file_too_large': '파일이 너무 큽니다\n최대 {maxSize}MB까지만 업로드 가능합니다.',

    // ========== 미디어 피커 ==========
    'media_type_video': '영상',
    'media_type_image': '사진',
    'select_video': '영상 선택',
    'select_image': '사진 선택',
    'add_with_count': '{count}개 추가',
    'limited_video_access_title': '영상에 대한 제한된 액세스',
    'limited_photo_access_title': '사진에 대한 제한된 액세스',
    'limited_video_access_message': '선택한 영상만 앱에서 사용할 수 있습니다.',
    'limited_photo_access_message': '선택한 사진만 앱에서 사용할 수 있습니다.',
    'photo_library_permission_required': '사진 라이브러리 권한이 필요합니다',
    'open_permission_settings': '설정에서 권한을 허용해주세요',
    'group_image': '그룹 이미지',
    'edit_image': '이미지 편집',
    'edit_video': '비디오 편집',
    'no_videos': '영상이 없습니다',
    'no_images': '사진이 없습니다',
    'media_picker_selected_images_here': '선택된 이미지가 여기에 표시돼요',
    'add_more_video': '추가 영상 선택',
    'add_more_photo': '추가 사진 선택',
    'allow_full_access_in_settings': '설정에서 전체 허용',

    // ========== 이미지 레이아웃 선택 ==========
    'select_layout': '레이아웃 선택',
    'individual_images': '개별 이미지',
    'grid_2_column': '2열 그리드',
    'grid_3_column': '3열 그리드',
    'pageview_layout': '페이지뷰',
  };

  /// 에디터 패키지 번역 맵 (영어)
  static const Map<String, String> _translationsEn = {
    // ========== 공통 버튼/액션 ==========
    'editor_save': 'Save',
    'editor_cancel': 'Cancel',
    'editor_delete': 'Delete',
    'editor_exit': 'Exit',
    'editor_next': 'Next',
    'editor_close': 'Close',
    'close': 'Close',
    'drafts': 'Drafts',
    'editor_confirm': 'Confirm',
    'editor_add': 'Add',
    'editor_modify': 'Modify',
    'editor_search': 'Search',
    'editor_loading': 'Loading...',

    // ========== 공통 메시지 ==========
    'editor_error': 'Error',
    'editor_error_occurred': 'An error occurred',
    'editor_success': 'Success',
    'editor_notification': 'Notification',
    'editor_uploading': 'Uploading...',
    'editor_wait': 'Waiting...',
    'editor_upload_wait': 'Please wait until the upload is complete.',

    // ========== 드래프트 관련 ==========
    'editor_draft': 'Draft',
    'editor_drafts': 'Drafts',
    'editor_save_draft': 'Save Draft',
    'editor_load_draft': 'Load Draft',
    'editor_draft_saved': 'Draft saved',
    'editor_draft_save_failed': 'Failed to save draft',
    'editor_draft_load_failed': 'Failed to load draft',
    'editor_draft_list_failed': 'Failed to load draft list',
    'editor_no_drafts': 'No drafts',
    'editor_delete_draft_confirm_title': 'Delete Draft',
    'editor_delete_draft_confirm_message': 'Do you want to delete this draft?',
    'delete_draft_confirm_title': 'Delete Draft',
    'delete_draft_confirm_message': 'Do you want to delete this draft?',
    'delete': 'Delete',
    'editor_post_delete_confirm_title': 'Delete Post',
    'editor_post_delete_confirm_message':
        'This post will be permanently deleted. Do you want to delete it?',

    // ========== 콘텐츠 검증 ==========
    'editor_body_required': 'Please enter body',
    'editor_title_required': 'Please enter title',
    'editor_title_required_for_draft': 'Please enter draft title',
    'editor_content_required': 'Please enter content',
    'editor_thumbnail_required': 'Please select thumbnail',

    // ========== 나가기/저장 다이얼로그 ==========
    'editor_discard_or_save_title': 'Exit without saving?',
    'editor_discard_or_save_message': 'Changes will not be saved',
    'editor_save_and_exit': 'Save and Exit',
    'editor_discard_without_save': 'Exit without Saving',
    'editor_exit_writing_title': 'Exit writing?',
    'editor_exit_writing_message': 'Your writing may be lost',
    'editor_continue_writing': 'Continue Writing',
    'editor_cancel_edit_title': 'Cancel editing?',
    'editor_cancel_edit_message': 'Your edits may be lost',
    'editor_finish_edit': 'Finish Edit',

    // ========== 미디어 업로드 ==========
    'editor_wait_for_media_upload': 'Waiting for media upload',
    'editor_media_still_uploading': 'Media is still uploading',
    'editor_image_uploading': 'Uploading image...',
    'editor_upload_failed': 'Upload failed',
    'editor_load_failed': 'Failed to load',
    'editor_image_edit_failed': 'Failed to edit image',
    'editor_selection_limit': 'Selection limit exceeded',

    // ========== 발행/수정 관련 ==========
    'editor_publish': 'Publish',
    'editor_publish_failed': 'Failed to publish',
    'editor_thumbnail_upload_required': 'Thumbnail upload required',
    'editor_modify_complete': 'Modify Complete',
    'editor_edit_failed': 'Failed to edit',

    // ========== 공개 범위 ==========
    'editor_public': 'Public',
    'editor_private': 'Private',
    'editor_friends': 'Friends',

    // ========== 멘션 ==========
    'editor_mention': 'Mention',
    'editor_who_to_mention': 'Who would you like to mention?',
    'editor_show_recent_list': 'Show Recent List',
    'editor_hide_recent_list': 'Hide Recent List',
    'editor_no_search_results': 'No search results',

    // ========== 링크 ==========
    'search_link': 'Search Link',
    'editor_search_link': 'Search Link',
    'editor_add_link_please': 'Please add a link',
    'editor_link_may_invalid': 'Link may be invalid',

    // ========== 에디터 상태 ==========
    'editor_tap_to_start_writing': 'Tap to start writing',
    'editor_tap_to_start_writing_hint': 'Tap here to start writing',

    // ========== 기타 ==========
    'editor_replay': 'Replay',

    // ========== 툴바 ==========
    'editor_link': 'Link',
    'editor_divider': 'Divider',
    'editor_list_numbered': 'Numbered list',
    'editor_list_bullet': 'Bullet list',
    'editor_list_checklist': 'Checklist',
    'editor_list_quote': 'Quote',
    'editor_tag': 'Tag',
    'editor_default': 'Default',

    // ========== 드래프트 ==========
    'editor_no_title': 'Untitled',
    'no_title': 'Untitled',
    'resume_writing_title': "You have a draft you were writing",
    'resume_writing_continue': 'Continue writing',
    'resume_writing_new': 'Start new',

    // ========== 폰트 카테고리 ==========
    'editor_font_size_mixed': 'Mixed',
    'editor_font_category_all': 'All',
    'editor_font_category_handwriting': 'Handwriting',
    'editor_font_category_sans_serif': 'Sans Serif',
    'editor_font_default_sans_serif': 'Default Sans Serif',

    // ========== 에러 메시지 ==========
    'editor_unsupported_file_format':
        'Unsupported file format\nOnly mp4, mov, m4v formats are supported',
    'editor_file_too_large': 'File is too large\nMaximum {maxSize}MB allowed.',

    // ========== 미디어 피커 (Media Picker) ==========
    'media_type_video': 'Video',
    'media_type_image': 'Photo',
    'select_video': 'Select Video',
    'select_image': 'Select Photo',
    'add_with_count': 'Add {count}',
    'limited_video_access_title': 'Limited Access to Videos',
    'limited_photo_access_title': 'Limited Access to Photos',
    'limited_video_access_message':
        'Only selected videos are available in the app.',
    'limited_photo_access_message':
        'Only selected photos are available in the app.',
    'photo_library_permission_required': 'Photo library permission required',
    'open_permission_settings': 'Open permission settings',
    'group_image': 'Group Image',
    'edit_image': 'Edit Image',
    'edit_video': 'Edit Video',
    'no_videos': 'No videos',
    'no_images': 'No photos',
    'media_picker_selected_images_here': 'Selected images will appear here',
    'add_more_video': 'Select More Videos',
    'add_more_photo': 'Select More Photos',
    'allow_full_access_in_settings': 'Allow Full Access in Settings',

    // ========== 이미지 레이아웃 선택 ==========
    'select_layout': 'Select Layout',
    'individual_images': 'Individual Images',
    'grid_2_column': '2 Column Grid',
    'grid_3_column': '3 Column Grid',
    'pageview_layout': 'Page View',
  };

  /// 현재 언어에 맞는 번역 맵 가져오기
  static Map<String, String> get translations {
    switch (_currentLocale) {
      case EditorLocale.korean:
        return _translationsKo;
      case EditorLocale.english:
        return _translationsEn;
    }
  }

  /// 번역된 문자열 가져오기 (플레이스홀더 지원)
  static String translate(String key, {Map<String, String>? placeholders}) {
    final translation = translations[key] ?? key;
    if (placeholders == null || placeholders.isEmpty) {
      return translation;
    }

    String result = translation;
    placeholders.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }
}

/// Extension for easy access to editor translations
extension EditorLocalizationExtension on BuildContext {
  /// 번역 키로 번역된 문자열을 가져옵니다.
  ///
  /// [key] 번역 키 (예: 'editor_save')
  /// [placeholders] 플레이스홀더 값 (예: {'maxSize': '100'})
  ///
  /// 반환: 번역된 문자열 또는 키 그대로 (번역이 없을 경우)
  String tr(String key, {Map<String, String>? placeholders}) {
    return EditorTranslations.translate(key, placeholders: placeholders);
  }
}
