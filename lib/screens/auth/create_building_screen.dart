import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/address_autocomplete_field.dart';

/// Shown when a prospective building admin navigates to /setup.
///
/// Allows the admin to register a new building with a name and address.
/// The address field uses Google Places Autocomplete to validate and geocode
/// the address — latitude and longitude are captured automatically when the
/// user selects a suggestion.
///
/// After the building is created, the admin is navigated directly to the
/// AdminDashboard — no extra login step is needed since they are already
/// authenticated via Google OAuth.
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

  // Address state — filled by the autocomplete widget callback.
  String _address = '';
  double? _latitude;
  double? _longitude;

  bool _isLoading = false;
  bool _success = false;
  String? _errorMessage;

  @override
  void dispose() {
    _buildingNameController.dispose();
    super.dispose();
  }

  void _onAddressSelected(AddressResult result) {
    setState(() {
      _address = result.address;
      _latitude = result.latitude;
      _longitude = result.longitude;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;

      // Guard: ensure a valid session exists before calling the edge function.
      // After a Google OAuth redirect the session may not be restored yet.
      final session = supabase.auth.currentSession;
      if (session == null) {
        throw Exception('setup.not_signed_in'.tr());
      }

      final body = <String, dynamic>{
        'building_name': _buildingNameController.text.trim(),
        if (_address.isNotEmpty) 'address': _address,
        if (_latitude != null) 'latitude': _latitude,
        if (_longitude != null) 'longitude': _longitude,
      };

      // Explicitly pass the Authorization header so the edge function always
      // receives a valid JWT even if the Supabase client hasn't auto-injected it
      // (e.g. when the session was just restored from localStorage on web).
      final accessToken = session.accessToken;
      final response = await supabase.functions.invoke(
        'create-building-admin',
        body: body,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['success'] != true) {
        throw Exception(data?['error'] ?? 'Unknown error from server');
      }

      if (!mounted) return;
      // Navigate directly to the admin dashboard — no intermediate success view.
      widget.onCreated();
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
      return fieldName;
    }
    return null;
  }

  String? _validateAddress(String? value) {
    final text = (value ?? _address).trim();
    if (text.isEmpty) return 'setup.address_required'.tr();
    return null;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'language_toggle'.tr(),
            icon: const Icon(Icons.translate_rounded),
            onPressed: () {
              final current = context.locale;
              context.setLocale(
                current.languageCode == 'he'
                    ? const Locale('en')
                    : const Locale('he'),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _success
                  ? _buildSuccessView(theme, colorScheme)
                  : _buildFormView(theme, colorScheme),
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
          'setup.title'.tr(),
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'setup.subtitle'.tr(),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),

        // ── Form ──────────────────────────────────────────────────────────────
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Building name
              TextFormField(
                controller: _buildingNameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'setup.building_name_label'.tr(),
                  hintText: 'setup.building_name_hint'.tr(),
                  prefixIcon: const Icon(Icons.business_rounded),
                ),
                validator: (v) =>
                    _validateRequired(v, 'setup.building_name_required'.tr()),
              ),
              const SizedBox(height: 16),

              // Address — autocomplete
              AddressAutocompleteField(
                labelText: 'setup.building_address_label'.tr(),
                hintText: 'setup.building_address_hint'.tr(),
                initialValue: _address.isEmpty ? null : _address,
                validator: _validateAddress,
                onAddressSelected: _onAddressSelected,
                onChanged: (value) {
                  // If the user edits text after picking a suggestion,
                  // clear the cached lat/lng so we don't store stale coords.
                  if (value != _address) {
                    setState(() {
                      _address = value;
                      _latitude = null;
                      _longitude = null;
                    });
                  }
                },
              ),

              // Show captured coordinates (subtle hint that geocoding worked)
              if (_latitude != null && _longitude != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.check_circle_outline_rounded,
                        size: 14, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      tr('setup.location_confirmed', namedArgs: {
                        'lat': _latitude!.toStringAsFixed(4),
                        'lng': _longitude!.toStringAsFixed(4),
                      }),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 28),

              // ── Error ──────────────────────────────────────────────────────
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: colorScheme.onErrorContainer, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer),
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
                    : Text('setup.create_button'.tr()),
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
        Icon(Icons.check_circle_rounded,
            size: 72, color: colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          'setup.success_title'.tr(),
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'setup.success_message'.tr(),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),
        FilledButton(
          onPressed: widget.onCreated,
          child: Text('setup.go_to_dashboard'.tr()),
        ),
      ],
    );
  }
}
