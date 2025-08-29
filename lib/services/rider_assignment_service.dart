import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/material.dart';

class RiderAssignmentService {
  static final RiderAssignmentService _instance = RiderAssignmentService._internal();
  factory RiderAssignmentService() => _instance;
  RiderAssignmentService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final double _maxDistanceKm = 5.0; // Maximum distance in kilometers

  /// Gets available riders near the specified location
  /// 
  /// [latitude] - The latitude of the location to search around
  /// [longitude] - The longitude of the location to search around
  /// Returns a list of riders sorted by distance (nearest first)
  Future<List<Map<String, dynamic>>> getAvailableRidersNearby(
      double latitude, double longitude) async {
    try {
      debugPrint('Finding available riders near: $latitude, $longitude');
      
      // Validate input coordinates
      if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        debugPrint('Invalid coordinates provided: $latitude, $longitude');
        return [];
      }
      
      // Try to find riders using the PostGIS spatial query
      final riders = await _findAvailableRiders(latitude, longitude);
      
      // Log the result
      if (riders.isEmpty) {
        debugPrint('No available riders found within ${_maxDistanceKm}km');
      } else {
        debugPrint('Found ${riders.length} available riders within ${_maxDistanceKm}km');
      }
      
      return riders;
      
    } catch (e) {
      debugPrint('Error in getAvailableRidersNearby: $e');
      // In production, you might want to log this error to a monitoring service
      return [];
    }
  }
  
  // Assign a specific rider to an order
  Future<bool> assignSpecificRiderToOrder(String orderId, String riderId) async {
    return await _assignOrderToRider(orderId, riderId);
  }

  // Find available riders using PostGIS spatial query
  Future<List<Map<String, dynamic>>> _findAvailableRiders(double latitude, double longitude) async {
    try {
      debugPrint('Searching for riders near: $latitude, $longitude');
      
      // Format the restaurant's location as a PostGIS point (SRID=4326;POINT(longitude latitude))
      final restaurantPoint = 'SRID=4326;POINT($longitude $latitude)';
      
      // Call the PostGIS function to find nearby riders
      final response = await _supabase.rpc('find_nearby_riders', params: {
        'p_restaurant_point': restaurantPoint,
        'p_max_distance': _maxDistanceKm * 1000, // Convert km to meters
        'p_limit': 20 // Increased limit to ensure we get enough riders after filtering
      });
      
      if (response == null) {
        debugPrint('No riders found in the database');
        return [];
      }
      
      final ridersList = response as List;
      debugPrint('Found ${ridersList.length} riders from database');
      
      // Process and validate riders
      final availableRiders = <Map<String, dynamic>>[];
      
      for (final rider in ridersList) {
        try {
          // Extract location from the new format with separate lat/lng fields
          final lat = rider['latitude']?.toDouble();
          final lng = rider['longitude']?.toDouble();
          
          // Skip if we couldn't get the location
          if (lat == null || lng == null) {
            debugPrint('Skipping rider ${rider['id']} - missing latitude or longitude');
            continue;
          }
          
          // Calculate distance in meters
          final distanceInMeters = Geolocator.distanceBetween(
            latitude,
            longitude,
            lat,
            lng,
          );
          
          // Skip if rider is too far (shouldn't happen due to PostGIS query, but good to double-check)
          if (distanceInMeters > (_maxDistanceKm * 1000)) {
            debugPrint('Skipping rider ${rider['id']} - too far away: ${distanceInMeters.toStringAsFixed(0)}m');
            continue;
          }
          
          // Add rider to available riders
          availableRiders.add({
            'id': rider['id'],
            'user_id': rider['user_id'],
            'name': rider['name'] ?? 'Rider ${rider['user_id']?.toString().substring(0, 6) ?? ''}',
            'phone': rider['phone'] ?? '',
            'email': rider['email'] ?? '',
            'latitude': lat,
            'longitude': lng,
            'distance': distanceInMeters,
            'vehicle_type': rider['vehicle_type']?.toString().toLowerCase() ?? 'bike',
            'is_online': rider['is_online'] ?? false,
          });
          
          debugPrint('Added rider ${rider['id']} - ${distanceInMeters.toStringAsFixed(0)}m away');
          
        } catch (e) {
          debugPrint('Error processing rider ${rider['id']}: $e');
        }
      }
      
      // Sort by distance (nearest first)
      availableRiders.sort((a, b) {
        final distanceA = (a['distance'] as num).toDouble();
        final distanceB = (b['distance'] as num).toDouble();
        return distanceA.compareTo(distanceB);
      });
      
      debugPrint('Found ${availableRiders.length} available riders with valid locations');
      return availableRiders;
    } catch (e) {
      debugPrint('Error finding available riders: $e');
      return [];
    }
  }
  
  /// Gets the restaurant's location from the users table
  /// Throws an exception if the location is not set
  /// Updates the restaurant's location in the database
  /// Returns true if successful, false otherwise
  Future<bool> updateRestaurantLocation({
    required String userId,
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      debugPrint('Updating restaurant location for user: $userId');
      final supabase = Supabase.instance.client;
      
      // First, check if the user is authenticated
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null || currentUser.id != userId) {
        debugPrint('User not authenticated or user ID mismatch');
        debugPrint('Current user: ${currentUser?.id}, Requested user: $userId');
        return false;
      }
      
      // Prepare the data to upsert
      final locationData = {
        'user_id': userId,
        'latitude': latitude,
        'longitude': longitude,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (address != null) {
        locationData['address'] = address;
      }
      
      debugPrint('Upserting location data: $locationData');
      
      // First try to update existing restaurant location
      final response = await supabase
          .from('restaurant_locations')
          .upsert(
            locationData,
            onConflict: 'user_id'
          );
          
      if (response.error != null) {
        debugPrint('Error updating restaurant location: ${response.error?.message}');
        
        // If the error is about RLS, try to insert with the correct user context
        if (response.error?.message?.contains('row-level security') == true) {
          debugPrint('RLS violation detected, trying with RPC...');
          return await _updateRestaurantLocationWithRpc(
            userId: userId,
            latitude: latitude,
            longitude: longitude,
            address: address,
          );
        }
        
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error in updateRestaurantLocation: $e');
      return false;
    }
  }

  /// Gets the restaurant's location from the users table
  /// Throws an exception if the location is not set
  /// Gets the current device's location
  /// Throws an exception if location services are disabled or permissions are denied
  Future<Position> getCurrentLocation() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      // Check if location services are enabled
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location services are disabled
        throw Exception('Location services are disabled. Please enable location services in your device settings.');
      }

      // Check location permissions
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Request permission if not granted
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are required to find nearby riders. Please grant location permissions in app settings.');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        // Permissions are denied forever
        throw Exception(
          'Location permissions are permanently denied. ' 
          'Please enable location permissions for this app in your device settings to find nearby riders.'
        );
      }

      // Get the current position with timeout
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('Error in getCurrentLocation: $e');
      rethrow; // Re-throw to let the caller handle the error
    }
  }

  /// Gets the restaurant's location from the database
  /// If not set, tries to get the current device location and save it
  Future<Position> getRestaurantLocation(String restaurantId) async {
    final supabase = Supabase.instance.client;
    
    try {
      // First try to get the saved restaurant location from the database
      final response = await supabase
          .from('restaurant_locations')
          .select('latitude, longitude')
          .eq('user_id', restaurantId)
          .maybeSingle();

      if (response != null && response['latitude'] != null && response['longitude'] != null) {
        return Position(
          latitude: (response['latitude'] as num).toDouble(),
          longitude: (response['longitude'] as num).toDouble(),
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      }
      
      // If no saved location, get current device location
      final position = await getCurrentLocation();
      debugPrint('Got current device location: ${position.latitude}, ${position.longitude}');
      
      // Try to get address from coordinates
      String? address;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude, 
          position.longitude
        ).timeout(const Duration(seconds: 5));
        
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          address = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
            place.postalCode,
            place.country
          ].where((s) => s?.isNotEmpty ?? false).join(', ');
        }
      } catch (e) {
        debugPrint('Error getting address from coordinates: $e');
      }
      
      // Save the location to the database
      await updateRestaurantLocation(
        userId: restaurantId,
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
      );
      
      return position;
      
    } catch (e) {
      debugPrint('Error in getRestaurantLocation: $e');
      rethrow; // Re-throw the exception to be handled by the caller
    }
  }

  // Assign an order to a rider
  Future<bool> _assignOrderToRider(String orderId, String riderId) async {
    try {
      if (orderId.isEmpty || riderId.isEmpty) {
        debugPrint('Invalid orderId or riderId');
        return false;
      }
      
      debugPrint('Assigning order $orderId to rider $riderId');
      
      // First, check if the order exists and is in the correct status
      final orderCheck = await _supabase
          .from('orders')
          .select('id, status, rider_id')
          .eq('id', orderId)
          .single();
      
      debugPrint('Order check result: $orderCheck');
      
      if (orderCheck == null) {
        debugPrint('Order not found: $orderId');
        return false;
      }
      
      if (orderCheck['rider_id'] != null) {
        debugPrint('Order already has a rider assigned: ${orderCheck['rider_id']}');
        return false;
      }
      
      if (orderCheck['status'] != 'ready' && orderCheck['status'] != 'preparing') {
        debugPrint('Order status is not ready for assignment: ${orderCheck['status']}');
        return false;
      }
      
      // Also check if the rider exists and is online
      final riderCheck = await _supabase
          .from('riders')
          .select('id, is_online')
          .eq('id', riderId)
          .single();
      
      debugPrint('Rider check result: $riderCheck');
      
      if (riderCheck == null) {
        debugPrint('Rider not found: $riderId');
        return false;
      }
      
      if (riderCheck['is_online'] != true) {
        debugPrint('Rider is not online: $riderId');
        return false;
      }
      
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('orders')
          .update({
            'rider_id': riderId,
            'status': 'assigned',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .select()
          .single();

      if (response == null) {
        debugPrint('Failed to assign order: No response from server');
        return false;
      }
      
      debugPrint('Successfully assigned order $orderId to rider $riderId');
      
      // Here you might want to add push notification to the rider
      // await _sendNotificationToRider(riderId, orderId);
      
      return true;
    } catch (e) {
      debugPrint('Error in _assignOrderToRider: $e');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error details: ${e.toString()}');
      return false;
    }
  }

  // Helper method to update restaurant location using RPC to bypass RLS if needed
  Future<bool> _updateRestaurantLocationWithRpc({
    required String userId,
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      debugPrint('Calling RPC to update restaurant location');
      
      final response = await _supabase.rpc('update_restaurant_location', params: {
        'p_user_id': userId,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_address': address,
      });
      
      debugPrint('RPC response: $response');
      return true;
    } catch (e) {
      debugPrint('Error in _updateRestaurantLocationWithRpc: $e');
      return false;
    }
  }
  
  // Helper method to calculate distance between two points in kilometers
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000.0;
  }
  
  // Debug method to check online riders
  Future<List<Map<String, dynamic>>> debugGetOnlineRiders() async {
    try {
      debugPrint('Checking for online riders in database...');
      
      final response = await _supabase
          .from('riders')
          .select('''
            id,
            user_id,
            is_online,
            current_location,
            vehicle_type,
            users!inner(
              name,
              email
            )
          ''')
          .eq('is_online', true);
      
      final riders = List<Map<String, dynamic>>.from(response);
      debugPrint('Found ${riders.length} online riders in database');
      
      for (final rider in riders) {
        debugPrint('Rider: ${rider['users']['name']} - Online: ${rider['is_online']} - Location: ${rider['current_location']}');
      }
      
      return riders;
    } catch (e) {
      debugPrint('Error checking online riders: $e');
      return [];
    }
  }
  
  // Future method to get merchant's location (to be implemented)
  // This would involve geocoding the pickup address or having merchants set their location
  Future<Map<String, double>?> _getMerchantLocation(String merchantId) async {
    // Implement geocoding or fetch from merchant profile if available
    return null;
  }
}
