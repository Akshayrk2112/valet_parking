import 'package:flutter/material.dart';
import 'home_screen.dart';

class BookingConfirmedScreen extends StatefulWidget {
  final String slotId;
  final String parkingName;
  final String bookingId;
  final String vehicleType;
  final String vehicleNumber;
  final DateTime? bookingTime;
  final String? paymentMethod;
  final int? paymentAmount;

  const BookingConfirmedScreen({
    Key? key,
    required this.slotId,
    required this.parkingName,
    required this.bookingId,
    this.vehicleType = 'Unknown',
    this.vehicleNumber = 'N/A',
    this.bookingTime,
    this.paymentMethod,
    this.paymentAmount,
  }) : super(key: key);

  @override
  State<BookingConfirmedScreen> createState() => _BookingConfirmedScreenState();
}

class _BookingConfirmedScreenState extends State<BookingConfirmedScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Confirmed'),
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Success Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 50,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Success Message
                Text(
                  'Parking Booked Successfully!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                Text(
                  'Your parking slot is now reserved',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Booking Details Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Booking ID
                      _buildDetailRow(
                        label: 'Booking ID',
                        value: widget.bookingId,
                      ),

                      const SizedBox(height: 12),

                      // Parking Location
                      _buildDetailRow(
                        label: 'Parking Location',
                        value: widget.parkingName,
                      ),

                      const SizedBox(height: 12),

                      // Slot Number
                      _buildDetailRow(
                        label: 'Slot Number',
                        value: widget.slotId,
                      ),

                      const SizedBox(height: 12),

                      // Vehicle Type
                      _buildDetailRow(
                        label: 'Vehicle Type',
                        value: widget.vehicleType,
                      ),

                      const SizedBox(height: 12),

                      // Vehicle Number
                      _buildDetailRow(
                        label: 'Vehicle Number',
                        value: widget.vehicleNumber,
                      ),

                      if (widget.paymentAmount != null) ...[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          label: 'Payment',
                          value: 'Rs ${widget.paymentAmount}',
                        ),
                      ],

                      if (widget.paymentMethod != null &&
                          widget.paymentMethod!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          label: 'Payment Method',
                          value: widget.paymentMethod!,
                        ),
                      ],

                      if (widget.bookingTime != null) ...[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          label: 'Booking Time',
                          value: _formatDateTime(widget.bookingTime!),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Info Box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info,
                        color: Colors.blue.shade600,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Please arrive at your designated parking slot within 30 minutes.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Action Buttons
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.home),
                  label: const Text('Back to Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Booking details copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Share Booking'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade600,
                    side: BorderSide(color: Colors.blue.shade600),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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

  Widget _buildDetailRow({
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
