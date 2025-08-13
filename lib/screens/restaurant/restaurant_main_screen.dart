import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../core/constants/app_constants.dart';
import 'restaurant_dashboard_screen.dart';
import 'restaurant_menu_screen.dart';
import '../auth/login_screen.dart';

class RestaurantMainScreen extends StatefulWidget {
  final int initialTabIndex;
  final String? userId;
  
  const RestaurantMainScreen({super.key, this.initialTabIndex = 0, this.userId});

  @override
  State<RestaurantMainScreen> createState() => _RestaurantMainScreenState();
}

class _RestaurantMainScreenState extends State<RestaurantMainScreen> {
  late int _currentIndex;
  String? _userId;

  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _userId = widget.userId;
    _initializeScreens();
  }

  void _initializeScreens() {
    _screens.clear();
    _screens.addAll([
      RestaurantDashboardScreen(userId: _userId),
      const _ReportsScreen(),
      const _OrdersScreen(),
      const _SettingsScreen(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main content (all screens)
          Positioned.fill(
            child: _screens[_currentIndex],
          ),
          // Floating bottom navigation bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.all(8),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: BottomNavigationBar(
                    currentIndex: _currentIndex,
                    onTap: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    type: BottomNavigationBarType.fixed,
                    backgroundColor: Colors.white,
                    selectedItemColor: AppConstants.primaryColor,
                    unselectedItemColor: Colors.grey,
                    selectedLabelStyle: const TextStyle(fontSize: 0),
                    unselectedLabelStyle: const TextStyle(fontSize: 0),
                    elevation: 0,
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.dashboard),
                        label: '',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.assessment),
                        label: '',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.receipt_long),
                        label: '',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.settings),
                        label: '',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Orders Screen (dedicated orders view)
class _OrdersScreen extends StatefulWidget {
  const _OrdersScreen();

  @override
  State<_OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<_OrdersScreen> with TickerProviderStateMixin {
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
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _restaurantId = user.id;
    }
  }

  Future<void> _fetchOrders() async {
    if (_restaurantId == null) return;
    
    setState(() => _isLoading = true);
    try {
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
        
        if (order['status'] == 'completed') {
          processedCompletedOrders.add(orderData);
        } else {
          processedOrders.add(orderData);
        }
      }
      
      setState(() {
        orders = processedOrders;
        completedOrders = processedCompletedOrders;
        _isLoading = false;
      });
    } catch (e) {
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
        padding: const EdgeInsets.all(16),
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
        title: const Text('Orders'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: AppConstants.textOnPrimary,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Tab bar for orders
            Container(
              height: 50,
              margin: const EdgeInsets.all(16),
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
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryColor))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOrdersList(orders, false),
                        _buildOrdersList(completedOrders, true),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Reports Screen (restaurant analytics and reports)
class _ReportsScreen extends StatefulWidget {
  const _ReportsScreen();

  @override
  State<_ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<_ReportsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: AppConstants.textOnPrimary,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Restaurant Analytics',
                style: AppConstants.headingStyle,
              ),
              const SizedBox(height: 24),
              
              // Sales Overview Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppConstants.primaryColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.trending_up, color: Colors.white),
                          const SizedBox(width: 12),
                          Text(
                            'Sales Overview',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      'SAR 0.00',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: AppConstants.primaryColor,
                                      ),
                                    ),
                                    Text('Today\'s Sales', style: TextStyle(color: Colors.grey[600])),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      '0',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: AppConstants.secondaryColor,
                                      ),
                                    ),
                                    Text('Orders Today', style: TextStyle(color: Colors.grey[600])),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Performance Metrics Card
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.assessment, color: AppConstants.primaryColor),
                      title: Text('Performance Metrics', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('View detailed performance data'),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Detailed analytics coming soon!'),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.history, color: AppConstants.primaryColor),
                      title: Text('Order History', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('View past orders and trends'),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Order history analytics coming soon!'),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.people, color: AppConstants.primaryColor),
                      title: Text('Customer Insights', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Analyze customer behavior'),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Customer insights coming soon!'),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Quick Actions Card
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.download, color: AppConstants.primaryColor),
                      title: Text('Export Reports', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Download reports in various formats'),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Report export functionality coming soon!'),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.schedule, color: AppConstants.primaryColor),
                      title: Text('Scheduled Reports', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Set up automated report delivery'),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Scheduled reports coming soon!'),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      },
                    ),
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

