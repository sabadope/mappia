import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'delivery_screen.dart';
import '../../services/rider_location_service.dart';
import '../../services/rider_service.dart';
import '../../core/constants/app_constants.dart';
import 'rider_profile_setup_screen.dart';

class RiderDashboardScreen extends StatefulWidget {
  final String? userId;

  const RiderDashboardScreen({super.key, this.userId});

  @override
  State<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends State<RiderDashboardScreen>
    with WidgetsBindingObserver {
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
    _initializeDashboard();
    // Add a listener to handle when the app returns to the foreground
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRiderStatus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // When the app comes back to the foreground, refresh the status
      _loadRiderStatus();
    }
  }

  Future<void> _initializeDashboard() async {
    try {
      setState(() => _isLoading = true);

      // Use the provided userId from the constructor
      final userId = widget.userId;
      if (userId == null || userId.isEmpty) {
        debugPrint('No user ID provided to RiderDashboardScreen');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication error. Please log in again.'),
            ),
          );
          Navigator.of(context).pop(); // Go back to login
        }
        return;
      }

      // Set the user ID in both services
      _riderService.setCurrentUserId(userId);
      _locationService.setCurrentUserId(userId);
      debugPrint('Initializing dashboard for user ID: $userId');

      // Check if rider profile exists
      final riderProfile = await _riderService.getRiderProfile(userId: userId);
      if (riderProfile == null) {
        debugPrint('No rider profile found for user ID: $userId');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const RiderProfileSetupScreen(),
            ),
          );
        }
        return;
      }

      // If rider profile exists, load data and set up subscriptions
      await _loadRiderData();
      await _loadDashboardData();
      _setupOrdersSubscription();
    } catch (e) {
      debugPrint('Error initializing dashboard: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing dashboard: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _ordersSubscription?.cancel();
    // Remove the lifecycle observer when the widget is disposed
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Add this method to load the rider's current status
  Future<void> _loadRiderStatus() async {
    try {
      final riderData = await _riderService.getRiderProfile();
      if (mounted && riderData != null) {
        final isOnline = riderData['is_online'] ?? false;
        // Only update if the status has changed to avoid unnecessary rebuilds
        if (_isOnline != isOnline) {
          setState(() {
            _isOnline = isOnline;
            _isLocationTracking = isOnline;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading rider status: $e');
    }
  }

  void _setupOrdersSubscription() async {
    try {
      final userId = widget.userId;
      if (userId == null) {
        debugPrint('Cannot set up subscription: No user ID available');
        return;
      }

      final profile = await _riderService.getRiderProfile(userId: userId);
      if (profile == null) {
        debugPrint('Error: Could not load rider profile');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load rider profile')),
          );
        }
        return;
      }

      _ordersSubscription?.cancel();

      // Set up a new subscription to watch for assigned orders with status 'ready'
      _ordersSubscription = _riderService.watchAssignedOrders().listen(
        (orders) {
          if (mounted) {
            setState(() {
              _assignedOrders.clear();
              _assignedOrders.addAll(orders);
              _availableOrders = orders.length;
            });
          }
        },
        onError: (error) {
          debugPrint('Error in orders subscription: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error loading orders. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );

      // Also watch for active deliveries
      _riderService.watchActiveDelivery().listen((order) async {
        if (order != null && mounted) {
          // If there's an active delivery, navigate to delivery screen
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) =>
                  DeliveryScreen(order: order, wasOnline: _isOnline),
            ),
          );
          // When returning from delivery screen, refresh the dashboard
          _loadDashboardData();
        }
      });
    } catch (e) {
      debugPrint('Error in _setupOrdersSubscription: $e');
    }
  }

  Future<void> _setCurrentUserId() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        _riderService.setCurrentUserId(user.id);
        debugPrint('Set current user ID: ${user.id}');
      } else {
        debugPrint('No authenticated user found!');
      }
    } catch (e) {
      debugPrint('Error setting current user ID: $e');
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
          _recentTransactions = List<Map<String, dynamic>>.from(
            dashboardData?['recent_transactions'] ?? [],
          );
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

  Widget _buildStatusContainer({Widget? child, String? message}) {
    return Card(
      elevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(child: child ?? Text(message ?? '')),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      final shouldEnable = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location Services Disabled'),
          content: const Text('Please enable location services to go online.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (shouldEnable == true) {
        await Geolocator.openLocationSettings();
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are required to go online'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Location Permissions Required'),
              content: const Text(
                'Location permissions are permanently denied. Please enable them in app settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open Settings'),
                ),
              ],
            );
          },
        );

        if (openSettings == true) {
          await Geolocator.openAppSettings();
        }
      }
      return false;
    }

    return true;
  }

  Future<void> _toggleOnlineStatus(bool value, {bool force = false}) async {
    if (!force && _isOnline == value) return;

    if (!mounted) return;

    // If trying to go online, check location permissions first
    if (value) {
      bool hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        // If permission was denied, don't proceed with going online
        setState(() => _isLoading = false);
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      // First, ensure we have a valid user ID
      final userId = _riderService.currentUserId;
      if (userId == null || userId.isEmpty) {
        debugPrint('No user ID available');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication error. Please log in again.'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop(); // Go back to login
        }
        return;
      }

      // Update the online status in the backend
      final result = await _locationService.setOnlineStatus(value);
      final success = result['success'] == true;

      if (mounted) {
        if (!success) {
          final errorMessage = result['error'] ?? 'Failed to update status';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage.toString()),
              backgroundColor: Colors.red,
            ),
          );
        }

        // Update the UI state
        setState(() {
          _isOnline = success ? value : _isOnline;
          _isLocationTracking = success ? value : _isLocationTracking;
          _isLoading = false;
        });

        // If going online, ensure location tracking starts
        if (success && value) {
          try {
            await _locationService.startLocationTracking();
          } catch (e) {
            debugPrint('Error starting location tracking: $e');
            // Don't show error to user, just log it
          }
        } else if (success && !value) {
          // If going offline, stop location tracking
          await _locationService.stopLocationTracking();
        }
      }
    } catch (e) {
      debugPrint('Error in _toggleOnlineStatus: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
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
        ) ??
        false;
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                    style: TextStyle(fontSize: 14, color: Colors.grey),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delivery Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                      _isOnline
                          ? 'Ready to accept orders'
                          : 'Not available for delivery',
                      style: const TextStyle(fontSize: 14, color: Colors.green),
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
                    style: TextStyle(fontSize: 14, color: Colors.green),
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
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
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
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
          ..._recentTransactions.map(
            (transaction) => _buildTransactionCard(transaction),
          ),
      ],
    );
  }

  // Build a single transaction card
  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final customer = order['users'] ?? {};
    final merchant = order['merchants'] ?? {};
    final orderItems = order['order_items'] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order #${order['id']}'.substring(0, 8).toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '\$${order['total_amount']?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'From: ${merchant['name'] ?? 'Unknown Restaurant'}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              'To: ${customer['name'] ?? 'Customer'} (${customer['phone'] ?? 'No phone'})',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isOnline ? () => _acceptOrder(order) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isOnline
                      ? AppConstants.primaryColor
                      : Colors.grey,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  _isOnline ? 'Accept Order' : 'Go Online to Accept Orders',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to calculate order total from order items
  double _calculateOrderTotal(Map<String, dynamic> order) {
    double total = 0.0;
    if (order['order_items'] != null && order['order_items'] is List) {
      for (var item in order['order_items']) {
        final food = item['foods'] ?? {};
        final price = (food['price'] ?? 0).toDouble();
        final quantity = (item['quantity'] ?? 1).toInt();
        total += price * quantity;
      }
    }
    return total;
  }

  Future<void> _acceptOrder(Map<String, dynamic> order) async {
    try {
      setState(() => _isLoading = true);

      // Show confirmation dialog
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Accept Order'),
          content: const Text('Do you want to accept and mark this order as picked up?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Accept & Pick Up'),
            ),
          ],
        ),
      );

      if (confirm != true) {
        setState(() => _isLoading = false);
        return;
      }

      // Call the service to accept and mark the order as picked up
      final success = await _riderService.acceptAndPickUpOrder(order['id']);

      if (success && mounted) {
        // Create a copy of the order with updated status
        final updatedOrder = Map<String, dynamic>.from(order);
        updatedOrder['status'] = 'picked_up';
        updatedOrder['picked_up_at'] = DateTime.now().toIso8601String();

        // Update the UI
        setState(() {
          // Remove from assigned orders
          _assignedOrders.removeWhere((o) => o['id'] == order['id']);
          
          // Add to recent transactions
          _recentTransactions.insert(0, {
            'id': order['id'],
            'type': 'pickup',
            'description': 'Order #${order['id']} - Picked Up',
            'amount': _calculateOrderTotal(order),
            'status': 'picked_up',
            'date': DateTime.now().toIso8601String(),
            'order': updatedOrder,
          });
          
          _availableOrders = _assignedOrders.length;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order picked up successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          // Navigate to delivery screen
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DeliveryScreen(order: updatedOrder, wasOnline: _isOnline),
            ),
          );

          // Refresh dashboard data when returning from delivery
          _loadDashboardData();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to pick up order. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error accepting order: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An error occurred. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
