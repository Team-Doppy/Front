import 'user_model.dart';

class GroupMember {
  final int id;
  final User member;
  // 'group' 정보는 중복될 수 있으므로 필요에 따라 포함하거나 제외할 수 있습니다.
  // final Group group;

  GroupMember({required this.id, required this.member});

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'],
      member: User.fromJson(json['member']),
    );
  }
}