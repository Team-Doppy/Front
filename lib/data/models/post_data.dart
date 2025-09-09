class PostData {
  final String imagePath;
  final String title;
  final String author;
  final String content;
  final int postId;
  final List<String>? mentionedFriends; // 언급된 친구들
  final List<String>? tags; // 태그
  bool isLiked;
  int likeCount;

  PostData({
    required this.imagePath,
    required this.title,
    required this.author,
    required this.content,
    required this.postId,
    this.mentionedFriends,
    this.tags,
    this.isLiked = false,
    this.likeCount = 0,
  });
}

class PostDataProvider {
  static List<PostData> getSamplePosts() {
    return List.generate(10, (index) {
      // 이미지 경로 결정
      String imagePath =
          index % 3 == 0
              ? 'assets/image/feed1.jpg'
              : index % 3 == 1
              ? 'assets/image/feed2.png'
              : 'assets/image/feed3.png';

      // 제목 결정
      String title =
          index == 0
              ? '모태솔로지만연애를해야할까///'
              : index == 1
              ? '오늘 날씨가 너무 좋아서 산책했어요'
              : index == 2
              ? '새로운 카페를 발견했어요!'
              : index == 3
              ? '블로그 1000억 무조건 부자될 것 같아'
              : index == 4
              ? '오늘은 수강신청을 망쳐버렸어요'
              : index == 5
              ? '감성 여름이고 싶은데...'
              : index == 6
              ? '새로운 영화를 봤어요'
              : index == 7
              ? '오늘 하루도 힘내자고 화이팅!'
              : index == 8
              ? '새로운 취미를 시작했어요'
              : '오늘은 정말 특별한 하루였어요';

      // 작성자 결정
      String author =
          index == 0
              ? '수최영'
              : index == 1
              ? '김여름'
              : index == 2
              ? '박카페'
              : index == 3
              ? '이블로그'
              : index == 4
              ? '정수강'
              : index == 5
              ? '한감성'
              : index == 6
              ? '최영화'
              : index == 7
              ? '강화이팅'
              : index == 8
              ? '윤취미'
              : '임특별';

      // 본문 내용 결정
      String content =
          index == 0
              ? '안녕하세여,.오늘은 모태솔로지만연애는하고싶 어후기로돌아왓어요다들키스씬은보셧나요저는보다가기절을할뻔했어요 완전 찰스엔터됨 진짜 갈!!!!!!!!!!!!할뻔함 어쩌고 저쩌고 저ㅉ고어쩌고'
              : index == 1
              ? '오늘 날씨가 정말 좋아서 산책을 다녀왔어요. 햇살이 따뜻하고 바람도 시원해서 정말 기분이 좋았어요. 특히 공원에서 만난 강아지들이 너무 귀여웠어요!'
              : index == 2
              ? '새로운 카페를 발견했어요! 분위기도 좋고 커피도 맛있어서 정말 만족스러웠어요. 다음에 친구들과 함께 가보려고 해요.'
              : index == 3
              ? '블로그로 1000억 벌어서 부자가 될 것 같아요! 열심히 글 쓰고 있으니까 조만간 성공할 것 같아요. 다들 응원해주세요!'
              : index == 4
              ? '오늘 수강신청을 망쳐버렸어요... 원하는 과목을 못 들었어요. 다음 학기에 다시 도전해보려고 해요. 화이팅!'
              : index == 5
              ? '감성적인 여름이 되고 싶은데... 바다도 가고 싶고, 별자리도 보고 싶어요. 로맨틱한 여름을 만들어보려고 해요.'
              : index == 6
              ? '새로운 영화를 봤어요! 스토리도 좋고 연기도 훌륭해서 정말 만족스러웠어요. 추천해드릴게요!'
              : index == 7
              ? '오늘 하루도 힘내자고 화이팅! 매일매일이 새로운 도전이지만 포기하지 않고 열심히 살아가려고 해요.'
              : index == 8
              ? '새로운 취미를 시작했어요! 그림 그리기를 시작했는데 생각보다 재미있어요. 시간 가는 줄 모르고 그리게 되네요.'
              : '오늘은 정말 특별한 하루였어요. 뜻밖의 좋은 일들이 많이 일어나서 기분이 너무 좋아요. 이런 날들이 더 많았으면 좋겠어요.';

      // 언급된 친구들 결정
      List<String> mentionedFriends = [];
      List<String> tags = [];
      if (index == 0) {
        mentionedFriends = ['김여름', '박카페'];
        tags = ['오늘 날씨', '산책', '카페'];
      } else if (index == 1) {
        mentionedFriends = ['이블로그', '정수강', '한감성'];
        tags = ['블로그', '수강신청', '취미'];
      } else if (index == 2) {
        mentionedFriends = [];
        tags = [];
      } else if (index == 3) {
        mentionedFriends = ['강화이팅', '윤취미', '임특별', '수최영'];
        tags = ['화이팅', '취미', '카페'];
      } else if (index == 4) {
        mentionedFriends = ['김여름', '박카페'];
        tags = ['오늘 날씨', '산책', '카페'];
      } else if (index == 5) {
        mentionedFriends = ['이블로그', '정수강'];
        tags = ['블로그', '수강신청', '취미'];
      } else if (index == 6) {
        mentionedFriends = ['한감성', '최영화', '강화이팅'];
        tags = ['화이팅', '취미', '카페'];
      } else if (index == 7) {
        mentionedFriends = [];
        tags = [];
      } else if (index == 8) {
        mentionedFriends = ['임특별', '수최영', '김여름'];
        tags = ['화이팅', '취미', '카페'];
      } else if (index == 9) {
        mentionedFriends = ['박카페', '이블로그', '정수강', '한감성', '최영화'];
      }

      return PostData(
        imagePath: imagePath,
        title: title,
        author: author,
        content: content,
        postId: 47 + index, // 실제로는 고유한 ID를 사용해야 함
        mentionedFriends: mentionedFriends,
        tags: tags,
      );
    });
  }
}
