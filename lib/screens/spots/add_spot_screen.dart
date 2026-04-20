import 'package:flutter/material.dart';
import '../../services/parking_spot_service.dart';
import '../../widgets/app_snack.dart';

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
        AppSnack.success(context, 'Spot added');
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add parking spot')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          children: [
            Text(
              'What\'s your spot called?',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use whatever matches the sign or your deed — e.g. "A-123" or "Level 2 · Spot 45". Each spot must be unique inside your building.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _spotIdentifierController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _isLoading ? null : _addSpot(),
              decoration: const InputDecoration(
                labelText: 'Spot identifier',
                hintText: 'A-123',
                prefixIcon: Icon(Icons.local_parking_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a spot identifier';
                }
                return null;
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: scheme.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isLoading ? null : _addSpot,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(_isLoading ? 'Adding…' : 'Add spot'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
