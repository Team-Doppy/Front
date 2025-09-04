import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// ImageRowNode를 렌더링하는 컴포넌트
class ImageRowComponent extends StatelessWidget {
  const ImageRowComponent({
    Key? key,
    required this.componentContext,
    required this.componentViewModel,
  }) : super(key: key);

  final SingleColumnDocumentComponentContext componentContext;
  final ImageRowComponentViewModel componentViewModel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children:
            componentViewModel.imageUrls
                .map(
                  (imageUrl) => Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                        right:
                            componentViewModel.imageUrls.last == imageUrl
                                ? 0
                                : componentViewModel.spacing,
                      ),
                      child: _buildImage(imageUrl),
                    ),
                  ),
                )
                .toList(),
      ),
    );
  }

  Widget _buildImage(String imageUrl) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          height: 200,
          color: Colors.grey.shade200,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 200,
          color: Colors.grey.shade300,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text("이미지 로드 실패", style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ImageRowNode의 뷰모델
class ImageRowComponentViewModel extends SingleColumnLayoutComponentViewModel {
  ImageRowComponentViewModel({
    required super.nodeId,
    required this.imageUrls,
    required this.spacing,
  }) : super(createdAt: DateTime.now(), padding: EdgeInsets.zero);

  final List<String> imageUrls;
  final double spacing;

  @override
  SingleColumnLayoutComponentViewModel copy() {
    return ImageRowComponentViewModel(
      nodeId: nodeId,
      imageUrls: imageUrls,
      spacing: spacing,
    );
  }
}
