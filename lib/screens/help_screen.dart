import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = _HelpThemeColors();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Guide'),
        elevation: 0,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.primary, colors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.surfaceTop, colors.surfaceBottom],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.primary, colors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withOpacity(0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.35)),
                      ),
                      child: const Icon(
                        Icons.assistant,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Need a quick guide?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Everything you need to book, track, and return your vehicle.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _QuickChip(
                    label: 'Book Valet',
                    icon: Icons.car_rental,
                    color: colors.primary,
                  ),
                  _QuickChip(
                    label: 'Track Vehicle',
                    icon: Icons.track_changes,
                    color: colors.accent,
                  ),
                  _QuickChip(
                    label: 'Request Return',
                    icon: Icons.assignment_return,
                    color: colors.secondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _HelpSection(
                title: 'Valet Parking Facilities',
                icon: Icons.local_parking,
                color: colors.primary,
                items: const [
                  'Book Valet pickup from the customer dashboard.',
                  'Track your vehicle status in Track Valet.',
                  'Parking slot and location appear after security confirmation.',
                  'Return request with desired location is supported.',
                ],
              ),
              const SizedBox(height: 12),
              _HelpSection(
                title: 'How To Book Valet',
                icon: Icons.directions_car,
                color: colors.accent,
                items: const [
                  'Open Customer Dashboard and tap Book Valet.',
                  'Enter vehicle details and pickup information.',
                  'Confirm booking and wait for driver acceptance.',
                  'Driver picks up and parks; security confirms parking.',
                ],
              ),
              const SizedBox(height: 12),
              _HelpSection(
                title: 'How To Park Yourself',
                icon: Icons.person_pin_circle,
                color: colors.secondary,
                items: const [
                  'Tap Park Yourself on the dashboard.',
                  'Choose parking location and available slot.',
                  'Pay the shown amount and confirm parking.',
                  'Track booking status from your dashboard.',
                ],
              ),
              const SizedBox(height: 12),
              _HelpSection(
                title: 'Updates & Notifications',
                icon: Icons.notifications_active,
                color: colors.warning,
                items: const [
                  'Use the bell icon to view booking updates.',
                  'You will receive status changes for parking and return.',
                  'Driver/security actions are reflected in notifications.',
                ],
              ),
              const SizedBox(height: 12),
              _HelpSection(
                title: 'Need More Help?',
                icon: Icons.support_agent,
                color: colors.dark,
                items: const [
                  'For support, contact: valetrix@gmail.com',
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  const _HelpSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...items.map((item) => _HelpItem(text: item, color: color)),
          ],
        ),
      ),
    );
  }
}

class _HelpItem extends StatelessWidget {
  final String text;
  final Color color;

  const _HelpItem({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.check,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey.shade800,
                height: 1.35,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _QuickChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpThemeColors {
  final Color primary = const Color(0xFF1E5AA8);
  final Color primaryDark = const Color(0xFF123D73);
  final Color accent = const Color(0xFF2B9EB3);
  final Color secondary = const Color(0xFF4F9D69);
  final Color warning = const Color(0xFFFFB347);
  final Color dark = const Color(0xFF3E3E3E);
  final Color surfaceTop = const Color(0xFFF3F6FB);
  final Color surfaceBottom = Colors.white;
}
