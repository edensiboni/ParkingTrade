import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

// ---------------------------------------------------------------------------
// Phone normalisation is handled by AuthService.normalisePhone.
// The screen sends the normalised number to the service so the OTP step and
// the verification step always use the same E.164 string.
// ---------------------------------------------------------------------------

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _authService = AuthService();
  bool _isOtpSent = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// Returns the normalised E.164 phone number from the text field.
  String get _normalisedPhone =>
      AuthService.normalisePhone(_phoneController.text);

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final sanitized = _normalisedPhone;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Pass the normalised number so Supabase always receives clean E.164.
      await _authService.signInWithPhone(sanitized);
      setState(() {
        _isOtpSent = true;
        _isLoading = false;
      });
    } on Exception catch (e) {
      setState(() => _isLoading = false);

      final message = e.toString().replaceAll('Exception: ', '');
      // Check for 400-style errors surfaced from AuthService.
      final is400 = message.contains('couldn\'t send') ||
          message.contains('check your number') ||
          message.contains('Failed to send');

      final snackMessage = is400
          ? tr('auth.send_failed', namedArgs: {'phone': sanitized})
          : message;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Also show inline so the user sees it without dismissing the snackbar.
      setState(() => _errorMessage = snackMessage);
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'auth.otp_required'.tr());
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _authService.verifyOtp(
        _normalisedPhone,
        _otpController.text.trim(),
      );
      if (response.user != null) {
        // AuthWrapper handles routing.
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    _Hero(scheme: scheme, theme: theme),
                    const SizedBox(height: 40),
                    if (!_isOtpSent)
                      _buildPhoneStep(theme, scheme)
                    else
                      _buildOtpStep(theme, scheme),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: _errorMessage!),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'auth.privacy_note'.tr(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _signInWithGoogle,
          icon: const Icon(Icons.g_mobiledata, size: 28),
          label: Text('auth.continue_google'.tr()),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Divider(color: scheme.outlineVariant),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'auth.or'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Divider(color: scheme.outlineVariant),
            ),
          ],
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            labelText: 'auth.phone_label'.tr(),
            hintText: 'auth.phone_hint'.tr(),
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'auth.phone_required'.tr();
            }
            // Normalise first so we validate what will actually be sent.
            final normalised = AuthService.normalisePhone(value);
            // After normalisation the number must start with '+' and contain
            // only digits (7–15 digits after the '+').
            final e164Regex = RegExp(r'^\+\d{7,15}$');
            if (!e164Regex.hasMatch(normalised)) {
              return 'auth.phone_invalid'.tr();
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _isLoading ? null : _sendOtp,
          child: _isLoading
              ? const _ButtonSpinner()
              : Text('auth.send_code'.tr()),
        ),
      ],
    );
  }

  Widget _buildOtpStep(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'auth.enter_code_title'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          tr('auth.code_sent_to', namedArgs: {'phone': _normalisedPhone}),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          maxLength: 6,
          enabled: !_isLoading,
          decoration: const InputDecoration(
            hintText: '••••••',
            counterText: '',
          ),
          onChanged: (value) {
            if (value.length == 6 && !_isLoading) {
              _verifyOtp();
            }
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _isLoading ? null : _verifyOtp,
          child: _isLoading
              ? const _ButtonSpinner()
              : Text('auth.verify_continue'.tr()),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _isLoading
              ? null
              : () {
                  setState(() {
                    _isOtpSent = false;
                    _otpController.clear();
                    _errorMessage = null;
                  });
                },
          child: Text('auth.different_phone'.tr()),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final ColorScheme scheme;
  final ThemeData theme;
  const _Hero({required this.scheme, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.local_parking, size: 36, color: scheme.primary),
        ),
        const SizedBox(height: 20),
        Text(
          'auth.welcome'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'auth.tagline'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
