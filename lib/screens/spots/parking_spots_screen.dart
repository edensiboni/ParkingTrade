import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../../services/parking_spot_service.dart';
import '../../services/auth_service.dart';
import '../../models/parking_spot.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_chip.dart';
import '../admin/admin_dashboard_screen.dart';
import 'manage_apartment_screen.dart';
import 'manage_availability_screen.dart';
import '../bookings/bookings_screen.dart';

class ParkingSpotsScreen extends StatefulWidget {
  const ParkingSpotsScreen({super.key});

  @override
  State<ParkingSpotsScreen> createState() => _ParkingSpotsScreenState();
}

class _ParkingSpotsScreenState extends State<ParkingSpotsScreen> {
  final _spotService = ParkingSpotService();
  final _authService = AuthService();
  final _adminService = AdminService();
  List<ParkingSpot> _spots = [];
  bool _isLoading = true;
  String? _displayName;
  bool _isAdmin = false;
  bool _isApartmentAdmin = false;
  int _pendingAdminCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  Future<void> _loadSpots() async {
    setState(() => _isLoading = true);
    try {
      final profile = await _authService.getCurrentProfile();
      _displayName = profile?.displayName;
      _isAdmin = profile?.isAdmin ?? false;
      _isApartmentAdmin = profile?.isApartmentAdmin ?? false;

      final spots = await _spotService.getUserSpots();
      if (!mounted) return;
      setState(() {
        _spots = spots;
        _isLoading = false;
      });

      // Best-effort pending count for building admins — non-blocking.
      if (_isAdmin) {
        _refreshAdminPendingCount();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context, 'home.could_not_load_spots'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  Future<void> _refreshAdminPendingCount() async {
    try {
      final pending = await _adminService.getPendingMembers();
      if (!mounted) return;
      setState(() => _pendingAdminCount = pending.length);
    } catch (_) {
      // Silent — the main screen keeps loading.
    }
  }

  Future<void> _openAdminDashboard() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
    );
    if (!mounted) return;
    _refreshAdminPendingCount();
  }

  Future<void> _openManageApartment() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManageApartmentScreen()),
    );
  }

  Future<void> _toggleSpotActive(ParkingSpot spot) async {
    try {
      await _spotService.updateSpot(spotId: spot.id, isActive: !spot.isActive);
      _loadSpots();
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'home.could_not_load_spots'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('home.sign_out_dialog_title'.tr()),
        content: Text('home.sign_out_dialog_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('home.cancel'.tr()),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('home.sign_out'.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pushNamedAndRemoveUntil('/auth', (r) => false);
      }
    }
  }

  void _toggleLanguage() {
    final current = context.locale;
    if (current.languageCode == 'he') {
      context.setLocale(const Locale('en'));
    } else {
      context.setLocale(const Locale('he'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activeCount = _spots.where((s) => s.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('home.title'.tr()),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: _pendingAdminCount > 0
                  ? Badge.count(
                      count: _pendingAdminCount,
                      backgroundColor: scheme.error,
                      textColor: scheme.onError,
                      child: const Icon(Icons.shield_outlined),
                    )
                  : const Icon(Icons.shield_outlined),
              tooltip: 'home.building_admin_tooltip'.tr(),
              onPressed: _openAdminDashboard,
            ),
          if (_isApartmentAdmin)
            IconButton(
              icon: const Icon(Icons.manage_accounts_outlined),
              tooltip: 'home.manage_apartment_tooltip'.tr(),
              onPressed: _openManageApartment,
            ),
          IconButton(
            icon: const Icon(Icons.directions_car_outlined),
            tooltip: 'home.bookings_tooltip'.tr(),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BookingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.language_rounded),
            tooltip: 'language_toggle'.tr(),
            onPressed: _toggleLanguage,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'signout') _confirmSignOut();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, size: 20),
                    const SizedBox(width: 12),
                    Text('home.sign_out'.tr()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSpots,
        child: _isLoading
            ? const SkeletonList(count: 4)
            : _spots.isEmpty
                ? EmptyState(
                    icon: Icons.local_parking_rounded,
                    title: 'home.no_spots_title'.tr(),
                    message: 'home.no_spots_message'.tr(),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _SummaryBanner(
                        scheme: scheme,
                        theme: theme,
                        displayName: _displayName,
                        activeCount: activeCount,
                        totalCount: _spots.length,
                      ),
                      const SizedBox(height: 16),
                      ..._spots.map(
                        (spot) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SpotCard(
                            spot: spot,
                            onToggle: () => _toggleSpotActive(spot),
                            onManageAvailability: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ManageAvailabilityScreen(spot: spot),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  final ColorScheme scheme;
  final ThemeData theme;
  final String? displayName;
  final int activeCount;
  final int totalCount;

  const _SummaryBanner({
    required this.scheme,
    required this.theme,
    required this.displayName,
    required this.activeCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = displayName?.isNotEmpty == true
        ? displayName!.split(' ').first
        : null;
    final greeting = firstName != null
        ? 'home.greeting_named'.tr(namedArgs: {'name': firstName})
        : 'home.greeting_unnamed'.tr();

    // Derive text direction from the active locale so that switching to English
    // (LTR) inside a Hebrew (RTL) ambient context doesn't produce bidi artifacts
    // like ",Welcome back" or "of 1 spots active 1".
    final isRtl = context.locale.languageCode == 'he';
    final textDir = isRtl ? TextDirection.rtl : TextDirection.ltr;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, Colors.black, 0.15)!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Directionality(
        textDirection: textDir,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'home.spots_active_summary'.tr(namedArgs: {
                'active': activeCount.toString(),
                'total': totalCount.toString(),
              }),
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'home.spots_toggle_hint'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotCard extends StatelessWidget {
  final ParkingSpot spot;
  final VoidCallback onToggle;
  final VoidCallback onManageAvailability;

  const _SpotCard({
    required this.spot,
    required this.onToggle,
    required this.onManageAvailability,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = spot.isActive;

    return Card(
      child: InkWell(
        onTap: active ? onManageAvailability : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primaryContainer.withValues(alpha: 0.5)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  active ? Icons.local_parking_rounded : Icons.block_rounded,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.spotIdentifier,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    StatusChip(
                      label: active
                          ? 'home.spot_active'.tr()
                          : 'home.spot_inactive'.tr(),
                      tone: active ? StatusTone.success : StatusTone.neutral,
                      icon: active
                          ? Icons.check_circle_outline
                          : Icons.pause_circle_outline,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                tooltip: 'home.manage_availability_tooltip'.tr(),
                onPressed: active ? onManageAvailability : null,
              ),
              Switch(
                value: active,
                onChanged: (_) => onToggle(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
