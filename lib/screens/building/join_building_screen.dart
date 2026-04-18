import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/building.dart';
import '../../services/address_autocomplete_service.dart';
import '../../services/auth_service.dart';
import '../../services/building_service.dart';
import 'pending_approval_screen.dart';
import '../spots/parking_spots_screen.dart';

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

  void _onSearchBuildingChanged() {
    _runBuildingSearch();
  }

  Future<void> _runBuildingSearch() async {
    final query = _searchBuildingController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _buildingSearchResults = [];
      });
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite code copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_createSuccess && _createdInviteCode != null) {
      return _buildCreateSuccessContent();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your building'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Join your building or create one.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // --- Join: I have an invite code ---
                const Text(
                  'I have an invite code',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _inviteCodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Invite Code',
                    hintText: 'ABC123',
                    prefixIcon: Icon(Icons.key),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter an invite code';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Display name (optional)',
                    hintText: 'How others will see you',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _joinWithCode,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Join with code'),
                ),
                const SizedBox(height: 24),

                // --- Join: Find my building ---
                const Text(
                  'Find my building',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchBuildingController,
                  decoration: const InputDecoration(
                    hintText: 'Search by building name',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _runBuildingSearch(),
                ),
                if (_buildingSearchLoading)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_searchBuildingController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  if (_buildingSearchResults.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'No buildings found. Create one below.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _buildingSearchResults.length,
                      itemBuilder: (context, index) {
                        final b = _buildingSearchResults[index];
                        return ListTile(
                          title: Text(b.name),
                          subtitle: b.approvalRequired
                              ? const Text('Requires approval to join')
                              : null,
                          trailing: const Icon(Icons.arrow_forward),
                          onTap: () => _joinWithBuilding(b),
                        );
                      },
                    ),
                ],
                const SizedBox(height: 24),

                // --- Create new building ---
                const Text(
                  'First here? Create your building',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (!AddressAutocompleteService.isAvailable)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'On mobile: add PLACES_API_KEY for address autocomplete. Web uses the server.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ),
                if (AddressAutocompleteService.isAvailable)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      'Type 3+ characters to see address suggestions.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                Stack(
                  children: [
                    TextFormField(
                      controller: _createBuildingNameController,
                      decoration: const InputDecoration(
                        labelText: 'Building name or address',
                        hintText: 'e.g. 123 Main St',
                        prefixIcon: Icon(Icons.location_on),
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
                        top: 56,
                        child: Material(
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _addressSuggestions.length,
                              itemBuilder: (context, index) {
                                final s = _addressSuggestions[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(s.displayText),
                                  onTap: () {
                                    _createBuildingNameController.text =
                                        s.displayText;
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
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _isLoading ? null : _createBuilding,
                  child: const Text('Create building'),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateSuccessContent() {
    return Scaffold(
      appBar: AppBar(title: const Text('Building created')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 24),
            const Text(
              'Building created. Share this code with neighbors:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            SelectableText(
              _createdInviteCode!,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _copyInviteCode,
              icon: const Icon(Icons.copy),
              label: const Text('Copy code'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _continueAfterCreate,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
