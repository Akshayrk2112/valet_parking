import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../core/config.dart';
import '../core/utils/auth_token_store.dart';
import 'login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityParkingLayoutScreen extends StatefulWidget {
  final String parkingName;

  const SecurityParkingLayoutScreen({
    Key? key,
    required this.parkingName,
  }) : super(key: key);

  @override
  State<SecurityParkingLayoutScreen> createState() =>
      _SecurityParkingLayoutScreenState();
}

class _SecurityParkingLayoutScreenState
    extends State<SecurityParkingLayoutScreen> {
  List<Map<String, dynamic>> parkingSlots = [];
  bool _isLoading = true;
  String? _errorMessage;
  int? _locationId;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchParkingLayout();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _fetchParkingLayout(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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

  Future<void> _fetchParkingLayout({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final jwtToken = AuthTokenStore().token;
    try {
      final locationResp = await http.get(
        Uri.parse('$apiBase/api/parking/locations'),
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (locationResp.statusCode != 200) {
        if (silent) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load locations';
        });
        return;
      }

      final locationsData = jsonDecode(locationResp.body);
      final locations = (locationsData['locations'] as List<dynamic>? ?? []);
      final nameKey = widget.parkingName.trim().toLowerCase();
      final location = locations.cast<Map<String, dynamic>?>().firstWhere(
            (loc) =>
                (loc?['name']?.toString().trim().toLowerCase() ?? '') ==
                nameKey,
            orElse: () => null,
          );

      if (location == null) {
        if (silent) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Parking location not found in database';
        });
        return;
      }

      _locationId = location['id'] as int?;
      if (_locationId == null) {
        if (silent) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid parking location id';
        });
        return;
      }

      final slotsResp = await http.get(
        Uri.parse('$apiBase/api/parking/slots/$_locationId'),
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (slotsResp.statusCode != 200) {
        if (silent) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load parking slots';
        });
        return;
      }

      final bookingsResp = await http.get(
        Uri.parse('$apiBase/api/bookings'),
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );

      final bookingBySlot = <String, Map<String, dynamic>>{};
      if (bookingsResp.statusCode == 200) {
        final bookingsData = jsonDecode(bookingsResp.body);
        final bookings = (bookingsData['bookings'] as List<dynamic>? ?? []);
        for (final b in bookings) {
          final booking = b as Map<String, dynamic>;
          final sameLocation = booking['location_id'] == _locationId;
          final slot = booking['slot_number']?.toString();
          if (!sameLocation || slot == null || slot.isEmpty) continue;
          final status = (booking['status'] ?? '').toString().toLowerCase();
          final returnStatus =
              (booking['return_status'] ?? '').toString().toLowerCase();
          final shouldBlockSlot = status == 'pending' ||
              (status == 'confirmed' &&
                  returnStatus != 'released' &&
                  returnStatus != 'completed');

          if (shouldBlockSlot) {
            final existing = bookingBySlot[slot];
            final existingRawId = existing == null ? null : existing['id'];
            final existingId = existingRawId is int
                ? existingRawId
                : int.tryParse(existingRawId?.toString() ?? '');
            final currentId = booking['id'] is int
                ? booking['id'] as int
                : int.tryParse(booking['id']?.toString() ?? '');
            if (existing == null ||
                (currentId != null &&
                    (existingId == null || currentId > existingId))) {
              bookingBySlot[slot] = booking;
            }
          }
        }
      }

      final slotData = jsonDecode(slotsResp.body);
      final slots = (slotData['slots'] as List<dynamic>? ?? []);
      final built = slots.map((s) {
        final slot = s as Map<String, dynamic>;
        final slotNumber = (slot['slot_number'] ?? '').toString();
        final relatedBooking = bookingBySlot[slotNumber];
        final vehicleNumber =
            relatedBooking?['vehicle_number']?.toString() ?? '';
        final vehicleName = relatedBooking?['vehicle_type']?.toString() ?? '';
        final bookingStatus = relatedBooking?['status']?.toString();
        final dbSlotStatus = (slot['status'] ?? 'available').toString();
        final customerName =
            (relatedBooking?['customer_name'] ?? '').toString().trim();

        String uiStatus = 'available';
        if (relatedBooking != null && bookingStatus == 'pending') {
          // Customer has booked slot; awaiting security confirmation.
          uiStatus = 'pending';
        } else if (relatedBooking != null && bookingStatus == 'confirmed') {
          uiStatus = 'occupied';
        } else if (dbSlotStatus == 'occupied') {
          uiStatus = 'occupied';
        } else if (dbSlotStatus == 'reserved') {
          uiStatus = 'pending';
        }

        return {
          'dbId': slot['id'],
          'id': slotNumber,
          'status': uiStatus,
          'vehicleName': vehicleName,
          'vehicleNumber': vehicleNumber,
          'vehicleInfo': vehicleName.isNotEmpty || vehicleNumber.isNotEmpty
              ? '$vehicleName\n$vehicleNumber'
              : '',
          'bookingStatus': bookingStatus ?? '',
          'bookingTime': relatedBooking?['booking_time']?.toString() ?? '',
          'returnRequestedAt':
              relatedBooking?['return_requested_at']?.toString() ?? '',
          'returnStatus': relatedBooking?['return_status']?.toString() ?? '',
          'returnDriverId':
              relatedBooking?['return_driver_id']?.toString() ?? '',
          'returnDriverName':
              relatedBooking?['return_driver_name']?.toString() ?? '',
          'desiredReturnLocation':
              relatedBooking?['desired_return_location']?.toString() ?? '',
          'customerName': customerName.isNotEmpty
              ? customerName
              : (relatedBooking?['user_id'] != null
                  ? 'Customer ${relatedBooking?['user_id']}'
                  : ''),
        };
      }).toList();

      setState(() {
        parkingSlots = built.cast<Map<String, dynamic>>();
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (silent) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error while loading parking layout';
      });
    }
  }

  String _vehicleModel(Map<String, dynamic> slot) {
    final value = (slot['vehicleName'] ?? '').toString().trim();
    return value.isNotEmpty ? value : 'N/A';
  }

  String _vehicleNumber(Map<String, dynamic> slot) {
    final value = (slot['vehicleNumber'] ?? '').toString().trim();
    return value.isNotEmpty ? value : 'N/A';
  }

  String _reservationExpiryLabel(Map<String, dynamic> slot) {
    final rawBookingTime = (slot['bookingTime'] ?? '').toString().trim();
    if (rawBookingTime.isEmpty) return 'Reservation window: 30 minutes';
    final bookingTime = DateTime.tryParse(rawBookingTime);
    if (bookingTime == null) return 'Reservation window: 30 minutes';
    final expiry = bookingTime.toLocal().add(const Duration(minutes: 30));
    final hh = expiry.hour.toString().padLeft(2, '0');
    final mm = expiry.minute.toString().padLeft(2, '0');
    return 'Reservation expires at $hh:$mm';
  }

  String _extractApiError(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        final error = data['error']?.toString();
        if (error != null && error.isNotEmpty) return error;
        final message = data['message']?.toString();
        if (message != null && message.isNotEmpty) return message;
      }
    } catch (_) {}
    return 'Request failed (${response.statusCode})';
  }

  Color _getSlotColor(String status) {
    switch (status) {
      case 'available':
        return Colors.green.shade600;
      case 'pending':
        return Colors.red.shade500;
      case 'occupied':
        return Colors.amber.shade700;
      default:
        return Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parking Layout'),
        backgroundColor: Colors.orange.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fetchParkingLayout();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Legend Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Slot Status Legend',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildLegendItem(
                        Colors.green.shade600,
                        'Free slot',
                      ),
                      const SizedBox(width: 24),
                      _buildLegendItem(
                        Colors.red.shade500,
                        'Booked (awaiting confirmation)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildLegendItem(
                        Colors.amber.shade700,
                        'Confirmed parked',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Zone Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'ZONE A - GROUND FLOOR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 1,
                ),
              ),
            ),

            // Parking Layout
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade600),
                          ),
                        )
                      : parkingSlots.isEmpty
                          ? const Center(
                              child: Text(
                                  'No parking slots found for this location'),
                            )
                          : Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ...List.generate(
                                        (parkingSlots.length / 2).ceil(),
                                        (rowIndex) {
                                      final leftSlotIndex = rowIndex * 2;
                                      final rightSlotIndex = rowIndex * 2 + 1;
                                      if (leftSlotIndex >=
                                          parkingSlots.length) {
                                        return const SizedBox.shrink();
                                      }

                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12.0),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: GestureDetector(
                                                onTap: () => _showSlotDetails(
                                                  parkingSlots[leftSlotIndex],
                                                  leftSlotIndex,
                                                ),
                                                child: _buildParkingSlot(
                                                  parkingSlots[leftSlotIndex],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Container(
                                              width: 50,
                                              height: 80,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade300,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  'D',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            if (rightSlotIndex <
                                                parkingSlots.length)
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap: () => _showSlotDetails(
                                                    parkingSlots[
                                                        rightSlotIndex],
                                                    rightSlotIndex,
                                                  ),
                                                  child: _buildParkingSlot(
                                                    parkingSlots[
                                                        rightSlotIndex],
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

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildParkingSlot(Map<String, dynamic> slot) {
    return Container(
      height: 80,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _getSlotColor(slot['status']),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _getSlotColor(slot['status']).withOpacity(0.3),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            slot['id'],
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          if (slot['vehicleInfo'].isNotEmpty)
            Text(
              slot['vehicleInfo'],
              style: const TextStyle(
                fontSize: 8,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  void _showSlotDetails(Map<String, dynamic> slot, int slotIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        if (slot['status'] == 'available') {
          return _buildAvailableSlotModal(slot, slotIndex);
        } else if (slot['status'] == 'pending') {
          return _buildPendingSlotModal(slot, slotIndex);
        } else {
          return _buildOccupiedSlotModal(slot, slotIndex);
        }
      },
    );
  }

  // Available Slot Modal (Green)
  Widget _buildAvailableSlotModal(Map<String, dynamic> slot, int slotIndex) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Slot ${slot['id']}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.close,
                    color: Colors.grey.shade600,
                    size: 24,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Available',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'This slot is currently available and ready for booking.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 24),

            // Refresh Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _fetchParkingLayout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Refresh',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Pending Slot Modal (Yellow)
  Widget _buildPendingSlotModal(Map<String, dynamic> slot, int slotIndex) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Slot ${slot['id']}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.close,
                    color: Colors.grey.shade600,
                    size: 24,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.red.shade500,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Booked - Awaiting Confirmation',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Vehicle Details
            Text(
              'Vehicle Details',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),

            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vehicle Name: ${_vehicleModel(slot)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Vehicle Number: ${_vehicleNumber(slot)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Customer has booked this slot. Please verify and confirm parked status.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              _reservationExpiryLabel(slot),
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 24),

            // Confirm Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _confirmParked(slotIndex);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Confirm Parking',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Occupied Slot Modal (Red)
  Widget _buildOccupiedSlotModal(Map<String, dynamic> slot, int slotIndex) {
    final hasReturnRequest =
        (slot['returnRequestedAt'] ?? '').toString().trim().isNotEmpty;
    final returnStatus =
        (slot['returnStatus'] ?? '').toString().trim().toLowerCase();
    final canConfirmReturn = hasReturnRequest &&
        (returnStatus == 'accepted' || returnStatus.isEmpty);
    final acceptedDriverName =
        (slot['returnDriverName'] ?? '').toString().trim();
    final acceptedDriverId = (slot['returnDriverId'] ?? '').toString().trim();
    final acceptedDriverLabel = acceptedDriverName.isNotEmpty
        ? acceptedDriverName
        : (acceptedDriverId.isNotEmpty ? 'Driver ID $acceptedDriverId' : '');

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Slot ${slot['id']}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.close,
                    color: Colors.grey.shade600,
                    size: 24,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.amber.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Confirmed Parked',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Parked Vehicle Details
            Text(
              'Parked Vehicle',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),

            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vehicle Name: ${_vehicleModel(slot)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Vehicle Number: ${_vehicleNumber(slot)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (hasReturnRequest) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Return Destination',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (slot['desiredReturnLocation'] ?? '')
                              .toString()
                              .isNotEmpty
                          ? slot['desiredReturnLocation'].toString()
                          : 'Not specified',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      returnStatus == 'accepted' &&
                              acceptedDriverLabel.isNotEmpty
                          ? 'Accepted by: $acceptedDriverLabel'
                          : (returnStatus.isEmpty
                              ? 'No driver acceptance required'
                              : 'Awaiting driver acceptance'),
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            (returnStatus == 'accepted' || returnStatus.isEmpty)
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            Text(
              !hasReturnRequest
                  ? 'Waiting for customer return request before releasing this slot.'
                  : canConfirmReturn
                      ? (returnStatus == 'accepted'
                          ? 'Driver accepted return request. Confirm to release slot as available.'
                          : 'Customer requested return. Confirm to release slot as available.')
                      : 'Return requested. Waiting for a driver to accept.',
              style: TextStyle(
                fontSize: 12,
                color: canConfirmReturn
                    ? Colors.red.shade700
                    : Colors.grey.shade600,
                fontWeight:
                    canConfirmReturn ? FontWeight.w600 : FontWeight.normal,
                fontStyle: FontStyle.italic,
              ),
            ),

            const SizedBox(height: 24),

            // Confirm Retrieved Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: hasReturnRequest
                    ? () {
                        if (!canConfirmReturn) return;
                        Navigator.pop(context);
                        _confirmRetrieved(slotIndex);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  disabledBackgroundColor: Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  !hasReturnRequest
                      ? 'Awaiting Return Request'
                      : canConfirmReturn
                          ? 'Confirm Return'
                          : 'Awaiting Driver Acceptance',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmParked(int slotIndex) async {
    final slotId = parkingSlots[slotIndex]['dbId'];
    final jwtToken = AuthTokenStore().token;
    final response = await http.patch(
      Uri.parse('$apiBase/api/parking/slots/$slotId'),
      headers: {
        'Content-Type': 'application/json',
        if (jwtToken != null && jwtToken.isNotEmpty)
          'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({'status': 'occupied'}),
    );

    if (!mounted) return;
    if (response.statusCode == 200) {
      await _fetchParkingLayout();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Parked confirmed! Notifications sent to customer and driver.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractApiError(response)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmRetrieved(int slotIndex) async {
    final slotId = parkingSlots[slotIndex]['dbId'];
    final jwtToken = AuthTokenStore().token;
    final response = await http.patch(
      Uri.parse('$apiBase/api/parking/slots/$slotId'),
      headers: {
        'Content-Type': 'application/json',
        if (jwtToken != null && jwtToken.isNotEmpty)
          'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({'status': 'available'}),
    );

    if (!mounted) return;
    if (response.statusCode == 200) {
      await _fetchParkingLayout();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle return confirmed. Slot is now available.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractApiError(response)),
          backgroundColor: Colors.red,
        ),
      );
    }
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
            fontSize: 12,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
