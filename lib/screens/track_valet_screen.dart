import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';
import '../models/parking_models.dart';
import '../widgets/custom_drawer.dart';
import 'parking_layout_screen.dart';

class TrackValetScreen extends StatefulWidget {
  const TrackValetScreen({Key? key}) : super(key: key);

  @override
  State<TrackValetScreen> createState() => _TrackValetScreenState();
}

class _TrackValetScreenState extends State<TrackValetScreen> {
  List<Map<String, dynamic>> parkingLocations = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _awaitingParkingAssignment = false;
  String? _userBookingToken;
  int? _userParkingLocationId;
  String? _userSlotNumber;
  String? _userBookingStatus;
  String? _returnRequestedAt;
  String? _returnStatus;
  bool _isSubmittingReturnRequest = false;
  bool _isConfirmingReturnCompletion = false;
  bool _returnCompleted = false;
  Map<String, dynamic>? _currentBooking;
  Map<int, bool> _expandedLocations = {};

  bool get _isParkingConfirmed =>
      (_userBookingStatus ?? '').toLowerCase() == 'confirmed';

  @override
  void initState() {
    super.initState();
    _loadAllParkingData();
  }

  Future<void> _loadAllParkingData() async {
    try {
      final jwtToken = AuthTokenStore().token;

      // Fetch user's current active booking first.
      final bookingUrl = Uri.parse('$apiBase/api/bookings/current');
      http.Response? bookingResponse;
      try {
        bookingResponse = await http.get(
          bookingUrl,
          headers: {
            'Content-Type': 'application/json',
            if (jwtToken != null && jwtToken.isNotEmpty)
              'Authorization': 'Bearer $jwtToken',
          },
        );
      } catch (_) {
        bookingResponse = null;
      }

      if (bookingResponse == null || bookingResponse.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No active parking booking found';
          _currentBooking = null;
          parkingLocations = [];
        });
        return;
      }
      final bookingData = jsonDecode(bookingResponse.body);
      final bookingRaw = bookingData['booking'];
      final booking = bookingRaw is Map<String, dynamic>
          ? bookingRaw
          : (bookingRaw is Map
              ? Map<String, dynamic>.from(bookingRaw)
              : <String, dynamic>{});
      _currentBooking = booking;
      _userBookingToken = booking['booking_token']?.toString();
      _userParkingLocationId = booking['location_id'];
      _userSlotNumber = booking['slot_number'];
      _userBookingStatus = booking['status']?.toString();
      _returnRequestedAt = booking['return_requested_at']?.toString();
      _returnStatus = booking['return_status']?.toString();

      final isReturnReleased =
          (_returnStatus ?? '').toLowerCase() == 'released';
      if (_userParkingLocationId == null || _userSlotNumber == null) {
        if (isReturnReleased) {
          setState(() {
            _isLoading = false;
            _awaitingParkingAssignment = false;
            _errorMessage = null;
            parkingLocations = [];
            _returnCompleted = false;
          });
          return;
        }
        setState(() {
          _isLoading = false;
          _awaitingParkingAssignment = true;
          _errorMessage = null;
          parkingLocations = [];
        });
        return;
      }

