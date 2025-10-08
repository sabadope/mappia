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
import '../auth/login_screen.dart';

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
  List<Map<String, dynamic>> _completedOrders = [];
  int _selectedIndex = 0;
  final List<Map<String, dynamic>> _assignedOrders = [];

  StreamSubscription? _ordersSubscription;
  StreamSubscription? _locationSubscription;

  StreamSubscription? _orderCompletedSubscription;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
    // Add a listener to handle when the app returns to the foreground
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRiderStatus();
    });

    // Listen for order completion events
    _orderCompletedSubscription = _riderService.onOrderCompleted.listen((orderId) {
      debugPrint('🔄 Order $orderId completed, refreshing dashboard...');
      _loadDashboardData();
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
    _orderCompletedSubscription?.cancel();
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
          final shouldRefresh = await Navigator.of(context).pushReplacement<bool, bool>(
            MaterialPageRoute<bool>(
              builder: (context) => DeliveryScreen(order: order, wasOnline: _isOnline),
            ),
          ) ?? false;

          // Refresh dashboard if we returned from a completed delivery
          if (shouldRefresh && mounted) {
            await _loadDashboardData();
          }
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
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('🔄 Loading dashboard data...');

      // Load rider profile, dashboard data, and completed orders separately
      final results = await Future.wait([
        _riderService.getRiderProfile(),
        _riderService.getDashboardData(),
        _fetchCompletedOrders(), // Fetch completed orders directly
      ]);

      final riderData = results[0] as Map<String, dynamic>?;
      final dashboardData = results[1] as Map<String, dynamic>?;
      final completedOrders = results[2] as List<Map<String, dynamic>>;

      if (!mounted) return;

      debugPrint('📊 Dashboard data loaded:');
      debugPrint('   - Today\'s earnings: ${dashboardData?['today_earnings'] ?? 0}');
      debugPrint('   - Available orders: ${dashboardData?['available_orders'] ?? 0}');
      debugPrint('   - Recent transactions: ${dashboardData?['recent_transactions']?.length ?? 0}');
      debugPrint('   - Completed orders: ${completedOrders.length}');

      if (completedOrders.isNotEmpty) {
        debugPrint('   - First completed order ID: ${completedOrders.first['id']}');
      }

      // Update state with new data
      setState(() {
        // Update rider profile
        _riderName = riderData?['users']?['name'] ?? 'Rider';
        _riderLevel = riderData?['level']?.toString() ?? 'Bronze';
        _isOnline = riderData?['is_online'] ?? false;
        _isLocationTracking = _isOnline;

        // Update dashboard data
        _todayEarnings = (dashboardData?['today_earnings'] ?? 0).toDouble();
        _availableOrders = dashboardData?['available_orders'] ?? 0;
        _completedOrders = completedOrders;
      });

      debugPrint('✅ Dashboard data updated successfully');
    } catch (e) {
      debugPrint('❌ Error loading dashboard data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load dashboard data. Pull to refresh.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
    Widget content = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 16),
          _buildStatusCard(),
          const SizedBox(height: 24),
          _buildAssignedOrders(),
          const SizedBox(height: 24),
          _buildCompletedOrders(),
          const SizedBox(height: 24),
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: () async {
        await _loadDashboardData();
        // Small delay to show the refresh indicator
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : content,
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

  // Build completed orders section
  Widget _buildCompletedOrders() {
    debugPrint('🔄 Building completed orders section. Found ${_completedOrders.length} orders');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Completed Orders',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_completedOrders.isNotEmpty)
              Text(
                '${_completedOrders.length} orders',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoading && _completedOrders.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (_completedOrders.isEmpty)
          const Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: Text('No completed orders')),
            ),
          )
        else
          ..._completedOrders.map((order) {
            debugPrint('📦 Order ${order['id']} - Status: ${order['status']} - Completed at: ${order['completed_at']}');
            return _buildCompletedOrderCard(order);
          }).toList(),
      ],
    );
  }

  // Build completed order card
  Widget _buildCompletedOrderCard(Map<String, dynamic> order) {
    final orderId = order['id']?.toString().substring(0, 8) ?? 'N/A';
    final total = order['total_amount']?.toStringAsFixed(2) ?? '0.00';
    final completedAt = order['completed_at'] != null
        ? DateTime.parse(order['completed_at']).toLocal().toString().substring(0, 16)
        : 'N/A';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green),
        title: Text('Order #$orderId'),
        subtitle: Text('Completed: $completedAt'),
        trailing: Text('\$$total', style: const TextStyle(fontWeight: FontWeight.bold)),
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
          _availableOrders = _assignedOrders.length;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order picked up successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          // Navigate to delivery screen and wait for result
          final shouldRefresh = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (context) => DeliveryScreen(order: updatedOrder, wasOnline: _isOnline),
            ),
          ) ?? false;

          // Refresh dashboard if we returned from a completed delivery
          if (shouldRefresh && mounted) {
            await _loadDashboardData();
          }

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

  void _onNavigationItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildCurrentPage() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardBody();
      case 1:
        return _buildOngoingOrdersPage();
      case 2:
        return _buildProfilePage();
      default:
        return _buildDashboardBody();
    }
  }

  Widget _buildOngoingOrdersPage() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchOngoingOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final ongoingOrders = snapshot.data ?? [];

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {}); // Trigger rebuild to refetch
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ongoing Orders',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (ongoingOrders.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.delivery_dining,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No ongoing orders',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...ongoingOrders.map((order) => _buildOngoingOrderCard(order)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchOngoingOrders() async {
    try {
      final riderId = await _riderService.getCurrentRiderId();
      if (riderId == null) return [];

      // Fetch orders that are picked_up (ongoing delivery)
      final response = await Supabase.instance.client
          .from('orders')
          .select('''
            *,
            users:customer_id(name, contact),
            merchants:merchant_id(name),
            order_items(
              *,
              foods(name, price)
            )
          ''')
          .eq('rider_id', riderId)
          .eq('status', 'picked_up')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error fetching ongoing orders: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCompletedOrders() async {
    try {
      final riderId = await _riderService.getCurrentRiderId();
      if (riderId == null) {
        debugPrint('❌ No rider ID available for fetching completed orders');
        return [];
      }

      debugPrint('🔍 Fetching completed orders for rider ID: $riderId');

      // Fetch orders that are completed
      final response = await Supabase.instance.client
          .from('orders')
          .select('''
            *,
            users:customer_id(name, contact),
            merchants:merchant_id(name),
            order_items(
              *,
              foods(name, price)
            )
          ''')
          .eq('rider_id', riderId)
          .eq('status', 'completed')
          .order('completed_at', ascending: false)
          .limit(10); // Limit to last 10 completed orders

      final orders = List<Map<String, dynamic>>.from(response);
      debugPrint('✅ Fetched ${orders.length} completed orders');

      return orders;
    } catch (e) {
      debugPrint('❌ Error fetching completed orders: $e');
      return [];
    }
  }

  Widget _buildOngoingOrderCard(Map<String, dynamic> order) {
    final customer = order['users'] ?? {};
    final merchant = order['merchants'] ?? {};
    final orderItems = order['order_items'] ?? [];
    final total = _calculateOrderTotal(order);

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () async {
          // Navigate to delivery screen
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DeliveryScreen(order: order, wasOnline: _isOnline),
            ),
          );

          // Refresh data when returning from delivery screen
          if (result == true && mounted) {
            setState(() {}); // Trigger rebuild to refetch ongoing orders
            await _loadDashboardData();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.delivery_dining,
                          color: AppConstants.primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #${order['id']?.toString().substring(0, 8) ?? 'N/A'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'IN DELIVERY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[600]),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    customer['name'] ?? 'Unknown Customer',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.restaurant, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    merchant['name'] ?? 'Unknown Merchant',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.shopping_bag, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    '${orderItems.length} ${orderItems.length == 1 ? 'item' : 'items'}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Amount:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'SAR ${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfilePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: AppConstants.primaryColor,
                  child: const Icon(
                    Icons.person,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _riderName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _riderLevel,
                    style: TextStyle(
                      color: Colors.orange[800],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.monetization_on, color: Colors.green),
                  title: const Text('Total Earnings'),
                  trailing: Text(
                    '\$${_todayEarnings.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delivery_dining, color: Colors.blue),
                  title: const Text('Completed Orders'),
                  trailing: Text(
                    '${_completedOrders.length}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    _isOnline ? Icons.online_prediction : Icons.offline_bolt,
                    color: _isOnline ? Colors.green : Colors.grey,
                  ),
                  title: const Text('Status'),
                  trailing: Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isOnline ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Settings'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    // TODO: Navigate to settings
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help & Support'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    // TODO: Navigate to help
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),
                  onTap: () async {
                    final shouldLogout = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Logout'),
                        content: const Text('Are you sure you want to log out?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text(
                              'Okay',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (shouldLogout == true && mounted) {
                      await Supabase.instance.client.auth.signOut();
                      if (mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = 'Rider Dashboard';
    if (_selectedIndex == 1) {
      appBarTitle = 'Ongoing Orders';
    } else if (_selectedIndex == 2) {
      appBarTitle = 'Profile';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _buildCurrentPage(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavigationItemTapped,
        selectedItemColor: AppConstants.primaryColor,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.delivery_dining),
            label: 'Ongoing Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
