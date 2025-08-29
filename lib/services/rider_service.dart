import 'package:supabase_flutter/supabase_flutter.dart';

class RiderService {
  static final RiderService _instance = RiderService._internal();
  factory RiderService() => _instance;
  RiderService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Store the current user ID from custom authentication
  String? _currentUserId;
  
  // Set the current user ID (called after login)
  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  // Get current user ID
  String? get currentUserId => _currentUserId;

  // Get rider profile
  Future<Map<String, dynamic>?> getRiderProfile() async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        print('Error: currentUserId is null');
        return null;
      }

      print('Fetching rider profile for user ID: $userId');

      final response = await _supabase
          .from('riders')
          .select('''
            *,
            users!inner(
              name,
              email
            )
          ''')
          .eq('user_id', userId)
          .single();

      print('Rider profile found: $response');
      return response;
    } catch (e) {
      print('Error fetching rider profile: $e');
      print('Error details: ${e.toString()}');
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
      print('Creating rider profile for user ID: $targetUserId');
      
      if (targetUserId == null) {
        print('Error: User ID is null');
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

      print('Rider data to insert: $riderData');

      final response = await _supabase
          .from('riders')
          .upsert(riderData, onConflict: 'user_id');

      print('Rider profile created successfully: $response');
      return true;
    } catch (e) {
      print('Error creating rider profile: $e');
      print('Error details: ${e.toString()}');
      return false;
    }
  }

  // Update online status
  Future<bool> updateOnlineStatus(bool isOnline) async {
    try {
      final userId = currentUserId;
      if (userId == null) return false;

      print('Updating online status for user ID: $userId to: $isOnline');

      await _supabase
          .from('riders')
          .update({
            'is_online': isOnline,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId);

      print('Online status updated successfully');
      return true;
    } catch (e) {
      print('Error updating online status: $e');
      print('Error details: ${e.toString()}');
      return false;
    }
  }

  // Get dashboard data
  Future<Map<String, dynamic>?> getDashboardData({DateTime? date}) async {
    try {
      final userId = currentUserId;
      if (userId == null) return null;

      print('Fetching dashboard data for user ID: $userId');

      // Get rider profile
      final riderProfile = await getRiderProfile();
      if (riderProfile == null) {
        print('No rider profile found');
        return {
          'today_earnings': 0.0,
          'total_orders': 0,
          'available_orders': 0,
          'rider_level': 1,
          'rider_rating': 0.0,
        };
      }

      // Get today's earnings
      final targetDate = date ?? DateTime.now();
      final dateString = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

      final earningsResponse = await _supabase
          .from('rider_earnings')
          .select('total_earnings')
          .eq('rider_id', riderProfile['id'])
          .eq('delivery_date', dateString);

      double todayEarnings = 0.0;
      int totalOrders = 0;
      if (earningsResponse.isNotEmpty) {
        for (var earning in earningsResponse) {
          todayEarnings += (earning['total_earnings'] ?? 0.0);
          totalOrders++;
        }
      }

      // Get available orders count
      final availableOrdersResponse = await _supabase
          .from('orders')
          .select('id')
          .eq('status', 'ready')
          .filter('rider_id', 'is', null);

      final availableOrders = availableOrdersResponse.length;

      print('Dashboard data fetched successfully');
      return {
        'today_earnings': todayEarnings,
        'total_orders': totalOrders,
        'available_orders': availableOrders,
        'rider_level': riderProfile['level'] ?? 1,
        'rider_rating': riderProfile['rating'] ?? 0.0,
      };
    } catch (e) {
      print('Error fetching dashboard data: $e');
      print('Error details: ${e.toString()}');
      return {
        'today_earnings': 0.0,
        'total_orders': 0,
        'available_orders': 0,
        'rider_level': 1,
        'rider_rating': 0.0,
      };
    }
  }

  // Get recent transactions/earnings
  Future<List<Map<String, dynamic>>> getRecentTransactions({int limit = 10}) async {
    try {
      final userId = currentUserId;
      if (userId == null) return [];

      final response = await _supabase
          .from('rider_earnings')
          .select('''
            *,
            orders!inner(
              id,
              status,
              created_at,
              estimated_distance
            )
          ''')
          .eq('rider_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching recent transactions: $e');
      return [];
    }
  }

  // Get available orders
  Future<List<Map<String, dynamic>>> getAvailableOrders() async {
    try {
      print('Fetching available orders...');
      
      final response = await _supabase
          .from('orders')
          .select('*')
          .eq('status', 'ready')
          .filter('rider_id', 'is', null)
          .order('created_at', ascending: true);

      print('Available orders response: $response');
      print('Number of available orders: ${response.length}');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching available orders: $e');
      print('Error details: ${e.toString()}');
      return [];
    }
  }

  // Accept an order
  Future<bool> acceptOrder(String orderId) async {
    try {
      final userId = currentUserId;
      if (userId == null) return false;

      // Get rider ID
      final riderProfile = await getRiderProfile();
      if (riderProfile == null) return false;

      // Update order with rider assignment
      await _supabase
          .from('orders')
          .update({
            'rider_id': riderProfile['id'],
            'status': 'picked_up',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .eq('status', 'ready');

      return true;
    } catch (e) {
      print('Error accepting order: $e');
      return false;
    }
  }

  // Complete delivery
  Future<bool> completeDelivery(String orderId, double tipAmount) async {
    try {
      final userId = currentUserId;
      if (userId == null) return false;

      final riderProfile = await getRiderProfile();
      if (riderProfile == null) return false;

      // Update order status
      await _supabase
          .from('orders')
          .update({
            'status': 'delivered',
            'tip_amount': tipAmount,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .eq('rider_id', riderProfile['id']);

      // Calculate earnings (you can adjust the formula)
      final orderResponse = await _supabase
          .from('orders')
          .select('delivery_fee, total_amount')
          .eq('id', orderId)
          .single();

      final baseEarnings = orderResponse['delivery_fee'] ?? 5.0; // Default delivery fee
      final totalEarnings = baseEarnings + tipAmount;

      // Record earnings
      await _supabase.from('rider_earnings').insert({
        'rider_id': riderProfile['id'],
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
            'total_deliveries': riderProfile['total_deliveries'] + 1,
            'total_earnings': riderProfile['total_earnings'] + totalEarnings,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', riderProfile['id']);

      return true;
    } catch (e) {
      print('Error completing delivery: $e');
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
      print('Error fetching order details: $e');
      return null;
    }
  }

  // Update rider location
  Future<bool> updateLocation(double latitude, double longitude) async {
    try {
      final userId = currentUserId;
      if (userId == null) return false;

      await _supabase.rpc('update_rider_location', params: {
        'p_user_id': userId,
        'p_latitude': latitude,
        'p_longitude': longitude,
      });

      return true;
    } catch (e) {
      print('Error updating location: $e');
      return false;
    }
  }

  // Get assigned orders
  Future<List<Map<String, dynamic>>> getAssignedOrders() async {
    try {
      final userId = currentUserId;
      if (userId == null) return [];
      
      final response = await _supabase
          .from('orders')
          .select()
          .eq('rider_id', userId)
          .eq('status', 'assigned')
          .order('created_at', ascending: false);
          
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting assigned orders: $e');
      return [];
    }
  }

  // Watch assigned orders in real-time
  Stream<List<Map<String, dynamic>>> watchAssignedOrders() {
    final userId = currentUserId;
    if (userId == null) return const Stream.empty();
    
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('rider_id', userId.toString())  // Convert to string to ensure type safety
        .map((data) {
          // Filter for assigned orders in the map function
          final orders = List<Map<String, dynamic>>.from(data);
          return orders.where((order) => order['status'] == 'assigned').toList();
        });
  }
}