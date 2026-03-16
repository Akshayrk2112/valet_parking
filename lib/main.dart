import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'providers/parking_provider.dart';
import 'screens/public_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ValetParkingApp());
}

class ValetParkingApp extends StatelessWidget {
  const ValetParkingApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ParkingProvider()),
      ],
      child: MaterialApp(
        title: 'Valet Parking',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          primaryColor: Colors.blue.shade600,
          useMaterial3: true,
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.blue.shade600,
            elevation: 0,
            centerTitle: true,
            titleTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          scaffoldBackgroundColor: Colors.grey.shade50,
        ),
          home: const SplashScreen(),
      ),
    );
  }
}
