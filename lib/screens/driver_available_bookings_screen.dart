import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';
import '../widgets/custom_drawer.dart';

class DriverAvailableBookingsScreen extends StatefulWidget {
  const DriverAvailableBookingsScreen({Key? key}) : super(key: key);

  @override
  State<DriverAvailableBookingsScreen> createState() =>
      _DriverAvailableBookingsScreenState();
}

class _DriverAvailableBookingsScreenState
    extends State<DriverAvailableBookingsScreen> {
  static const List<String> _declineReasons = [
    'Too far from location',
    'Currently handling another task',
    'Vehicle type issue',
    'Customer location unclear',
    'Parking area unavailable',
    'Shift ending',
    'Personal emergency',
    'Other',
  ];

  List<Map<String, dynamic>> _availableBookings = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchAvailableBookings();
  }

  Future<void> _fetchAvailableBookings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final jwtToken = AuthTokenStore().token;
      final url = Uri.parse('$apiBase/api/bookings/available');
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
        final bookings = data['bookings'] as List<dynamic>;
        _availableBookings = bookings
            .map((b) => {
                  'booking_token': b['booking_token'],
                  'vehicle_number': b['vehicle_number'],
                  'vehicle_type': b['vehicle_type'] ?? 'Car',
                  'booking_time': b['booking_time'],
                  'location_id': b['location_id'],
                  'user_id': b['user_id'],
                  'eligible_to_accept': b['eligible_to_accept'] == true,
                  'priority_position': b['priority_position'],
                  'accepted_requests_today': b['accepted_requests_today'],
                })
            .toList();
      } else {
        _errorMessage = 'Failed to load bookings';
        _availableBookings = [];
      }
    } catch (e) {
      _errorMessage = 'Error: $e';
      _availableBookings = [];
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _acceptBooking(String bookingToken) async {
    final jwtToken = AuthTokenStore().token;
    final driverId = AuthTokenStore().userId;
    final url = Uri.parse('$apiBase/api/bookings/$bookingToken');
    try {
      final response = await http.patch(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'status': 'accepted',
          if (driverId != null) 'driver_id': driverId,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking accepted! You can now proceed.'),
            backgroundColor: Colors.green,
          ),
        );
        await _fetchAvailableBookings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to accept booking'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Network error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  Future<Map<String, String>?> _askDeclineDetails() async {
    String selectedReason = _declineReasons.first;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: const Text('Decline Booking'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.42,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      border: OutlineInputBorder(),
                    ),
                    items: _declineReasons
                        .map(
                          (reason) => DropdownMenuItem<String>(
                            value: reason,
                            child: Text(
                              reason,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedReason = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'reason': selectedReason,
                });
              },
              child: const Text('Decline'),
            ),
          ],
        ),
      ),
    );

    return result;
  }

  Future<void> _declineBooking(String bookingToken) async {
    final declineDetails = await _askDeclineDetails();
    if (declineDetails == null) return;

    final jwtToken = AuthTokenStore().token;
    final url = Uri.parse('$apiBase/api/bookings/$bookingToken');
    try {
      final response = await http.patch(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null && jwtToken.isNotEmpty)
            'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'status': 'declined',
          'decline_reason': declineDetails['reason'],
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking declined. Admin has been notified.'),
          ),
        );
        await _fetchAvailableBookings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_extractErrorMessage(response)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Network error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Bookings'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      drawer: const CustomDrawer(),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _fetchAvailableBookings,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _availableBookings.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No available bookings',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _fetchAvailableBookings,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchAvailableBookings,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _availableBookings.length,
                          itemBuilder: (context, index) {
                            final booking = _availableBookings[index];
                            return _buildBookingCard(booking);
                          },
                        ),
                      ),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final bookingTime =
        DateTime.tryParse(booking['booking_time'] ?? '')?.toString() ?? 'N/A';
    final isEligible = booking['eligible_to_accept'] == true;
    final priorityPosition = booking['priority_position'];
    final acceptedToday = booking['accepted_requests_today'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with vehicle info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking['vehicle_type'],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      booking['vehicle_number'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'New',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Divider
          Container(
            height: 1,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 12),
          // Details
          _buildDetailRow('Booking Time', bookingTime.split('.')[0]),
          const SizedBox(height: 8),
          _buildDetailRow(
              'Location ID', booking['location_id']?.toString() ?? 'N/A'),
          const SizedBox(height: 8),
          _buildDetailRow(
              'Token', booking['booking_token'].substring(0, 8) + '...'),
          const SizedBox(height: 8),
          _buildDetailRow(
            'Priority',
            isEligible
                ? 'Your turn'
                : (priorityPosition == null
                    ? 'Waiting'
                    : 'Queue position $priorityPosition'),
          ),
          if (acceptedToday != null) ...[
            const SizedBox(height: 8),
            _buildDetailRow('Accepted Today', acceptedToday.toString()),
          ],
          const SizedBox(height: 16),
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: isEligible
                      ? () => _acceptBooking(booking['booking_token'])
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: isEligible
                      ? () => _declineBooking(booking['booking_token'])
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade600),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Decline',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }
}
