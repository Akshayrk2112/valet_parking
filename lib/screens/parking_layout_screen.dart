import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../models/parking_models.dart';
import '../core/utils/auth_token_store.dart';
import '../core/utils/validators.dart';
import '../core/config.dart';
import 'booking_confirmed_screen.dart';

class ParkingLayoutScreen extends StatefulWidget {
  final ParkingLocation parking;
  final String? userSlotNumber;

  const ParkingLayoutScreen({
    Key? key,
    required this.parking,
    this.userSlotNumber,
  }) : super(key: key);

  @override
  State<ParkingLayoutScreen> createState() => _ParkingLayoutScreenState();
}

class _ParkingLayoutScreenState extends State<ParkingLayoutScreen> {
  static const int _selfParkingFee = 50;

  List<Map<String, dynamic>> parkingSlots = [];
  String? _selectedSlot;
  Set<String> _bookedSlots = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _userSlotNumber;
  String? _userBookingStatus;
  int? _resolvedLocationId;
  String? _userBookingToken;
  String _userVehicleName = '';
  String _userVehicleNumber = '';
  String? _returnRequestedAt;
  bool _isRequestingReturn = false;
  bool _isCancellingBooking = false;
  Timer? _refreshTimer;

  bool get _isParkingConfirmed =>
      (_userBookingStatus ?? '').toLowerCase() == 'confirmed';

  @override
  void initState() {
    super.initState();
    _userSlotNumber = widget.userSlotNumber;
    _loadParkingSlots();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadParkingSlots(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadParkingSlots({bool silent = false}) async {
    try {
      if (!silent) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }
      final jwtToken = AuthTokenStore().token;
      var locationId = widget.parking.id;

      // Fallback: if the passed parking lacks an id, try to resolve it by name
      if (locationId == null) {
        try {
          final locsUrl = Uri.parse('$apiBase/api/parking/locations');
          final locsResp = await http.get(locsUrl, headers: {
            'Content-Type': 'application/json',
            if (jwtToken != null && jwtToken.isNotEmpty)
              'Authorization': 'Bearer $jwtToken',
          });
          if (locsResp.statusCode == 200) {
            final locData = jsonDecode(locsResp.body);
            final locs = (locData['locations'] as List<dynamic>?) ?? [];
            final match = locs.firstWhere(
              (l) =>
                  (l['name'] ?? '').toString().trim() ==
                  widget.parking.name.trim(),
              orElse: () => null,
            );
            if (match != null) {
              locationId = match['id'] is int
                  ? match['id']
                  : int.tryParse(match['id']?.toString() ?? '');
            }
          }
        } catch (e) {
          print('[ParkingLayoutScreen] Error resolving location: $e');
        }
      }

      if (locationId == null) {
        if (silent) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid parking location';
        });
        return;
      }

      _resolvedLocationId = locationId;
      await _loadCurrentBooking(locationId, jwtToken: jwtToken);

      // Step 1: Fetch actual slots for this location from backend.
      final slotsUrl = Uri.parse('$apiBase/api/parking/slots/$locationId');
      final slotsResponse = await http.get(
        slotsUrl,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (slotsResponse.statusCode != 200) {
        if (silent) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load slots for this parking location';
        });
        return;
      }
      final slotsData = jsonDecode(slotsResponse.body);
      final slots = (slotsData['slots'] as List<dynamic>? ?? []);

      // Step 2: Fetch all active bookings to reflect latest occupancy state.
      final bookingsUrl = Uri.parse('$apiBase/api/bookings');
      final bookingsResponse = await http.get(
        bookingsUrl,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );

