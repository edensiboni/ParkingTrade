import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/booking_service.dart';
import '../../models/parking_spot.dart';

class RequestSpotScreen extends StatefulWidget {
  final VoidCallback? onBookingCreated;

  const RequestSpotScreen({
    super.key,
    this.onBookingCreated,
  });

  @override
  State<RequestSpotScreen> createState() => _RequestSpotScreenState();
}

class _RequestSpotScreenState extends State<RequestSpotScreen> {
  final _bookingService = BookingService();
  List<ParkingSpot> _availableSpots = [];
  ParkingSpot? _selectedSpot;
  DateTime? _startTime;
  DateTime? _endTime;
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAvailableSpots();
  }

  Future<void> _loadAvailableSpots() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // If start and end times are selected, filter spots by availability
      final spots = await _bookingService.getAvailableSpots(
        startTime: _startTime,
        endTime: _endTime,
      );
      setState(() {
        _availableSpots = spots;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading spots: $e';
      });
    }
  }

  // Reload spots when time changes
  void _onTimeChanged() {
    if (_startTime != null && _endTime != null) {
      _loadAvailableSpots();
    }
  }

  Future<void> _selectStartTime() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (!mounted) return;

    if (picked != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (!mounted) return;

      if (time != null) {
        setState(() {
          _startTime = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
          _endTime = null; // Reset end time when start time changes
        });
        _onTimeChanged();
      }
    }
  }

  Future<void> _selectEndTime() async {
    if (_startTime == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start time first')),
      );
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _startTime!,
      firstDate: _startTime!,
      lastDate: _startTime!.add(const Duration(days: 365)),
    );

    if (!mounted) return;

    if (picked != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_startTime!.add(const Duration(hours: 1))),
      );

      if (!mounted) return;

      if (time != null) {
        final endTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time.hour,
          time.minute,
        );

        if (!endTime.isAfter(_startTime!)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End time must be after start time')),
          );
          return;
        }

        setState(() {
          _endTime = endTime;
        });
        _onTimeChanged();
      }
    }
  }

  Future<void> _submitRequest() async {
    if (_selectedSpot == null || _startTime == null || _endTime == null) {
      setState(() {
        _errorMessage = 'Please fill in all fields';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await _bookingService.createBookingRequest(
        spotId: _selectedSpot!.id,
        startTime: _startTime!,
        endTime: _endTime!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking request created successfully')),
        );
        widget.onBookingCreated?.call();
        setState(() {
          _selectedSpot = null;
          _startTime = null;
          _endTime = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Request a Parking Spot',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_availableSpots.isEmpty)
            const Center(
              child: Text('No available spots in your building'),
            )
          else ...[
            const Text(
              'Select Spot',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ParkingSpot>(
              value: _selectedSpot,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_parking),
              ),
              items: _availableSpots.map((spot) {
                return DropdownMenuItem(
                  value: spot,
                  child: Text(spot.spotIdentifier),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedSpot = value;
                });
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Start Time',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _selectStartTime,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _startTime == null
                    ? 'Select start time'
                    : DateFormat('MMM dd, yyyy HH:mm').format(_startTime!),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'End Time',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _selectEndTime,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _endTime == null
                    ? 'Select end time'
                    : DateFormat('MMM dd, yyyy HH:mm').format(_endTime!),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitRequest,
              child: _isSubmitting
                  ? const CircularProgressIndicator()
                  : const Text('Request Spot'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

