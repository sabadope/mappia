import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // Get current location once
  Future<Position?> getCurrentLocation() async {
    try {
      print('Checking location services...');
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return null;
      }
      print('Location services are enabled');

      // Check location permissions
      print('Checking location permissions...');
      LocationPermission permission = await Geolocator.checkPermission();
      print('Current permission status: $permission');
      
      if (permission == LocationPermission.denied) {
        print('Requesting location permission...');
        permission = await Geolocator.requestPermission();
        print('Permission after request: $permission');
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          print('Location permissions denied by user');
          return null;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied');
        return null;
      }

      if (permission == LocationPermission.whileInUse || 
          permission == LocationPermission.always) {
        print('Location permission granted, getting current position...');
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10), // Reduce timeout to 10 seconds
        );
      } else {
        print('Unexpected permission status: $permission');
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
      if (_currentUserId == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

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

        print('Updating online status in database...');
        // Update location and online status in a transaction
        try {
          await _supabase.rpc('update_rider_online_status', params: {
            'p_user_id': _currentUserId,
            'p_is_online': isOnline,
            'p_latitude': position.latitude,
            'p_longitude': position.longitude,
          }).timeout(const Duration(seconds: 10));
          
          print('Starting location tracking...');
          // Start tracking
          final trackingStarted = await startLocationTracking();
          if (!trackingStarted) {
            return {'success': false, 'message': 'Failed to start location tracking'};
          }
          
          return {'success': true, 'message': 'You are now online'};
        } catch (e) {
          print('Error updating online status: $e');
          return {'success': false, 'message': 'Failed to update status. Please try again.'};
        }
      } else {
        print('Going offline...');
        // When going offline, stop tracking first
        await stopLocationTracking();
        
        // Update online status
        try {
          await _supabase
              .from('riders')
              .update({'is_online': false})
              .eq('user_id', _currentUserId!)
              .timeout(const Duration(seconds: 10));
              
          return {'success': true, 'message': 'You are now offline'};
        } catch (e) {
          print('Error going offline: $e');
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
}
