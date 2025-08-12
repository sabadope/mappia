import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../core/constants/app_constants.dart';
import 'restaurant_menu_screen.dart';
import '../auth/login_screen.dart';

class RestaurantDashboardScreen extends StatefulWidget {
  final String? userId;
  const RestaurantDashboardScreen({super.key, this.userId});

  @override
  State<RestaurantDashboardScreen> createState() => _RestaurantDashboardScreenState();
}

class _RestaurantDashboardScreenState extends State<RestaurantDashboardScreen> with TickerProviderStateMixin {
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> completedOrders = [];
  bool _isLoading = true;
  String? _restaurantId;
  Timer? _refreshTimer;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _getCurrentRestaurant();
    _fetchOrders();
    // Refresh orders every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchOrders();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentRestaurant() async {
    // Check if userId was passed from login
    if (widget.userId != null) {
      _restaurantId = widget.userId;
      print('DEBUG: Restaurant ID set from widget: $_restaurantId');
      return;
    }
    
    // Fallback to Supabase Auth (for admin users)
    final user = Supabase.instance.client.auth.currentUser;
    print('DEBUG: Current user: ${user?.id}');
    print('DEBUG: User email: ${user?.email}');
    if (user != null) {
      _restaurantId = user.id;
      print('DEBUG: Restaurant ID set from Supabase Auth: $_restaurantId');
    } else {
      print('DEBUG: No user found!');
    }
  }

  Future<void> _fetchOrders() async {
    print('DEBUG: Fetching orders for restaurant: $_restaurantId');
    if (_restaurantId == null) {
      print('DEBUG: Restaurant ID is null, returning');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      print('DEBUG: Executing Supabase query...');
      // Fetch orders for this restaurant directly using merchant_id
      final response = await Supabase.instance.client
          .from('orders')
          .select('''
            *,
            order_items(
              *,
              foods(
                *
              )
            ),
            users!customer_id(
              name,
              contact
            )
          ''')
          .eq('merchant_id', _restaurantId!)
          .order('created_at', ascending: false);
      
      print('DEBUG: Query response: $response');
      
             // Process orders
       final List<Map<String, dynamic>> processedOrders = [];
       final List<Map<String, dynamic>> processedCompletedOrders = [];
       
       for (final order in response) {
         final orderItems = order['order_items'] as List<dynamic>? ?? [];
         final customer = order['users'] as Map<String, dynamic>? ?? {};
         final items = orderItems.map((item) {
           final food = item['foods'] as Map<String, dynamic>?;
           return food?['name'] ?? 'Unknown Item';
         }).toList();
         
         final orderData = {
           'id': order['id'],
           'customer': customer['name'] ?? 'Unknown Customer',
           'items': items,
           'status': order['status'] ?? 'pending',
           'address': order['delivery_address'] ?? 'No address',
           'total_amount': order['total_amount'] ?? 0.0,
           'created_at': order['created_at'],
         };
         
         // Separate active and completed orders
         if (order['status'] == 'completed') {
           processedCompletedOrders.add(orderData);
         } else {
           processedOrders.add(orderData);
         }
       }
       
       print('DEBUG: Active orders: ${processedOrders.length}');
       print('DEBUG: Completed orders: ${processedCompletedOrders.length}');
       setState(() {
         orders = processedOrders;
         completedOrders = processedCompletedOrders;
         _isLoading = false;
       });
    } catch (e) {
      print('DEBUG: Error fetching orders: $e');
      setState(() => _isLoading = false);
    }
  }

  final Map<String, Color> statusColors = {
    'pending': AppConstants.warningColor,
    'preparing': AppConstants.secondaryColor,
    'ready': AppConstants.successColor,
    'completed': Colors.grey,
  };

  Future<void> _updateOrderStatus(int index) async {
    final order = orders[index];
    final currentStatus = order['status'];
    String newStatus = currentStatus;
    
    if (currentStatus == 'pending') {
      newStatus = 'preparing';
    } else if (currentStatus == 'preparing') {
      newStatus = 'ready';
    } else if (currentStatus == 'ready') {
      newStatus = 'completed';
    }
    
    try {
      await Supabase.instance.client
          .from('orders')
          .update({'status': newStatus})
          .eq('id', order['id']);
      
      // Refresh orders to get updated data
      _fetchOrders();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order status updated to ${newStatus.toUpperCase()}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating order status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _nextStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Start Preparing';
      case 'preparing':
        return 'Mark as Ready';
      case 'ready':
        return 'Complete Order';
      default:
        return '';
    }
  }

  String _formatDate(DateTime date) {
    // Convert UTC time to Philippines time (UTC+8)
    // Since the database stores UTC time, we need to add 8 hours for Philippines time
    final philippinesTime = date.add(const Duration(hours: 8));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(philippinesTime.year, philippinesTime.month, philippinesTime.day);
    
    if (dateOnly == today) {
      return 'Today, ${philippinesTime.hour}:${philippinesTime.minute.toString().padLeft(2, '0')}';
    } else if (dateOnly == yesterday) {
      return 'Yesterday, ${philippinesTime.hour}:${philippinesTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${philippinesTime.month}/${philippinesTime.day}, ${philippinesTime.hour}:${philippinesTime.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> orderList, bool isHistory) {
    if (orderList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isHistory ? Icons.history : Icons.receipt_long,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              isHistory ? 'No completed orders yet' : 'No active orders',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              isHistory 
                ? 'Completed orders will appear here'
                : 'Orders will appear here when customers place them',
              style: TextStyle(color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchOrders,
      color: AppConstants.primaryColor,
      child: ListView.builder(
        itemCount: orderList.length,
        itemBuilder: (context, index) {
          final order = orderList[index];
          return Card(
            color: AppConstants.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge)),
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.paddingLarge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Order #${order['id']}',
                          style: AppConstants.subheadingStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(order['status'].toString().toUpperCase()),
                        backgroundColor: statusColors[order['status']]?.withOpacity(0.15),
                        labelStyle: TextStyle(
                          color: statusColors[order['status']] ?? AppConstants.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Customer: ${order['customer']}', style: AppConstants.bodyStyle),
                  Text('Address: ${order['address']}', style: AppConstants.bodyStyle),
                  const SizedBox(height: 4),
                  Text(
                    'Ordered: ${_formatDate(DateTime.parse(order['created_at']))}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text('Items: ${order['items'].join(", ")}', style: AppConstants.bodyStyle),
                  const SizedBox(height: 8),
                  // Price breakdown
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal:', style: TextStyle(fontSize: 14)),
                      Text(
                        'SAR ${((order['total_amount'] ?? 0.0) - 3.0).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Delivery Fee:', style: TextStyle(fontSize: 14)),
                      const Text('SAR 3.00', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                  const Divider(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'SAR ${(order['total_amount'] ?? 0.0).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  if (!isHistory && order['status'] != 'completed') ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: AppConstants.primaryButton,
                        onPressed: () => _updateOrderStatus(index),
                        child: Text(_nextStatusLabel(order['status'])),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
             appBar: AppBar(
         title: const Text('Restaurant Dashboard'),
         backgroundColor: AppConstants.primaryColor,
         foregroundColor: AppConstants.textOnPrimary,
         elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              // TODO: Implement notifications functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notifications coming soon!'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
          ),
        ],
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order statistics
              Row(
                children: [
                  Expanded(
                    child: Card(
                      color: AppConstants.primaryColor.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              orders.where((o) => o['status'] == 'pending').length.toString(),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.primaryColor,
                              ),
                            ),
                            const Text('Pending', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      color: AppConstants.secondaryColor.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              orders.where((o) => o['status'] == 'preparing').length.toString(),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.secondaryColor,
                              ),
                            ),
                            const Text('Preparing', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      color: AppConstants.successColor.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              orders.where((o) => o['status'] == 'ready').length.toString(),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.successColor,
                              ),
                            ),
                            const Text('Ready', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tab bar for orders
              Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppConstants.primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey[600],
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.pending_actions, size: 16),
                          const SizedBox(width: 4),
                          Text('Active Orders (${orders.length})'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.history, size: 16),
                          const SizedBox(width: 4),
                          Text('Order History (${completedOrders.length})'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryColor))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          // Active Orders Tab
                          _buildOrdersList(orders, false),
                          // Order History Tab
                          _buildOrdersList(completedOrders, true),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 