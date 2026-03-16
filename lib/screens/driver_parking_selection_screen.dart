import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/parking_models.dart';
import 'driver_parking_layout_screen.dart';
import 'login_screen.dart';
import '../core/config.dart';
import '../core/utils/auth_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriverParkingSelectionScreen extends StatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback onCompleted;

  const DriverParkingSelectionScreen({
    Key? key,
    required this.request,
    required this.onCompleted,
  }) : super(key: key);

  @override
  State<DriverParkingSelectionScreen> createState() =>
      _DriverParkingSelectionScreenState();
}

class _DriverParkingSelectionScreenState
    extends State<DriverParkingSelectionScreen> {
  List<ParkingLocation> _parkingLocations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchParkingLocations();
  }

  double _toDouble(dynamic value, double fallback) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  Future<void> _fetchParkingLocations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final jwtToken = AuthTokenStore().token;
      final response = await http.get(
        Uri.parse('$apiBase/api/parking/locations'),
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load parking locations';
        });
        return;
      }

      final data = jsonDecode(response.body);
      final locations = (data['locations'] as List<dynamic>? ?? [])
          .map((loc) => ParkingLocation(
                id: loc['id'] as int?,
                name: (loc['name'] ?? 'Parking').toString(),
                distance: (loc['address'] ?? '').toString(),
                location: LatLng(
                  _toDouble(loc['latitude'], 0.0),
                  _toDouble(loc['longitude'], 0.0),
                ),
                availableSpots: (loc['available_slots'] as num?)?.toInt() ?? 0,
              ))
          .toList();

      setState(() {
        _parkingLocations = locations;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _error = 'Network error while loading parking locations';
      });
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (shouldLogout != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('user_id');
    } catch (_) {}

    try {
      AuthTokenStore().token = null;
      AuthTokenStore().userId = null;
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (context) => const LoginScreen(fromLogout: true)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Parking Location'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nearby Parking',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(_error!,
                                    style: const TextStyle(fontSize: 14)),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: _fetchParkingLocations,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _parkingLocations.length,
                            itemBuilder: (context, index) {
                              final parking = _parkingLocations[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          DriverParkingLayoutScreen(
                                        parking: parking,
                                        request: widget.request,
                                        onCompleted: widget.onCompleted,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.location_on,
                                            color: Colors.blue.shade600,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              parking.name,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey.shade800,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${parking.availableSpots} Available - ${parking.distance}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16,
                                        color: Colors.grey.shade400,
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
        ),
      ),
    );
  }
}
