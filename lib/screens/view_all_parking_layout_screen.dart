import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';
import '../widgets/custom_drawer.dart';

class ViewAllParkingLayoutScreen extends StatefulWidget {
  const ViewAllParkingLayoutScreen({Key? key}) : super(key: key);

  @override
  State<ViewAllParkingLayoutScreen> createState() =>
      _ViewAllParkingLayoutScreenState();
}

class _ViewAllParkingLayoutScreenState extends State<ViewAllParkingLayoutScreen> {
  List<Map<String, dynamic>> parkingLocations = [];
  bool _isLoading = true;
  String? _errorMessage;
  int? _selectedLocationId;
  int? _userParkingLocationId;
  String? _userSlotNumber;

  @override
  void initState() {
    super.initState();
    _loadAllParkingData();
  }

  Future<void> _loadAllParkingData() async {
    try {
      final jwtToken = AuthTokenStore().token;

      // First, fetch user's current booking to highlight their location
      final bookingUrl = Uri.parse('$apiBase/api/bookings/current');
      final bookingResponse = await http.get(
        bookingUrl,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      ).catchError((_) => null);

      if (bookingResponse != null && bookingResponse.statusCode == 200) {
        final bookingData = jsonDecode(bookingResponse.body);
        final booking = bookingData['booking'];
        _userParkingLocationId = booking['location_id'];
        _userSlotNumber = booking['slot_number'];
      }

      // Fetch all parking locations
      final locUrl = Uri.parse('$apiBase/api/parking/locations');
      final locResponse = await http.get(
        locUrl,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );

      if (locResponse.statusCode == 200) {
        final locData = jsonDecode(locResponse.body);
        final locations = locData['locations'] as List<dynamic>;

        // Fetch slots for each location
        List<Map<String, dynamic>> allLocations = [];
        for (var location in locations) {
          final locId = location['id'];
          final slotsUrl = Uri.parse('$apiBase/api/parking/slots/$locId');

          final slotsResponse = await http.get(
            slotsUrl,
            headers: {
              'Content-Type': 'application/json',
              if (jwtToken != null && jwtToken.isNotEmpty)
                'Authorization': 'Bearer $jwtToken',
            },
          );

          List<Map<String, dynamic>> slots = [];
          if (slotsResponse.statusCode == 200) {
            final slotsData = jsonDecode(slotsResponse.body);
            final slotList = slotsData['slots'] as List<dynamic>;
            slots = slotList.map((slot) => {
              'id': slot['slot_number'],
              'status': slot['status'],
              'isUserCar': slot['slot_number'] == _userSlotNumber &&
                  locId == _userParkingLocationId,
            }).toList();
          }

          allLocations.add({
            'id': locId,
            'name': location['name'] ?? 'Unknown Location',
            'address': location['address'] ?? 'No address',
            'latitude': location['latitude'] ?? 0,
            'longitude': location['longitude'] ?? 0,
            'slots': slots,
            'isUserLocation': locId == _userParkingLocationId,
          });
        }

        parkingLocations = allLocations;
        // Select first location or user's location by default
        if (_userParkingLocationId != null) {
          _selectedLocationId = _userParkingLocationId;
        } else if (parkingLocations.isNotEmpty) {
          _selectedLocationId = parkingLocations[0]['id'];
        }
      } else {
        _errorMessage = 'Failed to load parking locations';
        parkingLocations = [];
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading data: $e';
        parkingLocations = [];
      });
    }
  }

  Color _getSlotColor(Map<String, dynamic> slot) {
    if (slot['isUserCar']) {
      return Colors.grey.shade600;
    }
    switch (slot['status']) {
      case 'available':
        return Colors.green.shade600;
      case 'reserved':
      case 'occupied':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade400;
    }
  }

  String _getSlotLabel(Map<String, dynamic> slot) {
    if (slot['isUserCar']) {
      return 'Your car';
    }
    return slot['id'];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Parking Layout'),
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        drawer: const CustomDrawer(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Parking Layout'),
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        drawer: const CustomDrawer(),
        body: Center(
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    final selectedLocation = parkingLocations.firstWhere(
      (loc) => loc['id'] == _selectedLocationId,
      orElse: () => {},
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parking Layout'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: const CustomDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Location selector dropdown
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<int>(
                  value: _selectedLocationId,
                  isExpanded: true,
                  underline: const SizedBox(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  items: parkingLocations.map((location) {
                    return DropdownMenuItem<int>(
                      value: location['id'],
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: location['isUserLocation']
                                ? Colors.blue.shade600
                                : Colors.grey.shade600,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  location['name'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: location['isUserLocation']
                                        ? Colors.blue.shade600
                                        : Colors.grey.shade800,
                                  ),
                                ),
                                Text(
                                  location['address'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (location['isUserLocation'])
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Your Car',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (int? newValue) {
                    setState(() {
                      _selectedLocationId = newValue;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Legend
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem(Colors.green.shade600, 'Available'),
                  const SizedBox(width: 20),
                  _buildLegendItem(Colors.red.shade600, 'Occupied'),
                  const SizedBox(width: 20),
                  _buildLegendItem(Colors.grey.shade600, 'Your car'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Parking Layout for selected location
            if (selectedLocation.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Location info
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Text(
                            selectedLocation['name'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        // User's car info if in this location
                        if (selectedLocation['isUserLocation'] ?? false)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                border: Border.all(
                                  color: Colors.blue.shade300,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.directions_car,
                                    color: Colors.blue.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Your Vehicle',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Slot: $_userSlotNumber',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Parking slots grid
                        _buildParkingSlotsGrid(
                          selectedLocation['slots'] ?? [],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildParkingSlotsGrid(List<Map<String, dynamic>> slots) {
    if (slots.isEmpty) {
      return Center(
        child: Text(
          'No parking slots available',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate((slots.length / 2).ceil(), (rowIndex) {
          final leftSlotIndex = rowIndex * 2;
          final rightSlotIndex = rowIndex * 2 + 1;
          final leftSlot = slots[leftSlotIndex];
          final rightSlot =
              rightSlotIndex < slots.length ? slots[rightSlotIndex] : null;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: _buildParkingSlot(leftSlot),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 60,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                if (rightSlot != null)
                  Expanded(
                    child: _buildParkingSlot(rightSlot),
                  )
                else
                  Expanded(child: Container()),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildParkingSlot(Map<String, dynamic> slot) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: _getSlotColor(slot),
        borderRadius: BorderRadius.circular(8),
        boxShadow: slot['isUserCar']
            ? [
                BoxShadow(
                  color: Colors.grey.shade600.withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Slot',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _getSlotLabel(slot),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
