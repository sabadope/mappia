import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rider_service.dart';

class RiderLocationService {
  static final RiderLocationService _instance = RiderLocationService._internal();
  factory RiderLocationService() => _instance;
  RiderLocationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isTracking = false;
  String? _currentUserId;

  // Set the current user ID (called after login)
  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  // Get current user ID
  String? get currentUserId => _currentUserId ?? _supabase.auth.currentUser?.id;

  // Get current location once
  Future<Position?> getCurrentLocation() async {
    try {
      debugPrint('Checking location services...');
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        // Request to enable location services
        serviceEnabled = await Geolocator.openLocationSettings();
        if (!serviceEnabled) {
          debugPrint('User did not enable location services');
          return null;
        }
      }
      debugPrint('Location services are enabled');

      // Check location permissions
      debugPrint('Checking location permissions...');
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('Current permission status: $permission');
      
      if (permission == LocationPermission.denied) {
        debugPrint('Requesting location permission...');
        permission = await Geolocator.requestPermission();
        debugPrint('Permission after request: $permission');
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          debugPrint('Location permissions denied by user');
          return null;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied');
        // Open app settings to enable permissions
        await Geolocator.openAppSettings();
        return null;
      }

      if (permission == LocationPermission.whileInUse || 
          permission == LocationPermission.always) {
        debugPrint('Location permission granted, getting current position...');
        
        // Try to get last known position first (faster)
        try {
          final lastPosition = await Geolocator.getLastKnownPosition();
          if (lastPosition != null) {
            debugPrint('Using last known position');
            return lastPosition;
          }
        } catch (e) {
          debugPrint('Error getting last known position: $e');
        }
        
        // If no last known position, get fresh location
        debugPrint('Getting fresh location...');
        try {
          return await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 15), // Increased timeout to 15 seconds
          );
        } on TimeoutException {
          debugPrint('Location request timed out');
          // Try one more time with lower accuracy
          return await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
        }
      } else {
        debugPrint('Unexpected permission status: $permission');
        return null;
      }
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  // Start location tracking
  Future<bool> startLocationTracking() async {
    try {
      if (_isTracking) return true;
      if (_currentUserId == null) return false;

      // Request location permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          print('Location permissions denied');
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied');
        return false;
      }

      // Set up location settings
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50, // Update when device moves 50 meters
      );

      // Listen to location updates
      _positionStreamSubscription = 
          Geolocator.getPositionStream(locationSettings: locationSettings)
              .listen((position) async {
        if (position.accuracy > 100) return; // Skip inaccurate updates
        
        // Update location in Supabase
        try {
          await _supabase.rpc('update_rider_location', params: {
            'p_user_id': _currentUserId,
            'p_latitude': position.latitude,
            'p_longitude': position.longitude,
          });
          print('Location updated: ${position.latitude}, ${position.longitude}');
        } catch (e) {
          print('Error updating location: $e');
        }
      });

      _isTracking = true;
      return true;
    } catch (e) {
      print('Error starting location tracking: $e');
      return false;
    }
  }

  // Stop location tracking
  Future<void> stopLocationTracking() async {
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _isTracking = false;
  }

  // Check if location tracking is active
  bool get isTracking => _isTracking;

  // Update rider's online status and start/stop tracking
  Future<Map<String, dynamic>> setOnlineStatus(bool isOnline) async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        debugPrint('Error: User ID is null in setOnlineStatus');
        return {'success': false, 'message': 'User not authenticated. Please log in again.'};
      }
      
      // Get the rider profile first
      final riderService = RiderService();
      debugPrint('🔍 [setOnlineStatus] Getting rider profile for user ID: $userId');
      final riderProfile = await riderService.getRiderProfile(userId: userId);
      if (riderProfile == null) {
        debugPrint('❌ [setOnlineStatus] Error: Rider profile not found for user ID: $userId');
        return {'success': false, 'message': 'Rider profile not found. Please complete your rider profile first.'};
      }
      debugPrint('✅ [setOnlineStatus] Found rider profile with ID: ${riderProfile['id']}');

      if (isOnline) {
        print('Attempting to go online...');
        
        // When going online, get current location first with timeout
        print('Getting current location...');
        final position = await getCurrentLocation()
            .timeout(const Duration(seconds: 12), onTimeout: () {
          print('Location request timed out after 12 seconds');
          return null;
        });
        
        if (position == null) {
          return {'success': false, 'message': 'Could not get current location. Please check your location permissions and try again.'};
        }

        try {
          print('Updating online status in database for rider ID: ${riderProfile['id']}');
          final response = await _supabase
              .from('riders')
              .update({
                'is_online': isOnline,
                'updated_at': DateTime.now().toIso8601String(),
                if (position != null)
                  'current_location': _convertToPostGisPoint(
                    position.latitude,
                    position.longitude,
                  ),
              })
              .eq('id', riderProfile['id'])
              .select()
              .single();

          print('Successfully updated online status: $response');
        } on PostgrestException catch (e) {
          print('Error updating online status: ${e.message}');
          return {'success': false, 'message': 'Failed to update online status: ${e.message}'};
        } catch (e) {
          print('Unexpected error updating online status: $e');
          return {'success': false, 'message': 'An unexpected error occurred while updating status'};
        }
        
        // Successfully went online and updated location
        return {'success': true, 'message': 'You are now online and ready to receive orders'};
      } else {
        print('Going offline...');
        // When going offline, stop tracking first
        await stopLocationTracking();
        
        // Update online status using the rider's ID
        try {
          print('Updating offline status in database for rider ID: ${riderProfile['id']}');
          final response = await _supabase
              .from('riders')
              .update({
                'is_online': false,
                'is_available': false, // Also set as not available when going offline
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', riderProfile['id'])
              .select()
              .single();
              
          print('Successfully updated offline status: $response');
          return {'success': true, 'message': 'You are now offline'};
        } on PostgrestException catch (e) {
          print('Error updating offline status: ${e.message}');
          return {'success': false, 'message': 'Failed to update status: ${e.message}'};
        } catch (e) {
          debugPrint('Unexpected error going offline: $e');
          return {'success': false, 'message': 'Failed to go offline. Please try again.'};
        }
      }
    } catch (e) {
      print('Unexpected error in setOnlineStatus: $e');
      return {'success': false, 'message': 'An unexpected error occurred. Please try again.'};
    }
  }

  // Clean up resources
  void dispose() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _isTracking = false;
  }
  
  // Convert latitude and longitude to PostGIS point format
  String _convertToPostGisPoint(double latitude, double longitude) {
    // PostGIS uses WKT (Well-Known Text) format: POINT(longitude latitude)
    // Note: In PostGIS, coordinates are in (longitude, latitude) order
    return 'SRID=4326;POINT($longitude $latitude)';
  }
}
