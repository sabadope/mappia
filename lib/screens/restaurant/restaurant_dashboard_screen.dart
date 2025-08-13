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

class _RestaurantDashboardScreenState extends State<RestaurantDashboardScreen> {
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> completedOrders = [];
  bool _isLoading = true;
  String? _restaurantId;
  Timer? _refreshTimer;

  // New state for 2x2 grid navigation
  String _selectedStatus = 'pending'; // Default to pending

  @override
  void initState() {
    super.initState();

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
    super.dispose();
  }

  Future<void> _getCurrentRestaurant() async {
    // Check if userId was passed from dashboard
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
    final orderList = _getOrdersByStatus(_selectedStatus);
    if (index >= orderList.length) return;

    final order = orderList[index];
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

  void _selectStatus(String status) {
    setState(() {
      _selectedStatus = status;
    });
  }

  List<Map<String, dynamic>> _getOrdersByStatus(String status) {
    switch (status) {
      case 'pending':
        return orders.where((o) => o['status'] == 'pending').toList();
      case 'preparing':
        return orders.where((o) => o['status'] == 'preparing').toList();
      case 'ready':
        return orders.where((o) => o['status'] == 'ready').toList();
      case 'completed':
        return completedOrders;
      default:
        return [];
    }
  }

  String _getStatusDisplayName(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'preparing':
        return 'Serving';
      case 'ready':
        return 'Ready';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.blue;
      case 'preparing':
        return Colors.red;
      case 'ready':
        return const Color(0xFFD4A900); // Muted yellow
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
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
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: orderList.length,
        itemBuilder: (context, index) {
          final order = orderList[index];
          final statusColor = _getStatusColor(order['status']);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: statusColor.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  _showOrderDetails(order);
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row - Order ID and quick stats
                      Row(
                        children: [
                          // Left side - Food Order ID
                          Expanded(
                            flex: 3,
                            child: Text(
'Order #${order['id'].toString().substring(0, 8)}...',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Right side - Items count and time
                          Expanded(
                            flex: 2,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '${order['items'].length} items',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '• ${_formatTimeAgo(DateTime.parse(order['created_at']))}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Bottom row - Customer name and total amount
                      Row(
                        children: [
                          // Left side - Customer name
                          Expanded(
                            flex: 3,
                            child: Text(
                              order['customer'] ?? 'Unknown Customer',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Right side - Total amount
                          Expanded(
                            flex: 2,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
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
                          ),
                        ],
                      ),

                      // Action button row
                      if (order['status'] == 'completed') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            // Status indicator on the left
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Status text
                            Text(
                              order['status'].toString().toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            // Details button (same layout as other phases)
                            Container(
                              height: 36,
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () => _showOrderDetails(order),
                                child: const Text(
                                  'Order Details',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            // Status indicator on the left
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Status text
                            Text(
                              order['status'].toString().toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            // Action button (search bar style)
                            Container(
                              height: 36,
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () => _updateOrderStatus(index),
                                child: Text(
                                  _nextStatusLabel(order['status']),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _getActionIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.play_arrow;
      case 'preparing':
        return Icons.check;
      case 'ready':
        return Icons.done;
      default:
        return Icons.arrow_forward;
    }
  }

  String _formatTimeAgo(DateTime orderTime) {
    final now = DateTime.now();
    final difference = now.difference(orderTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final statusColor = _getStatusColor(order['status']);
        final items = (order['items'] as List<dynamic>? ?? []).cast<String>();
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Order Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(order['status'].toString().toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('SAR ${(order['total_amount'] ?? 0.0).toStringAsFixed(2)}', style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Order #${order['id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Customer: ${order['customer'] ?? 'Unknown'}'),
                Text('Address: ${order['address'] ?? 'N/A'}'),
                const SizedBox(height: 12),
                if (items.isNotEmpty) ...[
                  const Text('Items', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...items.map((name) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Text('• '),
                            Expanded(child: Text(name)),
                          ],
                        ),
                      )),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBox(String status, String title, Color color, IconData icon) {
    final isSelected = _selectedStatus == status;
    final orderCount = _getOrdersByStatus(status).length;

    return Expanded(
      child: GestureDetector(
        onTap: () => _selectStatus(status),
        child: Container(
          margin: const EdgeInsets.all(4),
          height: 50,
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.15) : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Icon on the left
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(
                  icon,
                  size: 20,
                  color: color,
                ),
              ),
              // Text in the middle
              Expanded(
                child: Center(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? color : Colors.grey[700],
                    ),
                  ),
                ),
              ),
              // Count on the right
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  '(${orderCount})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
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
              // 2x2 Status Grid
              Container(
                height: 120,
                child: Column(
                  children: [
                    // Upper row
                    Expanded(
                      child: Row(
                        children: [
                          _buildStatusBox('pending', 'Pending', Colors.blue, Icons.pending_actions),
                          _buildStatusBox('preparing', 'Serving', Colors.red, Icons.restaurant),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Lower row
                    Expanded(
                      child: Row(
                        children: [
                          _buildStatusBox('ready', 'Ready', const Color(0xFFD4A900), Icons.check_circle),
                          _buildStatusBox('completed', 'Completed', Colors.green, Icons.done_all),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Status Title
              Row(
                children: [
                  Text(
                    '${_getStatusDisplayName(_selectedStatus)} Orders',
                    style: AppConstants.subheadingStyle.copyWith(
                      color: _getStatusColor(_selectedStatus),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_getOrdersByStatus(_selectedStatus).length} orders',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Orders List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryColor))
                    : _buildOrdersList(
                  _getOrdersByStatus(_selectedStatus),
                  _selectedStatus == 'completed',
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 86.0), // Move FAB above the bottom nav
        child: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RestaurantMenuScreen(userId: _restaurantId),
              ),
            );
          },
          backgroundColor: AppConstants.primaryColor,
          child: const Icon(Icons.restaurant, color: Colors.white, size: 28),
          tooltip: 'Add Food Item',
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }
}