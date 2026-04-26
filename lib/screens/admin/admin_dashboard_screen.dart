import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_service.dart';
import '../../services/building_service.dart';
import '../../services/auth_service.dart';
import '../../models/building.dart';
import '../../models/profile.dart';
import '../../widgets/address_autocomplete_field.dart';
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
    _tabController = TabController(length: 5, vsync: this);
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        itemCount: _allMembers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
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
        title: const Text('Building Admin'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await AuthService().signOut();
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: TabBar(
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
                  const Tab(text: 'Building Settings'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPendingList(),
              _buildAllMembersList(),
              _ManageApartmentsTab(adminService: _adminService),
              _BulkImportTab(adminService: _adminService),
              _BuildingSettingsTab(adminService: _adminService),
            ],
          ),
        ),
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
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(name: member.displayName),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName ?? 'Unnamed resident',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Requested ${dateFmt.format(member.createdAt.toLocal())}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const StatusChip(
              label: 'Pending',
              tone: StatusTone.warning,
              icon: Icons.hourglass_top_rounded,
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: onReject,
              icon: Icon(Icons.close_rounded, color: scheme.error, size: 18),
              label: Text('Decline', style: TextStyle(color: scheme.error)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: scheme.error),
                minimumSize: const Size(0, 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onApprove,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Approve'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
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

    return CustomScrollView(
      slivers: [
        // ── Add Apartment Form Card ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Card(
              color: scheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.add_home_rounded,
                              size: 20, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Add Apartment',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Unit number
                          SizedBox(
                            width: 130,
                            child: TextFormField(
                              controller: _unitController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Unit No.',
                                hintText: 'e.g. 4B',
                                prefixIcon: Icon(Icons.door_front_door_outlined),
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
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                              validator: _validatePhone,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Add button — aligned to the input height
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _isSubmitting ? null : _addApartment,
                              icon: _isSubmitting
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.add_rounded),
                              label: Text(
                                  _isSubmitting ? 'Adding…' : 'Add'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Section header ───────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(
              children: [
                Text(
                  'Authorized Apartments',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                if (!_isLoading && _apartments.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_apartments.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // ── Apartment List ───────────────────────────────────────────────────
        if (_isLoading)
          const SliverFillRemaining(
            child: SkeletonList(count: 5),
          )
        else if (_apartments.isEmpty)
          const SliverFillRemaining(
            child: EmptyState(
              icon: Icons.door_front_door_outlined,
              title: 'No apartments yet',
              message:
                  'Add a unit number and resident phone above to authorize access.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            sliver: SliverList.separated(
              itemCount: _apartments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final apt = _apartments[index];
                final id = apt['id'] as String;
                final unit = apt['unit_number'] as String;
                final phone = apt['resident_phone'] as String;

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        unit.length <= 3 ? unit : unit.substring(0, 3),
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
                      onPressed: () => _deleteApartment(id, unit),
                    ),
                  ),
                );
              },
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header card ──────────────────────────────────────────────────
          Card(
            color: scheme.secondaryContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.upload_file_rounded,
                            color: scheme.secondary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Bulk Import Apartments',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Paste a JSON array of apartments to create them along with their residents and parking spots in one go.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── JSON input ───────────────────────────────────────────────────
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              alignLabelWithHint: true,
            ),
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: 16),

          // ── Import button ────────────────────────────────────────────────
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
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
              label: Text(_isImporting ? 'Importing…' : 'Run Import'),
            ),
          ),
          const SizedBox(height: 28),

          // ── Format reference ─────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('Expected format', style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            padding: const EdgeInsets.all(16),
            child: Text(
              _placeholder,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Building Settings Tab ────────────────────────────────────────────────────

class _BuildingSettingsTab extends StatefulWidget {
  final AdminService adminService;
  const _BuildingSettingsTab({required this.adminService});

  @override
  State<_BuildingSettingsTab> createState() => _BuildingSettingsTabState();
}

class _BuildingSettingsTabState extends State<_BuildingSettingsTab> {
  Building? _building;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBuilding();
  }

  Future<void> _loadBuilding() async {
    setState(() => _isLoading = true);
    try {
      final building = await widget.adminService.getAdminBuilding();
      if (!mounted) return;
      setState(() {
        _building = building;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _openEditDialog() async {
    if (_building == null) return;

    final updated = await showDialog<Building>(
      context: context,
      builder: (context) =>
          _EditBuildingDialog(building: _building!),
    );

    if (updated != null && mounted) {
      setState(() => _building = updated);
      AppSnack.success(context, 'Building settings saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_building == null) {
      return EmptyState(
        icon: Icons.apartment_rounded,
        title: 'Building not found',
        message: 'Could not load your building details.',
        action: TextButton.icon(
          onPressed: _loadBuilding,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    }

    final b = _building!;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header card ──────────────────────────────────────────────────
          Card(
            color: scheme.primaryContainer.withValues(alpha: 0.25),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.apartment_rounded,
                        color: scheme.primary, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (b.address != null && b.address!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            b.address!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _openEditDialog,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Details grid ─────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Details',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      )),
                  const SizedBox(height: 16),
                  _DetailRow(
                    icon: Icons.vpn_key_outlined,
                    label: 'Invite Code',
                    value: b.inviteCode,
                    monospace: true,
                  ),
                  const Divider(height: 24),
                  _DetailRow(
                    icon: Icons.local_parking_rounded,
                    label: 'Total Parking Spots',
                    value: b.totalParkingSpots != null
                        ? '${b.totalParkingSpots}'
                        : 'Not set',
                  ),
                  const Divider(height: 24),
                  _DetailRow(
                    icon: Icons.approval_rounded,
                    label: 'Approval Required',
                    value: b.approvalRequired ? 'Yes' : 'No',
                  ),
                  if (b.latitude != null && b.longitude != null) ...[
                    const Divider(height: 24),
                    _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: 'Coordinates',
                      value:
                          '${b.latitude!.toStringAsFixed(5)}, ${b.longitude!.toStringAsFixed(5)}',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Edit Building Dialog ─────────────────────────────────────────────────────

class _EditBuildingDialog extends StatefulWidget {
  final Building building;
  const _EditBuildingDialog({required this.building});

  @override
  State<_EditBuildingDialog> createState() => _EditBuildingDialogState();
}

class _EditBuildingDialogState extends State<_EditBuildingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _spotsController;

  String _address = '';
  double? _latitude;
  double? _longitude;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.building;
    _nameController = TextEditingController(text: b.name);
    _spotsController = TextEditingController(
        text: b.totalParkingSpots != null ? '${b.totalParkingSpots}' : '');
    _address = b.address ?? '';
    _latitude = b.latitude;
    _longitude = b.longitude;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _spotsController.dispose();
    super.dispose();
  }

  void _onAddressSelected(AddressResult result) {
    setState(() {
      _address = result.address;
      _latitude = result.latitude;
      _longitude = result.longitude;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final spotsText = _spotsController.text.trim();
      final totalSpots =
          spotsText.isNotEmpty ? int.tryParse(spotsText) : null;

      final updated = await BuildingService().updateBuilding(
        buildingId: widget.building.id,
        name: _nameController.text.trim(),
        address: _address.isNotEmpty ? _address : null,
        latitude: _latitude,
        longitude: _longitude,
        totalParkingSpots: totalSpots,
      );

      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppSnack.error(
          context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Edit Building Settings'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Building name
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Building Name',
                    prefixIcon: Icon(Icons.business_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Building name is required'
                      : null,
                ),
                const SizedBox(height: 16),

                // Address autocomplete
                AddressAutocompleteField(
                  labelText: 'Building Address',
                  hintText: 'e.g. 12 Herzl St, Tel Aviv',
                  initialValue: _address.isEmpty ? null : _address,
                  onAddressSelected: _onAddressSelected,
                  onChanged: (value) {
                    if (value != _address) {
                      setState(() {
                        _address = value;
                        _latitude = null;
                        _longitude = null;
                      });
                    }
                  },
                ),
                if (_latitude != null && _longitude != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.check_circle_outline_rounded,
                          size: 14,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Location confirmed (${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)})',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),

                // Total parking spots
                TextFormField(
                  controller: _spotsController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Total Parking Spots (optional)',
                    prefixIcon: Icon(Icons.local_parking_rounded),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 1) {
                      return 'Enter a positive whole number';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ─── Detail row helper ────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool monospace;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: (monospace
                        ? theme.textTheme.bodyMedium
                            ?.copyWith(fontFamily: 'monospace')
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
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
