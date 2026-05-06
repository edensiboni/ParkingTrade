import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../widgets/address_autocomplete_field.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/who_am_i_strip.dart';

class NotRegisteredScreen extends StatefulWidget {
  const NotRegisteredScreen({super.key});

  @override
  State<NotRegisteredScreen> createState() => _NotRegisteredScreenState();
}

class _NotRegisteredScreenState extends State<NotRegisteredScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _aptController = TextEditingController();
  final _notesController = TextEditingController();

  String _address = '';
  double? _latitude;
  double? _longitude;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _phoneController.text = _supabase.auth.currentUser?.phone ?? '';
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _aptController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    await AuthService().signOut();
    navigator.pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  void _onAddressSelected(AddressResult result) {
    setState(() {
      _address = result.address;
      _latitude = result.latitude;
      _longitude = result.longitude;
    });
  }

  Future<void> _submitJoinRequest() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();
    final apt = _aptController.text.trim();
    final name = _nameController.text.trim();
    final notes = _notesController.text.trim();

    setState(() => _submitting = true);
    try {
      final response = await _supabase.functions.invoke(
        'create-join-request',
        body: {
          'phone': phone,
          'apartment_identifier': apt,
          'name': name.isNotEmpty ? name : null,
          'notes': notes.isNotEmpty ? notes : null,
          'address': _address,
          if (_latitude != null) 'latitude': _latitude,
          if (_longitude != null) 'longitude': _longitude,
        },
      );

      if (response.status != 200) {
        final msg = response.data is Map ? response.data['error'] : null;
        throw Exception(msg ?? 'Failed to send join request');
      }

      if (!mounted) return;
      AppSnack.success(context, 'auth.not_registered.request_sent'.tr());
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/pending-approval', (route) => false);
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('auth.not_registered.title'.tr()),
        automaticallyImplyLeading: false,
        bottom: const WhoAmIStrip(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.no_accounts_outlined,
                    size: 72,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'auth.not_registered.title'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'auth.not_registered.message'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'auth.not_registered.join_request_title'.tr(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            AddressAutocompleteField(
                              labelText:
                                  'auth.not_registered.address_label'.tr(),
                              hintText:
                                  'auth.not_registered.address_hint'.tr(),
                              initialValue: _address.isEmpty ? null : _address,
                              onAddressSelected: _onAddressSelected,
                              onChanged: (value) {
                                if (value != _address) {
                                  setState(() {
                                    _address = value;
                                    _latitude = null;
                                    _longitude = null;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _aptController,
                              decoration: InputDecoration(
                                labelText:
                                    'auth.not_registered.apartment_label'.tr(),
                                hintText:
                                    'auth.not_registered.apartment_hint'.tr(),
                                prefixIcon: const Icon(
                                    Icons.door_front_door_outlined),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'auth.not_registered.apartment_required'
                                      .tr()
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phoneController,
                              readOnly: _phoneController.text.isNotEmpty,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText:
                                    'auth.not_registered.phone_label'.tr(),
                                hintText:
                                    'auth.not_registered.phone_hint'.tr(),
                                prefixIcon:
                                    const Icon(Icons.phone_outlined),
                              ),
                              validator: (v) {
                                final raw = (v ?? '').trim();
                                if (raw.isEmpty) {
                                  return 'auth.not_registered.phone_required'
                                      .tr();
                                }
                                final normalised =
                                    AuthService.normalisePhone(raw);
                                if (!RegExp(r'^\+\d{7,15}$')
                                    .hasMatch(normalised)) {
                                  return 'auth.not_registered.phone_invalid'
                                      .tr();
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText:
                                    'auth.not_registered.name_label'.tr(),
                                hintText:
                                    'auth.not_registered.name_hint'.tr(),
                                prefixIcon:
                                    const Icon(Icons.person_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _notesController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText:
                                    'auth.not_registered.notes_label'.tr(),
                                hintText:
                                    'auth.not_registered.notes_hint'.tr(),
                                prefixIcon:
                                    const Icon(Icons.notes_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _submitting ? null : _submitJoinRequest,
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: Text(_submitting
                                  ? 'auth.not_registered.sending'.tr()
                                  : 'auth.not_registered.send_request'.tr()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: () => _signOut(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('auth.not_registered.sign_out'.tr()),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushNamed('/setup'),
                    child: Text('auth.not_registered.admin_link'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
