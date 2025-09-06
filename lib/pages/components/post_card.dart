import 'dart:ui';

import 'package:flutter/material.dart';

class PostCard extends StatefulWidget {
  final double containerWidth;
  final String imagePath;
  final String title;
  final String author;
  final String content;

  const PostCard({
    super.key,
    required this.containerWidth,
    required this.imagePath,
    required this.title,
    required this.author,
    required this.content,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool isLiked = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.containerWidth,
      height: 425,
      margin: EdgeInsets.symmetric(horizontal: 0, vertical: 0),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          //_build1(),
          // 오른쪽 텍스트 영역
          SizedBox(height: 5),
          _build2(),
          _build4(),
        ],
      ),
    );
  }

  Widget _build1() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 20, 20, 20),
              borderRadius: BorderRadius.circular(300),
            ),
            child: Image.network(
              "https://thumbnews.nateimg.co.kr/view610///news.nateimg.co.kr/orgImg/pt/2025/06/12/202506122116776778_684ac5398c368.jpg",
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2.5),
                child: Text(
                  widget.author,
                  style: TextStyle(
                    color: const Color.fromARGB(255, 20, 20, 20),
                    fontSize: 12,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              SizedBox(width: 2),
              Text(
                "@affection-jk",
                style: TextStyle(
                  color: const Color.fromARGB(255, 20, 20, 20),
                  fontSize: 12,
                  fontFamily: 'Pretendard Variable',
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          SizedBox(width: 10),
          Spacer(),
          Container(
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 194, 194, 194),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Text(
                "2다리",
                style: TextStyle(
                  color: const Color.fromARGB(255, 255, 255, 255),
                  fontSize: 10,
                  fontFamily: 'Pretendard Variable',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _build2() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Stack(
        children: [
          SizedBox(
            width: 450,
            height: 380, // 4:3 비율

            child: ClipRRect(
              borderRadius: BorderRadius.only(
                bottomRight: Radius.circular(10),
                bottomLeft: Radius.circular(2),
                topRight: Radius.circular(10),
                topLeft: Radius.circular(10),
              ),
              child: Image.asset(
                widget.imagePath,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          // 블러+반투명 검정 오버레이
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(15),
                  bottomLeft: Radius.circular(15),
                  topRight: Radius.circular(15),
                  topLeft: Radius.circular(15),
                ),
                color: const Color.fromARGB(6, 91, 91, 91).withOpacity(0.15),
              ),
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            child: // 제목
                _build3(),
          ),

          Positioned(
            top: 12,
            right: 10,
            child: Padding(
              padding: const EdgeInsets.symmetric(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        isLiked = !isLiked;
                      });
                    },
                    child: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_outline,
                      size: 20,
                      weight: 0.01,
                      color:
                          isLiked
                              ? const Color.fromARGB(255, 255, 255, 255)
                              : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 10,
            child: Padding(
              padding: const EdgeInsets.symmetric(),
              child: Row(
                children: [
                  Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 255, 255, 255),
                      borderRadius: BorderRadius.circular(300),
                      border: Border.all(
                        color: const Color.fromARGB(255, 202, 202, 202),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(300),
                      child: Image.network(
                        "https://thumbnews.nateimg.co.kr/view610///news.nateimg.co.kr/orgImg/pt/2025/06/12/202506122116776778_684ac5398c368.jpg",
                        fit: BoxFit.cover,
                        width: 33,
                        height: 33,
                      ),
                    ),
                  ),
                  SizedBox(width: 4),
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.author,
                          style: TextStyle(
                            color: const Color.fromARGB(255, 225, 225, 225),
                            fontSize: 12,
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w600,
                            height: 0.9,
                          ),
                        ),
                        Text(
                          "@affection-jk",
                          style: TextStyle(
                            color: const Color.fromARGB(255, 255, 255, 255),
                            fontSize: 12,
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _build3() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "1일 전",
            style: TextStyle(
              color: const Color.fromARGB(255, 247, 247, 247),
              fontSize: 11,
              fontFamily: 'Pretendard Variable',
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          SizedBox(height: 5),
          Text(
            widget.title,
            style: TextStyle(
              color: const Color.fromARGB(255, 255, 255, 255),
              fontSize: 18,
              fontFamily: 'Pretendard Variable',
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),

          // 본문 내용 미리보기
          Text(
            widget.content,
            style: TextStyle(
              color: const Color.fromARGB(255, 231, 231, 231),
              fontSize: 11,
              fontFamily: 'Pretendard Variable',
              fontWeight: FontWeight.w300,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _build4() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.favorite,
            size: 20,
            color: const Color.fromARGB(255, 255, 112, 112),
          ),
          SizedBox(width: 4),
          Text(
            "123",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
          ),
          SizedBox(width: 10),
          /*
          Icon(
            Icons.add,
            size: 20,
            color: const Color.fromARGB(255, 43, 43, 43),
          ),
          SizedBox(width: 4),
          Text(
            "45",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
          ),*/
        ],
      ),
    );
  }
}
