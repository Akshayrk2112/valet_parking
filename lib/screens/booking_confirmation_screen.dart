import 'package:flutter/material.dart';

class BookingConfirmationScreen extends StatelessWidget {
  final String parking;
  final String slot;
  final String vehicleModel;
  final String vehicleNumber;
  final String location;

  const BookingConfirmationScreen({
    Key? key,
    required this.parking,
    required this.slot,
    required this.vehicleModel,
    required this.vehicleNumber,
    required this.location,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String _selectedOption = 'self';
    int _payment = 0;
    return StatefulBuilder(
      builder: (context, setState) {
        _payment = _selectedOption == 'self' ? 50 : 100;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Booking Confirmation'),
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Parking: $parking', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Slot: $slot'),
                const SizedBox(height: 8),
                Text('Vehicle: $vehicleModel ($vehicleNumber)'),
                const SizedBox(height: 8),
                Text('Location: $location'),
                const SizedBox(height: 24),
                const Text('How would you like to park?', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Radio<String>(
                      value: 'self',
                      groupValue: _selectedOption,
                      onChanged: (value) {
                        setState(() => _selectedOption = value!);
                      },
                    ),
                    const Text('Park Yourself'),
                    const SizedBox(width: 24),
                    Radio<String>(
                      value: 'valet',
                      groupValue: _selectedOption,
                      onChanged: (value) {
                        setState(() => _selectedOption = value!);
                      },
                    ),
                    const Text('Need Driver Agent'),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Payment: ₹$_payment', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // You can add navigation to payment or final screen here
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Booking Confirmed!'),
                          content: Text('Thank you for your booking.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Confirm & Pay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
