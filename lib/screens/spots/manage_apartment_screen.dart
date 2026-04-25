import 'package:flutter/material.dart';
import '../../services/apartment_service.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';

class ManageApartmentScreen extends StatefulWidget {
  const ManageApartmentScreen({super.key});

  @override
  State<ManageApartmentScreen> createState() => _ManageApartmentScreenState();
}

class _ManageApartmentScreenState extends State<ManageApartmentScreen> {
  final _apartmentService = ApartmentService();

  List<ApartmentProfile> _profiles = [];
  bool _isLoading = true;

  // Track which profile IDs are currently being updated to show per-row
  // loading indicators and prevent concurrent toggles on the same row.
  final Set<String> _updatingIds = {};

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    try {
      final profiles = await _apartmentService.getApartmentProfiles();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(
        context,
        e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  Future<void> _togglePush(ApartmentProfile ap, bool value) async {
    final id = ap.profile.id;
    if (_updatingIds.contains(id)) return;
    setState(() => _updatingIds.add(id));

    try {
      await _apartmentService.updateNotificationPreferences(
        profileId: id,
        receivesPush: value,
      );
      if (!mounted) return;
      // Optimistically update local state.
      setState(() {
        final idx = _profiles.indexWhere((p) => p.profile.id == id);
        if (idx != -1) {
          final updated = _profiles[idx];
          _profiles[idx] = ApartmentProfile(
            profile: updated.profile.copyWith(receivesPushNotifications: value),
            phone: updated.phone,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(
        context,
        e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _updatingIds.remove(id));
    }
  }

  Future<void> _toggleChat(ApartmentProfile ap, bool value) async {
    final id = ap.profile.id;
    if (_updatingIds.contains(id)) return;
    setState(() => _updatingIds.add(id));

    try {
      await _apartmentService.updateNotificationPreferences(
        profileId: id,
        receivesChat: value,
      );
      if (!mounted) return;
      // Optimistically update local state.
      setState(() {
        final idx = _profiles.indexWhere((p) => p.profile.id == id);
        if (idx != -1) {
          final updated = _profiles[idx];
          _profiles[idx] = ApartmentProfile(
            profile:
                updated.profile.copyWith(receivesChatNotifications: value),
            phone: updated.phone,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(
        context,
        e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _updatingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage apartment'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfiles,
        child: _isLoading
            ? const SkeletonList(count: 4)
            : _profiles.isEmpty
                ? const EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'No residents found',
                    message:
                        'No profiles are currently linked to your apartment.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _SectionHeader(
                        title: 'Residents',
                        subtitle:
                            '${_profiles.length} ${_profiles.length == 1 ? 'person' : 'people'} in your apartment',
                      ),
                      const SizedBox(height: 8),
                      ..._profiles.map(
                        (ap) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ResidentCard(
                            ap: ap,
                            isUpdating:
                                _updatingIds.contains(ap.profile.id),
                            onTogglePush: (v) => _togglePush(ap, v),
                            onToggleChat: (v) => _toggleChat(ap, v),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ─── Sub-widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _ResidentCard extends StatelessWidget {
  final ApartmentProfile ap;
  final bool isUpdating;
  final ValueChanged<bool> onTogglePush;
  final ValueChanged<bool> onToggleChat;

  const _ResidentCard({
    required this.ap,
    required this.isUpdating,
    required this.onTogglePush,
    required this.onToggleChat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = ap.profile;

    final displayName = profile.displayName?.isNotEmpty == true
        ? profile.displayName!
        : null;
    final phone = ap.phone?.isNotEmpty == true ? ap.phone! : null;
    final initial = (displayName ?? phone ?? '?')[0].toUpperCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ─────────────────────────────────────────────
            Row(
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (displayName != null)
                        Text(
                          displayName,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (phone != null)
                        Text(
                          phone,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (displayName == null && phone == null)
                        Text(
                          'Resident',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isUpdating)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  ),
                if (profile.isApartmentAdmin)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Tooltip(
                      message: 'Apartment admin',
                      child: Icon(
                        Icons.manage_accounts_outlined,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            // ── Toggle rows ────────────────────────────────────────────
            _ToggleRow(
              icon: Icons.notifications_outlined,
              label: 'Push notifications',
              value: profile.receivesPushNotifications,
              enabled: !isUpdating,
              onChanged: onTogglePush,
            ),
            const SizedBox(height: 4),
            _ToggleRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Chat notifications',
              value: profile.receivesChatNotifications,
              enabled: !isUpdating,
              onChanged: onToggleChat,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
