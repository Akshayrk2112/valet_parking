import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/utils/auth_token_store.dart';

class AdminActiveBookingsScreen extends StatefulWidget {
  final int activeBookings;

  const AdminActiveBookingsScreen({
    Key? key,
    required this.activeBookings,
  }) : super(key: key);

  @override
  State<AdminActiveBookingsScreen> createState() =>
      _AdminActiveBookingsScreenState();
}

class _AdminActiveBookingsScreenState extends State<AdminActiveBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  Map<int, String> _locationNames = {};
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _fetchLocations();
      await _fetchBookings();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) return message;
        final error = decoded['error']?.toString();
        if (error != null && error.isNotEmpty) return error;
      }
    } catch (_) {}
    return 'HTTP ${response.statusCode}';
  }

  Future<void> _fetchLocations() async {
    final jwtToken = AuthTokenStore().token;
    final response = await http.get(
      Uri.parse('$apiBase/api/parking/locations'),
      headers: {
        'Content-Type': 'application/json',
        if (jwtToken != null && jwtToken.isNotEmpty)
          'Authorization': 'Bearer $jwtToken',
      },
    );
    if (response.statusCode != 200) return;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final locations = (data['locations'] as List<dynamic>? ?? []);
    final mapped = <int, String>{};
    for (final entry in locations) {
      final loc = Map<String, dynamic>.from(entry as Map);
      final id = loc['id'];
      if (id is int) {
        mapped[id] = (loc['name'] ?? 'Unknown').toString();
      } else {
        final parsed = int.tryParse(id?.toString() ?? '');
        if (parsed != null) {
          mapped[parsed] = (loc['name'] ?? 'Unknown').toString();
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _locationNames = mapped;
    });
  }

  Future<void> _fetchBookings() async {
    final jwtToken = AuthTokenStore().token;
    final response = await http.get(
      Uri.parse('$apiBase/api/bookings'),
      headers: {
        'Content-Type': 'application/json',
        if (jwtToken != null && jwtToken.isNotEmpty)
          'Authorization': 'Bearer $jwtToken',
      },
    );

    if (response.statusCode != 200) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Failed to load bookings: ${_extractErrorMessage(response)}';
        _bookings = [];
      });
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final bookings = (data['bookings'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    bookings.sort((a, b) {
      final aId = int.tryParse('${a['id'] ?? ''}') ?? 0;
      final bId = int.tryParse('${b['id'] ?? ''}') ?? 0;
      return bId.compareTo(aId);
    });

    if (!mounted) return;
    setState(() {
      _bookings = bookings;
    });
  }

  String _formatTime(dynamic raw) {
    final text = (raw ?? '').toString();
    if (text.isEmpty) return 'N/A';
    final dt = DateTime.tryParse(text);
    if (dt == null) return text;
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yy = local.year;
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yy $hh:$min';
  }

  String _bookingType(Map<String, dynamic> booking) {
    return _isValetBooking(booking) ? 'Valet' : 'Self Parking';
  }

  bool _hasAssignedSlot(Map<String, dynamic> booking) {
    final slot = (booking['slot_number'] ?? '').toString().trim();
    return slot.isNotEmpty;
  }

  bool _hasAssignedLocation(Map<String, dynamic> booking) {
    final locationIdRaw = booking['location_id'];
    final locationId = locationIdRaw is int
        ? locationIdRaw
        : int.tryParse(locationIdRaw?.toString() ?? '');
    return locationId != null;
  }

  bool _hasReturnFlowData(Map<String, dynamic> booking) {
    final returnRequestedAt =
        (booking['return_requested_at'] ?? '').toString().trim();
    final returnStatus = (booking['return_status'] ?? '').toString().trim();
    final returnDriverId = booking['return_driver_id'];
    final desiredReturnLocation =
        (booking['desired_return_location'] ?? '').toString().trim();

    return returnRequestedAt.isNotEmpty ||
        returnStatus.isNotEmpty ||
        returnDriverId != null ||
        desiredReturnLocation.isNotEmpty;
  }

  bool _isValetBooking(Map<String, dynamic> booking) {
    final driverId = booking['driver_id'];
    if (driverId != null) return true;

    // Fresh valet bookings are created without assigned location/slot
    // until a driver accepts and parks the vehicle.
    final hasSlot = _hasAssignedSlot(booking);
    final hasLocation = _hasAssignedLocation(booking);
    if (!hasSlot && !hasLocation) return true;

    // Return-flow fields exist only for valet lifecycle.
    if (_hasReturnFlowData(booking)) return true;

    // Self parking always has an assigned slot; use that as final signal.
    return false;
  }

  bool _isReturnCompleted(Map<String, dynamic> booking) {
    return (booking['return_status'] ?? '').toString().trim().toLowerCase() ==
        'completed';
  }

  bool _isBookingCompleted(Map<String, dynamic> booking) {
    return (booking['status'] ?? '').toString().trim().toLowerCase() ==
        'completed';
  }

  bool _isBookingCancelled(Map<String, dynamic> booking) {
    return (booking['status'] ?? '').toString().trim().toLowerCase() ==
        'cancelled';
  }

  List<Map<String, dynamic>> get _activeValetBookings => _bookings
      .where(
          (booking) =>
              _isValetBooking(booking) &&
              !_isReturnCompleted(booking) &&
              !_isBookingCancelled(booking))
      .toList();

  List<Map<String, dynamic>> get _activeSelfParkingBookings => _bookings
      .where((booking) =>
          !_isValetBooking(booking) &&
          !_isBookingCompleted(booking) &&
          !_isBookingCancelled(booking))
      .toList();

  String _statusLabel(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? 'unknown').toString().toLowerCase();
    final returnStatus =
        (booking['return_status'] ?? '').toString().toLowerCase().trim();

    final base = status[0].toUpperCase() + status.substring(1);
    if (returnStatus.isEmpty || returnStatus == 'completed') {
      return base;
    }

    final returnPart =
        returnStatus[0].toUpperCase() + returnStatus.substring(1);
    return '$base / Return $returnPart';
  }

  Color _statusColor(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? '').toString().toLowerCase();
    final returnStatus =
        (booking['return_status'] ?? '').toString().toLowerCase();

    if (status == 'completed') return Colors.blue.shade600;
    if (status == 'cancelled') return Colors.red.shade600;
    if (returnStatus == 'requested' || returnStatus == 'accepted') {
      return Colors.deepPurple.shade600;
    }
    if (status == 'confirmed') return Colors.green.shade600;
    if (status == 'pending') return Colors.amber.shade700;
    return Colors.grey.shade600;
  }

  String _customerName(Map<String, dynamic> booking) {
    final fromApi = (booking['customer_name'] ?? '').toString().trim();
    if (fromApi.isNotEmpty) return fromApi;
    return 'Customer ${booking['user_id'] ?? 'N/A'}';
  }

  String _driverName(Map<String, dynamic> booking) {
    final driverId = booking['driver_id'];
    if (driverId == null) {
      return _isValetBooking(booking)
          ? 'Not assigned yet (Valet)'
          : 'Not assigned (Self Parking)';
    }
    final fromApi = (booking['driver_name'] ?? '').toString().trim();
    if (fromApi.isNotEmpty) return '$fromApi (ID $driverId)';
    return 'Driver $driverId';
  }

  List<Map<String, dynamic>> _declines(Map<String, dynamic> booking) {
    final raw = booking['declines'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _declineDriverLabel(Map<String, dynamic> decline) {
    final driverName = (decline['driver_name'] ?? '').toString().trim();
    final driverId = decline['driver_id'];
    if (driverName.isNotEmpty) return '$driverName (ID $driverId)';
    return 'Driver ${driverId ?? 'N/A'}';
  }

  String _locationName(Map<String, dynamic> booking) {
    final locIdRaw = booking['location_id'];
    final locId =
        locIdRaw is int ? locIdRaw : int.tryParse(locIdRaw?.toString() ?? '');
    if (locId == null) return 'Not assigned';
    return _locationNames[locId] ?? 'Location $locId';
  }

  @override
  Widget build(BuildContext context) {
    final activeValet = _activeValetBookings;
    final activeSelfParking = _activeSelfParkingBookings;
    final activeTotal = activeValet.length + activeSelfParking.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Bookings'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red.shade600,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Active Bookings: $activeTotal',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Valet: ${activeValet.length}  |  Self Parking: ${activeSelfParking.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: activeTotal == 0
                              ? Center(
                                  child: Text(
                                    'No active bookings found',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              : ListView(
                                  children: [
                                    Text(
                                      'Valet Bookings',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (activeValet.isEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Text(
                                          'No active valet bookings',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      )
                                    else
                                      ...activeValet
                                          .map((booking) =>
                                              _buildBookingCard(booking))
                                          .toList(),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Park Yourself Bookings',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (activeSelfParking.isEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Text(
                                          'No active self parking bookings',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      )
                                    else
                                      ...activeSelfParking
                                          .map((booking) =>
                                              _buildBookingCard(booking))
                                          .toList(),
                                  ],
                                ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final type = _bookingType(booking);
    final statusText = _statusLabel(booking);
    final statusColor = _statusColor(booking);
    final bookingTime = _formatTime(booking['booking_time']);
    final parkedTime = _formatTime(booking['parked_confirmed_at']);
    final location = _locationName(booking);
    final slot = (booking['slot_number'] ?? '').toString().trim();
    final slotText = slot.isNotEmpty ? slot : 'Not assigned';
    final declines = _declines(booking);

    return GestureDetector(
      onTap: () => _showBookingDetails(booking),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking ID: ${booking['id']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _customerName(booking),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: type == 'Valet'
                        ? Colors.blue.shade50
                        : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: type == 'Valet'
                          ? Colors.blue.shade200
                          : Colors.teal.shade200,
                    ),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: type == 'Valet'
                          ? Colors.blue.shade700
                          : Colors.teal.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Vehicle: ${(booking['vehicle_type'] ?? 'N/A')} (${booking['vehicle_number'] ?? 'N/A'})',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Booking Time: $bookingTime',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            Text(
              'Parked Time: $parkedTime',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            Text(
              'Location: $location  |  Slot: $slotText',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            Text(
              'Driver: ${_driverName(booking)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            if (declines.isNotEmpty)
              Text(
                'Declines: ${declines.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBookingDetails(Map<String, dynamic> booking) {
    final statusText = _statusLabel(booking);
    final statusColor = _statusColor(booking);
    final type = _bookingType(booking);

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Booking Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: type == 'Valet'
                            ? Colors.blue.shade50
                            : Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: type == 'Valet'
                              ? Colors.blue.shade200
                              : Colors.teal.shade200,
                        ),
                      ),
                      child: Text(
                        type,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: type == 'Valet'
                              ? Colors.blue.shade700
                              : Colors.teal.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Booking ID', '${booking['id']}'),
                _buildDetailRow('Booking Token',
                    (booking['booking_token'] ?? 'N/A').toString()),
                _buildDetailRow('Customer', _customerName(booking)),
                _buildDetailRow('Vehicle Type',
                    (booking['vehicle_type'] ?? 'N/A').toString()),
                _buildDetailRow('Vehicle Number',
                    (booking['vehicle_number'] ?? 'N/A').toString()),
                _buildDetailRow('Driver', _driverName(booking)),
                _buildDetailRow('Location', _locationName(booking)),
                _buildDetailRow(
                  'Slot',
                  (booking['slot_number'] ?? '').toString().trim().isEmpty
                      ? 'Not assigned'
                      : booking['slot_number'].toString(),
                ),
                _buildDetailRow(
                    'Status', (booking['status'] ?? 'unknown').toString()),
                _buildDetailRow('Return Status',
                    (booking['return_status'] ?? 'N/A').toString()),
                _buildDetailRow('Payment Status',
                    (booking['payment_status'] ?? 'N/A').toString()),
                _buildDetailRow('Payment Method',
                    (booking['payment_method'] ?? 'N/A').toString()),
                _buildDetailRow(
                  'Payment Amount',
                  (booking['payment_amount'] ?? 'N/A').toString(),
                ),
                _buildDetailRow(
                  'Booking Time',
                  _formatTime(booking['booking_time']),
                ),
                _buildDetailRow(
                  'Parked Confirmed At',
                  _formatTime(booking['parked_confirmed_at']),
                ),
                _buildDetailRow(
                  'Return Requested At',
                  _formatTime(booking['return_requested_at']),
                ),
                _buildDetailRow(
                  'Return Accepted At',
                  _formatTime(booking['return_accepted_at']),
                ),
                _buildDetailRow(
                  'Completed At',
                  _formatTime(booking['completed_at']),
                ),
                _buildDeclineHistory(booking),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeclineHistory(Map<String, dynamic> booking) {
    final declines = _declines(booking);
    if (declines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Decline History',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 8),
          ...declines.map((decline) {
            final reason =
                (decline['decline_reason'] ?? 'No reason').toString();
            final note = (decline['decline_note'] ?? '').toString().trim();
            final requestType =
                (decline['request_type'] ?? 'pickup').toString();
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _declineDriverLabel(decline),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${requestType.toUpperCase()} | $reason',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(decline['declined_at']),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
