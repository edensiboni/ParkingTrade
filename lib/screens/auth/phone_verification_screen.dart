import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../models/profile.dart';

/// One-time phone verification screen for users who signed in via Google OAuth.
///
/// Flow:
///   1. User enters their phone number → OTP is sent.
///   2. User enters the OTP → Supabase links the phone to their auth account.
///   3. App checks if the phone exists in authorized_apartments:
///        • Found  → profile is already linked by magic trigger; navigate
///                   based on profile role/status.
///        • Not found → save phone to profile row and go to NotRegisteredScreen
///                      so the user can contact their building admin.
class PhoneVerificationScreen extends StatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final _authService = AuthService();
  final _supabase = Supabase.instance.client;

  // Step 1 — enter phone; Step 2 — enter OTP
  bool _otpSent = false;
  bool _isLoading = false;
  String? _errorMessage;
  String _normalisedPhone = '';

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ── Step 1: send OTP ─────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) {
      setState(() => _errorMessage = 'Please enter your phone number.');
      return;
    }

    final normalised = AuthService.normalisePhone(raw);
    if (!RegExp(r'^\+\d{7,15}$').hasMatch(normalised)) {
      setState(() =>
          _errorMessage = 'Enter a valid phone number, e.g. 050-123-4567');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.signInWithPhone(raw);
      if (!mounted) return;
      setState(() {
        _normalisedPhone = normalised;
        _otpSent = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  // ── Step 2: verify OTP and route ────────────────────────────────────────

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      setState(() => _errorMessage = 'Please enter the verification code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.verifyOtp(_normalisedPhone, otp);

      if (!mounted) return;

      // Check if this phone is in authorized_apartments.
      final rows = await _supabase
          .from('authorized_apartments')
          .select('id')
          .eq('phone', _normalisedPhone)
          .limit(1);

      if (!mounted) return;

      if ((rows as List).isNotEmpty) {
        // Phone is authorised → fetch profile and route properly.
        await _routeBasedOnProfile();
      } else {
        // Phone not found → save phone to profile for the admin's reference,
        // then go to NotRegisteredScreen.
        try {
          await _authService.updateProfile(phone: _normalisedPhone);
        } catch (_) {
          // Best-effort; don't block the redirect if update fails.
        }
        if (!mounted) return;
        Navigator.of(context)
            .pushReplacementNamed('/not-registered');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _routeBasedOnProfile() async {
    final profile = await _authService.getCurrentProfile();

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (profile == null || profile.apartmentId == null) {
      if (profile != null && profile.isAdmin) {
        Navigator.of(context)
            .pushReplacementNamed('/admin-dashboard');
      } else {
        Navigator.of(context).pushReplacementNamed('/not-registered');
      }
      return;
    }

    if (profile.isAdmin) {
      Navigator.of(context).pushReplacementNamed('/admin-dashboard');
    } else if (profile.status == ProfileStatus.pending) {
      Navigator.of(context).pushReplacementNamed('/pending-approval');
    } else if (profile.status == ProfileStatus.rejected) {
      Navigator.of(context).pushReplacementNamed('/rejected');
    } else {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  Icon(Icons.phone_rounded,
                      size: 56, color: scheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    _otpSent
                        ? 'Enter Verification Code'
                        : 'Verify Your Phone',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _otpSent
                        ? 'We sent a 6-digit code to $_normalisedPhone.'
                        : 'We need to verify your phone number to link it to your building account.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),

                  // ── Input ──────────────────────────────────────────────
                  if (!_otpSent) ...[
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _sendOtp(),
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        hintText: '05X-XXX-XXXX or +972 5X XXX XXXX',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _verifyOtp(),
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Verification Code',
                        hintText: '6-digit code',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                  ],

                  // ── Error ──────────────────────────────────────────────
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded,
                              color: scheme.onErrorContainer, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── Primary action ─────────────────────────────────────
                  FilledButton(
                    onPressed:
                        _isLoading ? null : (_otpSent ? _verifyOtp : _sendOtp),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_otpSent ? 'Verify' : 'Send Code'),
                  ),

                  // ── Back / resend ──────────────────────────────────────
                  if (_otpSent) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() {
                                _otpSent = false;
                                _otpController.clear();
                                _errorMessage = null;
                              }),
                      child: const Text('Use a different number'),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ── Sign out / try different account ───────────────────
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signOut,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Sign out'),
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