      Set<String> bookedSlots = {};
      if (bookingsResponse.statusCode == 200) {
        final bookingsData = jsonDecode(bookingsResponse.body);
        final bookings = (bookingsData['bookings'] as List<dynamic>?) ?? [];

        // Collect slot_numbers only for active bookings at this location.
        // Completed/cancelled bookings should not block slots.
        for (var booking in bookings) {
          final status = (booking['status'] ?? '').toString();
          final isActive = status == 'pending' || status == 'confirmed';
          if (isActive &&
              booking['location_id'] == locationId &&
              booking['slot_number'] != null) {
            final slotNum = booking['slot_number'].toString();
            bookedSlots.add(slotNum);
            print('[ParkingLayoutScreen] Found booked slot: $slotNum');
          }
        }
      }

      // Step 3: Build UI slots using real DB slot ids/numbers so security and customer share same slots.
      final builtSlots = slots.map((slotRaw) {
        final slot = slotRaw as Map<String, dynamic>;
        final slotNumber = (slot['slot_number'] ?? '').toString();
        final dbStatus = (slot['status'] ?? 'available').toString();
        final isBookedByStatus =
            dbStatus == 'reserved' || dbStatus == 'occupied';
        final isBookedByBooking = bookedSlots.contains(slotNumber);
        final isUserSlot =
            _userSlotNumber != null && slotNumber == _userSlotNumber;
        final isUserCar = isUserSlot && _isParkingConfirmed;
        final isUserBooked = isUserSlot && !_isParkingConfirmed;

        return {
          'dbId': slot['id'],
          'id': slotNumber,
          'status': (isBookedByStatus || isBookedByBooking)
              ? 'occupied'
              : 'available',
          'isUserCar': isUserCar,
          'isUserBooked': isUserBooked,
          'isSelected': false,
        };
      }).toList();

