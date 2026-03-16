import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/parking_models.dart';
import 'login_screen.dart';
import '../core/config.dart';
import '../core/utils/auth_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriverParkingLayoutScreen extends StatefulWidget {
  final ParkingLocation parking;
  final Map<String, dynamic> request;
  final VoidCallback onCompleted;

  const DriverParkingLayoutScreen({
    Key? key,
    required this.parking,
    required this.request,
    required this.onCompleted,
  }) : super(key: key);

  @override
  State<DriverParkingLayoutScreen> createState() =>
      _DriverParkingLayoutScreenState();
}

class _DriverParkingLayoutScreenState extends State<DriverParkingLayoutScreen> {
  List<Map<String, dynamic>> parkingSlots = [];
  String? _selectedSlot;
  int? _selectedSlotDbId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchParkingSlots();
  }

  Future<void> _fetchParkingSlots() async {
    if (widget.parking.id == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final jwtToken = AuthTokenStore().token;
      final response = await http.get(
        Uri.parse('$apiBase/api/parking/slots/${widget.parking.id}'),
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final slots = (data['slots'] as List<dynamic>? ?? []);
        setState(() {
          parkingSlots = slots
              .map((slot) => {
                    'dbId': slot['id'],
                    'id': slot['slot_number'],
                    'status': slot['status'] ?? 'available',
                    'isSelected': false,
                  })
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        _isLoading = false;
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

  Color _getSlotColor(String status) {
    switch (status) {
      case 'available':
        return Colors.green.shade600;
      case 'occupied':
        return Colors.red.shade600;
      case 'pending':
        return Colors.amber.shade600;
      case 'reserved':
        return Colors.amber.shade600;
      case 'maintenance':
        return Colors.grey.shade500;
      default:
        return Colors.grey.shade400;
    }
  }

  void _selectSlot(int index) {
    final slot = parkingSlots[index];

    if (slot['status'] == 'available') {
      setState(() {
        if (_selectedSlot == slot['id']) {
          _selectedSlot = null;
          _selectedSlotDbId = null;
          parkingSlots[index]['isSelected'] = false;
        } else {
          // Deselect previous
          if (_selectedSlot != null) {
            final prevIndex =
                parkingSlots.indexWhere((s) => s['id'] == _selectedSlot);
            if (prevIndex != -1) {
              parkingSlots[prevIndex]['isSelected'] = false;
            }
          }
          _selectedSlot = slot['id'];
          _selectedSlotDbId = slot['dbId'] as int?;
          parkingSlots[index]['isSelected'] = true;
        }
      });
    }
  }

  void _parkVehicle() {
    if (_selectedSlot == null || _selectedSlotDbId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a parking slot'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Show confirmation dialog without parking charges
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vehicle Parking Summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Parking Slot',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  _selectedSlot!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Parking Location',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  widget.parking.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    color: Colors.amber.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Slot booked for this vehicle.\nSecurity will verify and mark it parked.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final jwtToken = AuthTokenStore().token;

              final slotResponse = await http.patch(
                Uri.parse('$apiBase/api/parking/slots/$_selectedSlotDbId'),
                headers: {
                  'Content-Type': 'application/json',
                  if (jwtToken != null && jwtToken.isNotEmpty)
                    'Authorization': 'Bearer $jwtToken',
                },
                body: jsonEncode({'status': 'reserved'}),
              );

              if (slotResponse.statusCode != 200) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to book selected slot'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final bookingToken = widget.request['id'];
              if (bookingToken != null && widget.parking.id != null) {
                await http.patch(
                  Uri.parse('$apiBase/api/bookings/$bookingToken'),
                  headers: {
                    'Content-Type': 'application/json',
                    if (jwtToken != null && jwtToken.isNotEmpty)
                      'Authorization': 'Bearer $jwtToken',
                  },
                  body: jsonEncode({
                    'location_id': widget.parking.id,
                    'slot_number': _selectedSlot,
                  }),
                );
              }

              if (!mounted) return;
              Navigator.pop(context);
              widget.onCompleted();
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Slot booked. Awaiting security confirmation.'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Colors.amber,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700),
            child: const Text('Confirm Booking'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Park Vehicle'),
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
        child: Column(
          children: [
            // Parking Location Title
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                widget.parking.name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ),

            // Legend
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem(Colors.green.shade600, 'Available'),
                  const SizedBox(width: 24),
                  _buildLegendItem(Colors.amber.shade600, 'Booked'),
                  const SizedBox(width: 24),
                  _buildLegendItem(Colors.red.shade600, 'Occupied'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Parking Layout
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : parkingSlots.isEmpty
                      ? const Center(
                          child:
                              Text('No parking slots found for this location'),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ...List.generate(
                                    (parkingSlots.length / 2).ceil(),
                                    (rowIndex) {
                                  final leftSlotIndex = rowIndex * 2;
                                  final rightSlotIndex = rowIndex * 2 + 1;
                                  if (leftSlotIndex >= parkingSlots.length) {
                                    return const SizedBox.shrink();
                                  }

                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () =>
                                                _selectSlot(leftSlotIndex),
                                            child: _buildParkingSlot(
                                              parkingSlots[leftSlotIndex],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Container(
                                          width: 50,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade400,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        if (rightSlotIndex <
                                            parkingSlots.length)
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () =>
                                                  _selectSlot(rightSlotIndex),
                                              child: _buildParkingSlot(
                                                parkingSlots[rightSlotIndex],
                                              ),
                                            ),
                                          )
                                        else
                                          const Expanded(
                                              child: SizedBox.shrink()),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
            ),

            // Parked Button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _parkVehicle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Booked',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParkingSlot(Map<String, dynamic> slot) {
    final isSelected = slot['isSelected'] == true;

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: _getSlotColor(slot['status']),
        borderRadius: BorderRadius.circular(8),
        border: isSelected
            ? Border.all(
                color: Colors.white,
                width: 3,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: _getSlotColor(slot['status']).withOpacity(0.3),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: slot['status'] == 'available'
              ? () => _selectSlot(parkingSlots.indexOf(slot))
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Text(
              slot['id'],
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
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
