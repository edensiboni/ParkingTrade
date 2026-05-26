import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/spot_availability_period.dart';
import '../../services/admin_service.dart';
import '../../services/parking_spot_service.dart';
import '../../services/auth_service.dart';
import '../../models/parking_spot.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_chip.dart';
import '../admin/admin_dashboard_screen.dart';
import 'manage_apartment_screen.dart';
import 'manage_availability_screen.dart';
import '../bookings/bookings_screen.dart';
import 'available_now_feed.dart';

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

  /// Immediately shares [spot] until [endTime] without opening any sheet.
  /// Used by the quick-preset chips on the spot card.
  Future<void> _quickSharePreset(ParkingSpot spot, DateTime endTime) async {
    final now = DateTime.now();
    try {
      await _spotService.addAvailabilityPeriod(
        spotId: spot.id,
        startTime: now,
        endTime: endTime,
      );
      if (!mounted) return;
      final timeFmt = DateFormat('HH:mm');
      AppSnack.success(
        context,
        'home.quick_share_added'.tr(
          namedArgs: {'time': timeFmt.format(endTime.toLocal())},
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
      if (!mounted) return;
      context.go('/auth');
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
            // Tab 0: Available Now (community feed — default landing)
            const AvailableNowFeed(),

            // Tab 1: My Spot — Hero Toggle
            RefreshIndicator(
              onRefresh: _loadSpots,
              color: scheme.primary,
              child: _isLoading
                  ? const SkeletonList(count: 2)
                  : _spots.isEmpty
                      ? EmptyState(
                          icon: Icons.local_parking_rounded,
                          title: 'home.no_spots_title'.tr(),
                          message: 'home.no_spots_message'.tr(),
                        )
                      : _HeroSpotToggle(
                          spots: _spots,
                          spotPeriods: _spotPeriods,
                          displayName: _displayName,
                          hasActivePeriod: _hasActivePeriod,
                          activePeriod: _activePeriod,
                          onQuickSharePreset: _quickSharePreset,
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
        ? 'home.nav_available'.tr()
        : 'home.nav_my_spot'.tr();

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
                  if (v == 'signout') { onSignOutTap(); }
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
        margin: const EdgeInsetsDirectional.only(start: 2),
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
// Hero Spot Toggle — the new "My Spot" tab UI
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSpotToggle extends StatelessWidget {
  final List<ParkingSpot> spots;
  final Map<String, List<SpotAvailabilityPeriod>> spotPeriods;
  final String? displayName;
  final bool Function(String spotId) hasActivePeriod;
  final SpotAvailabilityPeriod? Function(String spotId) activePeriod;
  final Future<void> Function(ParkingSpot, DateTime endTime) onQuickSharePreset;
  final Future<void> Function(ParkingSpot) onStopSharing;
  final void Function(ParkingSpot) onManageAvailability;

  const _HeroSpotToggle({
    required this.spots,
    required this.spotPeriods,
    required this.displayName,
    required this.hasActivePeriod,
    required this.activePeriod,
    required this.onQuickSharePreset,
    required this.onStopSharing,
    required this.onManageAvailability,
  });

  String _greeting() {
    final hour = DateTime.now().hour;
    final firstName = displayName?.isNotEmpty == true
        ? displayName!.split(' ').first
        : null;
    if (hour < 12) {
      return 'home.hero_greeting_morning'.tr() +
          (firstName != null ? ' ${'home.hero_greeting_name'.tr(namedArgs: {'name': firstName})}' : '');
    }
    if (hour < 18) {
      return 'home.hero_greeting_afternoon'.tr() +
          (firstName != null ? ' ${'home.hero_greeting_name'.tr(namedArgs: {'name': firstName})}' : '');
    }
    return 'home.hero_greeting_evening'.tr() +
        (firstName != null ? ' ${'home.hero_greeting_name'.tr(namedArgs: {'name': firstName})}' : '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 40),
      children: [
        // ── Greeting ────────────────────────────────────────────────────────
        Text(
          _greeting(),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppTheme.inkMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'home.ready_to_share'.tr(),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: AppTheme.ink,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 28),
        // ── One hero card per spot ───────────────────────────────────────────
        ...spots.map((spot) {
          final isShared = hasActivePeriod(spot.id);
          final active = activePeriod(spot.id);
          final periods = spotPeriods[spot.id] ?? [];
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _HeroToggleCard(
              spot: spot,
              periods: periods,
              isShared: isShared,
              activePeriod: active,
              onRelease: (endTime) => onQuickSharePreset(spot, endTime),
              onMarkOccupied: () => onStopSharing(spot),
              onManage: () => onManageAvailability(spot),
            ),
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Toggle Card — the big single-spot card that dominates the My Spot tab
// ─────────────────────────────────────────────────────────────────────────────

class _HeroToggleCard extends StatefulWidget {
  final ParkingSpot spot;
  final List<SpotAvailabilityPeriod> periods;
  final bool isShared;
  final SpotAvailabilityPeriod? activePeriod;
  /// Called with the desired end-time when the user releases the spot.
  final Future<void> Function(DateTime endTime) onRelease;
  /// Called when the user marks the spot as occupied again.
  final Future<void> Function() onMarkOccupied;
  final VoidCallback onManage;

  const _HeroToggleCard({
    required this.spot,
    required this.periods,
    required this.isShared,
    required this.activePeriod,
    required this.onRelease,
    required this.onMarkOccupied,
    required this.onManage,
  });

  @override
  State<_HeroToggleCard> createState() => _HeroToggleCardState();
}

class _HeroToggleCardState extends State<_HeroToggleCard>
    with TickerProviderStateMixin {
  // ── Sage glow pulse (runs while shared) ──────────────────────────────────
  late final AnimationController _glowController;
  late final Animation<double> _glowAnim;

  // ── Success checkmark overlay (scale + fade) ──────────────────────────────
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;
  late final Animation<double> _checkOpacity;
  bool _showCheck = false;

  // ── Release-button press-scale (tactile feedback on tap) ──────────────────
  late final AnimationController _pressController;
  late final Animation<double> _pressScale;

  // ── Stop button scale-down dismiss animation ───────────────────────────────
  late final AnimationController _stopController;
  late final Animation<double> _stopScale;

  // ── Time-picker end time (defaults to 08:00 next morning) ─────────────────
  late DateTime _endTime;

  @override
  void initState() {
    super.initState();
    _endTime = _defaultEndTime();

    // Glow pulse
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _glowAnim = CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    );
    if (widget.isShared) { _glowController.repeat(reverse: true); }

    // Success checkmark: scale 0→1.15→1 with bounce, then fade out
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _checkScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.15)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.15, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 15,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 35),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 25,
      ),
    ]).animate(_checkController);
    _checkOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 65),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_checkController);
    _checkController.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _showCheck = false);
      }
    });

    // Release-button press bounce
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _pressScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.94)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.94, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
    ]).animate(_pressController);

    // Stop-button scale dismiss
    _stopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _stopScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.88)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.88, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 65,
      ),
    ]).animate(_stopController);
  }

  @override
  void didUpdateWidget(_HeroToggleCard old) {
    super.didUpdateWidget(old);
    if (widget.isShared && !_glowController.isAnimating) {
      _glowController.repeat(reverse: true);
    } else if (!widget.isShared && _glowController.isAnimating) {
      _glowController.stop();
      _glowController.animateTo(0, duration: const Duration(milliseconds: 300));
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    _checkController.dispose();
    _pressController.dispose();
    _stopController.dispose();
    super.dispose();
  }

  /// Default end time = 08:00 AM tomorrow morning.
  static DateTime _defaultEndTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 8, 0);
  }

  void _triggerCheckmark() {
    if (!mounted) return;
    setState(() => _showCheck = true);
    _checkController.forward(from: 0);
  }

  Future<void> _handleRelease() async {
    _pressController.forward(from: 0);
    await widget.onRelease(_endTime);
    _triggerCheckmark();
  }

  Future<void> _handleMarkOccupied() async {
    _stopController.forward(from: 0);
    await widget.onMarkOccupied();
  }

  /// Opens a time picker so the user can adjust the end time.
  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _endTime.hour, minute: _endTime.minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final now = DateTime.now();
    // Apply the picked time to tomorrow if the resulting time is in the past.
    DateTime candidate = DateTime(
      now.year, now.month, now.day, picked.hour, picked.minute,
    );
    if (candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    setState(() => _endTime = candidate);
  }

  /// Best period to show in the "until" line when shared.
  SpotAvailabilityPeriod? _bestPeriod() {
    final now = DateTime.now();
    final relevant = widget.periods
        .where((p) => !p.isRecurring && p.endTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (relevant.isEmpty) return null;
    final live = relevant.where(
      (p) => p.startTime.isBefore(now) && p.endTime.isAfter(now),
    );
    return live.isNotEmpty ? live.first : relevant.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isShared = widget.isShared;
    final timeFmt = DateFormat('HH:mm');
    final best = _bestPeriod();
    final untilLabel = best != null
        ? timeFmt.format(best.endTime.toLocal())
        : timeFmt.format(_endTime);

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) {
        final glowOpacity = isShared ? (0.14 + _glowAnim.value * 0.14) : 0.0;
        final glowColor = isShared
            ? AppTheme.communitySage
            : AppTheme.ink;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(
              color: isShared
                  ? AppTheme.communitySage
                      .withValues(alpha: 0.38 + _glowAnim.value * 0.22)
                  : AppTheme.hairline,
              width: isShared ? 1.6 : 1.0,
            ),
            boxShadow: [
              if (isShared)
                BoxShadow(
                  color: glowColor.withValues(alpha: glowOpacity),
                  blurRadius: 24 + _glowAnim.value * 10,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                ),
              BoxShadow(
                color: AppTheme.ink.withValues(alpha: isShared ? 0.04 : 0.03),
                blurRadius: isShared ? 14 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        child: Stack(
          children: [
            // ── Card body ──────────────────────────────────────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Top gradient area ─────────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    gradient: isShared
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.communitySageSoft,
                              Color(0xFFDFF0E8),
                            ],
                          )
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFF8F9FC), Color(0xFFF1F3F9)],
                          ),
                  ),
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 28, 24, 28),
                  child: Column(
                    children: [
                      // ── Spot badge + identifier row ─────────────────────
                      Row(
                        children: [
                          // Parking icon badge
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeOutCubic,
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: isShared
                                  ? const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppTheme.communitySage,
                                        AppTheme.communitySageDeep,
                                      ],
                                    )
                                  : const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFCBD2DD),
                                        Color(0xFFB0B8C8),
                                      ],
                                    ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: isShared
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.communitySage
                                            .withValues(alpha: 0.35),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: const Icon(
                              Icons.local_parking_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'home.hero_spot_label'
                                    .tr(namedArgs: {'id': widget.spot.spotIdentifier}),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: AppTheme.ink,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
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
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // ── Hero status line ────────────────────────────────
                      // "פנויה עד 08:00" (large) or "תפוסה" (muted)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.12),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: isShared
                            ? _HeroStatusAvailable(
                                key: const ValueKey('available'),
                                untilTime: untilLabel,
                              )
                            : _HeroStatusOccupied(
                                key: const ValueKey('occupied'),
                              ),
                      ),
                    ],
                  ),
                ),

                // ── Divider ────────────────────────────────────────────────
                Container(
                  height: 1,
                  color: isShared
                      ? AppTheme.communitySage.withValues(alpha: 0.18)
                      : AppTheme.hairline,
                ),

                // ── Action area ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 20),
                  child: isShared
                      ? _SharedActions(
                          stopScale: _stopScale,
                          onMarkOccupied: _handleMarkOccupied,
                          onManage: widget.onManage,
                        )
                      : _UnsharedActions(
                          endTime: _endTime,
                          pressScale: _pressScale,
                          onRelease: _handleRelease,
                          onPickTime: _pickEndTime,
                          onManage: widget.onManage,
                        ),
                ),
              ],
            ),

            // ── Success checkmark overlay ──────────────────────────────────
            if (_showCheck)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _checkController,
                    builder: (context, _) => Opacity(
                      opacity: _checkOpacity.value,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.communitySageSoft
                              .withValues(alpha: 0.88),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusXl),
                        ),
                        child: Center(
                          child: Transform.scale(
                            scale: _checkScale.value,
                            child: Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: AppTheme.communitySage
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.communitySageDeep,
                                size: 50,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Hero status widgets ────────────────────────────────────────────────────────

class _HeroStatusAvailable extends StatelessWidget {
  final String untilTime;
  const _HeroStatusAvailable({super.key, required this.untilTime});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'home.hero_available_until'.tr(namedArgs: {'time': untilTime}),
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            color: AppTheme.communitySageDeep,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _HeroStatusOccupied extends StatelessWidget {
  const _HeroStatusOccupied({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'home.hero_occupied'.tr(),
      textAlign: TextAlign.center,
      style: theme.textTheme.displaySmall?.copyWith(
        color: AppTheme.inkSoft,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.1,
      ),
    );
  }
}

// ── Action panels ──────────────────────────────────────────────────────────────

/// Shown when the spot is currently available — "Mark occupied" + "Manage" link.
class _SharedActions extends StatelessWidget {
  final Animation<double> stopScale;
  final Future<void> Function() onMarkOccupied;
  final VoidCallback onManage;

  const _SharedActions({
    required this.stopScale,
    required this.onMarkOccupied,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // "Mark as occupied" button
        AnimatedBuilder(
          animation: stopScale,
          builder: (context, child) =>
              Transform.scale(scale: stopScale.value, child: child),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onMarkOccupied,
              icon: const Icon(Icons.block_rounded, size: 18),
              label: Text('home.hero_mark_occupied'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.inkMuted,
                side: const BorderSide(color: AppTheme.hairline, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Manage link
        GestureDetector(
          onTap: onManage,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_month_rounded,
                  size: 14, color: AppTheme.inkSoft),
              const SizedBox(width: 5),
              Text(
                'home.hero_manage'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown when the spot is occupied — "Release spot" big CTA + time-picker row.
class _UnsharedActions extends StatelessWidget {
  final DateTime endTime;
  final Animation<double> pressScale;
  final Future<void> Function() onRelease;
  final VoidCallback onPickTime;
  final VoidCallback onManage;

  const _UnsharedActions({
    required this.endTime,
    required this.pressScale,
    required this.onRelease,
    required this.onPickTime,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFmt = DateFormat('HH:mm');
    final timeLabel = timeFmt.format(endTime);

    return Column(
      children: [
        // End-time picker row — "until HH:mm [change]"
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time_rounded,
                size: 15,
                color: AppTheme.inkSoft),
            const SizedBox(width: 5),
            Text(
              'home.hero_available_until'
                  .tr(namedArgs: {'time': timeLabel}),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.inkMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onPickTime,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.brandIndigo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(
                    color: AppTheme.brandIndigo.withValues(alpha: 0.20),
                    width: 1,
                  ),
                ),
                child: Text(
                  'home.hero_change_time'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.brandIndigo,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Big release CTA
        AnimatedBuilder(
          animation: pressScale,
          builder: (context, child) =>
              Transform.scale(scale: pressScale.value, child: child),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRelease,
              icon: const Icon(Icons.lock_open_rounded, size: 20),
              label: Text('home.hero_release'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.communitySage,
                foregroundColor: Colors.white,
                elevation: 0,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Manage link
        GestureDetector(
          onTap: onManage,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_month_rounded,
                  size: 14, color: AppTheme.inkSoft),
              const SizedBox(width: 5),
              Text(
                'home.hero_manage'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
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
                icon: Icons.groups_2_outlined,
                selectedIcon: Icons.groups_2_rounded,
                label: 'home.nav_available'.tr(),
                selected: selectedIndex == 0,
                onTap: () => onDestinationSelected(0),
              ),
              _NavItem(
                icon: Icons.local_parking_outlined,
                selectedIcon: Icons.local_parking_rounded,
                label: 'home.nav_my_spot'.tr(),
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
