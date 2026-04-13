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
      print('📅 Creating availability period:');
      print('   Local time: ${startDateTime.toLocal()} to ${endDateTime.toLocal()}');
      print('   UTC time: ${startDateTime.toUtc()} to ${endDateTime.toUtc()}');
      print('   ISO string: ${startDateTime.toIso8601String()} to ${endDateTime.toIso8601String()}');
      
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
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.access_time),
                            title: Text(
                              '${DateFormat('MMM dd, yyyy HH:mm').format(period.startTime)} - ${DateFormat('MMM dd, yyyy HH:mm').format(period.endTime)}',
                            ),
                            subtitle: Text(
                              _formatDuration(period.startTime, period.endTime),
                            ),
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
        onPressed: _addAvailabilityPeriod,
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
