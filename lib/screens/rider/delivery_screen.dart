import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../services/rider_service.dart';
import '../../services/location_service.dart'; // We'll create this later

class DeliveryScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool wasOnline;

  const DeliveryScreen({Key? key, required this.order, required this.wasOnline})
      : super(key: key);

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  @override
  void initState() {
    super.initState();
    _order = widget.order;
    // Initialize with the order's current status
    _currentStatus = _order['status'] ?? 'ready'; // Default to 'ready' if status is not set
    // Ensure the initial status is always set in timestamps
    if (!_statusTimestamps.containsKey(_currentStatus)) {
      _statusTimestamps[_currentStatus] = DateTime.now();
    }
    _initializeLocation();
    _startLocationUpdates();
    // Initial refresh of order status
    _refreshOrderStatus();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Details'),
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading || _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
  final RiderService _riderService = RiderService();
  final LocationService _locationService = LocationService();

  // State variables
  bool _isLoading = false;
  String _currentStatus = 'ready';
  Position? _currentPosition;
  bool _isMapReady = false;

  // Tracking variables
  final Map<String, DateTime> _statusTimestamps = {};
  double? _distanceToDestination;
  Duration? _estimatedTimeRemaining;
  Timer? _locationUpdateTimer;

  // Format for timestamps
  final DateFormat _timeFormat = DateFormat('h:mm a');

  // Order details
  late Map<String, dynamic> _order;

  // Rider delivery steps - only includes statuses relevant to rider workflow
  final List<Map<String, dynamic>> _deliverySteps = [
    {'id': 'ready', 'title': 'Ready for Pickup'},  // First status the rider sees
    {'id': 'picked_up', 'title': 'Picked Up'},     // Rider picks up the order
    {'id': 'on_the_way', 'title': 'On the Way'},   // Rider is delivering
    {'id': 'delivered', 'title': 'Delivered'}, // Rider has delivered the order
    {'id': 'completed', 'title': 'Order Completed'}, // Order completed and confirmed
  ];


  void _startLocationUpdates() {
    // Update location every 30 seconds
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _getCurrentLocation();
      }
    });
  }

  Future<void> _refreshOrderStatus() async {
    try {
      final response = await _riderService.getOrder(_order['id']);
      if (response != null && mounted) {
        setState(() {
          _order = response;
          _currentStatus = _order['status'] ?? _currentStatus;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing order status: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await _locationService.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        _updateRiderLocation();
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<void> _updateRiderLocation() async {
    if (_currentPosition == null) return;

    try {
      await _riderService.updateRiderLocation(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
    } catch (e) {
      debugPrint('Error updating rider location: $e');
    }
  }

  Future<void> _initializeLocation() async {
    try {
      // Get current location
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _currentStatus = 'navigating';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildMapPlaceholder() {
    return Container(
      height: 300,
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map, size: 48, color: Colors.grey[600]!),
            Container(height: 16),
            Text(
              'Map View Will Be Displayed Here',
              style: TextStyle(color: Colors.grey[600]!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return _buildMapPlaceholder();
  }

  // Status tracking
  bool get _isPickedUp =>
      _currentStatus == 'picked_up' ||
          _currentStatus == 'on_the_way' ||
          _currentStatus == 'completed';

  bool get _isOnTheWay =>
      _currentStatus == 'on_the_way' || _currentStatus == 'completed';

  bool get _isCompleted => _currentStatus == 'completed';

  // Status tracking getters
  bool get _canUpdateStatus => _currentStatus != 'completed';

  // Update order status with confirmation dialog for completion
  Widget _buildStatusActionButton(
      String label,
      IconData icon,
      Color color,
      String status,
      bool isEnabled,
      ) {
    return ElevatedButton(
      onPressed: isEnabled ? () => _updateStatus(status) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isEnabled
              ? Icon(icon, size: 20, color: Colors.white)
              : const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final currentStepIndex = _deliverySteps.indexWhere((step) => step['id'] == _currentStatus);
    final safeCurrentStepIndex = currentStepIndex == -1 ? 0 : currentStepIndex;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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
            const SizedBox(height: 24),

            // Horizontal timeline with connecting lines
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: _deliverySteps.asMap().entries.map((entry) {
                    final index = entry.key;
                    final step = entry.value;
                    final isCompleted = index < safeCurrentStepIndex;
                    final isCurrent = index == safeCurrentStepIndex;
                    final isLast = index == _deliverySteps.length - 1;
                    final statusColor = isCompleted || isCurrent
                        ? Theme.of(context).primaryColor
                        : Colors.grey[300];

                    return Container(
                      margin: EdgeInsets.only(right: isLast ? 0 : 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Status dot and connecting line
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Left connecting line (except for first item)
                              if (index > 0)
                                Container(
                                  height: 2,
                                  width: 24,
                                  color: statusColor,
                                ),

                              // Dot indicator
                              Container(
                                width: 16,
                                height: 16,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: isCompleted || isCurrent
                                      ? statusColor
                                      : Colors.grey[200]!,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: statusColor ?? Theme.of(context).primaryColor,
                                    width: 2,
                                  ),
                                ),
                                child: isCompleted
                                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                                    : isCurrent
                                    ? Container(
                                  margin: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
                                  ),
                                )
                                    : null,
                              ),

                              // Right connecting line (except for last item)
                              if (!isLast)
                                Container(
                                  height: 2,
                                  width: 24,
                                  color: statusColor,
                                ),
                            ],
                          ),

                          // Status text
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Text(
                              step['title'],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                color: isCurrent ? Theme.of(context).primaryColor : Colors.grey[700],
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action button - more prominent and always visible when there's a next step
            if (safeCurrentStepIndex < _deliverySteps.length - 1)
              Container(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _updateStatus(_deliverySteps[safeCurrentStepIndex + 1]['id']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    'Mark as ${_deliverySteps[safeCurrentStepIndex + 1]["title"]}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusConnector() {
    return Container(
      height: 20,
      width: 2,
      margin: const EdgeInsets.only(left: 11),
      color: Colors.grey[300],
    );
  }

  List<Widget> _buildStatusTimestamps() {
    if (_statusTimestamps.isEmpty) return [];

    return _statusTimestamps.entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          children: [
            Icon(
              _getStatusIcon(entry.key),
              size: 16,
              color: Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              '${_getStatusText(entry.key)}: ${_timeFormat.format(entry.value)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }).toList();
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'ready':
        return Icons.shopping_bag_outlined;
      case 'picked_up':
        return Icons.check_circle_outline;
      case 'on_the_way':
        return Icons.delivery_dining;
      case 'delivered':
        return Icons.location_on;
      case 'completed':
        return Icons.assignment_turned_in;
      default:
        return Icons.info_outline;
    }
  }

  Widget _buildActionButtons() {
    // This method is no longer needed as the action buttons are now
    // shown directly in the status timeline for each step
    return const SizedBox.shrink();
  }

  String? _getNextStatus() {
    final currentIndex = _deliverySteps.indexWhere((step) => step['id'] == _currentStatus);
    if (currentIndex < _deliverySteps.length - 1) {
      return _deliverySteps[currentIndex + 1]['id'];
    }
    return null;
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'picked_up':
        return 'Mark as Picked Up';
      case 'on_the_way':
        return 'Start Delivery';
      case 'delivered':
        return 'Mark as Delivered';
      case 'completed':
        return 'Complete Order';
      default:
        return 'Update Status';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'picked_up':
        return Theme.of(context).primaryColor;
      case 'on_the_way':
        return Colors.blue;
      case 'delivered':
        return Colors.lightGreen;  // Light green for delivered/arrived status
      case 'completed':
        return Colors.green[700]!;  // Darker green for completed
      default:
        return Theme.of(context).primaryColor;
    }
  }

  Widget _buildStatusButton(String status) {
    final nextStatus = _getNextStatus();
    if (nextStatus == null) return const SizedBox.shrink();

    return _buildStatusActionButton(
      _getStatusLabel(nextStatus),
      _getStatusIcon(nextStatus),
      _getStatusColor(nextStatus),
      nextStatus,
      true,
    );
  }


  Widget _buildBody() {
    return Column(
      children: [
        // Status indicator section
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Order Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildStatusIndicator(),
                const SizedBox(height: 8),
                ..._buildStatusTimestamps(),
              ],
            ),
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildActionButtons(),
        ),

        // Order and customer info
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildOrderInfoCard(),
                const SizedBox(height: 16),
                _buildCustomerInfoCard(),
                const SizedBox(height: 16),
                _buildOrderItemsCard(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusStep(String label, {bool isCompleted = false, bool isCurrent = false}) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isCompleted
                ? Theme.of(context).primaryColor
                : isCurrent
                ? Colors.white
                : Colors.grey[200],
            shape: BoxShape.circle,
            border: Border.all(
              color: isCompleted || isCurrent
                  ? Theme.of(context).primaryColor
                  : Colors.grey[300]!,
              width: isCurrent ? 2 : 1,
            ),
            boxShadow: isCurrent
                ? [
              BoxShadow(
                color: Theme.of(context).primaryColor.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 2,
              )
            ]
                : null,
          ),
          child: isCompleted
              ? Icon(Icons.check, size: 18, color: Colors.white)
              : isCurrent
              ? Icon(Icons.directions_bike, size: 18, color: Theme.of(context).primaryColor)
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            color: isCompleted || isCurrent
                ? Theme.of(context).primaryColor
                : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildOrderInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Order ID', '#${_order['id']?.toString().substring(0, 8) ?? 'N/A'}'),
            _buildInfoRow('Order Time', _formatDateTime(_order['created_at'])),
            if (_order['pickup_time'] != null)
              _buildInfoRow('Pickup Time', _formatDateTime(_order['pickup_time'])),
            if (_distanceToDestination != null)
              _buildInfoRow(
                'Distance',
                '${_distanceToDestination!.toStringAsFixed(1)} km',
              ),
            if (_estimatedTimeRemaining != null)
              _buildInfoRow(
                'Estimated Time',
                '${_estimatedTimeRemaining!.inMinutes} min',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerInfoCard() {
    final customer = _order['users'] ?? {};

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Customer Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              'Name',
              customer['name'] ?? 'N/A',
              trailing: IconButton(
                icon: const Icon(Icons.phone, color: Colors.green),
                onPressed: () {
                  final phone = customer['phone'];
                  if (phone != null) {
                    launchUrlString('tel:$phone');
                  }
                },
              ),
            ),
            _buildInfoRow('Phone', customer['phone'] ?? 'N/A'),
            _buildInfoRow('Address', _order['delivery_address'] ?? 'N/A'),
            if (_order['delivery_notes']?.isNotEmpty == true)
              _buildInfoRow('Notes', _order['delivery_notes']),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemsCard() {
    final items = _order['order_items'] ?? [];
    final total = _order['total_amount'] ?? 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order Items',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...items.map<Widget>((item) => _buildOrderItem(item)).toList(),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItem(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item['quantity']}x',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Container(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] ?? 'Item',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (item['notes']?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      item['notes'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '\$${((item['price'] ?? 0.0) * (item['quantity'] ?? 1)).toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          if (trailing != null) ...[
            Container(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';

    try {
      final dt = dateTime is DateTime ? dateTime : DateTime.parse(dateTime);
      return '${_timeFormat.format(dt)}';
    } catch (e) {
      return 'Invalid date';
    }
  }


  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      items: <BottomNavigationBarItem>[
        const BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.delivery_dining),
          label: 'Deliveries',
          backgroundColor: Theme.of(context).primaryColor,
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
      currentIndex: 1, // Highlight the Deliveries tab
      selectedItemColor: Theme.of(context).primaryColor,
      onTap: (index) {
        if (index == 0) {
          Navigator.of(context).pop(); // Just go back to previous screen
        } else if (index == 2) {
          // Handle profile navigation if needed
        }
      },
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'ready':
        return 'Ready for Pickup';
      case 'picked_up':
        return 'Picked Up';
      case 'on_the_way':
        return 'On the Way';
      case 'delivered':
        return 'At Destination';
      case 'completed':
        return 'Order Completed';
      default:
        return status;
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_isLoading) return;

    // Show confirmation for critical actions
    if (newStatus == 'completed') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Delivery'),
          content: const Text('Have you delivered the order to the customer?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('CONFIRM', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      bool success = false;

      // Check current order status first
      final currentStatus = _order['status'];

      // If we're trying to pick up but order is already picked up, move to next status
      if (newStatus == 'picked_up' && currentStatus == 'picked_up') {
        if (mounted) {
          setState(() {
            _currentStatus = 'picked_up';
          });
        }
        // Proceed to next status
        newStatus = 'on_the_way';
      }

      try {
        // Call the appropriate service method based on the new status
        switch (newStatus) {
          case 'picked_up':
            success = await _riderService.acceptAndPickUpOrder(_order['id']);
            break;
          case 'on_the_way':
            success = await _riderService.markOnTheWay(_order['id']);
            break;
          case 'delivered':
          case 'completed':
            debugPrint('🔄 Attempting to complete order delivery');
            try {
              success = await _riderService.completeDelivery(_order['id']);
              if (!success) {
                debugPrint('❌ Failed to complete order delivery');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to complete order delivery. Please try again.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } else {
                debugPrint('✅ Successfully completed order delivery');
              }
            } catch (e) {
              debugPrint('❌ Error completing delivery: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: ${e.toString()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              success = false;
            }
            break;
        }
      } catch (e) {
        debugPrint('Error in _updateStatus: $e');
        rethrow;
      }

      if (success && mounted) {
        // Record the timestamp for this status
        _statusTimestamps[newStatus] = DateTime.now();

        // If order is completed, pop with a result to trigger refresh
        if (newStatus == 'completed' || newStatus == 'delivered') {
          if (mounted) {
            Navigator.of(context).pop(true); // Pass true to indicate refresh is needed
            return;
          }
        }

        setState(() {
          _currentStatus = newStatus;
        });

        // If order is completed, show success message and navigate back
        if (newStatus == 'completed') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Delivery completed successfully!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );

          // Navigate back to dashboard after a short delay
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pop(); // Just go back to previous screen
          }
        }
      } else if (!success && mounted) {
        throw Exception('Failed to update order status');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating status: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      debugPrint('Error updating delivery status: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
