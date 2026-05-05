import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../models/spot_availability_period.dart';
import '../../services/admin_service.dart';
import '../../services/parking_spot_service.dart';
import '../../services/auth_service.dart';
import '../../models/parking_spot.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/add_availability_duration_sheet.dart';
import '../../widgets/status_chip.dart';
import '../admin/admin_dashboard_screen.dart';
import 'manage_apartment_screen.dart';
import 'manage_availability_screen.dart';
import '../bookings/bookings_screen.dart';
import '../bookings/available_spots_screen.dart';

class ParkingSpotsScreen extends StatefulWidget {
  const ParkingSpotsScreen({super.key});

  @override
  State<ParkingSpotsScreen> createState() => _ParkingSpotsScreenState();
}

class _ParkingSpotsScreenState extends State<ParkingSpotsScreen>
    with TickerProviderStateMixin {
  final _spotService = ParkingSpotService();
  final _authService = AuthService();
  final _adminService = AdminService();
  List<ParkingSpot> _spots = [];
  /// Maps spotId → active/future availability periods for display on the card.
  final Map<String, List<SpotAvailabilityPeriod>> _spotPeriods = {};
  bool _isLoading = true;
  String? _displayName;
  bool _isAdmin = false;
  bool _isApartmentAdmin = false;
  int _pendingAdminCount = 0;

  int _selectedTab = 0;

  late final AnimationController _tabAnimController;
  late final Animation<double> _tabFadeAnim;

  @override
  void initState() {
    super.initState();
    _tabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _tabFadeAnim = CurvedAnimation(
      parent: _tabAnimController,
      curve: Curves.easeOut,
    );
    _tabAnimController.forward();
    _loadSpots();
  }

  @override
  void dispose() {
    _tabAnimController.dispose();
    super.dispose();
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

      // Load availability periods for ALL spots (needed to determine true share state)
      final periodsMap = <String, List<SpotAvailabilityPeriod>>{};
      for (final spot in spots) {
        try {
          final periods = await _spotService.getAvailabilityPeriods(spot.id);
          periodsMap[spot.id] = periods;
        } catch (_) {
          // Non-fatal: skip period display for this spot
        }
      }

      if (!mounted) return;
      setState(() {
        _spots = spots;
        _spotPeriods
          ..clear()
          ..addAll(periodsMap);
        _isLoading = false;
      });

      if (_isAdmin) {
        _refreshAdminPendingCount();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context,
          'home.could_not_load_spots'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  /// Returns true if there is at least one non-recurring availability period
  /// for [spotId] that is currently active (now is between start and end).
  bool _hasActivePeriod(String spotId) {
    final periods = _spotPeriods[spotId] ?? [];
    final now = DateTime.now();
    return periods.any(
      (p) => !p.isRecurring &&
          p.startTime.isBefore(now) &&
          p.endTime.isAfter(now),
    );
  }

  /// Returns the first active period for a spot, or null.
  SpotAvailabilityPeriod? _activePeriod(String spotId) {
    final periods = _spotPeriods[spotId] ?? [];
    final now = DateTime.now();
    try {
      return periods.firstWhere(
        (p) => !p.isRecurring &&
            p.startTime.isBefore(now) &&
            p.endTime.isAfter(now),
      );
    } catch (_) {
      return null;
    }
  }

  /// Opens the duration sheet and, if a duration is selected, creates a
  /// spot_availability_periods record. The card becomes green only after this.
  Future<void> _quickShare(ParkingSpot spot) async {
    final duration = await showAddAvailabilityDurationSheet(context);
    if (duration == null || !mounted) return;

    try {
      await _spotService.addAvailabilityPeriod(
        spotId: spot.id,
        startTime: duration.startTime,
        endTime: duration.endTime,
      );
      if (!mounted) return;
      final timeFmt = DateFormat('HH:mm');
      AppSnack.success(
        context,
        'home.quick_share_added'.tr(
          namedArgs: {'time': timeFmt.format(duration.endTime.toLocal())},
        ),
      );
      _loadSpots();
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(
        context,
        'home.quick_share_error'.tr(namedArgs: {'error': e.toString()}),
      );
    }
  }

  /// Deletes the currently-active availability period for the spot, effectively
  /// stopping sharing immediately.
  Future<void> _stopSharing(ParkingSpot spot) async {
    final active = _activePeriod(spot.id);
    if (active == null) return;

    try {
      await _spotService.deleteAvailabilityPeriod(active.id);
      if (!mounted) return;
      AppSnack.success(context, 'home.quick_share_stopped'.tr());
      _loadSpots();
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(
        context,
        'home.quick_share_error'.tr(namedArgs: {'error': e.toString()}),
      );
    }
  }

  Future<void> _refreshAdminPendingCount() async {
    try {
      final pending = await _adminService.getPendingMembers();
      if (!mounted) return;
      setState(() => _pendingAdminCount = pending.length);
    } catch (_) {}
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

  void _onTabSelected(int index) {
    if (index == _selectedTab) return;
    _tabAnimController.forward(from: 0);
    setState(() => _selectedTab = index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: _PremiumAppBar(
        selectedTab: _selectedTab,
        isAdmin: _isAdmin,
        isApartmentAdmin: _isApartmentAdmin,
        pendingAdminCount: _pendingAdminCount,
        onAdminTap: _openAdminDashboard,
        onManageApartmentTap: _openManageApartment,
        onBookingsTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BookingsScreen()),
        ),
        onLanguageTap: _toggleLanguage,
        onSignOutTap: _confirmSignOut,
      ),
      body: FadeTransition(
        opacity: _tabFadeAnim,
        child: IndexedStack(
          index: _selectedTab,
          children: [
            // Tab 0: My Spots
            RefreshIndicator(
              onRefresh: _loadSpots,
              color: scheme.primary,
              child: _isLoading
                  ? const SkeletonList(count: 4)
                  : _spots.isEmpty
                      ? EmptyState(
                          icon: Icons.local_parking_rounded,
                          title: 'home.no_spots_title'.tr(),
                          message: 'home.no_spots_message'.tr(),
                        )
                      : _MySpotsTab(
                          spots: _spots,
                          spotPeriods: _spotPeriods,
                          displayName: _displayName,
                          hasActivePeriod: _hasActivePeriod,
                          onQuickShare: _quickShare,
                          onStopSharing: _stopSharing,
                          onManageAvailability: (spot) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ManageAvailabilityScreen(spot: spot),
                              ),
                            ).then((_) => _loadSpots());
                          },
                        ),
            ),

            // Tab 1: Find Parking
            const AvailableSpotsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _PremiumNavBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: _onTabSelected,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedTab;
  final bool isAdmin;
  final bool isApartmentAdmin;
  final int pendingAdminCount;
  final VoidCallback onAdminTap;
  final VoidCallback onManageApartmentTap;
  final VoidCallback onBookingsTap;
  final VoidCallback onLanguageTap;
  final VoidCallback onSignOutTap;

  const _PremiumAppBar({
    required this.selectedTab,
    required this.isAdmin,
    required this.isApartmentAdmin,
    required this.pendingAdminCount,
    required this.onAdminTap,
    required this.onManageApartmentTap,
    required this.onBookingsTap,
    required this.onLanguageTap,
    required this.onSignOutTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final title = selectedTab == 0
        ? 'home.nav_my_spots'.tr()
        : 'home.nav_find_parking'.tr();

    return Container(
      height: 64 + MediaQuery.of(context).padding.top,
      decoration: const BoxDecoration(
        color: AppTheme.appBackground,
        border: Border(
          bottom: BorderSide(color: AppTheme.hairline, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              // Brand icon
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brandIndigo.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.local_parking_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.2),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    title,
                    key: ValueKey(selectedTab),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              // Action row
              if (isAdmin)
                _AppBarIconBtn(
                  icon: pendingAdminCount > 0
                      ? Badge.count(
                          count: pendingAdminCount,
                          backgroundColor: scheme.error,
                          textColor: scheme.onError,
                          child: const Icon(Icons.shield_outlined, size: 22),
                        )
                      : const Icon(Icons.shield_outlined, size: 22),
                  onTap: onAdminTap,
                ),
              if (isApartmentAdmin)
                _AppBarIconBtn(
                  icon: const Icon(Icons.manage_accounts_outlined, size: 22),
                  onTap: onManageApartmentTap,
                ),
              _AppBarIconBtn(
                icon: const Icon(Icons.receipt_long_outlined, size: 22),
                onTap: onBookingsTap,
              ),
              _AppBarIconBtn(
                icon: const Icon(Icons.language_rounded, size: 22),
                onTap: onLanguageTap,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    size: 22, color: AppTheme.inkMuted),
                onSelected: (v) {
                  if (v == 'signout') onSignOutTap();
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
        ),
      ),
    );
  }
}

class _AppBarIconBtn extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;
  const _AppBarIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.only(left: 2),
        alignment: Alignment.center,
        child: IconTheme(
          data: const IconThemeData(color: AppTheme.inkMuted, size: 22),
          child: icon,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Spots Tab
// ─────────────────────────────────────────────────────────────────────────────

class _MySpotsTab extends StatelessWidget {
  final List<ParkingSpot> spots;
  final Map<String, List<SpotAvailabilityPeriod>> spotPeriods;
  final String? displayName;
  final bool Function(String spotId) hasActivePeriod;
  final void Function(ParkingSpot) onQuickShare;
  final void Function(ParkingSpot) onStopSharing;
  final void Function(ParkingSpot) onManageAvailability;

  const _MySpotsTab({
    required this.spots,
    required this.spotPeriods,
    required this.displayName,
    required this.hasActivePeriod,
    required this.onQuickShare,
    required this.onStopSharing,
    required this.onManageAvailability,
  });

  @override
  Widget build(BuildContext context) {
    // "Shared" count now based on active availability periods, not isActive flag.
    final activeCount = spots.where((s) => hasActivePeriod(s.id)).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        _HeroHeader(
          displayName: displayName,
          activeCount: activeCount,
          totalCount: spots.length,
        ),
        const SizedBox(height: 20),
        ...spots.map(
          (spot) {
            final isShared = hasActivePeriod(spot.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _SpotTicketCard(
                spot: spot,
                periods: spotPeriods[spot.id] ?? [],
                isShared: isShared,
                onQuickShare: () => onQuickShare(spot),
                onStopSharing: () => onStopSharing(spot),
                onManageAvailability: () => onManageAvailability(spot),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Header
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final String? displayName;
  final int activeCount;
  final int totalCount;

  const _HeroHeader({
    required this.displayName,
    required this.activeCount,
    required this.totalCount,
  });

  String _greeting(BuildContext context) {
    final hour = DateTime.now().hour;
    final firstName = displayName?.isNotEmpty == true
        ? displayName!.split(' ').first
        : null;
    final String base;
    final String emoji;
    if (hour < 12) {
      base = 'home.greeting_morning'.tr();
      emoji = '🌤';
    } else if (hour < 18) {
      base = 'home.greeting_afternoon'.tr();
      emoji = '☀️';
    } else {
      base = 'home.greeting_evening'.tr();
      emoji = '🌙';
    }
    if (firstName != null) {
      return '$base, $firstName $emoji';
    }
    return '$base $emoji';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = context.locale.languageCode == 'he';
    final textDir = isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr;
    final allActive = activeCount == totalCount && totalCount > 0;
    final noneActive = activeCount == 0;

    return Directionality(
      textDirection: textDir,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            _greeting(context),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppTheme.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'home.ready_to_share'.tr(),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatPill(
                icon: Icons.check_circle_rounded,
                label: 'home.stat_shared'.tr(namedArgs: {'shared': '$activeCount'}),
                color: activeCount > 0 ? AppTheme.success : AppTheme.inkSoft,
                bgColor: activeCount > 0
                    ? const Color(0xFFE4F3EA)
                    : AppTheme.subtleSurface,
              ),
              const SizedBox(width: 8),
              _StatPill(
                icon: Icons.local_parking_rounded,
                label: 'home.stat_total'.tr(namedArgs: {'total': '$totalCount'}),
                color: AppTheme.inkMuted,
                bgColor: AppTheme.subtleSurface,
              ),
              const Spacer(),
              if (allActive)
                _StatPill(
                  icon: Icons.star_rounded,
                  label: 'home.all_shared'.tr(),
                  color: const Color(0xFF8A5A10),
                  bgColor: const Color(0xFFFDF1DA),
                ),
              if (noneActive && totalCount > 0)
                _StatPill(
                  icon: Icons.info_outline_rounded,
                  label: 'home.none_shared'.tr(),
                  color: AppTheme.inkMuted,
                  bgColor: AppTheme.subtleSurface,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Spot Ticket Card — looks like a physical parking pass
// ─────────────────────────────────────────────────────────────────────────────

class _SpotTicketCard extends StatefulWidget {
  final ParkingSpot spot;
  final List<SpotAvailabilityPeriod> periods;
  /// True when there is a currently-active availability window for this spot.
  final bool isShared;
  final VoidCallback onQuickShare;
  final VoidCallback onStopSharing;
  final VoidCallback onManageAvailability;

  const _SpotTicketCard({
    required this.spot,
    required this.periods,
    required this.isShared,
    required this.onQuickShare,
    required this.onStopSharing,
    required this.onManageAvailability,
  });

  @override
  State<_SpotTicketCard> createState() => _SpotTicketCardState();
}

class _SpotTicketCardState extends State<_SpotTicketCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _glowAnim = CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    );
    if (widget.isShared) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_SpotTicketCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isShared && !_glowController.isAnimating) {
      _glowController.repeat(reverse: true);
    } else if (!widget.isShared && _glowController.isAnimating) {
      _glowController.stop();
      _glowController.animateTo(0,
          duration: const Duration(milliseconds: 300));
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isShared = widget.isShared;

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) {
        final glowOpacity =
            isShared ? (0.18 + _glowAnim.value * 0.12) : 0.0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isShared
                  ? AppTheme.success
                      .withValues(alpha: 0.4 + _glowAnim.value * 0.2)
                  : AppTheme.hairline,
              width: isShared ? 1.5 : 1.0,
            ),
            boxShadow: isShared
                ? [
                    BoxShadow(
                      color: AppTheme.success
                          .withValues(alpha: glowOpacity),
                      blurRadius: 16 + _glowAnim.value * 8,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: AppTheme.ink.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: AppTheme.ink.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isShared ? widget.onManageAvailability : null,
            child: Column(
              children: [
                _CardHeader(
                  spot: widget.spot,
                  periods: widget.periods,
                  isShared: widget.isShared,
                ),
                _PerforationDivider(active: isShared),
                _CardActions(
                  spot: widget.spot,
                  isShared: isShared,
                  onQuickShare: widget.onQuickShare,
                  onStopSharing: widget.onStopSharing,
                  onManageAvailability: widget.onManageAvailability,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final ParkingSpot spot;
  final List<SpotAvailabilityPeriod> periods;
  /// True when there is a currently-active availability window.
  final bool isShared;
  const _CardHeader({
    required this.spot,
    required this.periods,
    required this.isShared,
  });

  /// Finds the best availability window to display:
  /// 1. Currently active (now is within start–end)
  /// 2. Next upcoming (soonest future start)
  SpotAvailabilityPeriod? _bestPeriod() {
    final now = DateTime.now();
    // Filter to non-recurring, future or currently-active periods
    final relevant = periods
        .where((p) => !p.isRecurring && p.endTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (relevant.isEmpty) return null;
    // Prefer an actively-live period
    final livePeriods = relevant.where(
      (p) => p.startTime.isBefore(now) && p.endTime.isAfter(now),
    );
    return livePeriods.isNotEmpty ? livePeriods.first : relevant.first;
  }

  String _formatWindowLabel(SpotAvailabilityPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final startDay =
        DateTime(period.startTime.year, period.startTime.month, period.startTime.day);

    final timeFmt = DateFormat('HH:mm');
    final start = timeFmt.format(period.startTime.toLocal());
    final end = timeFmt.format(period.endTime.toLocal());

    if (startDay == today) {
      return 'home.availability_today'.tr(namedArgs: {'start': start, 'end': end});
    } else if (startDay == tomorrow) {
      return 'home.availability_tomorrow'.tr(namedArgs: {'start': start, 'end': end});
    } else {
      final dateFmt = DateFormat('d MMM');
      final date = dateFmt.format(period.startTime.toLocal());
      return 'home.availability_date'.tr(namedArgs: {'date': date, 'start': start, 'end': end});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bestPeriod = _bestPeriod();
    final windowLabel = bestPeriod != null ? _formatWindowLabel(bestPeriod) : null;
    final now = DateTime.now();
    final isLiveNow = bestPeriod != null &&
        bestPeriod.startTime.isBefore(now) &&
        bestPeriod.endTime.isAfter(now);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: isShared
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEEFBF3), Color(0xFFF0FDF4)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF8F9FC), Color(0xFFF1F3F9)],
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large spot number badge
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: isShared
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.success, Color(0xFF22C55E)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFCBD2DD), Color(0xFFB0B8C8)],
                    ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: isShared
                  ? [
                      BoxShadow(
                        color: AppTheme.success.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_parking_rounded,
                    color: Colors.white, size: 22),
                const SizedBox(height: 1),
                Text(
                  spot.spotIdentifier,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Info column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'home.parking_spot_label'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.inkSoft,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  spot.spotIdentifier,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: AppTheme.ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isShared
                      ? StatusChip(
                          key: const ValueKey('shared'),
                          label: '● ${'home.shared_with_neighbors'.tr()}',
                          tone: StatusTone.success,
                        )
                      : StatusChip(
                          key: const ValueKey('not_shared'),
                          label: 'home.not_sharing'.tr(),
                          tone: StatusTone.neutral,
                        ),
                ),
                // ── Time window chip ──────────────────────────────────────
                if (windowLabel != null) ...[
                  const SizedBox(height: 10),
                  _TimeWindowChip(
                    label: windowLabel,
                    isLive: isLiveNow,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill-shaped chip showing the exact availability timeframe.
class _TimeWindowChip extends StatelessWidget {
  final String label;
  final bool isLive;

  const _TimeWindowChip({required this.label, required this.isLive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Live = green tones; upcoming = indigo tones
    final bgColor = isLive
        ? const Color(0xFFDCFCE7)
        : AppTheme.brandIndigo.withValues(alpha: 0.09);
    final borderColor = isLive
        ? AppTheme.success.withValues(alpha: 0.45)
        : AppTheme.brandIndigo.withValues(alpha: 0.22);
    final iconColor = isLive ? AppTheme.success : AppTheme.brandIndigo;
    final textColor = isLive
        ? const Color(0xFF166534)
        : AppTheme.brandIndigo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLive ? Icons.access_time_filled_rounded : Icons.calendar_today_rounded,
            size: 12,
            color: iconColor,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PerforationDivider extends StatelessWidget {
  final bool active;
  const _PerforationDivider({required this.active});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Left notch
          Positioned(
            left: -12,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppTheme.appBackground,
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Right notch
          Positioned(
            right: -12,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppTheme.appBackground,
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Dashed line
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _DashedLine(
              color: active
                  ? AppTheme.success.withValues(alpha: 0.3)
                  : AppTheme.hairline,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        painter: _DashedLinePainter(color: color),
        size: Size.infinite,
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    double x = 0;
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

class _CardActions extends StatelessWidget {
  final ParkingSpot spot;
  /// True when there is a currently-active availability window.
  final bool isShared;
  final VoidCallback onQuickShare;
  final VoidCallback onStopSharing;
  final VoidCallback onManageAvailability;

  const _CardActions({
    required this.spot,
    required this.isShared,
    required this.onQuickShare,
    required this.onStopSharing,
    required this.onManageAvailability,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          // Primary action button
          Expanded(
            child: GestureDetector(
              onTap: isShared ? onStopSharing : onQuickShare,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: isShared
                      ? LinearGradient(
                          colors: [
                            AppTheme.success,
                            AppTheme.success.withValues(alpha: 0.85),
                          ],
                        )
                      : const LinearGradient(
                          colors: [
                            AppTheme.brandIndigo,
                            AppTheme.brandViolet,
                          ],
                        ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (isShared
                              ? AppTheme.success
                              : AppTheme.brandIndigo)
                          .withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        isShared
                            ? Icons.pause_circle_filled_rounded
                            : Icons.share_rounded,
                        key: ValueKey(isShared),
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        isShared
                            ? 'home.stop_sharing'.tr()
                            : 'home.share_spot'.tr(),
                        key: ValueKey(isShared),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Calendar button — always tappable so users can manage windows
          // even when the spot is not currently shared.
          GestureDetector(
            onTap: onManageAvailability,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppTheme.subtleSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.hairline),
              ),
              child: const Icon(Icons.calendar_month_rounded,
                  size: 20, color: AppTheme.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Navigation Bar
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumNavBar extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onDestinationSelected;

  const _PremiumNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border(top: BorderSide(color: AppTheme.hairline, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.local_parking_outlined,
                selectedIcon: Icons.local_parking_rounded,
                label: 'home.nav_my_spots'.tr(),
                selected: selectedIndex == 0,
                onTap: () => onDestinationSelected(0),
              ),
              _NavItem(
                icon: Icons.search_outlined,
                selectedIcon: Icons.search_rounded,
                label: 'home.nav_find_parking'.tr(),
                selected: selectedIndex == 1,
                onTap: () => onDestinationSelected(1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.brandIndigo.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Icon(
                selected ? selectedIcon : icon,
                key: ValueKey(selected),
                color: selected ? AppTheme.brandIndigo : AppTheme.inkSoft,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style:
                  (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
                color: selected
                    ? AppTheme.brandIndigo
                    : AppTheme.inkSoft,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
