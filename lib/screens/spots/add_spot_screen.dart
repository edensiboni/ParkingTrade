import 'package:flutter/material.dart';
import '../../services/parking_spot_service.dart';

class AddSpotScreen extends StatefulWidget {
  final String buildingId;

  const AddSpotScreen({
    super.key,
    required this.buildingId,
  });

  @override
  State<AddSpotScreen> createState() => _AddSpotScreenState();
}

class _AddSpotScreenState extends State<AddSpotScreen> {
  final _formKey = GlobalKey<FormState>();
  final _spotIdentifierController = TextEditingController();
  final _spotService = ParkingSpotService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _spotIdentifierController.dispose();
    super.dispose();
  }

  Future<void> _addSpot() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _spotService.addSpot(
        buildingId: widget.buildingId,
        spotIdentifier: _spotIdentifierController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Parking Spot'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text(
                'Enter your parking spot identifier',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This could be a spot number like "A-123" or "Level 2 - Spot 45"',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _spotIdentifierController,
                decoration: const InputDecoration(
                  labelText: 'Spot Identifier',
                  hintText: 'A-123',
                  prefixIcon: Icon(Icons.local_parking),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a spot identifier';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _addSpot,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Add Spot'),
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
          ),
        ),
      ),
    );
  }
}

