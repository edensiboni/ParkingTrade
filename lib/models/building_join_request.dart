class BuildingJoinRequest {
  final String id;
  final String requesterUserId;
  final String requesterPhone;
  final String? requesterName;
  final String apartmentIdentifier;
  final String? notes;
  final String status;
  final DateTime createdAt;

  BuildingJoinRequest({
    required this.id,
    required this.requesterUserId,
    required this.requesterPhone,
    required this.requesterName,
    required this.apartmentIdentifier,
    required this.notes,
    required this.status,
    required this.createdAt,
  });

  factory BuildingJoinRequest.fromJson(Map<String, dynamic> json) {
    return BuildingJoinRequest(
      id: json['id'] as String,
      requesterUserId: json['requester_user_id'] as String,
      requesterPhone: json['requester_phone'] as String,
      requesterName: json['requester_name'] as String?,
      apartmentIdentifier: json['apartment_identifier'] as String,
      notes: json['notes'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

