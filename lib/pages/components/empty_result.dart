import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';

class EmptyResult extends StatelessWidget {
  final String message;
  const EmptyResult({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: AppTextStyles.withWeight(
          AppTextStyles.bodyMedium,
          FontWeight.w500,
        ).copyWith(color: Colors.black54),
      ),
    );
  }
}
