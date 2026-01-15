import 'package:flutter/material.dart';
import '../../services/building_service.dart';
import '../../services/auth_service.dart';
import 'pending_approval_screen.dart';
import '../spots/parking_spots_screen.dart';

class JoinBuildingScreen extends StatefulWidget {
  const JoinBuildingScreen({super.key});

  @override
  State<JoinBuildingScreen> createState() => _JoinBuildingScreenState();
}

class _JoinBuildingScreenState extends State<JoinBuildingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _inviteCodeController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _buildingService = BuildingService();
  final _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _inviteCodeController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _joinBuilding() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _buildingService.joinBuilding(
        inviteCode: _inviteCodeController.text.trim().toUpperCase(),
        displayName: _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
      );

      if (!mounted) return;

      // Update profile with display name if provided
      if (_displayNameController.text.trim().isNotEmpty) {
        await _authService.updateProfile(
          displayName: _displayNameController.text.trim(),
        );
      }

      final requiresApproval = result['requires_approval'] as bool? ?? false;
      final status = result['status'] as String?;

      if (!mounted) return;

      if (requiresApproval && status == 'pending') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const PendingApprovalScreen(),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const ParkingSpotsScreen(),
          ),
        );
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
        title: const Text('Join Building'),
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
                'Enter the invite code for your building',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _inviteCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Invite Code',
                  hintText: 'ABC123',
                  prefixIcon: Icon(Icons.key),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an invite code';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name (Optional)',
                  hintText: 'How others will see you',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _joinBuilding,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Join Building'),
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

