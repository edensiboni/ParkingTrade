class Building {
  final String id;
  final String name;
  final String inviteCode;
  final bool approvalRequired;
  final DateTime createdAt;

  Building({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.approvalRequired,
    required this.createdAt,
  });

  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      inviteCode: json['invite_code'] as String,
      approvalRequired: json['approval_required'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'invite_code': inviteCode,
      'approval_required': approvalRequired,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

