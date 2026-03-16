import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';
import 'admin_parking_layout_screen.dart';

class AdminParkingLocationsScreen extends StatefulWidget {
  final int totalLocations;

  const AdminParkingLocationsScreen({
    Key? key,
    required this.totalLocations,
  }) : super(key: key);

  @override
  State<AdminParkingLocationsScreen> createState() =>
      _AdminParkingLocationsScreenState();
}

class _AdminParkingLocationsScreenState
    extends State<AdminParkingLocationsScreen> {
  GoogleMapController? mapController;
  List<Map<String, dynamic>> _parkings = [];
  Map<int, List<Map<String, dynamic>>> _parkingSlots = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchParkingLocations();
  }

  Future<void> _fetchParkingLocations() async {
    setState(() {
      _isLoading = true;
    });
    final jwtToken = AuthTokenStore().token;
    final url = Uri.parse('$apiBase/api/parking/locations');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final locations = data['locations'] as List<dynamic>;
        _parkings = locations
            .map((loc) => {
                  'id': loc['id'],
                  'name': loc['name'],
                  'address': loc['address'],
                  'latitude': loc['latitude'],
                  'longitude': loc['longitude'],
                  'available': loc['available_slots'],
                })
            .toList();

        // Fetch slots for each location
        for (var parking in _parkings) {
          await _fetchSlotsForLocation(parking['id']);
        }
      } else {
        _parkings = [];
      }
    } catch (_) {
      _parkings = [];
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchSlotsForLocation(int locationId) async {
    final jwtToken = AuthTokenStore().token;
    final url = Uri.parse('$apiBase/api/parking/slots/$locationId');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final slots = data['slots'] as List<dynamic>;
        _parkingSlots[locationId] = slots
            .map((slot) => {
                  'id': slot['id'],
                  'slot_number': slot['slot_number'],
                  'status': slot['status'],
                })
            .toList();
      }
    } catch (_) {
      _parkingSlots[locationId] = [];
    }
  }

  Future<void> _deleteParkingLocation(int id) async {
    final jwtToken = AuthTokenStore().token;
    final url = Uri.parse('$apiBase/api/parking/locations/$id');
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parking location deleted')),
        );
        await _fetchParkingLocations();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to delete parking location'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Network error: $e'), backgroundColor: Colors.red),
      );
    }
    setState(() {
      _isLoading = false;
    });
  }

  Set<Marker> _buildMarkers() {
    Set<Marker> markers = {};
    for (int i = 0; i < _parkings.length; i++) {
      final lat = _parkings[i]['latitude'];
      final lng = _parkings[i]['longitude'];
      if (lat != null && lng != null) {
        markers.add(
          Marker(
            markerId: MarkerId('parking_$i'),
            position: LatLng(
                double.parse(lat.toString()), double.parse(lng.toString())),
            infoWindow: InfoWindow(
              title: _parkings[i]['name'],
              snippet: '${_parkings[i]["available"]} Available',
            ),
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parking Locations'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Map
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GoogleMap(
                          initialCameraPosition: const CameraPosition(
                            target: LatLng(11.781500, 75.515600),
                            zoom: 15,
                          ),
                          onMapCreated: (controller) {
                            mapController = controller;
                          },
                          markers: _buildMarkers(),
                          myLocationButtonEnabled: true,
                          zoomControlsEnabled: true,
                          zoomGesturesEnabled: true,
                        ),
                      ),
                    ),
                  ),

                  // Parking Cards List
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available Parking Locations',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _parkings.length,
                              itemBuilder: (context, index) {
                                final parking = _parkings[index];
                                return _buildParkingCard(parking);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildParkingCard(Map<String, dynamic> parking) {
    final slots = _parkingSlots[parking['id']] ?? [];
    final availableSlots =
        slots.where((s) => s['status'] == 'available').length;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdminParkingLayoutScreen(
              locationId: parking['id'],
              locationName: parking['name'] ?? 'Parking Location',
              locationAddress: parking['address'] ?? '',
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
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.location_on,
                      color: Colors.blue.shade600,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parking['name'],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${parking["available"]} Available Spots',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        parking['address'] ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Parking Location'),
                        content: Text(
                            'Are you sure you want to delete ${parking['name']}?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _deleteParkingLocation(parking['id']);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Slots Summary
            Row(
              children: [
                Text(
                  'Slots: ${slots.length} total, $availableSlots available',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    mapController?.dispose();
    super.dispose();
  }
}
