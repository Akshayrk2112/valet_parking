import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';

class AdminParkingLayoutScreen extends StatefulWidget {
  final int locationId;
  final String locationName;
  final String locationAddress;

  const AdminParkingLayoutScreen({
    Key? key,
    required this.locationId,
    required this.locationName,
    required this.locationAddress,
  }) : super(key: key);

  @override
  State<AdminParkingLayoutScreen> createState() =>
      _AdminParkingLayoutScreenState();
}

class _AdminParkingLayoutScreenState extends State<AdminParkingLayoutScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _slots = [];

  @override
  void initState() {
    super.initState();
    _fetchSlots();
  }

  Future<void> _fetchSlots() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final jwtToken = AuthTokenStore().token;
    final url = Uri.parse('$apiBase/api/parking/slots/${widget.locationId}');
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
        final slotList = (data['slots'] as List<dynamic>? ?? []);
        _slots = slotList
            .map((slot) => {
                  'slot_number': slot['slot_number'],
                  'status': slot['status'],
                  'booking_vehicle_number': slot['booking_vehicle_number'],
                  'booking_vehicle_type': slot['booking_vehicle_type'],
                  'booking_status': slot['booking_status'],
                  'booking_return_status': slot['booking_return_status'],
                })
            .toList();
      } else {
        _errorMessage = 'Failed to load parking layout';
      }
    } catch (e) {
      _errorMessage = 'Error loading layout: $e';
    }
    setState(() {
      _isLoading = false;
    });
  }

  Color _getSlotColor(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString().toLowerCase();
    final bookingStatus = (slot['booking_status'] ?? '').toString().toLowerCase();

    if (bookingStatus == 'pending') {
      return Colors.amber.shade700;
    }
    if (bookingStatus == 'confirmed') {
      return Colors.red.shade600;
    }

    switch (status) {
      case 'available':
        return Colors.green.shade600;
      case 'reserved':
        return Colors.amber.shade700;
      case 'occupied':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade400;
    }
  }

  String _getSlotLabel(String status, String slotNumber) {
    if (status == 'reserved' || status == 'occupied') {
      return slotNumber;
    }
    return slotNumber;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.locationName),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSlots,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  )
                : Column(
                    children: [
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          widget.locationAddress,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildLegendItem(Colors.green.shade600, 'Available'),
                            const SizedBox(width: 16),
                            _buildLegendItem(Colors.amber.shade700, 'Reserved'),
                            const SizedBox(width: 16),
                            _buildLegendItem(Colors.red.shade600, 'Occupied'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: _buildSlotsGrid(),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildSlotsGrid() {
    if (_slots.isEmpty) {
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

    return SingleChildScrollView(
      child: Column(
        children: [
          ...List.generate((_slots.length / 2).ceil(), (rowIndex) {
            final leftSlotIndex = rowIndex * 2;
            final rightSlotIndex = rowIndex * 2 + 1;
            final leftSlot = _slots[leftSlotIndex];
            final rightSlot =
                rightSlotIndex < _slots.length ? _slots[rightSlotIndex] : null;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  Expanded(child: _buildSlot(leftSlot)),
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
                    Expanded(child: _buildSlot(rightSlot))
                  else
                    Expanded(child: Container()),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSlot(Map<String, dynamic> slot) {
    final status = (slot['status'] ?? '').toString();
    final slotNumber = (slot['slot_number'] ?? '').toString();
    final vehicleType = (slot['booking_vehicle_type'] ?? '').toString();
    final vehicleNumber = (slot['booking_vehicle_number'] ?? '').toString();
    final hasVehicleInfo = vehicleType.isNotEmpty || vehicleNumber.isNotEmpty;
    final color = _getSlotColor(slot);
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              hasVehicleInfo ? 'Vehicle' : 'Slot',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.85),
              ),
            ),
            const SizedBox(height: 4),
            if (hasVehicleInfo) ...[
              Text(
                vehicleType.isNotEmpty ? vehicleType : 'Vehicle',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                vehicleNumber.isNotEmpty ? vehicleNumber : slotNumber,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ] else
              Text(
                _getSlotLabel(status, slotNumber),
                textAlign: TextAlign.center,
                style: const TextStyle(
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
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
