import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/parking_spot_service.dart';
import '../../models/parking_spot.dart';
import '../../models/spot_availability_period.dart';

class ManageAvailabilityScreen extends StatefulWidget {
  final ParkingSpot spot;

  const ManageAvailabilityScreen({
    super.key,
    required this.spot,
  });

  @override
  State<ManageAvailabilityScreen> createState() => _ManageAvailabilityScreenState();
}

class _ManageAvailabilityScreenState extends State<ManageAvailabilityScreen> {
  final _spotService = ParkingSpotService();
  List<SpotAvailabilityPeriod> _periods = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  Future<void> _loadPeriods() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final periods = await _spotService.getAvailabilityPeriods(widget.spot.id);
      setState(() {
        _periods = periods;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading periods: $e')),
        );
      }
    }
  }

  Future<void> _addAvailabilityPeriod() async {
    final now = DateTime.now();
    
    // Pick start date
    final startDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (startDate == null || !mounted) return;

    // Pick start time
    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (startTime == null || !mounted) return;

    final startDateTime = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      startTime.hour,
      startTime.minute,
    );

    // Pick end date
    final endDate = await showDatePicker(
      context: context,
      initialDate: startDateTime,
      firstDate: startDateTime,
      lastDate: startDateTime.add(const Duration(days: 365)),
    );
    if (endDate == null || !mounted) return;

    // Pick end time
    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(startDateTime.add(const Duration(hours: 1))),
    );
    if (endTime == null || !mounted) return;

    final endDateTime = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      endTime.hour,
      endTime.minute,
    );

    if (!endDateTime.isAfter(startDateTime)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    try {
      // Debug: Print what we're about to save
      debugPrint('📅 Creating availability period:');
      debugPrint('   Local time: ${startDateTime.toLocal()} to ${endDateTime.toLocal()}');
      debugPrint('   UTC time: ${startDateTime.toUtc()} to ${endDateTime.toUtc()}');
      debugPrint('   ISO string: ${startDateTime.toIso8601String()} to ${endDateTime.toIso8601String()}');
      
      await _spotService.addAvailabilityPeriod(
        spotId: widget.spot.id,
        startTime: startDateTime,
        endTime: endDateTime,
      );
      _loadPeriods();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Availability period added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showAddSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.event),
                title: const Text('One-time availability'),
                subtitle: const Text('Specific date and time range'),
                onTap: () => Navigator.of(context).pop('once'),
              ),
              ListTile(
                leading: const Icon(Icons.event_repeat),
                title: const Text('Weekly recurring'),
                subtitle: const Text('Same days and hours every week'),
                onTap: () => Navigator.of(context).pop('weekly'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;
    if (choice == 'once') {
      await _addAvailabilityPeriod();
    } else if (choice == 'weekly') {
      await _addRecurringPeriod();
    }
  }

  Future<void> _addRecurringPeriod() async {
    // Pick start date (first occurrence anchor).
    final now = DateTime.now();
    final startDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (startDate == null || !mounted) return;

    // Pick start time-of-day.
    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (startTime == null || !mounted) return;

    // Pick end time-of-day.
    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (startTime.hour + 1) % 24,
        minute: startTime.minute,
      ),
    );
    if (endTime == null || !mounted) return;

    // Pick weekdays.
    final days = await _pickWeekdays(startDate.weekday);
    if (!mounted || days == null || days.isEmpty) return;

    // Build start/end DateTimes on the anchor date.
    final anchor = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      startTime.hour,
      startTime.minute,
    );
    var endAnchor = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      endTime.hour,
      endTime.minute,
    );
    if (!endAnchor.isAfter(anchor)) {
      // Treat as same-day window that wraps — bump end to next day.
      endAnchor = endAnchor.add(const Duration(days: 1));
    }

    final pattern = jsonEncode({
      'type': 'weekly',
      'days': days.toList()..sort(),
    });

    try {
      await _spotService.addAvailabilityPeriod(
        spotId: widget.spot.id,
        startTime: anchor,
        endTime: endAnchor,
        isRecurring: true,
        recurringPattern: pattern,
      );
      _loadPeriods();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recurring availability added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<Set<String>?> _pickWeekdays(int defaultWeekday) async {
    const labels = <String, String>{
      'MON': 'Mon',
      'TUE': 'Tue',
      'WED': 'Wed',
      'THU': 'Thu',
      'FRI': 'Fri',
      'SAT': 'Sat',
      'SUN': 'Sun',
    };
    const weekdayToCode = <int, String>{
      DateTime.monday: 'MON',
      DateTime.tuesday: 'TUE',
      DateTime.wednesday: 'WED',
      DateTime.thursday: 'THU',
      DateTime.friday: 'FRI',
      DateTime.saturday: 'SAT',
      DateTime.sunday: 'SUN',
    };

    final selected = <String>{weekdayToCode[defaultWeekday] ?? 'MON'};

    return showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('Repeat on'),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: labels.entries.map((entry) {
                final isSelected = selected.contains(entry.key);
                return FilterChip(
                  label: Text(entry.value),
                  selected: isSelected,
                  onSelected: (v) {
                    setStateDialog(() {
                      if (v) {
                        selected.add(entry.key);
                      } else {
                        selected.remove(entry.key);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(selected),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _describeRecurrence(SpotAvailabilityPeriod period) {
    if (!period.isRecurring) return '';
    final raw = period.recurringPattern ?? '';
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final type = decoded['type']?.toString() ?? 'weekly';
          if (type == 'weekly') {
            final daysRaw = decoded['days'];
            if (daysRaw is List && daysRaw.isNotEmpty) {
              const labels = <String, String>{
                'MON': 'Mon',
                'TUE': 'Tue',
                'WED': 'Wed',
                'THU': 'Thu',
                'FRI': 'Fri',
                'SAT': 'Sat',
                'SUN': 'Sun',
              };
              final days = daysRaw
                  .map((d) => labels[d.toString().toUpperCase()] ?? d.toString())
                  .join(', ');
              return 'Weekly · $days';
            }
            return 'Weekly';
          }
          return 'Repeats: $type';
        }
      } catch (_) {
        // Fall through to raw pattern.
      }
    }
    return 'Repeats: $raw';
  }

  Future<void> _deletePeriod(SpotAvailabilityPeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Availability Period'),
        content: const Text('Are you sure you want to delete this availability period?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _spotService.deleteAvailabilityPeriod(period.id);
      _loadPeriods();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Availability period deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Availability: ${widget.spot.spotIdentifier}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Set when your parking spot is available for others to book.',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _periods.isEmpty
                            ? 'No availability periods set. Your spot is always available for booking.'
                            : 'Your spot is only available during the periods below.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_periods.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No availability periods',
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add a period to restrict when your spot can be booked',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _periods.length,
                      itemBuilder: (context, index) {
                        final period = _periods[index];
                        final title = period.isRecurring
                            ? '${DateFormat('HH:mm').format(period.startTime)} – ${DateFormat('HH:mm').format(period.endTime)}'
                            : '${DateFormat('MMM dd, yyyy HH:mm').format(period.startTime)} - ${DateFormat('MMM dd, yyyy HH:mm').format(period.endTime)}';
                        final recurrence = _describeRecurrence(period);
                        final durationLabel = _formatDuration(period.startTime, period.endTime);
                        final subtitle = recurrence.isEmpty
                            ? durationLabel
                            : '$recurrence · $durationLabel';
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            leading: Icon(
                              period.isRecurring ? Icons.event_repeat : Icons.access_time,
                            ),
                            title: Text(title),
                            subtitle: Text(subtitle),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deletePeriod(period),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  String _formatDuration(DateTime start, DateTime end) {
    final duration = end.difference(start);
    if (duration.inDays > 0) {
      return '${duration.inDays} day${duration.inDays > 1 ? 's' : ''}';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} hour${duration.inHours > 1 ? 's' : ''}';
    } else {
      return '${duration.inMinutes} minute${duration.inMinutes > 1 ? 's' : ''}';
    }
  }
}