      // Fetch all locations once, then keep only the user's booking location.
      final locUrl = Uri.parse('$apiBase/api/parking/locations');
      final locResponse = await http.get(
        locUrl,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (locResponse.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load your parking location';
          parkingLocations = [];
        });
        return;
      }

      final locData = jsonDecode(locResponse.body);
      final locations = (locData['locations'] as List<dynamic>? ?? []);
      final currentLocation =
          locations.cast<Map<String, dynamic>?>().firstWhere(
                (loc) => loc?['id'] == _userParkingLocationId,
                orElse: () => null,
              );
      if (currentLocation == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Booked parking location not found';
          parkingLocations = [];
        });
        return;
      }

      // Fetch slots only for the user's parking location.
      final slotsUrl =
          Uri.parse('$apiBase/api/parking/slots/$_userParkingLocationId');
      final slotsResponse = await http.get(
        slotsUrl,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (slotsResponse.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load your parking layout';
          parkingLocations = [];
        });
        return;
      }

      final slotsData = jsonDecode(slotsResponse.body);
      final slotList = (slotsData['slots'] as List<dynamic>? ?? []);
      final slots = slotList.map((slotRaw) {
        final slot = slotRaw as Map<String, dynamic>;
        final isUserSlot = slot['slot_number'] == _userSlotNumber;
        return {
          'id': slot['slot_number'],
          'status': slot['status'],
          'isUserSlot': isUserSlot,
          'isUserCar': isUserSlot && _isParkingConfirmed,
        };
      }).toList();

      final locId = _userParkingLocationId!;
      parkingLocations = [
        {
          'id': locId,
          'name': currentLocation['name'] ?? 'Unknown Location',
          'address': currentLocation['address'] ?? 'No address',
          'latitude': currentLocation['latitude'] ?? 0,
          'longitude': currentLocation['longitude'] ?? 0,
          'slots': slots,
          'isUserLocation': true,
        }
      ];
      _expandedLocations[locId] = true;

      setState(() {
        _isLoading = false;
        _awaitingParkingAssignment = false;
        _returnCompleted = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _awaitingParkingAssignment = false;
        _errorMessage = 'Error loading data: $e';
        parkingLocations = [];
      });
    }
  }

  Color _getSlotColor(Map<String, dynamic> slot) {
    if (slot['isUserCar'] == true) {
      return Colors.grey.shade600;
    }
    if (slot['isUserSlot'] == true) {
      return Colors.amber.shade700;
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
    if (slot['isUserCar'] == true) {
      return 'Your car';
    }
    if (slot['isUserSlot'] == true) {
      return 'Booked here';
    }
    return slot['id'];
  }

  String _getUserParkingLocationName() {
    if (_userParkingLocationId == null) return 'Unknown Location';
    final location = parkingLocations.firstWhere(
      (loc) => loc['id'] == _userParkingLocationId,
      orElse: () => {},
    );
    return location.isNotEmpty
        ? location['name'] ?? 'Unknown Location'
        : 'Unknown Location';
  }

  bool get _hasReturnRequested =>
      (_returnRequestedAt ?? '').toString().trim().isNotEmpty;

  String _valueOrNA(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isNotEmpty ? text : 'N/A';
  }

  String _formatDateTime(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yy $hh:$min';
  }

  String _bookingStatusLabel() {
    final status = (_userBookingStatus ?? '').toLowerCase();
    if (status == 'pending') return 'Booked - awaiting parking confirmation';
    if (status == 'confirmed') return 'Parked and active';
    if (status == 'completed') return 'Completed';
    return _valueOrNA(_userBookingStatus);
  }

  String _returnStatusLabel() {
    final status = (_returnStatus ?? '').toLowerCase();
    if (status == 'requested') return 'Return requested - waiting for driver';
    if (status == 'accepted') return 'Driver accepted - waiting security release';
    if (status == 'released') return 'Released by security - vehicle on the way';
    if (status == 'completed') return 'Return completed';
    if (status.isEmpty && _hasReturnRequested) return 'Return requested';
    return 'Not requested';
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingDetailsCard() {
    final booking = _currentBooking;
    if (booking == null || booking.isEmpty) return const SizedBox.shrink();

    final locationName = _valueOrNA(
      booking['location_name'] ?? booking['location'] ?? _getUserParkingLocationName(),
    );
    final locationAddress = _valueOrNA(booking['location_address']);
    final driverName = _valueOrNA(booking['driver_name']);
    final driverPhone = _valueOrNA(booking['driver_phone']);
    final rawSecurityName = (booking['security_name'] ?? '').toString().trim();
    final rawSecurityPhone = (booking['security_phone'] ?? '').toString().trim();
    final securityLines = <String>[];
    final securityStaffRaw = booking['security_staff'];
    if (securityStaffRaw is List) {
      for (final entry in securityStaffRaw) {
        if (entry is Map) {
          final name = (entry['name'] ?? '').toString().trim();
          final phone = (entry['phone'] ?? '').toString().trim();
          if (name.isEmpty && phone.isEmpty) continue;
          if (name.isNotEmpty && phone.isNotEmpty) {
            securityLines.add('$name - $phone');
          } else if (name.isNotEmpty) {
            securityLines.add(name);
          } else {
            securityLines.add(phone);
          }
        }
      }
    }
    final pickupLat = booking['customer_latitude']?.toString() ?? '';
    final pickupLng = booking['customer_longitude']?.toString() ?? '';
    final pickupCoords =
        (pickupLat.trim().isNotEmpty && pickupLng.trim().isNotEmpty)
            ? '$pickupLat, $pickupLng'
            : 'N/A';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, size: 18, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Booking Details',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildDetailRow('Booking Token', _valueOrNA(booking['booking_token'])),
          _buildDetailRow('Vehicle Number', _valueOrNA(booking['vehicle_number'])),
          _buildDetailRow('Vehicle Type', _valueOrNA(booking['vehicle_type'])),
          _buildDetailRow('Booking Time', _formatDateTime(booking['booking_time'])),
          _buildDetailRow('Booking Status', _bookingStatusLabel()),
          _buildDetailRow('Pickup Lat/Lng', pickupCoords),
          _buildDetailRow('Driver', driverName),
          _buildDetailRow('Driver Contact', driverPhone),
          if (securityLines.isNotEmpty)
            _buildDetailRow(
              'Security Staff',
              securityLines.join('\n'),
            )
          else if (rawSecurityName.isNotEmpty || rawSecurityPhone.isNotEmpty)
            _buildDetailRow(
              'Security',
              rawSecurityName.isNotEmpty ? rawSecurityName : 'N/A',
            ),
          if (securityLines.isEmpty &&
              (rawSecurityName.isNotEmpty || rawSecurityPhone.isNotEmpty))
            _buildDetailRow(
              'Security Contact',
              rawSecurityPhone.isNotEmpty ? rawSecurityPhone : 'N/A',
            ),
          _buildDetailRow('Parking Location', locationName),
          _buildDetailRow('Location Address', locationAddress),
          if (_userSlotNumber != null) _buildDetailRow('Slot', _valueOrNA(_userSlotNumber)),
        ],
      ),
    );
  }

  Widget _buildReturnHandoverCard() {
    if (!_hasReturnRequested && (_returnStatus ?? '').toLowerCase() != 'released') {
      return const SizedBox.shrink();
    }

    final booking = _currentBooking ?? {};
    final lat = booking['desired_return_latitude']?.toString() ?? '';
    final lng = booking['desired_return_longitude']?.toString() ?? '';
    final coordinateText =
        (lat.trim().isNotEmpty && lng.trim().isNotEmpty) ? '$lat, $lng' : 'N/A';

    final returnDriverName = _valueOrNA(
      booking['return_driver_name'] ??
          (booking['return_driver_id'] != null
              ? 'Driver ID ${booking['return_driver_id']}'
              : null),
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping, size: 18, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(
                'Return Handover Details',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildDetailRow('Return Status', _returnStatusLabel()),
          _buildDetailRow(
            'Requested At',
            _formatDateTime(
              booking['return_requested_at'] ?? _returnRequestedAt,
            ),
          ),
          _buildDetailRow(
            'Destination',
            _valueOrNA(booking['desired_return_location']),
          ),
          _buildDetailRow('Destination Lat/Lng', coordinateText),
          _buildDetailRow('Return Driver', returnDriverName),
          _buildDetailRow(
            'Driver Contact',
            _valueOrNA(booking['return_driver_phone']),
          ),
          _buildDetailRow('Vehicle Number', _valueOrNA(booking['vehicle_number'])),
          _buildDetailRow('Vehicle Type', _valueOrNA(booking['vehicle_type'])),
          _buildDetailRow('Slot', _valueOrNA(_userSlotNumber ?? booking['slot_number'])),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchReturnEstimate() async {
    if (_userBookingToken == null || _userBookingToken!.isEmpty) {
      return null;
    }
    final jwtToken = AuthTokenStore().token;
    final response = await http.get(
      Uri.parse(
          '$apiBase/api/bookings/${Uri.encodeComponent(_userBookingToken!)}/return-estimate'),
      headers: {
        'Content-Type': 'application/json',
        if (jwtToken != null && jwtToken.isNotEmpty)
          'Authorization': 'Bearer $jwtToken',
      },
    );
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    return data['estimate'] as Map<String, dynamic>?;
  }

  Future<void> _showReturnRequestSheet() async {
    if (!_isParkingConfirmed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parking is not confirmed yet.'),
        ),
      );
      return;
    }
    if (_hasReturnRequested) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Return request already submitted.'),
        ),
      );
      return;
    }

    final estimate = await _fetchReturnEstimate();
    if (estimate == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to fetch return charge. Try again.'),
        ),
      );
      return;
    }

    final locationController = TextEditingController();
    final latController = TextEditingController();
    final lngController = TextEditingController();
    String paymentMethod = 'gpay';
    final booking = _currentBooking ?? {};
    final isSelfParking = (booking['driver_id'] == null ||
            booking['driver_id'] == 0 ||
            booking['driver_id'] == '0') &&
        booking['location_id'] != null &&
        booking['slot_number'] != null;
    final amount = (estimate['amount_rs'] is num)
        ? (estimate['amount_rs'] as num).toInt()
        : int.tryParse('${estimate['amount_rs']}') ?? 0;
    final parkedMinutes = (estimate['parked_minutes'] is num)
        ? (estimate['parked_minutes'] as num).toInt()
        : int.tryParse('${estimate['parked_minutes']}') ?? 0;
    final totalPaid = (estimate['total_paid_rs'] is num)
        ? (estimate['total_paid_rs'] as num).toInt()
        : int.tryParse('${estimate['total_paid_rs']}');
    final extraPerHour = (estimate['extra_fee_per_hour_rs'] is num)
        ? (estimate['extra_fee_per_hour_rs'] as num).toInt()
        : int.tryParse('${estimate['extra_fee_per_hour_rs']}');
    final extraHours = (estimate['extra_hours'] is num)
        ? (estimate['extra_hours'] as num).toInt()
        : int.tryParse('${estimate['extra_hours']}');
    final extraPer10Min = (estimate['extra_fee_per_10_min_rs'] is num)
        ? (estimate['extra_fee_per_10_min_rs'] as num).toInt()
        : int.tryParse('${estimate['extra_fee_per_10_min_rs']}');

    Future<void> fillCurrentLocation(StateSetter modalSetState) async {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      modalSetState(() {
        latController.text = pos.latitude.toStringAsFixed(6);
        lngController.text = pos.longitude.toStringAsFixed(6);
        if (locationController.text.trim().isEmpty) {
          locationController.text =
              'Lat ${latController.text}, Lng ${lngController.text}';
        }
      });
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, modalSetState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Return Request',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!isSelfParking) ...[
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(
                        labelText: 'Desired Return Location',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () => fillCurrentLocation(modalSetState),
                      icon: const Icon(Icons.my_location),
                      label: const Text('Use Current Location'),
                    ),
                    Text(
                      'Location coordinates will be captured automatically.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        'Return will be processed at the same parking location.',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
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
                        Text('Parked duration: $parkedMinutes minutes'),
                        const SizedBox(height: 4),
                        Text(
                          '${isSelfParking ? 'Additional payment' : 'Return charge'}: Rs $amount',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (!isSelfParking && extraPerHour != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Extra after 30 mins: Rs $extraPerHour per hour'
                              '${extraHours != null ? ' (extra hours: $extraHours)' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (isSelfParking && extraPerHour != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Extra after 30 mins: Rs $extraPerHour per hour'
                              '${extraHours != null ? ' (extra hours: $extraHours)' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (isSelfParking && totalPaid != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Total paid so far: Rs $totalPaid',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (isSelfParking && amount == 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'No extra payment required within 30 minutes.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (amount > 0) ...[
                    const Text(
                      'Choose payment method',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    ...['debitcard', 'credit card', 'gpay'].map((method) {
                      return RadioListTile<String>(
                        value: method,
                        groupValue: paymentMethod,
                        onChanged: (value) {
                          if (value == null) return;
                          modalSetState(() => paymentMethod = value);
                        },
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(method),
                      );
                    }).toList(),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_isSubmittingReturnRequest) return;
                        final desiredText = isSelfParking
                            ? _getUserParkingLocationName()
                            : locationController.text.trim();
                        if (!isSelfParking && desiredText.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Please enter desired return location'),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(context);
                        await _submitReturnRequest(
                          desiredLocation: desiredText,
                          desiredLatitude:
                              isSelfParking ? null : double.tryParse(latController.text.trim()),
                          desiredLongitude:
                              isSelfParking ? null : double.tryParse(lngController.text.trim()),
                          paymentMethod: amount > 0 ? paymentMethod : null,
                          paymentAmount: amount > 0 ? amount : null,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        amount > 0
                            ? 'Pay Rs $amount & Request Return'
                            : 'Request Return',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitReturnRequest({
    required String desiredLocation,
    required double? desiredLatitude,
    required double? desiredLongitude,
    String? paymentMethod,
    int? paymentAmount,
  }) async {
    if (_userBookingToken == null || _userBookingToken!.isEmpty) return;
    setState(() {
      _isSubmittingReturnRequest = true;
    });
    try {
      final jwt = AuthTokenStore().token;
      final payload = <String, dynamic>{
        'desired_return_location': desiredLocation,
        'desired_return_latitude': desiredLatitude,
        'desired_return_longitude': desiredLongitude,
      };
      if (paymentMethod != null) {
        payload['payment_method'] = paymentMethod;
      }
      if (paymentAmount != null) {
        payload['payment_amount'] = paymentAmount;
      }
      final response = await http.post(
        Uri.parse(
            '$apiBase/api/bookings/${Uri.encodeComponent(_userBookingToken!)}/request-return'),
        headers: {
          'Content-Type': 'application/json',
          if (jwt != null && jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode(payload),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final booking = data['booking'] as Map<String, dynamic>?;
        setState(() {
          _returnRequestedAt = booking?['return_requested_at']?.toString() ??
              DateTime.now().toIso8601String();
          _returnStatus = booking?['return_status']?.toString() ?? _returnStatus;
          if (booking != null) {
            _currentBooking = {...?_currentBooking, ...booking};
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Return requested and paid. Drivers and security have been notified.'),
          ),
        );
        await _loadAllParkingData();
      } else {
        final data = jsonDecode(response.body);
        final msg = data['message']?.toString() ??
            data['error']?.toString() ??
            'Failed to request return';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
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
          _isSubmittingReturnRequest = false;
        });
      }
    }
  }

  Future<void> _confirmReturnCompleted() async {
    if (_userBookingToken == null || _userBookingToken!.isEmpty) return;
    setState(() {
      _isConfirmingReturnCompletion = true;
    });

    try {
      final jwt = AuthTokenStore().token;
      final response = await http.post(
        Uri.parse(
            '$apiBase/api/bookings/${Uri.encodeComponent(_userBookingToken!)}/confirm-return-completed'),
        headers: {
          'Content-Type': 'application/json',
          if (jwt != null && jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
        },
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _returnStatus = 'completed';
          _returnCompleted = true;
          if (_currentBooking != null) {
            _currentBooking = {
              ..._currentBooking!,
              'return_status': 'completed',
              'return_completed_at': DateTime.now().toIso8601String(),
            };
          }
          parkingLocations = [];
          _awaitingParkingAssignment = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Return completed confirmed. Security has been notified.'),
          ),
        );
        return;
      }

      final data = jsonDecode(response.body);
      final msg = data['message']?.toString() ??
          data['error']?.toString() ??
          'Failed to confirm return completion';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to confirm return completion: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isConfirmingReturnCompletion = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Track Vehicle'),
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
          title: const Text('Track Vehicle'),
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

    if (_returnCompleted) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Track Vehicle'),
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        drawer: const CustomDrawer(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle,
                  size: 56,
                  color: Colors.green.shade600,
                ),
                const SizedBox(height: 16),
                Text(
                  'Return Completed',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Thank you. Security has been notified that return is complete.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_awaitingParkingAssignment) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Track Vehicle'),
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAllParkingData,
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Icon(
                    Icons.directions_car_filled_outlined,
                    size: 56,
                    color: Colors.blue.shade600,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your valet request is active',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Driver pickup is in progress. Parking location and slot will appear after assignment.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  _buildBookingDetailsCard(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if ((_returnStatus ?? '').toLowerCase() == 'released') {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Track Vehicle'),
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAllParkingData,
            ),
          ],
        ),
        drawer: const CustomDrawer(),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.local_shipping,
                    size: 56,
                    color: Colors.blue.shade600,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Vehicle Is On The Way',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Security confirmed handover to driver. Please confirm once you receive your vehicle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildBookingDetailsCard(),
                  const SizedBox(height: 12),
                  _buildReturnHandoverCard(),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isConfirmingReturnCompletion
                          ? null
                          : _confirmReturnCompleted,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        _isConfirmingReturnCompletion
                            ? 'Confirming...'
                            : 'Confirm Return Completed',
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Vehicle'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildBookingDetailsCard(),
              const SizedBox(height: 12),
              _buildReturnHandoverCard(),
              const SizedBox(height: 12),
              // User's Vehicle Info (if parked)
              if (_userSlotNumber != null && _userParkingLocationId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.directions_car,
                          color: Colors.white,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isParkingConfirmed
                                    ? 'Your Vehicle is Parked at:'
                                    : 'Your Slot is Booked at:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _getUserParkingLocationName(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Slot: $_userSlotNumber',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLegendItem(Colors.green.shade600, 'Available'),
                    const SizedBox(width: 20),
                    _buildLegendItem(Colors.red.shade600, 'Occupied'),
                    const SizedBox(width: 20),
                    _buildLegendItem(
                      _isParkingConfirmed
                          ? Colors.grey.shade600
                          : Colors.amber.shade700,
                      _isParkingConfirmed ? 'Your car' : 'Booked here',
                    ),
                  ],
                ),
              ),
              if (_isParkingConfirmed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _hasReturnRequested
                        ? 'Return request already submitted.'
                        : 'Tap your car slot to request return.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              // Parking Locations List
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: parkingLocations.length,
                itemBuilder: (context, index) {
                  final location = parkingLocations[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ExpansionTile(
                        title: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: location['isUserLocation']
                                  ? Colors.blue.shade600
                                  : Colors.grey.shade600,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    location['name'],
                                    style: TextStyle(
                                      fontSize: 16,
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
                                  ),
                                ],
                              ),
                            ),
                            if (location['isUserLocation'])
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _isParkingConfirmed
                                      ? 'Your Car'
                                      : 'Booked Here',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        initiallyExpanded: true,
                        onExpansionChanged: (expanded) {
                          setState(() {
                            _expandedLocations[location['id']] = expanded;
                          });
                        },
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () {
                                    final lat = (location['latitude'] is num)
                                        ? location['latitude'].toDouble()
                                        : 0.0;
                                    final lng = (location['longitude'] is num)
                                        ? location['longitude'].toDouble()
                                        : 0.0;
                                    final parking = ParkingLocation(
                                      id: location['id'],
                                      name: location['name'] ?? 'Unknown',
                                      distance: '',
                                      location: LatLng(lat, lng),
                                      availableSpots: (location['slots']
                                              as List)
                                          .where(
                                              (s) => s['status'] == 'available')
                                          .length,
                                    );

                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            ParkingLayoutScreen(
                                          parking: parking,
                                          userSlotNumber: _userSlotNumber,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.grid_on),
                                  label: const Text('View Layout'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: _buildParkingSlotsGrid(
                                location['slots'], location['name']),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParkingSlotsGrid(
      List<Map<String, dynamic>> slots, String locationName) {
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

    // Check if user's car is in this location
    final userSlotInThisLocation = slots.any((s) => s['isUserSlot'] == true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (userSlotInThisLocation)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade300, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.directions_car,
                    color: Colors.blue.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isParkingConfirmed
                              ? 'Your Vehicle Location'
                              : 'Your Booking Location',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$locationName - Slot $_userSlotNumber',
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
                  height: 60,
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
    final canRequestReturn = slot['isUserCar'] == true;
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: _getSlotColor(slot),
        borderRadius: BorderRadius.circular(8),
        boxShadow: slot['isUserSlot'] == true
            ? [
                BoxShadow(
                  color: Colors.grey.shade600.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Center(
        child: InkWell(
          onTap: canRequestReturn ? _showReturnRequestSheet : null,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.expand(
            child: Center(
              child: Text(
                _getSlotLabel(slot),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: slot['isUserSlot'] == true ? 10 : 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
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
