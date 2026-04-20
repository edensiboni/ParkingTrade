import 'package:flutter/material.dart';
import '../../services/parking_spot_service.dart';
import '../../services/auth_service.dart';
import '../../models/parking_spot.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_chip.dart';
import 'add_spot_screen.dart';
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
  List<ParkingSpot> _spots = [];
  bool _isLoading = true;
  String? _buildingId;
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  Future<void> _loadSpots() async {
    setState(() => _isLoading = true);
    try {
      final profile = await _authService.getCurrentProfile();
      _buildingId = profile?.buildingId;
      _displayName = profile?.displayName;

      final spots = await _spotService.getUserSpots();
      if (!mounted) return;
      setState(() {
        _spots = spots;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context, 'Could not load spots: $e');
    }
  }

  Future<void> _toggleSpotActive(ParkingSpot spot) async {
    try {
      await _spotService.updateSpot(spotId: spot.id, isActive: !spot.isActive);
      _loadSpots();
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Could not update spot: $e');
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can always sign back in with your phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
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

  Future<void> _openAddSpot() async {
    if (_buildingId == null) return;
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddSpotScreen(buildingId: _buildingId!),
      ),
    );
    if (result == true) _loadSpots();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activeCount = _spots.where((s) => s.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My parking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.directions_car_outlined),
            tooltip: 'Bookings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BookingsScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'signout') _confirmSignOut();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Sign out'),
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
                    title: 'No spots yet',
                    message:
                        'Add your parking spot to start swapping with neighbors.',
                    action: FilledButton.icon(
                      onPressed: _buildingId == null ? null : _openAddSpot,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add parking spot'),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
      floatingActionButton: _spots.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _buildingId == null ? null : _openAddSpot,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add spot'),
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
    final greeting = displayName?.isNotEmpty == true
        ? 'Hi ${displayName!.split(' ').first},'
        : 'Welcome back,';
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
            '$activeCount of $totalCount spots active',
            style: theme.textTheme.titleLarge?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Toggle a spot off anytime to stop new booking requests.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
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
                      label: active ? 'Active' : 'Inactive',
                      tone:
                          active ? StatusTone.success : StatusTone.neutral,
                      icon: active
                          ? Icons.check_circle_outline
                          : Icons.pause_circle_outline,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                tooltip: 'Manage availability',
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