      setState(() {
        parkingSlots = builtSlots.cast<Map<String, dynamic>>();
        _bookedSlots = parkingSlots
            .where((s) => s['status'] == 'occupied')
            .map((s) => s['id'].toString())
            .toSet();
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (silent) return;
      print('[ParkingLayoutScreen] Error loading slots: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading slots: $e';
      });
    }
  }

  Color _getSlotColor(Map<String, dynamic> slot) {
    if (slot['isUserCar'] == true) {
      return Colors.blue.shade600; // Blue for user's car
    }
    if (slot['isUserBooked'] == true) {
      return Colors.amber.shade700; // Pending security confirmation
    }
    final status = slot['status'] ?? 'available';
    switch (status) {
      case 'available':
        return Colors.green.shade600;
      case 'occupied':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade400;
    }
  }

  void _selectSlot(int index) {
    final slot = parkingSlots[index];

    if (slot['isUserCar'] == true || slot['isUserBooked'] == true) {
      _showUserVehicleDetails(slot);
      return;
    }

    if (slot['status'] == 'available' && !_bookedSlots.contains(slot['id'])) {
      _showSlotDetails(slot, index);
    }
  }

  Future<void> _loadCurrentBooking(
    int locationId, {
    required String? jwtToken,
  }) async {
    try {
      final bookingUrl = Uri.parse('$apiBase/api/bookings/current');
      final bookingResp = await http.get(
        bookingUrl,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (bookingResp.statusCode == 404) {
        _userSlotNumber = null;
        _userBookingStatus = null;
        _userBookingToken = null;
        _userVehicleName = '';
        _userVehicleNumber = '';
        _returnRequestedAt = null;
        return;
      }
      if (bookingResp.statusCode != 200) return;
      final bookingData = jsonDecode(bookingResp.body);
      final booking = bookingData['booking'] as Map<String, dynamic>?;
      if (booking == null) return;

      final bookingLocationId = booking['location_id'];
      final sameLocation = bookingLocationId == locationId;
      if (!sameLocation) return;

      _userSlotNumber = booking['slot_number']?.toString();
      _userBookingStatus = booking['status']?.toString();
      _userBookingToken = booking['booking_token']?.toString();
      _userVehicleName = booking['vehicle_type']?.toString() ?? '';
      _userVehicleNumber = booking['vehicle_number']?.toString() ?? '';
      _returnRequestedAt = booking['return_requested_at']?.toString();
    } catch (_) {
      // Non-fatal: parking layout can still render without booking details.
    }
  }

  String _extractApiError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error']?.toString();
        if (error != null && error.isNotEmpty) return error;
        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) return message;
      }
    } catch (_) {}
    return 'Request failed (${response.statusCode})';
  }

  bool get _hasReturnRequested {
    return (_returnRequestedAt ?? '').trim().isNotEmpty;
  }

  Future<void> _requestVehicleReturn() async {
    if (_userBookingToken == null || _userBookingToken!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active booking found for return')),
      );
      return;
    }

    if (_hasReturnRequested) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Return request already submitted')),
      );
      return;
    }

    setState(() {
      _isRequestingReturn = true;
    });
    try {
      final jwt = AuthTokenStore().token;
      final url = Uri.parse(
          '$apiBase/api/bookings/${Uri.encodeComponent(_userBookingToken!)}/request-return');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwt != null && jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
        },
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final booking = data['booking'] as Map<String, dynamic>?;
        setState(() {
          _returnRequestedAt = booking?['return_requested_at']?.toString() ??
              DateTime.now().toIso8601String();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Return requested. Please show this to security.')),
        );
        await _loadParkingSlots(silent: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_extractApiError(response))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to request return: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingReturn = false;
        });
      }
    }
  }

  Future<void> _cancelSelfParkingBooking() async {
    if (_userBookingToken == null || _userBookingToken!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active booking found to cancel')),
      );
      return;
    }

    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text(
          'Do you want to cancel this booking? The slot will become available again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (shouldCancel != true) return;

    setState(() {
      _isCancellingBooking = true;
    });

    try {
      final jwt = AuthTokenStore().token;
      final url = Uri.parse(
          '$apiBase/api/bookings/${Uri.encodeComponent(_userBookingToken!)}/cancel-self');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwt != null && jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final message = (data['message'] ?? '').toString().trim();
        Navigator.pop(context); // close slot details sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message.isNotEmpty
                  ? message
                  : 'Booking cancelled successfully. Slot is now available.',
            ),
          ),
        );
        await _loadParkingSlots();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_extractApiError(response))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel booking: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCancellingBooking = false;
        });
      }
    }
  }

  void _showUserVehicleDetails(Map<String, dynamic> slot) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isParkingConfirmed
                        ? 'Your Parked Vehicle'
                        : 'Your Booked Slot',
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
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Slot',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          slot['id'].toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Vehicle Name',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            _userVehicleName.isNotEmpty
                                ? _userVehicleName
                                : 'N/A',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Vehicle Number',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            _userVehicleNumber.isNotEmpty
                                ? _userVehicleNumber
                                : 'N/A',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                !_isParkingConfirmed
                    ? 'Security has not confirmed parking yet. This slot is currently booked. You can cancel if you do not want to park here.'
                    : _hasReturnRequested
                        ? 'Return already requested. Security will confirm return.'
                        : 'Your car is parked in this slot.',
                style: TextStyle(
                  fontSize: 12,
                  color: !_isParkingConfirmed
                      ? Colors.orange.shade700
                      : _hasReturnRequested
                          ? Colors.green.shade700
                          : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 20),
              _isParkingConfirmed
                  ? SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isCancellingBooking
                                ? null
                                : () async {
                                    await _cancelSelfParkingBooking();
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                            ),
                            child: _isCancellingBooking
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text(
                                    'Cancel Booking',
                                    style: TextStyle(color: Colors.white),
                                  ),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSlotDetails(Map<String, dynamic> slot, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
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
              // Header with close button
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

              const SizedBox(height: 12),

              // Message
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.check,
                        color: Colors.green.shade600,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This parking space is available',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Would you like to book it?',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Slot ID',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          slot['id'],
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Status',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Available',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _showVehicleInfoForm(slot, index);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showVehicleInfoForm(
      Map<String, dynamic> slot, int index) async {
    final vehicleTypeController = TextEditingController();
    final vehicleNumberController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Vehicle Details',
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
                TextField(
                  controller: vehicleTypeController,
                  decoration: InputDecoration(
                    labelText: 'Vehicle Name',
                    hintText: 'e.g., Swift, i20, City',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: vehicleNumberController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-Z0-9 \-]'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Vehicle Number/Plate',
                    hintText: 'e.g., KL58AH9653',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
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
                        'Self parking fee: Rs $_selfParkingFee',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Payment is required before confirming this booking.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final vehicleNumber = normalizeVehicleNumber(
                            vehicleNumberController.text,
                          );
                          final vehicleType = vehicleTypeController.text.trim();

                          if (vehicleType.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please enter vehicle name')),
                            );
                            return;
                          }

                          final vehicleNumberError = validateVehicleNumber(
                            vehicleNumberController.text,
                          );
                          if (vehicleNumberError != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(vehicleNumberError)),
                            );
                            return;
                          }

                          Navigator.pop(context);
                          await _showPaymentSheet(
                            slot,
                            index,
                            vehicleType: vehicleType,
                            vehicleNumber: vehicleNumber,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Proceed to Payment',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPaymentSheet(
    Map<String, dynamic> slot,
    int index, {
    required String vehicleType,
    required String vehicleNumber,
  }) async {
    String selectedPaymentMethod = 'gpay';
    bool isProcessing = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Payment',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    GestureDetector(
                      onTap: isProcessing ? null : () => Navigator.pop(context),
                      child: Icon(
                        Icons.close,
                        color: Colors.grey.shade600,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Self parking fee',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        'Rs $_selfParkingFee',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Choose payment method',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                ...['debitcard', 'credit card', 'gpay'].map((method) {
                  return RadioListTile<String>(
                    value: method,
                    groupValue: selectedPaymentMethod,
                    onChanged: isProcessing
                        ? null
                        : (value) {
                            if (value == null) return;
                            setModalState(() {
                              selectedPaymentMethod = value;
                            });
                          },
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(method),
                  );
                }).toList(),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isProcessing
                        ? null
                        : () async {
                            setModalState(() {
                              isProcessing = true;
                            });
                            await Future.delayed(
                                const Duration(milliseconds: 700));
                            if (!mounted) return;
                            Navigator.pop(context);
                            await _bookSlot(
                              slot,
                              index,
                              vehicleType: vehicleType,
                              vehicleNumber: vehicleNumber,
                              paymentMethod: selectedPaymentMethod,
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      disabledBackgroundColor: Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Pay Rs $_selfParkingFee & Book',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _bookSlot(
    Map<String, dynamic> slot,
    int index, {
    required String vehicleType,
    required String vehicleNumber,
    required String paymentMethod,
  }) async {
    final slotId = slot['id'];
    final dbSlotId = slot['dbId'];

    // Optimistically mark slot as booked
    setState(() {
      _bookedSlots.add(slotId);
      parkingSlots[index]['status'] = 'occupied';
    });

    try {
      final jwt = AuthTokenStore().token;
      final url = Uri.parse('$apiBase/api/bookings');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwt != null && jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode({
          'location_id': _resolvedLocationId ?? widget.parking.id,
          'slot_id': dbSlotId,
          'slot_number': slotId,
          'vehicle_number': vehicleNumber,
          'vehicle_type': vehicleType,
          'payment_method': paymentMethod,
          'payment_amount': _selfParkingFee,
          'booking_time': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        final booking = responseData['booking'];
        final bookingId = booking['booking_token'] ??
            'BK${DateTime.now().millisecondsSinceEpoch}';

        // Refetch slots to show booked slot as reserved/occupied
        await _loadParkingSlots();

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => BookingConfirmedScreen(
                slotId: slotId,
                parkingName: widget.parking.name,
                bookingId: bookingId,
                vehicleType: vehicleType,
                vehicleNumber: vehicleNumber,
                paymentMethod: paymentMethod,
                paymentAmount: _selfParkingFee,
                bookingTime: DateTime.now(),
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_extractApiError(response))),
          );
          // Revert optimistic update on failure
          setState(() {
            _bookedSlots.remove(slotId);
            parkingSlots[index]['status'] = 'available';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking error: $e')),
        );
        // Revert optimistic update on error
        setState(() {
          _bookedSlots.remove(slotId);
          parkingSlots[index]['status'] = 'available';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Valet Parking'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
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
                  const SizedBox(width: 16),
                  _buildLegendItem(Colors.red.shade600, 'Occupied'),
                  const SizedBox(width: 16),
                  _buildLegendItem(
                    _isParkingConfirmed
                        ? Colors.blue.shade600
                        : Colors.amber.shade700,
                    _isParkingConfirmed ? 'Your Car' : 'Booked Here',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Parking Layout
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_errorMessage!,
                                    style:
                                        TextStyle(color: Colors.red.shade700)),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLoading = true;
                                      _errorMessage = null;
                                    });
                                    _loadParkingSlots();
                                  },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : parkingSlots.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('No slots available for this location',
                                        style: TextStyle(
                                            color: Colors.grey.shade700)),
                                    const SizedBox(height: 12),
                                    ElevatedButton(
                                      onPressed: () {
                                        setState(() {
                                          _isLoading = true;
                                          _errorMessage = null;
                                        });
                                        _loadParkingSlots();
                                      },
                                      child: const Text('Refresh'),
                                    ),
                                  ],
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Build rows dynamically from parkingSlots
                                    ...List.generate(
                                        (parkingSlots.length / 2).ceil(),
                                        (rowIndex) {
                                      final leftSlotIndex = rowIndex * 2;
                                      final rightSlotIndex = rowIndex * 2 + 1;

                                      final Map<String, dynamic>? leftSlot =
                                          leftSlotIndex < parkingSlots.length
                                              ? parkingSlots[leftSlotIndex]
                                              : null;
                                      final Map<String, dynamic>? rightSlot =
                                          rightSlotIndex < parkingSlots.length
                                              ? parkingSlots[rightSlotIndex]
                                              : null;

                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12.0),
                                        child: Row(
                                          children: [
                                            // Left slot
                                            Expanded(
                                              child: leftSlot != null
                                                  ? GestureDetector(
                                                      onTap: () => _selectSlot(
                                                          leftSlotIndex),
                                                      child: _buildParkingSlot(
                                                          leftSlot),
                                                    )
                                                  : SizedBox(
                                                      height: 50,
                                                      child: Container()),
                                            ),
                                            const SizedBox(width: 12),
                                            // Center driveway
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
                                            // Right slot
                                            Expanded(
                                              child: rightSlot != null
                                                  ? GestureDetector(
                                                      onTap: () => _selectSlot(
                                                          rightSlotIndex),
                                                      child: _buildParkingSlot(
                                                          rightSlot),
                                                    )
                                                  : SizedBox(
                                                      height: 50,
                                                      child: Container()),
                                            ),
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
      height: 50,
      decoration: BoxDecoration(
        color: _getSlotColor(slot),
        borderRadius: BorderRadius.circular(8),
        border: slot['isUserCar'] == true
            ? Border.all(
                color: Colors.white,
                width: 3,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: _getSlotColor(slot).withValues(alpha: 0.3),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: null,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Text(
              slot['isUserCar'] == true
                  ? 'Your Car'
                  : slot['isUserBooked'] == true
                      ? 'Booked Here'
                      : slot['id'],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: (slot['isUserCar'] == true ||
                        slot['isUserBooked'] == true)
                    ? 10
                    : 12,
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
