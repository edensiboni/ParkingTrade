class BookingRequest {
  final String id;
  final String spotId;
  final String borrowerId;
  final String lenderId;
  final DateTime startTime;
  final DateTime endTime;
  final BookingStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  BookingRequest({
    required this.id,
    required this.spotId,
    required this.borrowerId,
    required this.lenderId,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BookingRequest.fromJson(Map<String, dynamic> json) {
    return BookingRequest(
      id: json['id'] as String,
      spotId: json['spot_id'] as String,
      borrowerId: json['borrower_id'] as String,
      lenderId: json['lender_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      status: BookingStatus.fromString(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'spot_id': spotId,
      'borrower_id': borrowerId,
      'lender_id': lenderId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'status': status.toString(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

enum BookingStatus {
  pending,
  approved,
  rejected,
  cancelled,
  completed;

  static BookingStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return BookingStatus.pending;
      case 'approved':
        return BookingStatus.approved;
      case 'rejected':
        return BookingStatus.rejected;
      case 'cancelled':
        return BookingStatus.cancelled;
      case 'completed':
        return BookingStatus.completed;
      default:
        throw ArgumentError('Invalid booking status: $value');
    }
  }

  @override
  String toString() {
    switch (this) {
      case BookingStatus.pending:
        return 'pending';
      case BookingStatus.approved:
        return 'approved';
      case BookingStatus.rejected:
        return 'rejected';
      case BookingStatus.cancelled:
        return 'cancelled';
      case BookingStatus.completed:
        return 'completed';
    }
  }
}

