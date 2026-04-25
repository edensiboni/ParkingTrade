import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shown when the app is loaded with `/?mode=setup`.
///
/// Allows a prospective building admin to register their building in a single
/// step — no authentication required. After the building is created the admin
/// logs in via the normal OTP flow; migration-014 automatically links the auth
/// account to the pre-created admin profile.
class CreateBuildingScreen extends StatefulWidget {
  /// Called after a successful creation so the caller can navigate away.
  final VoidCallback onCreated;

  const CreateBuildingScreen({super.key, required this.onCreated});

  @override
  State<CreateBuildingScreen> createState() => _CreateBuildingScreenState();
}

class _CreateBuildingScreenState extends State<CreateBuildingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _buildingNameController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  bool _success = false;
  String? _errorMessage;

  @override
  void dispose() {
    _buildingNameController.dispose();
    _adminNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'create-building-admin',
        body: {
          'building_name': _buildingNameController.text.trim(),
          'admin_display_name': _adminNameController.text.trim(),
          'admin_phone': _phoneController.text.trim(),
        },
      );

      // Supabase functions.invoke throws on non-2xx, but double-check the body.
      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['success'] != true) {
        throw Exception(data?['error'] ?? 'Unknown error from server');
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _success = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String? _validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone number is required';
    if (!value.trim().startsWith('+')) {
      return 'Use E.164 format: +1234567890';
    }
    if (value.trim().length < 8) return 'Phone number is too short';
    return null;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _success ? _buildSuccessView(theme, colorScheme) : _buildFormView(theme, colorScheme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ────────────────────────────────────────────────────────────
        Icon(Icons.apartment_rounded, size: 56, color: colorScheme.primary),
        const SizedBox(height: 20),
        Text(
          'Set Up Your Building',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Create your building and admin account. After setup you can log in with your phone number.',
          style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),

        // ── Form ──────────────────────────────────────────────────────────────
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _buildingNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Building Name',
                  hintText: 'e.g. Tower Residences',
                  prefixIcon: Icon(Icons.business_rounded),
                ),
                validator: (v) => _validateRequired(v, 'Building name'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _adminNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Your Name',
                  hintText: 'e.g. Dana Cohen',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                // Display name is optional — we just use it when provided
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+972501234567',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
                validator: _validatePhone,
              ),
              const SizedBox(height: 28),

              // ── Error ──────────────────────────────────────────────────────
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: colorScheme.onErrorContainer, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Submit ─────────────────────────────────────────────────────
              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Building'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_rounded, size: 72, color: colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          'Building Created!',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'You can now log in with your phone number to access the Admin Dashboard.',
          style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),
        FilledButton(
          onPressed: widget.onCreated,
          child: const Text('Go to Login'),
        ),
      ],
    );
  }
}