// Settings Screen
class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen();

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  // Floating notification state
  bool _showNotification = false;
  String _notificationMessage = '';
  Timer? _notificationTimer;

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  // Show floating notification
  void _showFloatingNotification(String message, {String type = 'success'}) {
    setState(() {
      _notificationMessage = message;
      _notificationType = type;
      _showNotification = true;
    });
    // Auto-dismiss after 3 seconds
    _notificationTimer?.cancel();
    _notificationTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showNotification = false;
        });
      }
    });
  }

  String _notificationType = 'success';

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'success':
        return Colors.green;
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.amber[800]!;
      case 'info':
        return Colors.blue;
      default:
        return AppConstants.primaryColor;
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'success':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      case 'warning':
        return Icons.warning;
      case 'info':
        return Icons.info;
      default:
        return Icons.info;
    }
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _performLogout(context);
              },
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _performLogout(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
        _showFloatingNotification('Logged out successfully!', type: 'success');
      }
    } catch (e) {
      if (context.mounted) {
        _showFloatingNotification('Error logging out: ${e.toString()}', type: 'error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            backgroundColor: AppConstants.primaryColor,
            foregroundColor: AppConstants.textOnPrimary,
            elevation: 0,
          ),
          backgroundColor: AppConstants.backgroundColor,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Restaurant Settings',
                    style: AppConstants.headingStyle,
                  ),
                  const SizedBox(height: 24),
                  
                  // Restaurant Profile Card
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppConstants.primaryColor,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                          ),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          child: Row(
                            children: [
                              Icon(Icons.restaurant, color: Colors.white),
                              const SizedBox(width: 12),
                              Text(
                                'Restaurant Profile',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            children: [
                              ListTile(
                                leading: Icon(Icons.business, color: AppConstants.primaryColor),
                                title: Text('Restaurant Information', style: TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('Update restaurant details'),
                                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                                onTap: () {
                                  _showFloatingNotification('Restaurant profile management coming soon!', type: 'info');
                                },
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: Icon(Icons.location_on, color: AppConstants.primaryColor),
                                title: Text('Delivery Settings', style: TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('Manage delivery areas and fees'),
                                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                                onTap: () {
                                  _showFloatingNotification('Delivery settings coming soon!', type: 'info');
                                },
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: Icon(Icons.schedule, color: AppConstants.primaryColor),
                                title: Text('Operating Hours', style: TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('Set restaurant hours'),
                                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                                onTap: () {
                                  _showFloatingNotification('Operating hours management coming soon!', type: 'info');
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // System Settings Card
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.notifications, color: AppConstants.primaryColor),
                          title: Text('Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Manage notification preferences'),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                          onTap: () {
                            _showFloatingNotification('Notification settings coming soon!', type: 'info');
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.security, color: AppConstants.primaryColor),
                          title: Text('Security', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Manage security settings'),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                          onTap: () {
                            _showFloatingNotification('Security settings coming soon!', type: 'info');
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.help, color: AppConstants.primaryColor),
                          title: Text('Help & Support', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Get help and contact support'),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                          onTap: () {
                            _showFloatingNotification('Help & support coming soon!', type: 'info');
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.logout, color: Colors.red),
                          title: Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                          subtitle: Text('Sign out of restaurant account'),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.red),
                          onTap: () => _showLogoutConfirmation(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Floating notification
        if (_showNotification)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              color: _getNotificationColor(_notificationType),
              child: Row(
                children: [
                  Icon(_getNotificationIcon(_notificationType), color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _notificationMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _showNotification = false;
                      });
                    },
                    icon: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
} 