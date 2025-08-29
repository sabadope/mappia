import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'core/constants/env_constants.dart';
import 'core/constants/app_constants.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/rider_location_service.dart';

// Global instance of RiderLocationService
final riderLocationService = RiderLocationService();

void main() async {
  // Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  await Supabase.initialize(
    url: EnvConstants.supabaseUrl,
    anonKey: EnvConstants.supabaseAnonKey,
  );
  
  // Request location permissions if not on web
  if (!kIsWeb) {
    await Geolocator.requestPermission();
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Clean up when the app is closed
    riderLocationService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (state == AppLifecycleState.paused) {
      // App is in background
      riderLocationService.stopLocationTracking();
    } else if (state == AppLifecycleState.resumed) {
      // App is back in foreground
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        riderLocationService.setCurrentUserId(user.id);
        // Optionally restart tracking if the rider was online
        // riderLocationService.startLocationTracking();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mappia - Food Delivery',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppConstants.primaryColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const OnboardingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
