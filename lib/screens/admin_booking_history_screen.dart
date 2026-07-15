import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/utils/auth_token_store.dart';

class AdminBookingHistoryScreen extends StatefulWidget {
  const AdminBookingHistoryScreen({Key? key}) : super(key: key);

  @override
  State<AdminBookingHistoryScreen> createState() =>
      _AdminBookingHistoryScreenState();
}

class _AdminBookingHistoryScreenState extends State<AdminBookingHistoryScreen> {
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
      final id = int.tryParse(loc['id']?.toString() ?? '');
      if (id != null) mapped[id] = (loc['name'] ?? 'Unknown').toString();
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
            'Failed to load booking history: ${_extractErrorMessage(response)}';
        _bookings = [];
      });
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final bookings = (data['bookings'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    bookings.sort((a, b) {
      final aTime = DateTime.tryParse((a['booking_time'] ?? '').toString());
      final bTime = DateTime.tryParse((b['booking_time'] ?? '').toString());
      if (aTime != null && bTime != null) return bTime.compareTo(aTime);
      final aId = int.tryParse('${a['id'] ?? ''}') ?? 0;
      final bId = int.tryParse('${b['id'] ?? ''}') ?? 0;
      return bId.compareTo(aId);
    });

    if (!mounted) return;
    setState(() {
      _bookings = bookings;
    });
  }

  String _valueOrNA(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'N/A' : text;
  }

  String _formatTime(dynamic raw) {
    final text = (raw ?? '').toString().trim();
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

  String _capitalize(String value) {
    if (value.isEmpty) return 'N/A';
    final readable = value.replaceAll('_', ' ');
    return readable[0].toUpperCase() + readable.substring(1);
  }

  bool _hasReturnFlowData(Map<String, dynamic> booking) {
    return _valueOrNA(booking['return_requested_at']) != 'N/A' ||
        _valueOrNA(booking['return_status']) != 'N/A' ||
        booking['return_driver_id'] != null ||
        _valueOrNA(booking['desired_return_location']) != 'N/A';
  }

  bool _isValetBooking(Map<String, dynamic> booking) {
    if (booking['driver_id'] != null) return true;
    final hasSlot = _valueOrNA(booking['slot_number']) != 'N/A';
    final hasLocation = booking['location_id'] != null;
    if (!hasSlot && !hasLocation) return true;
    return _hasReturnFlowData(booking);
  }

  String _bookingType(Map<String, dynamic> booking) {
    return _isValetBooking(booking) ? 'Valet' : 'Self Parking';
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
          ? 'Not assigned yet'
          : 'Not assigned (Self Parking)';
    }
    final fromApi = (booking['driver_name'] ?? '').toString().trim();
    if (fromApi.isNotEmpty) return '$fromApi (ID $driverId)';
    return 'Driver $driverId';
  }

  String _returnDriverName(Map<String, dynamic> booking) {
    final driverId = booking['return_driver_id'];
    if (driverId == null) return 'Not assigned';
    final fromApi = (booking['return_driver_name'] ?? '').toString().trim();
    if (fromApi.isNotEmpty) return '$fromApi (ID $driverId)';
    return 'Driver $driverId';
  }

  String _locationName(Map<String, dynamic> booking) {
    final locId = int.tryParse(booking['location_id']?.toString() ?? '');
    if (locId == null) return 'Not assigned';
    return _locationNames[locId] ?? 'Location $locId';
  }

  String _statusLabel(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? '').toString().toLowerCase().trim();
    final returnStatus =
        (booking['return_status'] ?? '').toString().toLowerCase().trim();
    final base = _capitalize(status);
    if (returnStatus.isEmpty || returnStatus == 'completed') return base;
    return '$base / Return ${_capitalize(returnStatus)}';
  }

  Color _statusColor(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? '').toString().toLowerCase();
    final returnStatus =
        (booking['return_status'] ?? '').toString().toLowerCase();
    if (status == 'completed' || returnStatus == 'completed') {
      return Colors.blue.shade600;
    }
    if (status == 'cancelled') return Colors.red.shade600;
    if (returnStatus == 'requested' ||
        returnStatus == 'accepted' ||
        returnStatus == 'released') {
      return Colors.deepPurple.shade600;
    }
    if (status == 'confirmed') return Colors.green.shade600;
    if (status == 'pending') return Colors.amber.shade700;
    return Colors.grey.shade600;
  }

  List<Map<String, dynamic>> _declines(Map<String, dynamic> booking) {
    final raw = booking['declines'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Widget _buildSummaryCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final type = _bookingType(booking);
    final statusText = _statusLabel(booking);
    final statusColor = _statusColor(booking);
    final typeColor = type == 'Valet' ? Colors.blue : Colors.teal;
    final slotText = _valueOrNA(booking['slot_number']) == 'N/A'
        ? 'Not assigned'
        : _valueOrNA(booking['slot_number']);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showBookingDetails(booking),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
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
                          'Booking ${booking['id'] ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _customerName(booking),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: typeColor.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: typeColor.shade200),
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: typeColor.shade700,
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
                      '${_valueOrNA(booking['vehicle_type'])} (${_valueOrNA(booking['vehicle_number'])})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Booked: ${_formatTime(booking['booking_time'])}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              Text(
                'Location: ${_locationName(booking)}  |  Slot: $slotText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              Text(
                'Driver: ${_driverName(booking)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
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
            width: 132,
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
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingDetails(Map<String, dynamic> booking) {
    final type = _bookingType(booking);
    final statusText = _statusLabel(booking);
    final statusColor = _statusColor(booking);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildBadge(statusText, statusColor, Colors.white),
                    _buildBadge(
                      type,
                      type == 'Valet'
                          ? Colors.blue.shade600
                          : Colors.teal.shade600,
                      Colors.white,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Booking ID', _valueOrNA(booking['id'])),
                _buildDetailRow(
                    'Booking Token', _valueOrNA(booking['booking_token'])),
                _buildDetailRow('Customer', _customerName(booking)),
                _buildDetailRow('Customer ID', _valueOrNA(booking['user_id'])),
                _buildDetailRow('Vehicle Type', _valueOrNA(booking['vehicle_type'])),
                _buildDetailRow(
                    'Vehicle Number', _valueOrNA(booking['vehicle_number'])),
                _buildDetailRow('Driver', _driverName(booking)),
                _buildDetailRow('Return Driver', _returnDriverName(booking)),
                _buildDetailRow('Location', _locationName(booking)),
                _buildDetailRow('Slot', _valueOrNA(booking['slot_number'])),
                _buildDetailRow('Status', _valueOrNA(booking['status'])),
                _buildDetailRow(
                    'Return Status', _valueOrNA(booking['return_status'])),
                _buildDetailRow(
                    'Payment Status', _valueOrNA(booking['payment_status'])),
                _buildDetailRow(
                    'Payment Method', _valueOrNA(booking['payment_method'])),
                _buildDetailRow(
                    'Payment Amount', _valueOrNA(booking['payment_amount'])),
                _buildDetailRow(
                    'Booking Time', _formatTime(booking['booking_time'])),
                _buildDetailRow(
                  'Driver Accepted',
                  _formatTime(booking['driver_accepted_at']),
                ),
                _buildDetailRow(
                  'Parked Confirmed',
                  _formatTime(booking['parked_confirmed_at']),
                ),
                _buildDetailRow(
                  'Return Requested',
                  _formatTime(booking['return_requested_at']),
                ),
                _buildDetailRow(
                  'Return Location',
                  _valueOrNA(booking['desired_return_location']),
                ),
                _buildDetailRow(
                  'Return Accepted',
                  _formatTime(booking['return_accepted_at']),
                ),
                _buildDetailRow(
                  'Return Completed',
                  _formatTime(booking['return_completed_at']),
                ),
                _buildDetailRow('Completed At', _formatTime(booking['completed_at'])),
                _buildDetailRow('Cancelled At', _formatTime(booking['cancelled_at'])),
                _buildDeclineHistory(booking),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
      ),
    );
  }

  Widget _buildDeclineHistory(Map<String, dynamic> booking) {
    final declines = _declines(booking);
    if (declines.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
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
            final driverName =
                (decline['driver_name'] ?? 'Driver ${decline['driver_id'] ?? 'N/A'}')
                    .toString();
            final reason =
                (decline['decline_reason'] ?? 'No reason').toString();
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
                    driverName,
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
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(decline['declined_at']),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final valetCount = _bookings.where(_isValetBooking).length;
    final selfParkingCount = _bookings.length - valetCount;
    final completedCount = _bookings.where((booking) {
      final status = (booking['status'] ?? '').toString().toLowerCase();
      final returnStatus =
          (booking['return_status'] ?? '').toString().toLowerCase();
      return status == 'completed' || returnStatus == 'completed';
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking History'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
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
                        Row(
                          children: [
                            _buildSummaryCard(
                              'Total',
                              _bookings.length,
                              Colors.blue.shade700,
                            ),
                            const SizedBox(width: 10),
                            _buildSummaryCard(
                              'Valet',
                              valetCount,
                              Colors.purple.shade600,
                            ),
                            const SizedBox(width: 10),
                            _buildSummaryCard(
                              'Completed',
                              completedCount,
                              Colors.green.shade700,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Self Parking: $selfParkingCount',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _bookings.isEmpty
                              ? Center(
                                  child: Text(
                                    'No booking history found',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _loadData,
                                  child: ListView.builder(
                                    itemCount: _bookings.length,
                                    itemBuilder: (context, index) =>
                                        _buildBookingCard(_bookings[index]),
                                  ),
                                ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
