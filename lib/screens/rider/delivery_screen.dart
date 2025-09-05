import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rider_dashboard_screen.dart';
import '../../services/rider_service.dart';

class DeliveryScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool wasOnline;

  const DeliveryScreen({Key? key, required this.order, required this.wasOnline})
    : super(key: key);

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final Set<Marker> _markers = {};
  final RiderService _riderService = RiderService();
  bool _isLoading = false;
  String _currentStatus = 'ready'; // Default status

  // Status tracking
  bool get _isPickedUp =>
      _currentStatus == 'picked_up' ||
      _currentStatus == 'on_the_way' ||
      _currentStatus == 'completed';

  bool get _isOnTheWay =>
      _currentStatus == 'on_the_way' || _currentStatus == 'completed';

  bool get _isCompleted => _currentStatus == 'completed';

  // Status tracking getters
  bool get _canPickUp => _currentStatus == 'ready';

  bool get _canMarkOnTheWay => _currentStatus == 'picked_up';

  bool get _canComplete => _currentStatus == 'on_the_way';

  Widget _buildStatusActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isLoading ? null : onPressed,
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Icon(icon, color: Colors.white),
          label: Text(label, style: const TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.order['status'] ?? 'ready';
    _initializeMap();
  }

  void _initializeMap() {
    // Initialize map with delivery location
    final LatLng deliveryLocation = const LatLng(
      14.5995,
      120.9842,
    ); // Default to Manila, replace with actual coordinates
    _markers.add(
      Marker(
        markerId: const MarkerId('delivery_location'),
        position: deliveryLocation,
        infoWindow: const InfoWindow(title: 'Delivery Location'),
      ),
    );
  }

  Future<void> _callCustomer() async {
    final phoneNumber = widget.order['users']?['phone'] ?? '';
    if (await canLaunchUrlString('tel:$phoneNumber')) {
      await launchUrlString('tel:$phoneNumber');
    }
  }

  Future<void> _messageCustomer() async {
    final phoneNumber = widget.order['users']?['phone'] ?? '';
    if (await canLaunchUrlString('sms:$phoneNumber')) {
      await launchUrlString('sms:$phoneNumber');
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      bool success = false;

      // Call the appropriate service method based on the new status
      switch (newStatus) {
        case 'picked_up':
          success = await _riderService.acceptAndPickUpOrder(
            widget.order['id'],
          );
          break;
        case 'on_the_way':
          success = await _riderService.markOnTheWay(widget.order['id']);
          break;
        case 'completed':
          success = await _riderService.completeDelivery(widget.order['id']);
          break;
      }

      if (success && mounted) {
        setState(() => _currentStatus = newStatus);

        // If order is completed, show success message and navigate back
        if (newStatus == 'completed') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Delivery completed successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          // Navigate back to dashboard after a short delay
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            Navigator.pop(context, true);
          }
        }
      } else if (!success && mounted) {
        throw Exception('Failed to update order status');
      }
    } catch (e) {
      debugPrint('Error updating delivery status: $e');
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

  @override
  Widget build(BuildContext context) {
    final customer = widget.order['users'] ?? {};
    final merchant = widget.order['merchants'] ?? {};
    final orderItems = widget.order['order_items'] ?? [];

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, widget.wasOnline);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Delivery Details'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, widget.wasOnline),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.phone),
              onPressed: _callCustomer,
              tooltip: 'Call Customer',
            ),
            IconButton(
              icon: const Icon(Icons.message),
              onPressed: _messageCustomer,
              tooltip: 'Message Customer',
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order Status Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Status indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatusStep('Ready', _currentStatus == 'ready'),
                          _buildStatusStep(
                            'Picked Up',
                            _currentStatus == 'picked_up',
                          ),
                          _buildStatusStep(
                            'On the Way',
                            _currentStatus == 'on_the_way',
                          ),
                          _buildStatusStep(
                            'Delivered',
                            _currentStatus == 'completed',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Action Buttons
                      if (_canPickUp)
                        _buildStatusActionButton(
                          'Mark as Picked Up',
                          Icons.check_circle,
                          Colors.orange,
                          () => _updateStatus('picked_up'),
                        ),
                      if (_canMarkOnTheWay)
                        _buildStatusActionButton(
                          'Start Delivery',
                          Icons.delivery_dining,
                          Colors.blue,
                          () => _updateStatus('on_the_way'),
                        ),
                      if (_canComplete)
                        _buildStatusActionButton(
                          'Mark as Delivered',
                          Icons.assignment_turned_in,
                          Colors.green,
                          () => _updateStatus('completed'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Order Summary Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Summary',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Order ID', '#${widget.order['id']}'),
                      _buildInfoRow(
                        'Customer',
                        customer['users']?['name'] ?? 'N/A',
                      ),
                      _buildInfoRow(
                        'Contact',
                        customer['users']?['phone'] ?? 'N/A',
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      ...orderItems
                          .map<Widget>(
                            (item) => Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Text(
                                '• ${item['foods']?['name'] ?? 'Item'} x${item['quantity']}',
                              ),
                            ),
                          )
                          .toList(),
                      const Divider(),
                      _buildInfoRow(
                        'Total',
                        '\$${widget.order['total_amount']?.toStringAsFixed(2) ?? '0.00'}',
                        isBold: true,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Delivery Address
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Delivery Address',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.order['delivery_address'] ??
                            'No address provided',
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        child: GoogleMap(
                          initialCameraPosition: const CameraPosition(
                            target: LatLng(14.5995, 120.9842),
                            // Default to Manila
                            zoom: 15,
                          ),
                          markers: _markers,
                          myLocationEnabled: true,
                          myLocationButtonEnabled: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildStatusIndicator(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Delivery Status
              Card(
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
                      _buildStatusIndicator(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              // Complete Delivery Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isOnTheWay
                      ? () => _updateStatus('delivered')
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  child: const Text(
                    'COMPLETE DELIVERY',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'ready':
        return 'Ready';
      case 'picked_up':
        return 'Picked Up';
      case 'on_the_way':
        return 'On The Way';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  Widget _buildStatusIndicator() {
    final statuses = ['ready', 'picked_up', 'on_the_way', 'completed'];
    final currentIndex = statuses.indexOf(_currentStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Progress indicator
        LinearProgressIndicator(
          value: (currentIndex + 1) / statuses.length,
          backgroundColor: Colors.grey[200],
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
        ),
        const SizedBox(height: 8),
        // Status steps
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: statuses.map((status) {
            final isActive = statuses.indexOf(status) <= currentIndex;
            final isCurrent = status == _currentStatus;

            return Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green : Colors.grey[300],
                    shape: BoxShape.circle,
                    border: isCurrent
                        ? Border.all(color: Colors.green, width: 2)
                        : null,
                  ),
                  child: isActive
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  _getStatusText(status),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? Colors.green : Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildActionButton() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (_currentStatus) {
      case 'ready':
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _updateStatus('picked_up'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.orange,
            ),
            child: const Text('Mark as Picked Up'),
          ),
        );
      case 'picked_up':
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _updateStatus('on_the_way'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.blue,
            ),
            child: const Text('Start Delivery'),
          ),
        );
      case 'on_the_way':
        return const SizedBox.shrink(); // Hide the button when on the way (using the bottom button instead)
      case 'completed':
        return const Center(
          child: Text(
            'Delivery Completed',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStatusStep(String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isActive ? Theme.of(context).primaryColor : Colors.grey[300],
            shape: BoxShape.circle,
          ),
          child: isActive
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Theme.of(context).primaryColor : Colors.grey[600],
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
