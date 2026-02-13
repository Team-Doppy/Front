import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../utils/trimmer_utils.dart';

/// For showing the thumbnails generated from the video in a scrollable view,
/// like a frame by frame preview.
class ScrollableThumbnailViewer extends StatelessWidget {
  /// The video file from which thumbnails are generated.
  final File videoFile;

  /// The total duration of the video in milliseconds.
  final int videoDuration;

  /// The height of each thumbnail.
  final double thumbnailHeight;

  /// The number of thumbnails to generate.
  final int numberOfThumbnails;

  /// How the thumbnails should be inscribed into the allocated space.
  final BoxFit fit;

  /// The scroll controller for the scrollable thumbnail view.
  final ScrollController scrollController;

  /// Callback function that is called when thumbnail loading is complete.
  final VoidCallback onThumbnailLoadingComplete;

  /// The quality of the generated thumbnails, ranging from 0 to 100.
  /// Defaults to 75.
  final int quality;

  /// Callback function that generates thumbnail bytes from a video path and timestamp.
  final Future<Uint8List?> Function(
    String videoPath,
    int timestamp,
    int quality,
  )
  thumbnailGenerator;

  /// Creates a [ScrollableThumbnailViewer] widget.
  ///
  /// - [videoFile] is the video file from which thumbnails are generated.
  /// - [videoDuration] is the total duration of the video in milliseconds.
  /// - [thumbnailHeight] is the height of each thumbnail.
  /// - [numberOfThumbnails] is the number of thumbnails to generate.
  /// - [fit] is how the thumbnails should be inscribed into the allocated space.
  /// - [scrollController] is the scroll controller for the scrollable thumbnail view.
  /// - [onThumbnailLoadingComplete] is the callback function that is called when thumbnail loading is complete.
  /// - [thumbnailGenerator] is the callback function that generates thumbnail bytes.
  /// - [quality] is the quality of the generated thumbnails, ranging from 0 to 100. Defaults to 75.
  const ScrollableThumbnailViewer({
    super.key,
    required this.videoFile,
    required this.videoDuration,
    required this.thumbnailHeight,
    required this.numberOfThumbnails,
    required this.fit,
    required this.scrollController,
    required this.onThumbnailLoadingComplete,
    required this.thumbnailGenerator,
    this.quality = 75,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: scrollController,
        child: SizedBox(
          width: numberOfThumbnails * thumbnailHeight,
          height: thumbnailHeight,
          child: StreamBuilder<List<Uint8List?>>(
            stream: generateThumbnail(
              videoPath: videoFile.path,
              videoDuration: videoDuration,
              numberOfThumbnails: numberOfThumbnails,
              thumbnailHeight: thumbnailHeight,
              quality: quality,
              onThumbnailLoadingComplete: onThumbnailLoadingComplete,
              thumbnailGenerator: thumbnailGenerator,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                List<Uint8List?> imageBytes = snapshot.data!;
                return Row(
                  mainAxisSize: MainAxisSize.max,
                  children: List.generate(
                    numberOfThumbnails,
                    (index) => SizedBox(
                      height: thumbnailHeight,
                      width: thumbnailHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (imageBytes.isNotEmpty && imageBytes[0] != null)
                            Opacity(
                              opacity: 0.2,
                              child: Image.memory(imageBytes[0]!, fit: fit),
                            ),
                          index < imageBytes.length && imageBytes[index] != null
                              ? Image.memory(imageBytes[index]!, fit: fit)
                              : const SizedBox(),
                        ],
                      ),
                    ),
                  ),
                );
              } else {
                return Container(
                  color: Colors.grey[900],
                  height: thumbnailHeight,
                  width: double.maxFinite,
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
