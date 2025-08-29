import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/rider_location_service.dart';
import '../../services/rider_service.dart';
import '../../core/constants/app_constants.dart';

class RiderDashboardScreen extends StatefulWidget {
  final String? userId;
  const RiderDashboardScreen({super.key, this.userId});

  @override
  State<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends State<RiderDashboardScreen> {
  final RiderLocationService _locationService = RiderLocationService();
  final RiderService _riderService = RiderService();
  
  // State variables
  bool _isOnline = false;
  bool _isLoading = false;
  bool _isLocationTracking = false;
  String _riderName = 'Loading...';
  String _riderLevel = 'Bronze';
  double _todayEarnings = 0.0;
  int _availableOrders = 0;
  List<Map<String, dynamic>> _recentTransactions = [];
  int _currentIndex = 0;
  final List<Map<String, dynamic>> _assignedOrders = [];

  StreamSubscription? _ordersSubscription;
  StreamSubscription? _locationSubscription;
  
  @override
  void initState() {
    super.initState();
    _setCurrentUserId();
    _loadRiderData();
    _loadDashboardData();
    _setupOrdersSubscription();
  }
  
  @override
  void dispose() {
    _locationSubscription?.cancel();
    _ordersSubscription?.cancel();
    super.dispose();
  }
  
  void _setupOrdersSubscription() {
    _ordersSubscription?.cancel();
    _assignedOrders.clear(); // Clear existing orders
    
    _ordersSubscription = _riderService.watchAssignedOrders().listen((orders) {
      if (mounted) {
        setState(() {
          _assignedOrders.clear();
          _assignedOrders.addAll(orders);
        });
      }
    }, onError: (error) {
      print('Error in orders subscription: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading orders: $error')),
        );
      }
    });
  }
  
  Future<void> _setCurrentUserId() async {
    try {
      // First, try to use the user ID passed from the widget
      if (widget.userId != null) {
        _locationService.setCurrentUserId(widget.userId!);
        _riderService.setCurrentUserId(widget.userId!);
        print('Set current user ID from widget: ${widget.userId}');
        return;
      }
      
      // Fallback to RiderService
      final currentUserId = _riderService.currentUserId;
      if (currentUserId != null) {
        _locationService.setCurrentUserId(currentUserId);
        print('Set current user ID from RiderService: $currentUserId');
      } else {
        print('No authenticated user found in RiderService');
        // Try to get from Supabase as fallback
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          _locationService.setCurrentUserId(user.id);
          _riderService.setCurrentUserId(user.id);
          print('Set current user ID from Supabase: ${user.id}');
        } else {
          print('No authenticated user found in Supabase either');
        }
      }
    } catch (e) {
      print('Error setting current user ID: $e');
    }
  }

  Future<void> _loadRiderData() async {
    try {
      final riderData = await _riderService.getRiderProfile();
      if (mounted) {
        setState(() {
          _riderName = riderData?['users']?['name'] ?? 'Rider';
          _riderLevel = riderData?['level']?.toString() ?? 'Bronze';
          _isOnline = riderData?['is_online'] ?? false;
          _isLocationTracking = _isOnline;
        });
      }
    } catch (e) {
      print('Error loading rider data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load rider data')),
        );
      }
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      // Load rider profile
      final riderData = await _riderService.getRiderProfile();
      if (mounted) {
        setState(() {
          _riderName = riderData?['users']?['name'] ?? 'Rider';
          _riderLevel = riderData?['level']?.toString() ?? 'Bronze';
          _isOnline = riderData?['is_online'] ?? false;
          _isLocationTracking = _isOnline;
        });
      }

      // Load dashboard data
      final dashboardData = await _riderService.getDashboardData();
      if (mounted) {
        setState(() {
          _todayEarnings = (dashboardData?['today_earnings'] ?? 0).toDouble();
          _availableOrders = dashboardData?['available_orders'] ?? 0;
          _recentTransactions = List<Map<String, dynamic>>.from(dashboardData?['recent_transactions'] ?? []);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load dashboard data: $e')),
        );
      }
    }
  }


  // Build assigned orders list with real-time updates
  Widget _buildAssignedOrders() {
    if (_assignedOrders.isEmpty) {
      return const Card(
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: Text('No assigned orders')),
        ),
      );
    }
    
    return _buildOrdersList(_assignedOrders);
  }

  Widget _buildErrorCard(String error) {
    return Card(
      elevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(15)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return const Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(15)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> orders) {
    return Card(
      elevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assigned Orders',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            orders.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.0),
                    child: Text(
                      'No assigned orders',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return _buildOrderCard(order);
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleOnlineStatus(bool value) async {
    if (_isOnline == value) return;
    setState(() => _isLoading = true);

    try {
      // If going online, check location permissions first
      if (value) {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied || 
            permission == LocationPermission.deniedForever) {
          // Show permission request dialog
          final shouldRequest = await _showLocationPermissionDialog();
          if (!shouldRequest) {
            setState(() => _isLoading = false);
            return;
          }
        }
      }

      final result = await _locationService.setOnlineStatus(value);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? (result['success'] ? 'Status updated' : 'Failed to update status')),
            backgroundColor: result['success'] == true ? Colors.green : Colors.red,
          ),
        );

        setState(() {
          _isOnline = result['success'] == true ? value : _isOnline;
          _isLocationTracking = result['success'] == true ? value : _isLocationTracking;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _showLocationPermissionDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
            'To go online and receive delivery requests, this app needs access to your location. '
            'Please grant location permission to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Grant Permission'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  // Build the dashboard body
  Widget _buildDashboardBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () async {
        // Only refresh dashboard data since orders are handled by the stream
        await _loadDashboardData();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderCard(),
            const SizedBox(height: 20),
            _buildStatusCard(),
            const SizedBox(height: 20),
            _buildAssignedOrders(),
            const SizedBox(height: 20),
            _buildQuickActions(),
            const SizedBox(height: 20),
            _buildRecentTransactions(),
          ],
        ),
      ),
    );
  }

  // Build header card with rider info
  Widget _buildHeaderCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  child: Icon(Icons.person, size: 30),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _riderName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _riderLevel,
                        style: TextStyle(
                          color: Colors.orange[800],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Today\'s Earnings',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${_todayEarnings.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build status card with toggle
  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delivery Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isOnline ? 'Online' : 'Offline',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isOnline ? 'Ready to accept orders' : 'Not available for delivery',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _isOnline,
                  onChanged: _isLoading ? null : _toggleOnlineStatus,
                  activeColor: Colors.green,
                ),
              ],
            ),
            if (_isLocationTracking) ...[  
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    'Location tracking active',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Build quick actions section
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.delivery_dining,
                label: 'Available Orders',
                onTap: _showAvailableOrders,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.history,
                label: 'Order History',
                onTap: () {
                  // Navigate to order history
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.settings,
                label: 'Settings',
                onTap: () {
                  // Navigate to settings
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Build a single action button
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: Colors.blue),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // Build recent transactions section
  Widget _buildRecentTransactions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Transactions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (_recentTransactions.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text('No recent transactions'),
            ),
          )
        else
          ..._recentTransactions.map((transaction) => _buildTransactionCard(transaction)),
      ],
    );
  }

  // Build a single transaction card
  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.delivery_dining, color: Colors.blue),
        ),
        title: Text(
          transaction['description'] ?? 'Delivery',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          transaction['date'] ?? '',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text(
          '\$${transaction['amount']?.toStringAsFixed(2) ?? '0.00'}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
      ),
    );
  }

  // Show available orders
  Future<void> _showAvailableOrders() async {
    try {
      final orders = await _riderService.getAvailableOrders();
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Available Orders'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: orders.isEmpty
                  ? const Center(
                      child: Text(
                        'No available orders',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: orders.length,
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return _buildOrderCard(order);
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading orders: $e')),
        );
      }
    }
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final customer = order['customers'] as Map<String, dynamic>? ?? {};
    final merchant = order['merchants'] as Map<String, dynamic>? ?? {};
    final orderItems = order['order_items'] as List<dynamic>? ?? [];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order #${order['id'].toString().substring(0, 8)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '\$${order['total_amount'].toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppConstants.primaryColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('From: ${merchant['name'] ?? 'Unknown Restaurant'}', style: const TextStyle(fontSize: 14)),
          Text('To: ${customer['name'] ?? 'Customer'}', style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          Text('Items: ${orderItems.length}', style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _acceptOrder(order['id']),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Accept Order'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      final success = await _riderService.acceptOrder(orderId);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order accepted successfully!'), backgroundColor: Colors.green),
          );
          Navigator.pop(context, true); // Return true to indicate order was accepted
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to accept order'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error accepting order'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Dashboard'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _buildDashboardBody(),
    );
  }
} 