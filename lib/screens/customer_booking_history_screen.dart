import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/utils/auth_token_store.dart';

class CustomerBookingHistoryScreen extends StatefulWidget {
  const CustomerBookingHistoryScreen({Key? key}) : super(key: key);

  @override
  State<CustomerBookingHistoryScreen> createState() =>
      _CustomerBookingHistoryScreenState();
}

class _CustomerBookingHistoryScreenState
    extends State<CustomerBookingHistoryScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBookings();
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

  Future<void> _loadBookings() async {
    final jwtToken = AuthTokenStore().token;
    final userId = AuthTokenStore().userId;
    if (userId == null || userId.isEmpty) {
      setState(() {
        _errorMessage = 'Missing user session. Please log in again.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/bookings'),
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
      );
      if (response.statusCode != 200) {
        setState(() {
          _errorMessage = _extractErrorMessage(response);
          _bookings = [];
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawBookings = (data['bookings'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where((booking) =>
              (booking['user_id']?.toString() ?? '') == userId)
          .toList();

      rawBookings.sort((a, b) {
        final aTime = DateTime.tryParse('${a['booking_time'] ?? ''}');
        final bTime = DateTime.tryParse('${b['booking_time'] ?? ''}');
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      setState(() {
        _bookings = rawBookings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
        _bookings = [];
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(dynamic raw) {
    final value = (raw ?? '').toString();
    if (value.isEmpty) return 'N/A';
    final dt = DateTime.tryParse(value);
    if (dt == null) return value;
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yy = local.year;
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yy $hh:$min';
  }

  String _bookingType(Map<String, dynamic> booking) {
    final hasSlot = (booking['slot_number'] ?? '').toString().trim().isNotEmpty;
    final hasLocation =
        booking['location_id'] != null || booking['location_name'] != null;
    final hasDriver = booking['driver_id'] != null;
    if (hasDriver || (!hasSlot && !hasLocation)) {
      return 'Valet';
    }
    return 'Self Parking';
  }

  String _statusLabel(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? 'unknown').toString().toLowerCase();
    if (status.isEmpty) return 'Unknown';
    return status[0].toUpperCase() + status.substring(1);
  }

  Color _statusColor(String status) {
    final value = status.toLowerCase();
    if (value == 'confirmed') return Colors.green.shade600;
    if (value == 'pending') return Colors.amber.shade700;
    if (value == 'completed') return Colors.blue.shade600;
    if (value == 'cancelled') return Colors.red.shade600;
    return Colors.grey.shade600;
  }

  Color _typeColor(String type) {
    return type == 'Valet' ? Colors.blue.shade700 : Colors.teal.shade700;
  }

  String _paymentLabel(Map<String, dynamic> booking) {
    final status =
        (booking['payment_status'] ?? '').toString().toLowerCase().trim();
    if (status.isEmpty) return 'N/A';
    return status[0].toUpperCase() + status.substring(1);
  }

  String _returnLabel(Map<String, dynamic> booking) {
    final status =
        (booking['return_status'] ?? '').toString().toLowerCase().trim();
    if (status.isEmpty) return 'N/A';
    return status[0].toUpperCase() + status.substring(1);
  }

  double _toAmount(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '0') ?? 0;
  }

  String _locationLabel(Map<String, dynamic> booking) {
    final name = (booking['location_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = booking['location_id'];
    if (id != null) return 'Location $id';
    return 'Not assigned';
  }

  String _slotLabel(Map<String, dynamic> booking) {
    final slot = (booking['slot_number'] ?? '').toString().trim();
    return slot.isEmpty ? 'Not assigned' : slot;
  }

  String _vehicleLabel(Map<String, dynamic> booking) {
    final type = (booking['vehicle_type'] ?? '').toString().trim();
    final number = (booking['vehicle_number'] ?? '').toString().trim();
    if (type.isEmpty && number.isEmpty) return 'N/A';
    if (type.isEmpty) return number;
    if (number.isEmpty) return type;
    return '$type ($number)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking History'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade700, Colors.blue.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBookings,
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
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
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade600,
                                  Colors.blue.shade400,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.shade300.withOpacity(0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.4),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.history,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Your Booking History',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Total bookings: ${_bookings.length}',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _bookings.isEmpty
                                ? Center(
                                    child: Text(
                                      'No bookings found',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _bookings.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final item = _bookings[index];
                                      return _buildBookingCard(item);
                                    },
                                  ),
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final type = _bookingType(booking);
    final status = _statusLabel(booking);
    final bookingTime = _formatDateTime(booking['booking_time']);
    final vehicle = _vehicleLabel(booking);
    final location = _locationLabel(booking);
    final slot = _slotLabel(booking);
    final statusColor = _statusColor(status);
    final typeColor = _typeColor(type);

    return GestureDetector(
      onTap: () => _showBookingDetails(booking),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: typeColor.withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: typeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: statusColor.withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '#${booking['id'] ?? 'N/A'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              vehicle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on,
                    size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    location,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Slot: $slot',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  bookingTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showBookingDetails(Map<String, dynamic> booking) {
    final type = _bookingType(booking);
    final status = _statusLabel(booking);
    final paymentStatus = _paymentLabel(booking);
    final returnStatus = _returnLabel(booking);
    final bookingTime = _formatDateTime(booking['booking_time']);
    final parkedTime = _formatDateTime(booking['parked_confirmed_at']);
    final completedTime = _formatDateTime(booking['completed_at']);
    final paymentTime = _formatDateTime(booking['payment_time']);
    final amount = _toAmount(booking['payment_amount']);

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
                _buildDetailRow('Booking ID', '${booking['id'] ?? 'N/A'}'),
                _buildDetailRow(
                  'Booking Token',
                  (booking['booking_token'] ?? 'N/A').toString(),
                ),
                _buildDetailRow('Type', type),
                _buildDetailRow('Status', status),
                _buildDetailRow('Return Status', returnStatus),
                _buildDetailRow('Vehicle', _vehicleLabel(booking)),
                _buildDetailRow('Location', _locationLabel(booking)),
                _buildDetailRow('Slot', _slotLabel(booking)),
                _buildDetailRow('Booking Time', bookingTime),
                _buildDetailRow('Parked Confirmed At', parkedTime),
                _buildDetailRow('Completed At', completedTime),
                _buildDetailRow('Payment Status', paymentStatus),
                _buildDetailRow(
                  'Payment Amount',
                  amount > 0 ? 'Rs ${amount.toStringAsFixed(2)}' : 'N/A',
                ),
                _buildDetailRow(
                  'Payment Method',
                  (booking['payment_method'] ?? 'N/A').toString(),
                ),
                _buildDetailRow('Payment Time', paymentTime),
              ],
            ),
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
            width: 140,
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
