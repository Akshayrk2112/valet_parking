import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../models/parking_models.dart';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';
import '../providers/parking_provider.dart';

class AddParkingLocationScreen extends StatefulWidget {
  final Function(ParkingLocation) onParkingAdded;

  const AddParkingLocationScreen({
    Key? key,
    required this.onParkingAdded,
  }) : super(key: key);

  @override
  State<AddParkingLocationScreen> createState() =>
      _AddParkingLocationScreenState();
}

class _AddParkingLocationScreenState extends State<AddParkingLocationScreen> {
  final _parkingNameController = TextEditingController();
  final _locationController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _maxCapacityController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _parkingNameController.dispose();
    _locationController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _maxCapacityController.dispose();
    super.dispose();
  }

  void _addParkingLocation() {

    if (_parkingNameController.text.isEmpty) {
      _showError('Please enter parking name');
      return;
    }
    if (_locationController.text.isEmpty) {
      _showError('Please enter address/location');
      return;
    }
    if (_latitudeController.text.isEmpty || _longitudeController.text.isEmpty) {
      _showError('Please enter both latitude and longitude');
      return;
    }
    if (_maxCapacityController.text.isEmpty) {
      _showError('Please enter max capacity');
      return;
    }
    double? latitude = double.tryParse(_latitudeController.text);
    double? longitude = double.tryParse(_longitudeController.text);
    if (latitude == null || longitude == null) {
      _showError('Latitude and Longitude must be valid numbers');
      return;
    }
    int maxCapacity;
    try {
      maxCapacity = int.parse(_maxCapacityController.text);
    } catch (e) {
      _showError('Max capacity must be a number');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Send POST request to backend
    final jwtToken = AuthTokenStore().token;
    final url = Uri.parse('$apiBase/api/parking/locations');
    http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (jwtToken != null && jwtToken.isNotEmpty)
          'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'name': _parkingNameController.text,
        'address': _locationController.text,
        'latitude': latitude,
        'longitude': longitude,
        'total_slots': maxCapacity,
        'available_slots': maxCapacity,
      }),
    ).then((response) async {
      setState(() {
        _isLoading = false;
      });
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_parkingNameController.text} added successfully!'),
            duration: const Duration(seconds: 2),
          ),
        );
        // Refresh provider parkings so UI updates immediately.
        try {
          final provider = Provider.of<ParkingProvider>(context, listen: false);
          // Try to get current user location and pass to fetchParkings
          try {
            final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
            provider.fetchParkings(LatLng(pos.latitude, pos.longitude));
          } catch (_) {
            provider.fetchParkings();
          }
        } catch (_) {}
        Navigator.pop(context);
      } else {
        String msg = 'Failed to add parking location';
        try {
          final data = jsonDecode(response.body);
          if (data['error'] != null) msg = data['error'];
        } catch (_) {}
        _showError(msg);
      }
    }).catchError((e) {
      setState(() {
        _isLoading = false;
      });
      _showError('Network error: $e');
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Parking Location'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Parking Name
                _buildFormLabel('Parking Name'),
                const SizedBox(height: 8),
                TextField(
                  controller: _parkingNameController,
                  decoration: InputDecoration(
                    hintText: 'e.g., Parking D',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.blue.shade600,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 20),


                // Address/Location
                _buildFormLabel('Address/Location'),
                const SizedBox(height: 8),
                TextField(
                  controller: _locationController,
                  decoration: InputDecoration(
                    hintText: 'e.g., Downtown, Main Street',
                    prefixIcon: Icon(
                      Icons.location_on,
                      color: Colors.grey.shade600,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.blue.shade600,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Latitude
                _buildFormLabel('Latitude'),
                const SizedBox(height: 8),
                TextField(
                  controller: _latitudeController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'e.g., 37.7749',
                    prefixIcon: Icon(
                      Icons.my_location,
                      color: Colors.grey.shade600,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.blue.shade600,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Longitude
                _buildFormLabel('Longitude'),
                const SizedBox(height: 8),
                TextField(
                  controller: _longitudeController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'e.g., -122.4194',
                    prefixIcon: Icon(
                      Icons.my_location,
                      color: Colors.grey.shade600,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.blue.shade600,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Max Capacity
                _buildFormLabel('Max Capacity'),
                const SizedBox(height: 8),
                TextField(
                  controller: _maxCapacityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'e.g., 16, 32, 50',
                    prefixIcon: Icon(
                      Icons.grid_3x3,
                      color: Colors.grey.shade600,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.blue.shade600,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Helper text
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    'Parking layout will be automatically created with the capacity you specify. It will equally distribute slots on both sides.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade600,
                      height: 1.5,
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Add Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _addParkingLocation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      disabledBackgroundColor: Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                Colors.blue.shade600,
                              ),
                            ),
                          )
                        : const Text(
                            'Add Parking Location',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.blue.shade600,
      ),
    );
  }
}
