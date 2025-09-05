import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class RiderService {
  static final RiderService _instance = RiderService._internal();

  factory RiderService() => _instance;

  RiderService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  String? _currentUserId;

  // Set the current user ID (called after login)
  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  // Get current user ID
  String? get currentUserId => _currentUserId;

  // Get rider profile
  Future<Map<String, dynamic>?> getRiderProfile({String? userId}) async {
    final effectiveUserId = userId ?? _supabase.auth.currentUser?.id;
    if (effectiveUserId == null) {
      debugPrint('❌ No user ID provided and no current user is logged in');
      return null;
    }

    debugPrint('🔍 Looking up rider profile for user ID: $effectiveUserId');

    try {
      // First, check if the user exists and has the rider role
      final userResponse = await _supabase
          .from('users')
          .select()
          .eq('id', effectiveUserId)
          .maybeSingle();

      if (userResponse == null) {
        debugPrint('❌ No user found with ID: $effectiveUserId');
        return null;
      }

      debugPrint('👤 User found with role: ${userResponse['role']}');

      // Then check for rider profile in the riders table
      debugPrint('🔍 Querying riders table for user_id: $effectiveUserId');
      final response = await _supabase
          .from('riders')
          .select()
          .eq('user_id', effectiveUserId)
          .maybeSingle();

      if (response != null) {
        debugPrint('✅ Rider profile found for user: $effectiveUserId');
        debugPrint('   Profile data: $response');
      } else {
        debugPrint('⚠️ No rider profile found for user: $effectiveUserId');
        // Check if there are any rider profiles at all
        final allProfiles = await _supabase
            .from('rider_profiles')
            .select('*')
            .limit(1);
        debugPrint(
          '   Total rider profiles in database: ${allProfiles.length}',
        );
      }

      return response;
    } catch (e) {
      debugPrint('❌ Error in getRiderProfile: $e');
      if (e is PostgrestException) {
        debugPrint('   Postgrest error details: ${e.details}');
        debugPrint('   Postgrest error hint: ${e.hint}');
        debugPrint('   Postgrest error code: ${e.code}');
      }
      return null;
    }
  }

  // Create or update rider profile
  Future<bool> createRiderProfile({
    required String vehicleType,
    String? vehicleNumber,
    String? licenseNumber,
    String? userId,
  }) async {
    try {
      final targetUserId = userId ?? currentUserId;
      if (targetUserId == null) {
        debugPrint('Error: User ID is null');
        return false;
      }

      final riderData = {
        'user_id': targetUserId,
        'vehicle_type': vehicleType,
        'vehicle_number': vehicleNumber,
        'license_number': licenseNumber,
        'is_online': false,
        'level': 1,
        'rating': 0.0,
        'total_deliveries': 0,
        'total_earnings': 0.0,
      };

      await _supabase.from('riders').upsert(riderData, onConflict: 'user_id');

      return true;
    } catch (e) {
      debugPrint('Error creating rider profile: $e');
      return false;
    }
  }

  // Update online status
  Future<bool> updateOnlineStatus(bool isOnline) async {
    try {
      final userId = _currentUserId ?? _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ No user ID available for updating online status');
        return false;
      }

      // First get the rider profile to get the rider's ID in the riders table
      final riderProfile = await getRiderProfile(userId: userId);
      if (riderProfile == null) {
        debugPrint('❌ Rider profile not found for user ID: $userId');
        return false;
      }

      final riderId = riderProfile['id'];
      debugPrint(
        '🔄 Updating online status to $isOnline for rider ID: $riderId',
      );

      await _supabase
          .from('riders')
          .update({
            'is_online': isOnline,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', riderId);

      return true;
    } catch (e) {
      debugPrint('❌ Error updating online status: $e');
      if (e is PostgrestException) {
        debugPrint('   Postgrest error details: ${e.details}');
        debugPrint('   Postgrest error hint: ${e.hint}');
        debugPrint('   Postgrest error code: ${e.code}');
      }
      return false;
    }
  }

  // Get available orders
  Future<List<Map<String, dynamic>>> getAvailableOrders() async {
    try {
      final response = await _supabase
          .from('orders')
          .select('*')
          .eq('status', 'ready')
          .filter('rider_id', 'is', null)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching available orders: $e');
      return [];
    }
  }

  /// Accept and mark order as picked up
  Future<bool> acceptAndPickUpOrder(String orderId) async {
    try {
      final userId = _currentUserId ?? _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Error: No user ID available');
        return false;
      }

      // Get rider profile
      final riderProfile = await getRiderProfile(userId: userId);
      if (riderProfile == null) {
        debugPrint('❌ Error: Rider profile not found');
        return false;
      }

      final riderId = riderProfile['id'];

      // Update order status to 'picked_up' and assign rider
      final updateResponse = await _supabase
          .from('orders')
          .update({
            'status': 'picked_up',
            'rider_id': riderId,
            'assigned_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .eq('status', 'ready') // Only update if still ready
          .select();

      if (updateResponse.isEmpty) {
        debugPrint('❌ No order found with status "ready" and ID: $orderId');
        return false;
      }

      // Update rider's availability
      await _supabase
          .from('riders')
          .update({
            'is_available': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', riderId);

      return true;
    } catch (e) {
      debugPrint('❌ Error accepting order: $e');
      if (e is PostgrestException) {
        debugPrint('   Postgrest error details: ${e.details}');
      }
      rethrow;
    }
  }

  /// Mark order as on the way
  Future<bool> markOnTheWay(String orderId) async {
    try {
      final userId = _currentUserId ?? _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Error: No user ID available');
        return false;
      }

      // Get rider profile
      final riderProfile = await getRiderProfile(userId: userId);
      if (riderProfile == null) {
        debugPrint('❌ Error: Rider profile not found');
        return false;
      }

      final riderId = riderProfile['id'];

      // Update order status to 'on_the_way'
      await _supabase
          .from('orders')
          .update({
            'status': 'on_the_way',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .eq('rider_id', riderId) // Only update if assigned to this rider
          .eq('status', 'picked_up'); // Only update if currently picked up

      return true;
    } catch (e) {
      debugPrint('❌ Error updating to on the way: $e');
      if (e is PostgrestException) {
        debugPrint('   Postgrest error details: ${e.details}');
      }
      rethrow;
    }
  }

  /// Watch for active delivery (picked_up or on_the_way)
  Stream<Map<String, dynamic>?> watchActiveDelivery() {
    final userId = _currentUserId ?? _supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('❌ Error: No user ID available');
      return Stream.value(null);
    }

    // For streams, we need to filter in the map function
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('rider_id', userId)
        .map((data) {
          // Filter for active statuses in the map function
          final activeOrders = (data as List)
              .where(
                (order) =>
                    ['picked_up', 'on_the_way'].contains(order['status']),
              )
              .toList();

          // Return the first active order or null if none
          if (activeOrders.isEmpty) return null;
          return Map<String, dynamic>.from(activeOrders.first);
        });
  }

  /// Completes an order and makes the rider available again
  /// Returns true if successful, false otherwise
  Future<bool> completeOrder(String orderId) async {
    try {
      debugPrint(
        '🔄 [completeOrder] Starting order completion for order: $orderId',
      );

      final userId = currentUserId;
      if (userId == null) {
        debugPrint('❌ [completeOrder] Error: No user ID available');
        return false;
      }

      // Get rider profile to verify ownership
      final riderProfile = await getRiderProfile(userId: userId);
      if (riderProfile == null) {
        debugPrint('❌ [completeOrder] Error: Rider profile not found');
        return false;
      }

      final riderId = riderProfile['id'];

      // Update order status to 'delivered'
      await _supabase
          .from('orders')
          .update({
            'status': 'delivered',
            'delivered_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);

      debugPrint('✅ [completeOrder] Successfully marked order as delivered');

      // Make rider available for new orders
      final success = await updateRiderAvailability(riderId, true);
      if (!success) {
        debugPrint('⚠️ [completeOrder] Failed to update rider availability');
        // Continue anyway as the order is already marked as delivered
      }

      debugPrint(
        '✅ [completeOrder] Successfully completed order and updated rider status',
      );
      return true;
    } catch (e) {
      debugPrint('❌ [completeOrder] Error: $e');
      return false;
    }
  }

  /// Updates the rider's availability status
  /// Returns true if successful, false otherwise
  Future<bool> updateRiderAvailability(String riderId, bool isAvailable) async {
    try {
      await _supabase
          .from('riders')
          .update({
            'is_available': isAvailable,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', riderId);

      debugPrint(
        '✅ [updateRiderAvailability] Rider $riderId availability updated to: $isAvailable',
      );
      return true;
    } catch (e) {
      debugPrint(
        '❌ [updateRiderAvailability] Error updating rider availability: $e',
      );
      return false;
    }
  }

  // Accept an order
  Future<bool> acceptOrder(String orderId) async {
    try {
      debugPrint(
        '🔄 [acceptOrder] Starting order acceptance for order: $orderId',
      );

      final userId = currentUserId;
      if (userId == null) {
        debugPrint('❌ [acceptOrder] Error: No user ID available');
        return false;
      }

      debugPrint('🔍 [acceptOrder] Getting rider profile for user ID: $userId');
      final riderProfile = await getRiderProfile(userId: userId);
      if (riderProfile == null) {
        debugPrint(
          '❌ [acceptOrder] Error: No rider profile found for user ID: $userId',
        );
        return false;
      }

      final riderId = riderProfile['id'];
      debugPrint('✅ [acceptOrder] Found rider ID: $riderId');
      debugPrint('🔄 [acceptOrder] Checking order $orderId details...');

      try {
        // First, check if the order exists and get its current status
        final orderCheck = await _supabase
            .from('orders')
            .select('id, status, rider_id')
            .eq('id', orderId)
            .single();

        debugPrint(
          '📋 [acceptOrder] Current order status: ${orderCheck['status']}',
        );
        debugPrint(
          '📋 [acceptOrder] Current rider_id: ${orderCheck['rider_id']}',
        );

        if (orderCheck['rider_id'] != null &&
            orderCheck['rider_id'] != riderId) {
          debugPrint(
            '❌ [acceptOrder] Error: Order $orderId is already assigned to another rider',
          );
          return false;
        }

        debugPrint('🔄 [acceptOrder] Updating order status to "picked_up"...');

        // Update order status to 'picked_up' and assign to rider
        final updateResponse = await _supabase
            .from('orders')
            .update({
              'status': 'picked_up',
              'rider_id': riderId,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', orderId)
            .select()
            .single();

        debugPrint('✅ [acceptOrder] Successfully updated order status');
        debugPrint('   Order details: $updateResponse');

        // Update rider's availability to false (on delivery)
        final success = await updateRiderAvailability(riderId, false);
        if (!success) {
          debugPrint('❌ [acceptOrder] Failed to update rider availability');
          return false;
        }

        debugPrint(
          '✅ [acceptOrder] Successfully accepted order and updated rider status',
        );
        return true;
      } on PostgrestException catch (e) {
        debugPrint('❌ [acceptOrder] Database error: ${e.message}');
        debugPrint('   Details: ${e.details}');
        debugPrint('   Hint: ${e.hint}');
        return false;
      }

      debugPrint('Successfully accepted order $orderId');
      return true;
    } catch (e) {
      debugPrint('Error in acceptOrder: $e');
      if (e is PostgrestException) {
        debugPrint('Postgrest error details: ${e.details}');
        debugPrint('Postgrest error hint: ${e.hint}');
        debugPrint('Postgrest error code: ${e.code}');
      }
      return false;
    }
  }

  // Complete delivery with optional tip amount
  Future<bool> completeDelivery(
    String orderId, [
    double tipAmount = 0.0,
  ]) async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        debugPrint('❌ Error: No user ID available. User must be logged in.');
        return false;
      }

      final riderProfile = await getRiderProfile();
      if (riderProfile == null) {
        debugPrint(
          '❌ Error: Rider profile not found. Make sure you have completed your rider profile.',
        );
        return false;
      }

      final riderId = riderProfile['id'];
      debugPrint('🔁 Completing delivery for order: $orderId, rider: $riderId');

      // First get the order details to ensure it's in a valid state
      final orderResponse = await _supabase
          .from('orders')
          .select('id, status, rider_id, delivery_fee, total_amount')
          .eq('id', orderId)
          .maybeSingle();

      if (orderResponse == null) {
        debugPrint('❌ Order not found with ID: $orderId');
        return false;
      }

      if (orderResponse['rider_id'] != riderId) {
        debugPrint(
          '❌ Order $orderId is assigned to rider ${orderResponse['rider_id']}, not current rider $riderId',
        );
        return false;
      }

      final currentStatus = orderResponse['status'];
      if (currentStatus != 'on_the_way' && currentStatus != 'picked_up') {
        debugPrint(
          '❌ Cannot complete order with status: $currentStatus. Order must be either "on_the_way" or "picked_up"',
        );
        return false;
      }

      // Update order status to completed
      final updateResponse = await _supabase
          .from('orders')
          .update({
            'status': 'completed',
            'tip_amount': tipAmount,
            'delivered_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .eq('rider_id', riderId);

      if (updateResponse.error != null) {
        debugPrint(
          '❌ Database error updating order status: ${updateResponse.error}',
        );
        return false;
      }

      if (updateResponse.data == null || updateResponse.data.isEmpty) {
        debugPrint(
          '❌ No rows were updated. Order $orderId may not exist or rider ID mismatch.',
        );
        return false;
      }

      debugPrint('✅ Order marked as completed');

      // Update rider availability
      await _supabase
          .from('riders')
          .update({
            'is_available': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', riderId);

      debugPrint('✅ Rider marked as available');

      // Calculate earnings - use the orderResponse we already have
      final baseEarnings = orderResponse['delivery_fee'] ?? 5.0;
      final totalEarnings = baseEarnings + tipAmount;

      // Record earnings
      await _supabase.from('rider_earnings').insert({
        'rider_id': riderId,
        'order_id': orderId,
        'base_earnings': baseEarnings,
        'tip_amount': tipAmount,
        'total_earnings': totalEarnings,
        'delivery_date': DateTime.now().toIso8601String().split('T')[0],
      });

      // Update rider stats
      await _supabase
          .from('riders')
          .update({
            'total_deliveries': (riderProfile['total_deliveries'] ?? 0) + 1,
            'total_earnings':
                (riderProfile['total_earnings'] ?? 0) + totalEarnings,
            'is_available': true, // Make sure rider is marked as available
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', riderId);

      return true;
    } catch (e) {
      debugPrint('Error completing delivery: $e');
      return false;
    }
  }

  // Get order details
  Future<Map<String, dynamic>?> getOrderDetails(String orderId) async {
    try {
      final response = await _supabase
          .from('orders')
          .select('''
            *,
            customers:users!orders_customer_id_fkey(
              id,
              name,
              phone,
              address
            ),
            merchants:users!orders_merchant_id_fkey(
              id,
              name,
              address,
              phone
            ),
            order_items(
              *,
              foods(*)
            )
          ''')
          .eq('id', orderId)
          .single();

      return response;
    } catch (e) {
      debugPrint('Error fetching order details: $e');
      return null;
    }
  }

  // Update rider location
  Future<bool> updateLocation(double latitude, double longitude) async {
    try {
      final userId = currentUserId;
      if (userId == null) return false;

      await _supabase.rpc(
        'update_rider_location',
        params: {
          'p_user_id': userId,
          'p_latitude': latitude,
          'p_longitude': longitude,
        },
      );

      return true;
    } catch (e) {
      debugPrint('Error updating location: $e');
      return false;
    }
  }

  // Get assigned orders
  Future<List<Map<String, dynamic>>> getAssignedOrders() async {
    try {
      final userId = _currentUserId ?? _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ No user ID available for getAssignedOrders');
        return [];
      }

      // Get the rider profile to get the rider ID
      final riderProfile = await getRiderProfile(userId: userId);
      if (riderProfile == null) {
        debugPrint('❌ No rider profile found for user ID: $userId');
        return [];
      }

      final riderId = riderProfile['id'];
      debugPrint('🔍 Fetching assigned orders for rider ID: $riderId');

      final response = await _supabase
          .from('orders')
          .select()
          .eq('rider_id', riderId)
          .eq('status', 'picked_up')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error getting assigned orders: $e');
      if (e is PostgrestException) {
        debugPrint('   Postgrest error details: ${e.details}');
        debugPrint('   Postgrest error hint: ${e.hint}');
        debugPrint('   Postgrest error code: ${e.code}');
      }
      return [];
    }
  }

  // Watch assigned orders in real-time
  Stream<List<Map<String, dynamic>>> watchAssignedOrders() {
    final userId = _currentUserId ?? _supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('❌ No user ID available for watchAssignedOrders');
      return const Stream.empty();
    }

    debugPrint('👀 Setting up order stream for user: $userId');
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    // Initial fetch
    _fetchAssignedOrders(userId)
        .then((orders) {
          debugPrint('📥 Initial orders fetched: ${orders.length}');
          if (!controller.isClosed) {
            controller.add(orders);
          } else {
            debugPrint('⚠️ Controller closed before initial fetch completed');
          }
        })
        .catchError((error) {
          debugPrint('❌ Error in initial fetch: $error');
          if (!controller.isClosed) {
            controller.addError(error);
          }
        });

    final channel = _supabase.channel('rider_$userId');

    // Listen for updates
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'orders',
      callback: (payload) async {
        debugPrint('🔄 Received order update: $payload');
        if (payload.newRecord?['rider_id'] == userId) {
          debugPrint('✅ Update is for current rider, refreshing orders...');
          try {
            final orders = await _fetchAssignedOrders(userId);
            if (!controller.isClosed) {
              controller.add(orders);
              debugPrint('✅ Updated orders in stream: ${orders.length} orders');
            } else {
              debugPrint('⚠️ Controller closed when trying to update orders');
            }
          } catch (e) {
            debugPrint('❌ Error in update handler: $e');
            if (!controller.isClosed) {
              controller.addError(e);
            }
          }
        }
      },
    );

    // Listen for new orders
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        debugPrint('🆕 New order inserted: $payload');
        if (payload.newRecord?['rider_id'] == userId) {
          _fetchAssignedOrders(userId).then((orders) {
            if (!controller.isClosed) {
              controller.add(orders);
              debugPrint('✅ Added new order to stream');
            }
          });
        }
      },
    );

    // Handle channel status changes
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            debugPrint('🔌 Order change received: $payload');
            // Refresh orders when changes are detected
            _fetchAssignedOrders(userId).then((orders) {
              if (!controller.isClosed) {
                controller.add(orders);
              }
            });
          },
        )
        .subscribe();

    // Cleanup
    controller.onCancel = () {
      debugPrint('🛑 Closing order stream');
      channel.unsubscribe();
    };

    controller.onListen = () {
      debugPrint('👂 Stream listener added');
    };

    return controller.stream;
  }

  // Helper method to fetch assigned orders
  Future<List<Map<String, dynamic>>> _fetchAssignedOrders(String userId) async {
    try {
      debugPrint(
        '🔍 [RiderService] Fetching active orders for rider ID: $userId',
      );

      // First get the rider profile to get the rider's ID in the riders table
      final riderProfile = await getRiderProfile(userId: userId);
      if (riderProfile == null) {
        debugPrint(
          '❌ [RiderService] No rider profile found for user ID: $userId',
        );
        return [];
      }

      final riderId = riderProfile['id'];
      debugPrint('🔍 [RiderService] Found rider ID in database: $riderId');

      // Get all active orders assigned to this rider (any status except 'completed')
      final response = await _supabase
          .from('orders')
          .select('''
            *,
            users!orders_customer_id_fkey(*),
            merchants:users!orders_merchant_id_fkey(*),
            order_items(*, foods(*))
          ''')
          .eq('rider_id', riderId)
          .neq('status', 'completed')
          .order('created_at', ascending: false);

      debugPrint(
        '✅ [RiderService] Found ${response.length} active orders for rider $userId',
      );
      if (response.isNotEmpty) {
        debugPrint('📋 [RiderService] First order details: ${response.first}');
      } else {
        debugPrint(
          'ℹ️ [RiderService] No active orders found for rider $userId',
        );
      }
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error fetching assigned orders: $e');
      rethrow;
    }
  }

  // Get dashboard data
  Future<Map<String, dynamic>> getDashboardData() async {
    try {
      final userId = _currentUserId ?? _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ No user ID available for getDashboardData');
        throw Exception('User not logged in');
      }

      // Get the rider profile to get the rider ID
      final riderProfile = await getRiderProfile(userId: userId);
      if (riderProfile == null) {
        debugPrint('❌ No rider profile found for user ID: $userId');
        throw Exception('Rider profile not found');
      }

      // Get today's date string in YYYY-MM-DD format
      final today = DateTime.now().toIso8601String().split('T')[0];

      // Get dashboard data using the database function
      final response = await _supabase
          .rpc(
            'get_rider_dashboard_data',
            params: {
              'rider_user_id': riderProfile['user_id'],
              'target_date': today,
            },
          )
          .single();

      return {
        'today_earnings':
            (response['today_earnings'] as num?)?.toDouble() ?? 0.0,
        'total_orders': response['total_orders'] ?? 0,
        'available_orders': response['available_orders'] ?? 0,
        'rider_level': response['rider_level'] ?? 1,
        'rider_rating': (response['rider_rating'] as num?)?.toDouble() ?? 0.0,
      };
    } catch (e) {
      debugPrint('Error getting dashboard data: $e');
      // Return default values in case of error
      return {
        'today_earnings': 0.0,
        'total_orders': 0,
        'available_orders': 0,
        'rider_level': 1,
        'rider_rating': 0.0,
      };
    }
  }
}
