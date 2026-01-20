import 'package:flutter/material.dart';
import '../../services/parking_spot_service.dart';
import '../../services/auth_service.dart';
import '../../models/parking_spot.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  Future<void> _loadSpots() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final profile = await _authService.getCurrentProfile();
      _buildingId = profile?.buildingId;

      final spots = await _spotService.getUserSpots();
      setState(() {
        _spots = spots;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading spots: $e')),
        );
      }
    }
  }

  Future<void> _toggleSpotActive(ParkingSpot spot) async {
    try {
      await _spotService.updateSpot(
        spotId: spot.id,
        isActive: !spot.isActive,
      );
      _loadSpots();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating spot: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Parking Spots'),
        actions: [
          IconButton(
            icon: const Icon(Icons.directions_car),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const BookingsScreen(),
                ),
              );
            },
            tooltip: 'Bookings',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'signout') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Sign Out'),
                    content: const Text('Are you sure you want to sign out?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  // Sign out and navigate to auth screen
                  await _authService.signOut();
                  // Force navigation to auth screen
                  if (mounted) {
                    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
                      '/auth',
                      (route) => false,
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_spots.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.local_parking,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No parking spots registered',
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add your first parking spot to get started',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _spots.length,
                      itemBuilder: (context, index) {
                        final spot = _spots[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            leading: Icon(
                              spot.isActive ? Icons.local_parking : Icons.block,
                              color: spot.isActive
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            title: Text(spot.spotIdentifier),
                            subtitle: Text(
                              spot.isActive ? 'Active' : 'Inactive',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.calendar_today),
                                  onPressed: spot.isActive
                                      ? () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  ManageAvailabilityScreen(spot: spot),
                                            ),
                                          );
                                        }
                                      : null,
                                  tooltip: 'Manage Availability',
                                ),
                                Switch(
                                  value: spot.isActive,
                                  onChanged: (value) => _toggleSpotActive(spot),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _buildingId == null
            ? null
            : () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => AddSpotScreen(buildingId: _buildingId!),
                  ),
                );
                if (result == true) {
                  _loadSpots();
                }
              },
        child: const Icon(Icons.add),
      ),
    );
  }
}

