import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'home_screen.dart';
import 'admin_dashboard_screen.dart';
import 'driver_dashboard_screen.dart';
import 'security_dashboard_screen.dart';
import 'register_screen.dart';
import 'public_home_screen.dart';
import '../core/utils/gmail_validator.dart';
import '../core/utils/auth_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config.dart';

class LoginScreen extends StatefulWidget {
  final bool fromLogout;

  const LoginScreen({Key? key, this.fromLogout = false}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _jwtToken;
  // State variables
  String _selectedRole = 'customer';
  bool _isLoading = false;
  bool _obscurePassword = true;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Demo/test credentials for each role
  final Map<String, Map<String, String>> _validCredentials = {
    'admin': {
      'email': 'admin@valet.com',
      'password': 'admin123',
    },
    'driver': {
      'email': 'driver@valet.com',
      'password': 'driver123',
    },
    'security': {
      'email': 'security@valet.com',
      'password': 'security123',
    },
  };

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _emailController.clear();
    _passwordController.clear();
    _obscurePassword = true;
  }

  void _login() async {
    // Print login response for debugging
    // Place after http.post call
    // ...existing code...
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.post(
        Uri.parse('$apiBase/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      );
      print('Login response: ${response.body}');
      if (!mounted) return; // widget disposed while waiting for response
      setState(() {
        _isLoading = false;
      });
      if (response.statusCode == 200) {
        print('JWT token after login: $_jwtToken');
        final data = jsonDecode(response.body);
        _jwtToken = data['token'];
        // Obtain SharedPreferences first so we can persist values
        final prefs = await SharedPreferences.getInstance();
        // Store token globally
        AuthTokenStore().token = _jwtToken;
        // Store user id for screens that need it (e.g., driver dashboard)
        final userIdValue = data['user']?['id'];
        if (userIdValue != null) {
          AuthTokenStore().userId = userIdValue.toString();
          await prefs.setString('user_id', userIdValue.toString());
        }
        // Store token in SharedPreferences
        await prefs.setString('jwt_token', _jwtToken ?? '');
        // Check role match (case-insensitive, trimmed, from user object)
        final backendRole =
            (data['user']?['role'] ?? '').toString().toLowerCase().trim();
        final selectedRole = _selectedRole.toLowerCase().trim();
        if (backendRole == selectedRole) {
          if (selectedRole == 'customer') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => HomeScreen(),
              ),
            );
          } else if (selectedRole == 'admin') {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => AdminDashboardScreen()));
          } else if (selectedRole == 'driver') {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => DriverDashboardScreen()));
          } else if (selectedRole == 'security') {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => SecurityDashboardScreen()));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid credentials')),
          );
        }
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid credentials')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.fromLogout) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const PublicHomeScreen()),
                (route) => false,
              );
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RegisterScreen()),
              );
            },
            child: const Text(
              'Register',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Title
                  Text(
                    'Welcome Back',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Login to your account',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Role Selection
                  Text(
                    'Select Your Role',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedRole,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: [
                        DropdownMenuItem(
                          value: 'customer',
                          child: Row(
                            children: [
                              Icon(Icons.person, color: Colors.blue.shade600),
                              const SizedBox(width: 12),
                              const Text('Customer'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'driver',
                          child: Row(
                            children: [
                              Icon(Icons.directions_car,
                                  color: Colors.green.shade600),
                              const SizedBox(width: 12),
                              const Text('Driver'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Row(
                            children: [
                              Icon(Icons.admin_panel_settings,
                                  color: Colors.orange.shade600),
                              const SizedBox(width: 12),
                              const Text('Admin'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'security',
                          child: Row(
                            children: [
                              Icon(Icons.security, color: Colors.red.shade600),
                              const SizedBox(width: 12),
                              const Text('Security'),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedRole = value;
                            _resetForm();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Email Field (for all roles)
                  _buildFormLabel('Email'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: _getHintEmail(),
                      prefixIcon: const Icon(Icons.email),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.blue.shade600,
                          width: 2,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    validator: validateGmail,
                  ),
                  const SizedBox(height: 16),
                  // Password Field
                  _buildFormLabel('Password'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      hintText: 'Enter your password',
                      prefixIcon: Icon(
                        Icons.lock,
                        color: Colors.grey.shade600,
                      ),
                      suffixIcon: GestureDetector(
                        onTap: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        child: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.blue.shade600,
                          width: 2,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    validator: (value) => value == null || value.length < 6
                        ? 'Password must be at least 6 characters'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  // Test Credentials Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Test Credentials:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Email: ${_validCredentials[_selectedRole]?['email'] ?? 'customer@example.com'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          'Password: ${_validCredentials[_selectedRole]?['password'] ?? 'password'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        disabledBackgroundColor: Colors.grey.shade400,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.blue.shade600,
                                ),
                              ),
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Toggle to Register
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => RegisterScreen()),
                        );
                      },
                      child: const Text("Don't have an account? Register"),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getHintEmail() {
    if (_validCredentials.containsKey(_selectedRole)) {
      return _validCredentials[_selectedRole]!['email']!;
    }
    return 'Enter your email';
  }

  Widget _buildFormLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.blue.shade600,
      ),
    );
  }
}
