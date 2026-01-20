class SpotAvailabilityPeriod {
  final String id;
  final String spotId;
  final DateTime startTime;
  final DateTime endTime;
  final bool isRecurring;
  final String? recurringPattern;
  final DateTime createdAt;

  SpotAvailabilityPeriod({
    required this.id,
    required this.spotId,
    required this.startTime,
    required this.endTime,
    this.isRecurring = false,
    this.recurringPattern,
    required this.createdAt,
  });

  factory SpotAvailabilityPeriod.fromJson(Map<String, dynamic> json) {
    return SpotAvailabilityPeriod(
      id: json['id'] as String,
      spotId: json['spot_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      isRecurring: json['is_recurring'] as bool? ?? false,
      recurringPattern: json['recurring_pattern'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'spot_id': spotId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'is_recurring': isRecurring,
      if (recurringPattern != null) 'recurring_pattern': recurringPattern,
      'created_at': createdAt.toIso8601String(),
    };
  }

  // Check if a requested time period overlaps with this availability period
  bool overlapsWith(DateTime requestedStart, DateTime requestedEnd) {
    return requestedStart.isBefore(endTime) && requestedEnd.isAfter(startTime);
  }
}
