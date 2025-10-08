import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class LocationUpdateService {
  static final LocationUpdateService _instance = LocationUpdateService._internal();
  factory LocationUpdateService() => _instance;
  LocationUpdateService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionSubscription;
  String? _currentOrderId;
  bool _isTracking = false;

  // Start tracking and sending location updates
  void startTracking(String orderId) {
    if (_isTracking && _currentOrderId == orderId) return;

    _currentOrderId = orderId;
    _isTracking = true;

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((Position position) {
      _updateRiderLocation(position);
    });
  }

  // Stop tracking location
  void stopTracking() {
    _positionSubscription?.cancel();
    _isTracking = false;
    _currentOrderId = null;
  }

  // Update rider's location in the database
  Future<void> _updateRiderLocation(Position position) async {
    try {
      await _supabase.rpc('update_rider_location', params: {
        'p_order_id': _currentOrderId,
        'p_lat': position.latitude,
        'p_lng': position.longitude,
      });
    } catch (e) {
      debugPrint('Error updating rider location: $e');
    }
  }

  // Get current rider location for an order
  Future<Map<String, double>?> getRiderLocation(String orderId) async {
    try {
      final response = await _supabase
          .from('rider_locations')
          .select('ST_Y(location::geometry) as lat, ST_X(location::geometry) as lng')
          .eq('order_id', orderId)
          .single();

      return {
        'lat': response['lat'] as double,
        'lng': response['lng'] as double,
      };
    } catch (e) {
      debugPrint('Error getting rider location: $e');
      return null;
    }
  }

  // Clean up
  void dispose() {
    stopTracking();
  }
}
