import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/booking_service.dart';
import '../../services/parking_spot_service.dart';
import '../../models/parking_spot.dart';

class AvailableSpotsScreen extends StatefulWidget {
  final VoidCallback? onBookingCreated;

  const AvailableSpotsScreen({super.key, this.onBookingCreated});

  @override
  State<AvailableSpotsScreen> createState() => _AvailableSpotsScreenState();
}

class _AvailableSpotsScreenState extends State<AvailableSpotsScreen> {
  final _bookingService = BookingService();
  final _spotService = ParkingSpotService();
  List<ParkingSpot> _spots = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  Future<void> _loadSpots() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final spots = await _bookingService.getAvailableSpots();
      setState(() {
        _spots = spots;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _showBookingDialog(ParkingSpot spot) async {
    final slots = await _spotService.getAvailableTimeSlots(spotId: spot.id);

    if (!mounted) return;

    if (slots.isEmpty) {
      _showQuickBookDialog(spot);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Available Slots — ${spot.spotIdentifier}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: slots.length,
                    itemBuilder: (context, index) {
                      final slot = slots[index];
                      final start = slot['start']!;
                      final end = slot['end']!;
                      final fmt = DateFormat('MMM dd, HH:mm');
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.access_time, color: Colors.green),
                          title: Text('${fmt.format(start.toLocal())} — ${fmt.format(end.toLocal())}'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showTimePickerForSlot(spot, start, end);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showTimePickerForSlot(
    ParkingSpot spot,
    DateTime slotStart,
    DateTime slotEnd,
  ) async {
    DateTime selectedStart = slotStart.toLocal();
    DateTime selectedEnd = slotEnd.toLocal();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final fmt = DateFormat('MMM dd, yyyy HH:mm');
          return AlertDialog(
            title: Text('Book ${spot.spotIdentifier}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select your booking window:'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedStart,
                      firstDate: slotStart.toLocal(),
                      lastDate: slotEnd.toLocal(),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(selectedStart),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      selectedStart = DateTime(
                        date.year, date.month, date.day,
                        time.hour, time.minute,
                      );
                    });
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Start: ${fmt.format(selectedStart)}'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedEnd,
                      firstDate: selectedStart,
                      lastDate: slotEnd.toLocal(),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(selectedEnd),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      selectedEnd = DateTime(
                        date.year, date.month, date.day,
                        time.hour, time.minute,
                      );
                    });
                  },
                  icon: const Icon(Icons.stop),
                  label: Text('End: ${fmt.format(selectedEnd)}'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Request'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _bookingService.createBookingRequest(
        spotId: spot.id,
        startTime: selectedStart,
        endTime: selectedEnd,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking request sent!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onBookingCreated?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showQuickBookDialog(ParkingSpot spot) async {
    DateTime? startTime;
    DateTime? endTime;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final fmt = DateFormat('MMM dd, yyyy HH:mm');
          return AlertDialog(
            title: Text('Book ${spot.spotIdentifier}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('This spot is always available. Choose your times:'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      startTime = DateTime(
                        date.year, date.month, date.day,
                        time.hour, time.minute,
                      );
                    });
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(startTime == null
                      ? 'Select start time'
                      : 'Start: ${fmt.format(startTime!)}'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final initial = startTime ?? DateTime.now();
                    final date = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: initial,
                      lastDate: initial.add(const Duration(days: 365)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(
                        initial.add(const Duration(hours: 1)),
                      ),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      endTime = DateTime(
                        date.year, date.month, date.day,
                        time.hour, time.minute,
                      );
                    });
                  },
                  icon: const Icon(Icons.stop),
                  label: Text(endTime == null
                      ? 'Select end time'
                      : 'End: ${fmt.format(endTime!)}'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: startTime != null && endTime != null
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: const Text('Request'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || startTime == null || endTime == null || !mounted) {
      return;
    }

    try {
      await _bookingService.createBookingRequest(
        spotId: spot.id,
        startTime: startTime!,
        endTime: endTime!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking request sent!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onBookingCreated?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadSpots, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_spots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_parking, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No available spots right now'),
            const SizedBox(height: 8),
            const Text(
              'Check back later or use the Request Spot tab',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadSpots,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSpots,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _spots.length,
        itemBuilder: (context, index) {
          final spot = _spots[index];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.local_parking, color: Colors.green),
              title: Text(spot.spotIdentifier),
              subtitle: const Text('Tap to view slots & book'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showBookingDialog(spot),
            ),
          );
        },
      ),
    );
  }
}
