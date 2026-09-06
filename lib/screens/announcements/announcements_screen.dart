import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../models/building_announcement.dart';
import '../../services/announcement_service.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';

/// Resident-facing history of building announcements (Roadmap Phase 4).
/// Read-only; newest first. Reached from the home screen's bell icon and
/// from a `building_announcement` push tap.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _service = AnnouncementService();
  List<BuildingAnnouncement> _announcements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await _service.getBuildingAnnouncements();
      if (!mounted) return;
      setState(() {
        _announcements = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context, 'announcements.load_error'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('announcements.screen_title'.tr())),
      body: _isLoading
          ? const SkeletonList(count: 4)
          : _announcements.isEmpty
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                      EmptyState(
                        icon: Icons.campaign_outlined,
                        title: 'announcements.empty_title'.tr(),
                        message: 'announcements.empty_message'.tr(),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: _announcements.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _AnnouncementCard(announcement: _announcements[index]),
                  ),
                ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final BuildingAnnouncement announcement;
  const _AnnouncementCard({required this.announcement});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFmt = DateFormat('MMM d, y • h:mm a');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    announcement.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(announcement.body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
            Text(
              dateFmt.format(announcement.createdAt.toLocal()),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
