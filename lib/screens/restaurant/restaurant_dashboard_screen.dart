import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../core/constants/app_constants.dart';
import 'restaurant_menu_screen.dart';
import '../auth/login_screen.dart';
import '../../services/rider_assignment_service.dart';
import '../../widgets/rider_selection_modal.dart';

class RestaurantDashboardScreen extends StatefulWidget {
  final String? userId;
  const RestaurantDashboardScreen({super.key, this.userId});

  @override
  State<RestaurantDashboardScreen> createState() => _RestaurantDashboardScreenState();
}

class _RestaurantDashboardScreenState extends State<RestaurantDashboardScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
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

  // Helper method to safely access context
  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // Helper method to show location error messages with optional action
  void _showLocationErrorSnackBar(
      String message, {
        SnackBarAction? action,
        Duration duration = const Duration(seconds: 5),
      }) {
    if (!mounted) return;

    final snackBar = SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      duration: duration,
      action: action,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
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
    if (!mounted) return;

    print('DEBUG: Fetching orders for restaurant: $_restaurantId');
    if (_restaurantId == null) {
      print('DEBUG: Restaurant ID is null, trying to get current restaurant');
      await _getCurrentRestaurant();
      if (_restaurantId == null) {
        print('DEBUG: Still no restaurant ID after refresh');
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      print('DEBUG: Executing Supabase query...');
      // Fetch orders for this restaurant directly using merchant_id
      final response = await _supabase
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

  Future<bool> _showRiderSelectionModal(
      BuildContext context,
      String orderId,
      Position restaurantLocation,
      ) async {
    final riderService = RiderAssignmentService();
    List<Map<String, dynamic>> availableRiders = [];
    bool isLoading = true;
    String? errorMessage;

    // Show the dialog and wait for a result
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // Load available riders when dialog is shown
          if (isLoading) {
            debugPrint('Loading available riders...');

            // First, debug check for online riders
            riderService.debugGetOnlineRiders().then((onlineRiders) {
              debugPrint('Debug: Found ${onlineRiders.length} online riders in database');
            });

            riderService
                .getAvailableRidersNearby(
              restaurantLocation.latitude,
              restaurantLocation.longitude,
            )
                .then((riders) {
              debugPrint('Found ${riders.length} available riders');

              if (mounted) {
                setState(() {
                  availableRiders = riders;
                  isLoading = false;
                  if (riders.isEmpty) {
                    errorMessage = 'No riders available in your area. Please try again later or contact support.';
                  }
                });
              }
            }).catchError((e) {
              debugPrint('Error loading riders: $e');

              if (mounted) {
                setState(() {
                  isLoading = false;
                  errorMessage = 'Error loading available riders. Please check your internet connection and try again.';
                });
              }
            });

            return AlertDialog(
              title: const Text('Finding Riders'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Searching for available riders near you...',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          // Show rider selection or error message
          return AlertDialog(
            title: const Text('Select a Rider'),
            content: SizedBox(
              width: double.maxFinite,
              child: errorMessage != null
                  ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    errorMessage!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (errorMessage!.contains('No riders available'))
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          isLoading = true;
                          errorMessage = null;
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                ],
              )
                  : availableRiders.isEmpty
                  ? const Text('No riders available in your area.')
                  : ListView.builder(
                shrinkWrap: true,
                itemCount: availableRiders.length,
                itemBuilder: (context, index) {
                  final rider = availableRiders[index];
                  final distance = Geolocator.distanceBetween(
                    restaurantLocation.latitude,
                    restaurantLocation.longitude,
                    (rider['latitude'] as num?)?.toDouble() ?? 0.0,
                    (rider['longitude'] as num?)?.toDouble() ?? 0.0,
                  );

                  String distanceText = '';
                  if (distance > 1000) {
                    distanceText = '${(distance / 1000).toStringAsFixed(1)} km';
                  } else {
                    distanceText = '${distance.toStringAsFixed(0)} m';
                  }

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
                        child: Icon(
                          Icons.delivery_dining,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      title: Text(
                        rider['name'] ?? 'Rider ${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${rider['vehicle_type'] ?? 'Bike'} • $distanceText away',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (rider['is_online'] == true)
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Text(
                                  'Online',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      onTap: () async {
                        // Show confirmation dialog
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Confirm Assignment'),
                            content: Text(
                              'Assign this order to ${rider['name'] ?? 'the selected rider'}?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('CANCEL'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('ASSIGN'),
                              ),
                            ],
                          ),
                        );

                        if (confirm != true) return;

                        // Show loading indicator
                        final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                        final overlaySize = overlay.size;

                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => Center(
                            child: Container(
                              width: overlaySize.width * 0.7,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Assigning rider...',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        try {
                          // Assign the selected rider
                          final success = await riderService
                              .assignSpecificRiderToOrder(orderId, rider['id']);

                          if (mounted) {
                            Navigator.of(context).pop(); // Close loading dialog

                            if (success) {
                              // Show success message and close the rider selection dialog
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Order assigned to ${rider['name'] ?? 'rider'}'
                                        ' (${rider['vehicle_type'] ?? 'Bike'})',
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                              // Close the rider selection dialog with success
                              Navigator.of(context).pop(true);
                              // Refresh orders to show updated status
                              _fetchOrders();
                            } else {
                              // Show error message but keep the dialog open
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to assign rider. Please try again.'),
                                  backgroundColor: Colors.red,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          debugPrint('Error assigning rider: $e');
                          if (mounted) {
                            Navigator.of(context).pop(); // Close loading dialog
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('An error occurred. Please try again.'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 3),
                                action: SnackBarAction(
                                  label: 'RETRY',
                                  textColor: Colors.white,
                                  onPressed: () {
                                    // Retry assignment
                                    Navigator.of(context).pop(false);
                                    _showRiderSelectionModal(context, orderId, restaurantLocation);
                                  },
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('CANCEL'),
              ),
              if (availableRiders.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      isLoading = true;
                      errorMessage = null;
                    });
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('REFRESH'),
                ),
            ],
          );
        },
      ),
    );

    // Return the result of the dialog (true if rider was assigned, false otherwise)
    return result ?? false;
  }

  Future<void> _updateOrderStatus(int index) async {
    final orderList = _getOrdersByStatus(_selectedStatus);
    if (index >= orderList.length) return;

    final order = orderList[index];
    final orderId = order['id'].toString();
    final currentStatus = order['status'];
    String newStatus = currentStatus;
    bool shouldUpdateStatus = true;

    setState(() => _isLoading = true);

    try {
      // Handle different status transitions
      if (currentStatus == 'pending') {
        // Pending -> Preparing
        newStatus = 'preparing';
      } else if (currentStatus == 'preparing') {
        // Preparing -> Ready (with rider assignment)
        try {
          // Get the restaurant's location - this will try to get the current location first
          final riderService = RiderAssignmentService();
          debugPrint('Attempting to get restaurant location...');
          final position = await riderService.getRestaurantLocation(_restaurantId!);

          debugPrint('Using restaurant location: ${position.latitude}, ${position.longitude}');

          // Show rider selection modal for 'preparing' -> 'ready' transition
          newStatus = 'ready';
          final riderAssigned = await _showRiderSelectionModal(
            context,
            orderId,
            position,
          );

          if (!riderAssigned) {
            // If no rider was assigned, keep status as 'preparing'
            newStatus = 'preparing';
            shouldUpdateStatus = false; // Don't update status if no rider was assigned
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Order status remains "Preparing" as no rider was assigned.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        } on LocationServiceDisabledException {
          debugPrint('Location services are disabled');
          if (mounted) {
            _showLocationErrorSnackBar(
              'Location services are disabled. Please enable location services in your device settings to find nearby riders.',
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            );
          }
          return;
        } on PermissionDeniedException {
          debugPrint('Location permission denied');
          if (mounted) {
            _showLocationErrorSnackBar(
              'Location permission is required to find nearby riders. Please grant location permissions in app settings.',
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: () => Geolocator.openAppSettings(),
              ),
            );
          }
          return;
        } on TimeoutException {
          debugPrint('Location request timed out');
          if (mounted) {
            _showLocationErrorSnackBar(
              'Location request timed out. Please check your internet connection and try again.',
            );
          }
          return;
        } catch (e) {
          debugPrint('Error getting location: $e');
          if (mounted) {
            _showLocationErrorSnackBar(
              'Could not determine your location. Please try again or check your internet connection.',
            );
          }
          return;
        }
      } else if (currentStatus == 'ready') {
        newStatus = 'completed';
      }

      // Only update status if it has changed and we should update it
      if (shouldUpdateStatus && newStatus != currentStatus) {
        debugPrint('Updating order $orderId status from $currentStatus to $newStatus');

        try {
          final response = await _supabase
              .from('orders')
              .update({
            'status': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
              .eq('id', orderId)
              .select();

          debugPrint('Update response: $response');

          if (response.isEmpty) {
            throw Exception('No data returned from server');
          }

          // Refresh the orders list
          _fetchOrders();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Order status updated to: ${_getStatusDisplayName(newStatus)}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          debugPrint('Error updating order status: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to update order status: ${e.toString()}'),
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
    } catch (e) {
      debugPrint('Error in _updateOrderStatus: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
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
    if (mounted) {
      setState(() {
        _selectedStatus = status;
      });
    }
  }

  List<Map<String, dynamic>> _getOrdersByStatus(String status) {
    if (!mounted) return [];

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
              isHistory ? Icons.history : Icons.receipt_long_outlined,
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
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          itemCount: orderList.length,
          itemBuilder: (context, index) {
            final order = orderList[index];
            final statusColor = _getStatusColor(order['status']);

            return Container(
              margin: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
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
                  onTap: () => _showOrderDetails(order),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row - Order ID and quick stats
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left side - Food Order ID
                              Expanded(
                                child: Text(
                                  'Order #${order['id'].toString().substring(0, 8)}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Right side - Items count and time
                              IntrinsicWidth(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${order['items']?.length ?? 0} items',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey[700],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '•',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        _formatTimeAgo(DateTime.parse(order['created_at'])),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Bottom row - Customer name and total amount
                        Row(
                          children: [
                            // Left side - Customer name
                            Expanded(
                              flex: 3,
                              child: Text(
                                order['customer']?.toString() ?? 'Unknown Customer',
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
                        // Status and action button
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            // Status indicator
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
                            // Action button
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
                                onPressed: () => order['status'] == 'completed'
                                    ? _showOrderDetails(order)
                                    : _updateOrderStatus(index),
                                child: Text(
                                  order['status'] == 'completed'
                                      ? 'Order Details'
                                      : _nextStatusLabel(order['status']),
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
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
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
    if (!mounted) return const SizedBox.shrink();

    return Scaffold(
      key: GlobalKey<ScaffoldState>(),
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
        child: RefreshIndicator(
          onRefresh: _fetchOrders,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                  _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryColor))
                      : _buildOrdersList(
                    _getOrdersByStatus(_selectedStatus),
                    _selectedStatus == 'completed',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: !mounted ? null : Builder(
        builder: (ctx) => Padding(
          padding: const EdgeInsets.only(bottom: 86.0),
          child: FloatingActionButton(
            onPressed: () {
              if (_restaurantId == null) {
                _showSnackBar('Restaurant ID not found. Please try again.');
                return;
              }
              Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (context) => RestaurantMenuScreen(userId: _restaurantId!),
                ),
              );
            },
            backgroundColor: AppConstants.primaryColor,
            child: const Icon(Icons.restaurant, color: Colors.white, size: 28),
            tooltip: 'Add Food Item',
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }
}