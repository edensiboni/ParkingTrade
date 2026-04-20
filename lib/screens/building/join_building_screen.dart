import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/building.dart';
import '../../services/address_autocomplete_service.dart';
import '../../services/auth_service.dart';
import '../../services/building_service.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/section_header.dart';
import 'pending_approval_screen.dart';
import '../spots/parking_spots_screen.dart';

enum _JoinMode { code, search, create }

class JoinBuildingScreen extends StatefulWidget {
  const JoinBuildingScreen({super.key});

  @override
  State<JoinBuildingScreen> createState() => _JoinBuildingScreenState();
}

class _JoinBuildingScreenState extends State<JoinBuildingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _inviteCodeController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _searchBuildingController = TextEditingController();
  final _createBuildingNameController = TextEditingController();

  final _buildingService = BuildingService();
  final _authService = AuthService();
  final _addressService = AddressAutocompleteService();

  _JoinMode _mode = _JoinMode.code;
  bool _isLoading = false;
  String? _errorMessage;

  List<Building> _buildingSearchResults = [];
  bool _buildingSearchLoading = false;
  List<AddressSuggestion> _addressSuggestions = [];
  bool _showAddressSuggestions = false;

  bool _createSuccess = false;
  String? _createdInviteCode;

  @override
  void initState() {
    super.initState();
    _searchBuildingController.addListener(_onSearchBuildingChanged);
    _createBuildingNameController.addListener(_onCreateBuildingNameChanged);
  }

  @override
  void dispose() {
    _inviteCodeController.dispose();
    _displayNameController.dispose();
    _searchBuildingController.dispose();
    _createBuildingNameController.dispose();
    _addressService.cancel();
    super.dispose();
  }

  void _onSearchBuildingChanged() => _runBuildingSearch();

  Future<void> _runBuildingSearch() async {
    final query = _searchBuildingController.text.trim();
    if (query.isEmpty) {
      setState(() => _buildingSearchResults = []);
      return;
    }
    setState(() => _buildingSearchLoading = true);
    try {
      final results = await _buildingService.searchBuildings(query);
      if (mounted) {
        setState(() {
          _buildingSearchResults = results;
          _buildingSearchLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _buildingSearchResults = [];
          _buildingSearchLoading = false;
        });
      }
    }
  }

  void _onCreateBuildingNameChanged() {
    if (!AddressAutocompleteService.isAvailable) return;
    final text = _createBuildingNameController.text.trim();
    if (text.length < 3) {
      setState(() {
        _addressSuggestions = [];
        _showAddressSuggestions = false;
      });
      return;
    }
    _addressService.suggest(text).then((list) {
      if (mounted) {
        setState(() {
          _addressSuggestions = list;
          _showAddressSuggestions = list.isNotEmpty;
        });
      }
    });
  }

  Future<void> _joinWithCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await _buildingService.joinBuilding(
        inviteCode: _inviteCodeController.text.trim().toUpperCase(),
        displayName: _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
      );
      if (!mounted) return;
      if (_displayNameController.text.trim().isNotEmpty) {
        await _authService.updateProfile(
          displayName: _displayNameController.text.trim(),
        );
      }
      if (!mounted) return;
      _navigateAfterJoin(
        requiresApproval: result['requires_approval'] as bool? ?? false,
        status: result['status'] as String?,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _joinWithBuilding(Building building) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await _buildingService.joinBuilding(
        inviteCode: building.inviteCode,
        displayName: _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
      );
      if (!mounted) return;
      if (_displayNameController.text.trim().isNotEmpty) {
        await _authService.updateProfile(
          displayName: _displayNameController.text.trim(),
        );
      }
      if (!mounted) return;
      _navigateAfterJoin(
        requiresApproval: result['requires_approval'] as bool? ?? false,
        status: result['status'] as String?,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _navigateAfterJoin({
    required bool requiresApproval,
    required String? status,
  }) {
    setState(() => _isLoading = false);
    if (requiresApproval && status == 'pending') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const PendingApprovalScreen(),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const ParkingSpotsScreen(),
        ),
      );
    }
  }

  Future<void> _createBuilding() async {
    final name = _createBuildingNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Enter a building name or address.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _showAddressSuggestions = false;
    });
    try {
      final result = await _buildingService.createBuilding(
        name: name,
        address: name,
        approvalRequired: false,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _createSuccess = true;
        _createdInviteCode = result['invite_code'] as String?;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _continueAfterCreate() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const ParkingSpotsScreen(),
      ),
    );
  }

  void _copyInviteCode() {
    if (_createdInviteCode != null) {
      Clipboard.setData(ClipboardData(text: _createdInviteCode!));
      AppSnack.success(context, 'Invite code copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_createSuccess && _createdInviteCode != null) {
      return _buildCreateSuccessContent();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your building'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Find your building',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Join with an invite code, search your address, or start a new one.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ModeSelector(
                    current: _mode,
                    onChanged: (m) => setState(() {
                      _mode = m;
                      _errorMessage = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Display name (optional)',
                      hintText: 'How neighbors will see you',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: Builder(
                      builder: (_) {
                        switch (_mode) {
                          case _JoinMode.code:
                            return _buildCodeSection(theme, scheme);
                          case _JoinMode.search:
                            return _buildSearchSection(theme, scheme);
                          case _JoinMode.create:
                            return _buildCreateSection(theme, scheme);
                        }
                      },
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _ErrorBanner(message: _errorMessage!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeSection(ThemeData theme, ColorScheme scheme) {
    return Column(
      key: const ValueKey('code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Enter your invite code',
          subtitle: 'Ask your building admin for a 6-character code.',
          icon: Icons.vpn_key_outlined,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _inviteCodeController,
          textCapitalization: TextCapitalization.characters,
          style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 3),
          decoration: const InputDecoration(
            labelText: 'Invite code',
            hintText: 'ABC123',
            prefixIcon: Icon(Icons.key_outlined),
          ),
          validator: (value) {
            if (_mode != _JoinMode.code) return null;
            if (value == null || value.isEmpty) {
              return 'Please enter an invite code';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _isLoading ? null : _joinWithCode,
          child: _isLoading
              ? const _ButtonSpinner()
              : const Text('Join building'),
        ),
      ],
    );
  }

  Widget _buildSearchSection(ThemeData theme, ColorScheme scheme) {
    return Column(
      key: const ValueKey('search'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Search by building name',
          subtitle: 'We\'ll match against buildings already on ParkingTrade.',
          icon: Icons.search_outlined,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchBuildingController,
          decoration: const InputDecoration(
            hintText: 'e.g. Skyline Towers',
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (_) => _runBuildingSearch(),
        ),
        const SizedBox(height: 8),
        if (_buildingSearchLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_searchBuildingController.text.trim().isNotEmpty) ...[
          if (_buildingSearchResults.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No matches yet. Try creating your building.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                for (final b in _buildingSearchResults)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              scheme.primaryContainer.withValues(alpha: 0.5),
                          foregroundColor: scheme.primary,
                          child: const Icon(Icons.apartment),
                        ),
                        title: Text(b.name),
                        subtitle: b.approvalRequired
                            ? const Text('Requires approval to join')
                            : const Text('Open to join'),
                        trailing: const Icon(Icons.arrow_forward, size: 18),
                        onTap: _isLoading ? null : () => _joinWithBuilding(b),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _buildCreateSection(ThemeData theme, ColorScheme scheme) {
    return Column(
      key: const ValueKey('create'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Create your building',
          subtitle:
              'Be the first from your building. We\'ll generate an invite code for your neighbors.',
          icon: Icons.apartment_outlined,
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            TextFormField(
              controller: _createBuildingNameController,
              decoration: const InputDecoration(
                labelText: 'Building name or address',
                hintText: 'e.g. 123 Main St',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              onTap: () {
                if (_addressSuggestions.isNotEmpty) {
                  setState(() => _showAddressSuggestions = true);
                }
              },
            ),
            if (_showAddressSuggestions && _addressSuggestions.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: 60,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _addressSuggestions.length,
                      itemBuilder: (context, index) {
                        final s = _addressSuggestions[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined, size: 18),
                          title: Text(s.displayText),
                          onTap: () {
                            _createBuildingNameController.text = s.displayText;
                            setState(() {
                              _addressSuggestions = [];
                              _showAddressSuggestions = false;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (AddressAutocompleteService.isAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 6.0, left: 4.0),
            child: Text(
              'Type 3+ characters for address suggestions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isLoading ? null : _createBuilding,
          icon: _isLoading
              ? const _ButtonSpinner()
              : const Icon(Icons.add_home_outlined),
          label: const Text('Create building'),
        ),
      ],
    );
  }

  Widget _buildCreateSuccessContent() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Building created')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.check_rounded,
                    size: 48, color: scheme.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'You\'re all set',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Share this invite code with your neighbors so they can join.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Center(
                  child: SelectableText(
                    _createdInviteCode!,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _copyInviteCode,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy code'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _continueAfterCreate,
                child: const Text('Continue to your spots'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final _JoinMode current;
  final ValueChanged<_JoinMode> onChanged;

  const _ModeSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_JoinMode>(
      segments: const [
        ButtonSegment(
          value: _JoinMode.code,
          icon: Icon(Icons.vpn_key_outlined, size: 18),
          label: Text('Code'),
        ),
        ButtonSegment(
          value: _JoinMode.search,
          icon: Icon(Icons.search, size: 18),
          label: Text('Search'),
        ),
        ButtonSegment(
          value: _JoinMode.create,
          icon: Icon(Icons.add_home_outlined, size: 18),
          label: Text('Create'),
        ),
      ],
      selected: {current},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        textStyle: WidgetStateProperty.all(
          Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
