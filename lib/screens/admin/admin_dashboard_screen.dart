import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
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
    _tabController = TabController(length: 4, vsync: this);
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
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await AuthService().signOut();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              text: _pendingMembers.isEmpty
                  ? 'Pending'
                  : 'Pending (${_pendingMembers.length})',
            ),
            Tab(text: 'Members (${_allMembers.length})'),
            const Tab(text: 'Manage Apartments'),
            const Tab(text: 'Bulk Import'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingList(),
          _buildAllMembersList(),
          _ManageApartmentsTab(adminService: _adminService),
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

// ─── Manage Apartments Tab ────────────────────────────────────────────────────

class _ManageApartmentsTab extends StatefulWidget {
  final AdminService adminService;
  const _ManageApartmentsTab({required this.adminService});

  @override
  State<_ManageApartmentsTab> createState() => _ManageApartmentsTabState();
}

class _ManageApartmentsTabState extends State<_ManageApartmentsTab> {
  final _formKey = GlobalKey<FormState>();
  final _unitController = TextEditingController();
  final _phoneController = TextEditingController();

  List<Map<String, dynamic>> _apartments = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadApartments();
  }

  @override
  void dispose() {
    _unitController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadApartments() async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.adminService.getAuthorizedApartments();
      if (!mounted) return;
      setState(() {
        _apartments = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _addApartment() async {
    if (!_formKey.currentState!.validate()) return;

    final rawPhone = _phoneController.text.trim();
    final phone = AuthService.normalisePhone(rawPhone);

    setState(() => _isSubmitting = true);
    try {
      await widget.adminService.addAuthorizedApartment(
        unitNumber: _unitController.text.trim(),
        phone: phone,
      );
      if (!mounted) return;
      AppSnack.success(context, 'Apartment added successfully.');
      _unitController.clear();
      _phoneController.clear();
      _loadApartments();
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteApartment(String id, String unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove authorization?'),
        content: Text(
          'Remove unit "$unit"? The resident will lose access on their next login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.adminService.deleteAuthorizedApartment(id);
      if (!mounted) return;
      AppSnack.success(context, 'Authorization removed.');
      _loadApartments();
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone number is required';
    final normalised = AuthService.normalisePhone(value);
    if (!RegExp(r'^\+\d{7,15}$').hasMatch(normalised)) {
      return 'Enter a valid phone number, e.g. 050-123-4567';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        // ── Add Apartment Form ───────────────────────────────────────────────
        Container(
          color: scheme.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add Apartment',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Unit number
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        controller: _unitController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Unit No.',
                          hintText: 'e.g. 4B',
                          isDense: true,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Phone
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _addApartment(),
                        decoration: const InputDecoration(
                          labelText: 'Resident Phone',
                          hintText: '05X-XXX-XXXX',
                          isDense: true,
                        ),
                        validator: _validatePhone,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Add button
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: FilledButton(
                        onPressed: _isSubmitting ? null : _addApartment,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: _isSubmitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.add_rounded),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const Divider(height: 1),

        // ── Apartment List ───────────────────────────────────────────────────
        Expanded(
          child: _isLoading
              ? const SkeletonList(count: 5)
              : _apartments.isEmpty
                  ? const EmptyState(
                      icon: Icons.door_front_door_outlined,
                      title: 'No apartments yet',
                      message:
                          'Add a unit number and resident phone above to authorize access.',
                    )
                  : RefreshIndicator(
                      onRefresh: _loadApartments,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _apartments.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final apt = _apartments[index];
                          final id = apt['id'] as String;
                          final unit = apt['unit_number'] as String;
                          final phone = apt['phone'] as String;

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    scheme.primaryContainer,
                                child: Text(
                                  unit.length <= 3
                                      ? unit
                                      : unit.substring(0, 3),
                                  style: TextStyle(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                'Unit $unit',
                                style: theme.textTheme.titleSmall,
                              ),
                              subtitle: Text(
                                phone,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: 'Remove authorization',
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: scheme.error,
                                ),
                                onPressed: () =>
                                    _deleteApartment(id, unit),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
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
