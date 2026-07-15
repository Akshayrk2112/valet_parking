import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/utils/auth_token_store.dart';

class AdminDeclinedRequestsScreen extends StatefulWidget {
  const AdminDeclinedRequestsScreen({Key? key}) : super(key: key);

  @override
  State<AdminDeclinedRequestsScreen> createState() =>
      _AdminDeclinedRequestsScreenState();
}

class _AdminDeclinedRequestsScreenState
    extends State<AdminDeclinedRequestsScreen> {
  List<Map<String, dynamic>> _declines = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDeclinedRequests();
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

  Future<void> _loadDeclinedRequests() async {
    final jwtToken = AuthTokenStore().token;
    if (jwtToken == null || jwtToken.isEmpty) {
      setState(() {
        _errorMessage = 'Missing login session token';
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
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'Failed to load declined requests: ${_extractErrorMessage(response)}';
          _declines = [];
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final bookings = (data['bookings'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final declines = <Map<String, dynamic>>[];
      for (final booking in bookings) {
        final rawDeclines = booking['declines'];
        if (rawDeclines is! List) continue;
        for (final rawDecline in rawDeclines) {
          if (rawDecline is! Map) continue;
          declines.add({
            ...Map<String, dynamic>.from(rawDecline),
            'booking_token': booking['booking_token'],
            'booking_id': booking['id'],
            'customer_name': booking['customer_name'],
            'user_id': booking['user_id'],
            'vehicle_type': booking['vehicle_type'],
            'vehicle_number': booking['vehicle_number'],
            'booking_time': booking['booking_time'],
          });
        }
      }

      declines.sort((a, b) {
        final aTime = DateTime.tryParse('${a['declined_at'] ?? ''}');
        final bTime = DateTime.tryParse('${b['declined_at'] ?? ''}');
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      if (!mounted) return;
      setState(() {
        _declines = declines;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Network error: $e';
        _declines = [];
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

  String _driverLabel(Map<String, dynamic> decline) {
    final name = (decline['driver_name'] ?? '').toString().trim();
    final id = decline['driver_id'];
    if (name.isNotEmpty) return '$name (ID $id)';
    return 'Driver ${id ?? 'N/A'}';
  }

  String _customerLabel(Map<String, dynamic> decline) {
    final name = (decline['customer_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return 'Customer ${decline['user_id'] ?? 'N/A'}';
  }

  String _requestTypeLabel(Map<String, dynamic> decline) {
    final type =
        (decline['request_type'] ?? 'pickup').toString().trim().toLowerCase();
    return type == 'return' ? 'Return' : 'Pickup';
  }

  Widget _buildSummaryPill({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeclineCard(Map<String, dynamic> decline) {
    final reason = (decline['decline_reason'] ?? 'No reason').toString();
    final note = (decline['decline_note'] ?? '').toString().trim();
    final typeLabel = _requestTypeLabel(decline);
    final typeColor = typeLabel == 'Return'
        ? Colors.deepPurple.shade700
        : Colors.red.shade700;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
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
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: typeColor.withOpacity(0.35)),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: typeColor,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDateTime(decline['declined_at']),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _driverLabel(decline),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Reason: $reason',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.red.shade700,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Note: $note',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade800,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 10),
          Text(
            'Booking ${(decline['booking_id'] ?? 'N/A')} - ${(decline['booking_token'] ?? 'N/A')}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_customerLabel(decline)} - ${(decline['vehicle_type'] ?? 'Vehicle')} (${decline['vehicle_number'] ?? 'N/A'})',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Booked: ${_formatDateTime(decline['booking_time'])}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickupCount = _declines
        .where((d) => (d['request_type'] ?? '').toString() != 'return')
        .length;
    final returnCount = _declines
        .where((d) => (d['request_type'] ?? '').toString() == 'return')
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Declined Requests'),
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
            onPressed: _loadDeclinedRequests,
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildSummaryPill(
                              label: 'Total',
                              value: _declines.length.toString(),
                              icon: Icons.report_problem,
                              color: Colors.red.shade700,
                            ),
                            _buildSummaryPill(
                              label: 'Pickup',
                              value: pickupCount.toString(),
                              icon: Icons.local_parking,
                              color: Colors.orange.shade700,
                            ),
                            _buildSummaryPill(
                              label: 'Return',
                              value: returnCount.toString(),
                              icon: Icons.keyboard_return,
                              color: Colors.deepPurple.shade700,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _declines.isEmpty
                              ? Center(
                                  child: Text(
                                    'No declined requests found',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _declines.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) =>
                                      _buildDeclineCard(_declines[index]),
                                ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
