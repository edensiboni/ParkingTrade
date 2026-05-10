import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/parking_spot.dart';
import '../../models/spot_availability_period.dart';
import '../../services/booking_service.dart';
import '../../services/parking_spot_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../bookings/available_spots_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for a feed entry (spot + its best live/upcoming period + owner info)
// ─────────────────────────────────────────────────────────────────────────────

class _FeedEntry {
  final ParkingSpot spot;
  final SpotAvailabilityPeriod period;
  final bool isLive;
  /// Display name pulled from the owning profile (may be null → fallback label).
  final String? ownerName;
  /// Apartment identifier, e.g. "12" or "4B".
  final String? aptIdentifier;

  const _FeedEntry({
    required this.spot,
    required this.period,
    required this.isLive,
    this.ownerName,
    this.aptIdentifier,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// AvailableNowFeed — community parking feed widget
// ─────────────────────────────────────────────────────────────────────────────

class AvailableNowFeed extends StatefulWidget {
  const AvailableNowFeed({super.key});

  @override
  State<AvailableNowFeed> createState() => _AvailableNowFeedState();
}

class _AvailableNowFeedState extends State<AvailableNowFeed> {
  final _bookingService = BookingService();
  final _spotService = ParkingSpotService();

  List<_FeedEntry> _entries = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Fetch all spots that are active in the building (neighbours' spots only,
      // BookingService.getAvailableSpots excludes the current user's apartment).
      // The query now joins `apartments(identifier)` so each spot carries the
      // human-readable unit identifier (e.g. "4B") without an extra round-trip.
      final spots = await _bookingService.getAvailableSpots();

      // Batch-fetch the owner display_name for every distinct apartment in one
      // query, keyed by apartment_id.
      final apartmentIds =
          spots.map((s) => s.apartmentId).where((id) => id.isNotEmpty).toSet().toList();
      final displayNames =
          await _bookingService.getDisplayNamesByApartment(apartmentIds);

      final now = DateTime.now();
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final tomorrowEnd = todayEnd.add(const Duration(days: 1));

      final entries = <_FeedEntry>[];

      for (final spot in spots) {
        List<SpotAvailabilityPeriod> periods;
        try {
          periods = await _spotService.getAvailabilityPeriods(spot.id);
        } catch (_) {
          periods = [];
        }

        // Filter to non-recurring periods that are currently live OR start
        // before tomorrow end (today/tomorrow upcoming).
        final relevant = periods
            .where((p) =>
                !p.isRecurring &&
                p.endTime.isAfter(now) &&
                p.startTime.isBefore(tomorrowEnd))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        if (relevant.isEmpty) continue;

        // Prefer a currently-live period; otherwise take the soonest upcoming.
        final live = relevant.where(
          (p) => p.startTime.isBefore(now) && p.endTime.isAfter(now),
        );
        final bestPeriod = live.isNotEmpty ? live.first : relevant.first;
        final isLive = live.isNotEmpty;

        entries.add(_FeedEntry(
          spot: spot,
          period: bestPeriod,
          isLive: isLive,
          // Resolved from the joined apartments data + the batched profiles query.
          ownerName: displayNames[spot.apartmentId],
          aptIdentifier: spot.apartmentIdentifier,
        ));
      }

      // Sort: live first (soonest end), then upcoming (soonest start).
      entries.sort((a, b) {
        if (a.isLive && !b.isLive) return -1;
        if (!a.isLive && b.isLive) return 1;
        if (a.isLive) {
          // Both live → soonest end first.
          return a.period.endTime.compareTo(b.period.endTime);
        }
        // Both upcoming → soonest start first.
        return a.period.startTime.compareTo(b.period.startTime);
      });

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SkeletonList(count: 5);

    if (_error != null) {
      return _ErrorBanner(message: _error!, onRetry: _load);
    }

    if (_entries.isEmpty) {
      return EmptyState(
        icon: Icons.weekend_outlined,
        title: 'feed.empty_title'.tr(),
        message: 'feed.empty_message'.tr(),
      );
    }

    final liveCount = _entries.where((e) => e.isLive).length;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.communitySage,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _FeedHeader(
              liveCount: liveCount,
              totalCount: _entries.length,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = _entries[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FeedTile(
                      entry: entry,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AvailableSpotsScreen(),
                        ),
                      ),
                    ),
                  );
                },
                childCount: _entries.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed Header — "● 3 פנויות עכשיו · 8 בסך הכל"
// ─────────────────────────────────────────────────────────────────────────────

class _FeedHeader extends StatefulWidget {
  final int liveCount;
  final int totalCount;
  const _FeedHeader({required this.liveCount, required this.totalCount});

  @override
  State<_FeedHeader> createState() => _FeedHeaderState();
}

class _FeedHeaderState extends State<_FeedHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
      child: Row(
        children: [
          // Pulsing dot
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppTheme.communitySage.withValues(
                  alpha: 0.55 + _pulseController.value * 0.45,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'feed.live_count'.tr(namedArgs: {'n': '${widget.liveCount}'}),
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.communitySage,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '·',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.inkSoft,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'feed.total_count'.tr(namedArgs: {'n': '${widget.totalCount}'}),
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed Tile — avatar bubble + person line + spot pill + window line + CTA
// ─────────────────────────────────────────────────────────────────────────────

class _FeedTile extends StatelessWidget {
  final _FeedEntry entry;
  final VoidCallback onTap;
  const _FeedTile({required this.entry, required this.onTap});

  /// Safe initial extraction: handles multi-byte / Hebrew characters.
  String _initial(String? name) {
    if (name == null || name.isEmpty) return '?';
    final chars = name.characters;
    return chars.isNotEmpty ? chars.first : '?';
  }

  String _personLine(BuildContext context) {
    final fallback = 'feed.neighbor_fallback'.tr();
    final name = entry.ownerName?.isNotEmpty == true
        ? entry.ownerName!
        : fallback;
    final apt = entry.aptIdentifier;
    if (apt != null && apt.isNotEmpty) {
      return 'feed.person_line'
          .tr(namedArgs: {'name': name, 'apt': apt});
    }
    return name;
  }

  String _windowLine(BuildContext context) {
    final now = DateTime.now();
    final timeFmt = DateFormat('HH:mm');

    if (entry.isLive) {
      return 'feed.window_live_until'.tr(
        namedArgs: {
          'until': timeFmt.format(entry.period.endTime.toLocal()),
        },
      );
    }

    // Upcoming: determine "today" / "tomorrow" label
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final startDay = DateTime(
      entry.period.startTime.year,
      entry.period.startTime.month,
      entry.period.startTime.day,
    );

    final String whenLabel;
    if (startDay == today) {
      whenLabel = 'feed.today'.tr();
    } else if (startDay == tomorrow) {
      whenLabel = 'feed.tomorrow'.tr();
    } else {
      whenLabel = DateFormat('d MMM').format(entry.period.startTime.toLocal());
    }

    return 'feed.window_upcoming'.tr(namedArgs: {
      'when': whenLabel,
      'from': timeFmt.format(entry.period.startTime.toLocal()),
      'until': timeFmt.format(entry.period.endTime.toLocal()),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLive = entry.isLive;

    final borderColor = isLive
        ? AppTheme.communitySage.withValues(alpha: 0.45)
        : AppTheme.hairline;
    final ctaColor = isLive ? AppTheme.communitySage : AppTheme.brandIndigo;
    final ctaBg = isLive
        ? AppTheme.communitySageSoft
        : AppTheme.brandIndigo.withValues(alpha: 0.08);
    final ctaBorder = isLive
        ? AppTheme.communitySage.withValues(alpha: 0.30)
        : AppTheme.brandIndigo.withValues(alpha: 0.20);

    final initial = _initial(entry.ownerName);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: borderColor, width: isLive ? 1.5 : 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Avatar bubble ──────────────────────────────────────────
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isLive
                        ? AppTheme.communitySageSoft
                        : AppTheme.subtleSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isLive
                          ? AppTheme.communitySage.withValues(alpha: 0.35)
                          : AppTheme.hairline,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isLive
                            ? AppTheme.communitySageDeep
                            : AppTheme.inkMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // ── Content column ─────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Person line
                      Text(
                        _personLine(context),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Spot pill + window line
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _SpotPill(
                            label: 'feed.spot_label'.tr(
                              namedArgs: {'id': entry.spot.spotIdentifier},
                            ),
                            isLive: isLive,
                          ),
                          Text(
                            _windowLine(context),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // ── CTA button ─────────────────────────────────────────────
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ctaBg,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: Border.all(color: ctaBorder, width: 1),
                    ),
                    child: Text(
                      'feed.request_cta'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ctaColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Spot pill — "חניה A3"
// ─────────────────────────────────────────────────────────────────────────────

class _SpotPill extends StatelessWidget {
  final String label;
  final bool isLive;
  const _SpotPill({required this.label, required this.isLive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isLive
            ? AppTheme.communitySage.withValues(alpha: 0.12)
            : AppTheme.subtleSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: isLive
              ? AppTheme.communitySage.withValues(alpha: 0.28)
              : AppTheme.hairline,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_parking_rounded,
            size: 11,
            color: isLive ? AppTheme.communitySageDeep : AppTheme.inkMuted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isLive ? AppTheme.communitySageDeep : AppTheme.inkMuted,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error banner with retry
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: theme.colorScheme.error, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'feed.error_title'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('feed.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
