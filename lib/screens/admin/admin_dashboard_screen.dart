import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_service.dart';
import '../../models/profile.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_chip.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _adminService = AdminService();
  late TabController _tabController;
  List<Profile> _pendingMembers = [];
  List<Profile> _allMembers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final [pending, all] = await Future.wait([
        _adminService.getPendingMembers(),
        _adminService.getBuildingMembers(),
      ]);
      if (!mounted) return;
      setState(() {
        _pendingMembers = pending;
        _allMembers = all;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(
          context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _handleAction(Profile member, String action) async {
    final label = switch (action) {
      'approve' => 'Approve',
      'reject' => 'Reject',
      'revoke' => 'Revoke',
      _ => action,
    };
    final isDestructive = action != 'approve';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label member?'),
        content: Text(
          action == 'approve'
              ? 'Give ${member.displayName ?? "this member"} full access to the building?'
              : action == 'reject'
                  ? 'Deny ${member.displayName ?? "this member"} access? They can contact you to retry.'
                  : 'Revoke access for ${member.displayName ?? "this member"}? Their bookings will be blocked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: isDestructive
                ? FilledButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(label),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _adminService.manageMember(
        memberId: member.id,
        action: action,
      );
      if (!mounted) return;
      AppSnack.success(context, '${label}d');
      _loadData();
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(
          context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Widget _buildPendingList() {
    if (_isLoading) return const SkeletonList(count: 3);

    if (_pendingMembers.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_rounded,
        title: 'Inbox zero',
        message: 'No membership requests waiting on you right now.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingMembers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final member = _pendingMembers[index];
          return _PendingMemberCard(
            member: member,
            onApprove: () => _handleAction(member, 'approve'),
            onReject: () => _handleAction(member, 'reject'),
          );
        },
      ),
    );
  }

  Widget _buildAllMembersList() {
    if (_isLoading) return const SkeletonList(count: 4);

    if (_allMembers.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline_rounded,
        title: 'No members yet',
        message: 'Share your invite code to get neighbors onboard.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _allMembers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final member = _allMembers[index];
          return _MemberCard(
            member: member,
            onRevoke: member.status == ProfileStatus.approved && !member.isAdmin
                ? () => _handleAction(member, 'revoke')
                : null,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Building admin'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: _pendingMembers.isEmpty
                  ? 'Pending'
                  : 'Pending (${_pendingMembers.length})',
            ),
            Tab(text: 'Members (${_allMembers.length})'),
            const Tab(text: 'Bulk Import'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingList(),
          _buildAllMembersList(),
          _BulkImportTab(adminService: _adminService),
        ],
      ),
    );
  }
}

class _PendingMemberCard extends StatelessWidget {
  final Profile member;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingMemberCard({
    required this.member,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFmt = DateFormat('MMM d, y');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(name: member.displayName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.displayName ?? 'Unnamed resident',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Requested ${dateFmt.format(member.createdAt.toLocal())}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const StatusChip(
                  label: 'Pending',
                  tone: StatusTone.warning,
                  icon: Icons.hourglass_top_rounded,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: Icon(Icons.close_rounded, color: scheme.error),
                    label: Text('Decline',
                        style: TextStyle(color: scheme.error)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: scheme.error),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final Profile member;
  final VoidCallback? onRevoke;

  const _MemberCard({
    required this.member,
    required this.onRevoke,
  });

  StatusTone _tone(ProfileStatus s) {
    switch (s) {
      case ProfileStatus.approved:
        return StatusTone.success;
      case ProfileStatus.pending:
        return StatusTone.warning;
      case ProfileStatus.rejected:
        return StatusTone.danger;
    }
  }

  String _statusLabel(ProfileStatus s) {
    switch (s) {
      case ProfileStatus.approved:
        return 'Approved';
      case ProfileStatus.pending:
        return 'Pending';
      case ProfileStatus.rejected:
        return 'Rejected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _Avatar(name: member.displayName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.displayName ?? 'Unnamed resident',
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (member.isAdmin) ...[
                        const SizedBox(width: 8),
                        const StatusChip(
                          label: 'Admin',
                          tone: StatusTone.info,
                          icon: Icons.shield_outlined,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  StatusChip(
                    label: _statusLabel(member.status),
                    tone: _tone(member.status),
                  ),
                ],
              ),
            ),
            if (onRevoke != null)
              IconButton(
                tooltip: 'Revoke access',
                icon: Icon(Icons.person_remove_outlined, color: scheme.error),
                onPressed: onRevoke,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Bulk Import Tab ─────────────────────────────────────────────────────────

class _BulkImportTab extends StatefulWidget {
  final AdminService adminService;
  const _BulkImportTab({required this.adminService});

  @override
  State<_BulkImportTab> createState() => _BulkImportTabState();
}

class _BulkImportTabState extends State<_BulkImportTab> {
  final _jsonController = TextEditingController();
  bool _isImporting = false;

  static const _placeholder = '''[
  {
    "apartment_identifier": "101",
    "phones": ["+972501234567"],
    "parking_spots": ["A1"]
  }
]''';

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _runImport() async {
    final raw = _jsonController.text.trim();
    if (raw.isEmpty) {
      AppSnack.error(context, 'Please paste a JSON array before importing.');
      return;
    }

    List<Map<String, dynamic>> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('Root must be a JSON array');
      data = decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      AppSnack.error(context, 'Invalid JSON: ${e.toString()}');
      return;
    }

    setState(() => _isImporting = true);
    try {
      final result = await widget.adminService.bulkImport(data);
      if (!mounted) return;

      final imported = (result['imported'] as List?)?.length ?? 0;
      final errs = result['errors'] as List?;

      if (errs != null && errs.isNotEmpty) {
        AppSnack.error(
          context,
          '$imported apartment(s) imported. ${errs.length} error(s) — check logs.',
        );
      } else {
        AppSnack.success(
          context,
          'Successfully imported $imported apartment(s).',
        );
        _jsonController.clear();
      }
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header card
          Card(
            color: scheme.secondaryContainer.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.upload_file_rounded,
                          color: scheme.secondary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Bulk Import',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Paste a JSON array of apartments to create them along with their residents and parking spots in one go.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // JSON input
          Text('JSON Payload', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _jsonController,
            maxLines: 14,
            decoration: InputDecoration(
              hintText: _placeholder,
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontFamily: 'monospace',
              ),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: 16),

          // Import button
          FilledButton.icon(
            onPressed: _isImporting ? null : _runImport,
            icon: _isImporting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.cloud_upload_rounded),
            label: Text(_isImporting ? 'Importing…' : 'Import'),
          ),
          const SizedBox(height: 24),

          // Format reference
          Text('Expected format', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: Text(
              _placeholder,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Avatar helper ────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()[0].toUpperCase()
        : '?';
    return Container(
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
    );
  }
}
