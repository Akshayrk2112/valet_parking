import 'package:flutter/material.dart';
import '../screens/login_screen.dart';
import '../screens/customer_booking_history_screen.dart';
import '../screens/help_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../core/utils/auth_token_store.dart';
import '../core/config.dart';

class CustomDrawer extends StatelessWidget {
  final bool showHomeItem;
  final bool showLoginItem;
  final bool showCustomerHistory;
  final WidgetBuilder? helpScreenBuilder;

  const CustomDrawer({
    Key? key,
    this.showHomeItem = true,
    this.showLoginItem = true,
    this.showCustomerHistory = false,
    this.helpScreenBuilder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Drawer Header
          Container(
            decoration: BoxDecoration(
              color: Colors.blue.shade600,
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.directions_car,
                    color: Colors.white,
                    size: 40,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Valetrix',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Menu Items
          if (showHomeItem)
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
              },
            ),

          if (showLoginItem)
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Login'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginScreen(),
                  ),
                );
              },
            ),

          if (showCustomerHistory)
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Booking History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CustomerBookingHistoryScreen(),
                  ),
                );
              },
            ),

          ListTile(
            leading: const Icon(Icons.help),
            title: const Text('Help'),
            onTap: () {
              Navigator.pop(context);
              if (helpScreenBuilder != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: helpScreenBuilder!),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HelpScreen()),
                );
              }
            },
          ),

          if (AuthTokenStore().token != null &&
              AuthTokenStore().token!.isNotEmpty) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () {
                Navigator.pop(context);
                final token = AuthTokenStore().token;
                // Call backend logout API if token exists
                if (token != null && token.isNotEmpty) {
                  http.post(
                    Uri.parse('$apiBase/api/auth/logout'),
                    headers: {
                      'Content-Type': 'application/json',
                      'Authorization': 'Bearer $token',
                    },
                  );
                }
                // Clear token from AuthTokenStore
                AuthTokenStore().token = null;
                // Remove token from SharedPreferences
                SharedPreferences.getInstance().then((prefs) {
                  prefs.remove('jwt_token');
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const LoginScreen(fromLogout: true)),
                  );
                });
              },
            ),
          ],
        ],
      ),
    );
  }
}
