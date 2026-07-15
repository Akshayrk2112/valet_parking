import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/utils/auth_token_store.dart';

class DriverAcceptedRequestsScreen extends StatefulWidget {
  const DriverAcceptedRequestsScreen({Key? key}) : super(key: key);

  @override
  State<DriverAcceptedRequestsScreen> createState() =>
      _DriverAcceptedRequestsScreenState();
}

class _DriverAcceptedRequestsScreenState
    extends State<DriverAcceptedRequestsScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadAcceptedRequests();
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
    return 'Request failed (${response.statusCode})';
  }

  Future<void> _loadAcceptedRequests() async {
    final token = AuthTokenStore().token;
    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Please login again to view accepted requests.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/drivers/mine/accepted-requests/today'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _error = _extractErrorMessage(response);
        });
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (decoded['requests'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      setState(() {
        _requests = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load accepted requests: $e';
      });
    }
  }

  String _valueOrNA(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'N/A' : text;
  }

  String _formatTime(dynamic value) {
    final raw = value?.toString().trim() ?? '';
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

  String _requestTypeLabel(Map<String, dynamic> request) {
    final type = (request['request_type'] ?? '').toString().toLowerCase();
    return type == 'return' ? 'Return Request' : 'Valet Parking';
  }

  IconData _requestTypeIcon(Map<String, dynamic> request) {
    final type = (request['request_type'] ?? '').toString().toLowerCase();
    return type == 'return' ? Icons.assignment_return : Icons.local_parking;
  }

  Color _requestTypeColor(Map<String, dynamic> request) {
    final type = (request['request_type'] ?? '').toString().toLowerCase();
    return type == 'return' ? Colors.deepPurple.shade600 : Colors.blue.shade600;
  }

  String _statusLabel(Map<String, dynamic> request) {
    final type = (request['request_type'] ?? '').toString().toLowerCase();
    if (type == 'return') {
      final status = (request['return_status'] ?? '').toString().toLowerCase();
      if (status == 'released') return 'Released by security';
      if (status == 'handover_confirmed') return 'Driver handover confirmed';
      if (status == 'completed') return 'Return completed';
      if (status == 'accepted') return 'Return accepted';
      return _valueOrNA(request['return_status']);
    }

    final status = (request['status'] ?? '').toString().toLowerCase();
    if (status == 'pending') return 'Pickup accepted';
    if (status == 'confirmed') return 'Parking confirmed';
    if (status == 'completed') return 'Completed';
    return _valueOrNA(request['status']);
  }

  Widget _buildSummaryCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.24)),
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
                fontWeight: FontWeight.w600,
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
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

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final typeColor = _requestTypeColor(request);
    final isReturn =
        (request['request_type'] ?? '').toString().toLowerCase() == 'return';
    final customerName = _valueOrNA(
      request['customer_name'] ?? 'Customer ${request['user_id'] ?? ''}',
    );
    final locationName = _valueOrNA(
      request['location_name'] ?? request['location_id'],
    );
    final returnLocation = _valueOrNA(request['desired_return_location']);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _requestTypeIcon(request),
                  color: typeColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _requestTypeLabel(request),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: typeColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(request['accepted_at']),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildDetailRow('Status', _statusLabel(request)),
          _buildDetailRow('Token', _valueOrNA(request['booking_token'])),
          _buildDetailRow('Vehicle', _valueOrNA(request['vehicle_type'])),
          _buildDetailRow('Vehicle No.', _valueOrNA(request['vehicle_number'])),
          _buildDetailRow('Customer Ph.', _valueOrNA(request['customer_phone'])),
          _buildDetailRow('Booked At', _formatTime(request['booking_time'])),
          if (isReturn) ...[
            _buildDetailRow('Return To', returnLocation),
            _buildDetailRow(
              'Return Asked',
              _formatTime(request['return_requested_at']),
            ),
          ] else ...[
            _buildDetailRow('Parking', locationName),
            _buildDetailRow('Slot', _valueOrNA(request['slot_number'])),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickupCount = _requests
        .where((request) =>
            (request['request_type'] ?? '').toString().toLowerCase() !=
            'return')
        .length;
    final returnCount = _requests.length - pickupCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accepted Requests'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadAcceptedRequests,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadAcceptedRequests,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        _buildSummaryCard(
                          'Total Today',
                          _requests.length,
                          Colors.blue.shade700,
                        ),
                        const SizedBox(width: 10),
                        _buildSummaryCard(
                          'Valet Parking',
                          pickupCount,
                          Colors.green.shade700,
                        ),
                        const SizedBox(width: 10),
                        _buildSummaryCard(
                          'Return',
                          returnCount,
                          Colors.deepPurple.shade600,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else if (_requests.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.assignment_turned_in,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No accepted valet parking or return requests today.',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._requests.map(_buildRequestCard),
                  ],
                ),
              ),
      ),
    );
  }
}
