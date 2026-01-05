class ApiErrorModel {
  final String? error;
  final String? message;

  const ApiErrorModel({this.error, this.message});

  factory ApiErrorModel.fromJson(Map<String, dynamic> json) {
    return ApiErrorModel(
      error: json['error']?.toString(),
      message: json['message']?.toString(),
    );
  }
}
