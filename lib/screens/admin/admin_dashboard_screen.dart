import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../../models/profile.dart';

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
    _tabController = TabController(length: 2, vsync: this);
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
      setState(() {
        _pendingMembers = pending;
        _allMembers = all;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}')),
        );
      }
    }
  }

  Future<void> _handleAction(Profile member, String action) async {
    final actionLabel = action == 'approve'
        ? 'Approve'
        : action == 'reject'
            ? 'Reject'
            : 'Revoke';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$actionLabel Member'),
        content: Text(
          '$actionLabel ${member.displayName ?? "this member"}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: action == 'approve' ? Colors.green : Colors.red,
            ),
            child: Text(actionLabel),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Member ${actionLabel.toLowerCase()}d successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildPendingList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_pendingMembers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No pending requests'),
            SizedBox(height: 8),
            Text(
              'All membership requests have been handled',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        itemCount: _pendingMembers.length,
        itemBuilder: (context, index) {
          final member = _pendingMembers[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(member.displayName ?? 'Unnamed'),
              subtitle: Text('Joined ${_formatDate(member.createdAt)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: () => _handleAction(member, 'approve'),
                    tooltip: 'Approve',
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () => _handleAction(member, 'reject'),
                    tooltip: 'Reject',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAllMembersList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_allMembers.isEmpty) {
      return const Center(child: Text('No members'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        itemCount: _allMembers.length,
        itemBuilder: (context, index) {
          final member = _allMembers[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _statusColor(member.status),
                child: Text(
                  (member.displayName ?? '?')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Row(
                children: [
                  Text(member.displayName ?? 'Unnamed'),
                  if (member.isAdmin) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Admin',
                        style: TextStyle(fontSize: 10, color: Colors.blue),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(member.status.toString()),
              trailing: member.status == ProfileStatus.approved && !member.isAdmin
                  ? IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                      onPressed: () => _handleAction(member, 'revoke'),
                      tooltip: 'Revoke',
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(ProfileStatus status) {
    switch (status) {
      case ProfileStatus.approved:
        return Colors.green;
      case ProfileStatus.pending:
        return Colors.orange;
      case ProfileStatus.rejected:
        return Colors.red;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Building Admin'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: _pendingMembers.isEmpty
                  ? 'Pending'
                  : 'Pending (${_pendingMembers.length})',
            ),
            const Tab(text: 'All Members'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingList(),
          _buildAllMembersList(),
        ],
      ),
    );
  }
}
