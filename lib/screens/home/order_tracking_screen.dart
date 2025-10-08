import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../services/location_service.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Map<String, dynamic>? _orderData;
  bool _isLoading = true;
  StreamSubscription? _orderSubscription;
  int _selectedIndex = 2; // Set to 2 for "My Orders" tab

  // Location tracking
  final LocationService _locationService = LocationService();
  Position? _riderPosition;
  StreamSubscription<Position>? _riderLocationSubscription;

  // Default coordinates (fallback if no location data)
  static const double _defaultLatitude = 24.7136; // Riyadh coordinates as default
  static const double _defaultLongitude = 46.6753;

  // Order status steps
  final List<Map<String, dynamic>> _statusSteps = [
    {
      'status': 'pending',
      'title': 'Order Placed',
      'subtitle': 'Your order has been received',
      'icon': Icons.receipt_long,
    },
    {
      'status': 'confirmed',
      'title': 'Order Confirmed',
      'subtitle': 'Restaurant is preparing your order',
      'icon': Icons.restaurant,
    },
    {
      'status': 'ready',
      'title': 'Ready for Pickup',
      'subtitle': 'Waiting for rider to pick up',
      'icon': Icons.check_circle,
    },
    {
      'status': 'picked_up',
      'title': 'Out for Delivery',
      'subtitle': 'Rider is on the way',
      'icon': Icons.delivery_dining,
    },
    {
      'status': 'completed',
      'title': 'Delivered',
      'subtitle': 'Order has been delivered',
      'icon': Icons.done_all,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadOrderData();
    _setupOrderSubscription();
    _startRiderLocationTracking();
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    _riderLocationSubscription?.cancel();
    super.dispose();
  }

  void _setupOrderSubscription() {
    _orderSubscription = Supabase.instance.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', widget.orderId)
        .listen((data) {
      if (data.isNotEmpty && mounted) {
        setState(() {
          _orderData = data.first;
        });
      }
    });
  }

  Future<void> _loadOrderData() async {
    try {
      setState(() => _isLoading = true);

      final response = await Supabase.instance.client
          .from('orders')
          .select('''
            *,
            merchants:merchant_id(name),
            riders:rider_id(users:user_id(name, contact)),
            order_items(
              *,
              foods(name, image_url, price)
            )
          ''')
          .eq('id', widget.orderId)
          .single();

      if (mounted) {
        setState(() {
          _orderData = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading order data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading order: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startRiderLocationTracking() async {
    try {
      // Request location permission
      await _locationService.checkAndRequestPermission();

      // Start listening to rider's location updates
      _riderLocationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      ).listen((Position position) {
        if (mounted) {
          setState(() {
            _riderPosition = position;
          });
        }
      });
    } catch (e) {
      debugPrint('Error starting location tracking: $e');
      // Continue without location tracking if permission denied
    }
  }

  void _onNavigationTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 0) {
      // Home - go back to menu screen
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (index == 1) {
      // Favorites - go back to menu screen and show favorites
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap Favorites in the menu to view your favorites')),
      );
    } else if (index == 3) {
      // Profile - go back to menu screen
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap Profile in the menu to view your profile')),
      );
    }
    // index == 2 is current screen (My Orders), so do nothing
  }

  int _getCurrentStepIndex() {
    if (_orderData == null) return 0;
    final status = _orderData!['status'] as String;
    return _statusSteps.indexWhere((step) => step['status'] == status);
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'ready':
        return Colors.purple;
      case 'picked_up':
        return AppConstants.primaryColor;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildMapSection() {
    if (_orderData == null) {
      return const SizedBox.shrink();
    }

    // Extract coordinates with null safety
    final deliveryLat = _orderData!['delivery_latitude'] as double? ?? _defaultLatitude;
    final deliveryLng = _orderData!['delivery_longitude'] as double? ?? _defaultLongitude;
    final riderLat = _riderPosition?.latitude ?? _defaultLatitude;
    final riderLng = _riderPosition?.longitude ?? _defaultLongitude;

    // Create LatLng points
    final customerPoint = LatLng(deliveryLat, deliveryLng);
    final riderPoint = LatLng(riderLat, riderLng);
    final bounds = LatLngBounds.fromPoints([customerPoint, riderPoint]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Live Order Tracking',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 300,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(
                (riderLat + deliveryLat) / 2,
                (riderLng + deliveryLng) / 2,
              ),
              initialZoom: 12.0,
              maxZoom: 18.0,
              minZoom: 3.0,
              bounds: bounds,
              boundsOptions: const FitBoundsOptions(padding: EdgeInsets.all(50)),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.mappia',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: customerPoint,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 40,
                    ),
                  ),
                  Marker(
                    point: riderPoint,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.delivery_dining,
                      color: Colors.green,
                      size: 40,
                    ),
                  ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [riderPoint, customerPoint],
                    color: Colors.blue.withOpacity(0.7),
                    strokeWidth: 4,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Order'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orderData == null
          ? const Center(child: Text('Order not found'))
          : RefreshIndicator(
        onRefresh: _loadOrderData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order ID and Status Card
              _buildOrderInfoCard(),
              const SizedBox(height: 24),

              // Live Map Tracking (if rider is assigned and on delivery)
              if (_orderData!['rider_id'] != null && (_orderData!['status'] == 'picked_up' || _orderData!['status'] == 'ready')) ...[
                _buildMapSection(),
                const SizedBox(height: 24),
              ],

              // Order Status Timeline
              _buildStatusTimeline(),
              const SizedBox(height: 24),

              // Rider Information (if assigned)
              if (_orderData!['rider_id'] != null) ...[
                _buildRiderInfo(),
                const SizedBox(height: 24),
              ],

              // Delivery Details
              _buildDeliveryDetails(),
              const SizedBox(height: 24),

              // Order Items
              _buildOrderItems(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavigationTapped,
        selectedItemColor: AppConstants.primaryColor,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'Favorites',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'My Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildOrderInfoCard() {
    final status = _orderData!['status'] as String;
    final statusColor = _getStatusColor(status);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppConstants.primaryColor,
            AppConstants.primaryColor.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Order ID',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '#${widget.orderId.substring(0, 8).toUpperCase()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SAR ${(_orderData!['total_amount'] as num).toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (_orderData!['estimated_time'] != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Est. Time',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_orderData!['estimated_time']} min',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline() {
    final currentStepIndex = _getCurrentStepIndex();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
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
          const SizedBox(height: 20),
          ...List.generate(_statusSteps.length, (index) {
            final step = _statusSteps[index];
            final isCompleted = index <= currentStepIndex;
            final isCurrent = index == currentStepIndex;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline indicator
                Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? AppConstants.primaryColor
                            : Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        step['icon'],
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    if (index < _statusSteps.length - 1)
                      Container(
                        width: 2,
                        height: 50,
                        color: isCompleted
                            ? AppConstants.primaryColor
                            : Colors.grey[300],
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                // Step details
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step['title'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                            color: isCompleted ? Colors.black87 : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          step['subtitle'],
                          style: TextStyle(
                            fontSize: 14,
                            color: isCompleted ? Colors.grey[600] : Colors.grey[400],
                          ),
                        ),
                        if (isCurrent)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppConstants.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Current Status',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppConstants.primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDistanceInfo(double riderLat, double riderLng, double customerLat, double customerLng) {
    final distance = _locationService.calculateDistance(
      riderLat,
      riderLng,
      customerLat,
      customerLng,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${distance.toStringAsFixed(1)} km',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.green,
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  bool _isValidCoordinate(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && lat != 0 && lng != 0 && lat.isFinite && lng.isFinite;
  }

  Widget _buildRiderInfo() {
    final rider = _orderData!['riders'];
    final riderUser = rider?['users'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery Rider',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppConstants.primaryColor,
                child: const Icon(
                  Icons.person,
                  size: 30,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      riderUser?['name'] ?? 'Rider',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      riderUser?['contact'] ?? 'No contact',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  // TODO: Implement call functionality
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Calling rider...')),
                  );
                },
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phone,
                    color: Colors.green,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryDetails() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            Icons.location_on,
            'Delivery Address',
            _orderData?['delivery_address'] ?? 'No address provided',
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            Icons.access_time,
            'Estimated Delivery',
            _orderData?['estimated_delivery_time'] ?? 'Calculating...',
          ),
          if (_orderData?['special_instructions'] != null) ...[
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.note,
              'Special Instructions',
              _orderData!['special_instructions'],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrderItems() {
    final items = _orderData?['order_items'] as List? ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Items',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...items.map<Widget>((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      image: item['image_url'] != null
                          ? DecorationImage(
                        image: NetworkImage(item['image_url']),
                        fit: BoxFit.cover,
                      )
                          : null,
                    ),
                    child: item['image_url'] == null
                        ? const Icon(Icons.fastfood, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'] ?? 'Item',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item['quantity']} x \$${item['price']?.toStringAsFixed(2) ?? '0.00'}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${(item['quantity'] * (item['price'] ?? 0)).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }).toList(),
          const Divider(height: 32),
          _buildOrderTotal(),
        ],
      ),
    );
  }

  Widget _buildOrderTotal() {
    final subtotal = _orderData?['subtotal'] ?? 0.0;
    final deliveryFee = _orderData?['delivery_fee'] ?? 0.0;
    final tax = _orderData?['tax'] ?? 0.0;
    final total = _orderData?['total'] ?? 0.0;

    return Column(
      children: [
        _buildTotalRow('Subtotal', subtotal),
        _buildTotalRow('Delivery Fee', deliveryFee),
        _buildTotalRow('Tax', tax),
        const Divider(height: 24),
        _buildTotalRow(
          'Total',
          total,
          isBold: true,
          textColor: Theme.of(context).primaryColor,
        ),
      ],
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool isBold = false, Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: textColor,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for the map
class _MapPainter extends CustomPainter {
  final BuildContext context;
  final bool Function(double, double) isValidCoordinate;
  final double riderLat;
  final double riderLng;
  final double customerLat;
  final double customerLng;
  final Offset center;
  final double scale;
  final LocationService _locationService;
  final Map<String, dynamic>? orderData;
  final List<Map<String, dynamic>> statusSteps;
  final bool isLoading;

  _MapPainter({
    required this.context,
    required this.isValidCoordinate,
    required this.riderLat,
    required this.riderLng,
    required this.customerLat,
    required this.customerLng,
    required this.center,
    required this.scale,
    required LocationService locationService,
    this.orderData,
    required this.statusSteps,
    required this.isLoading,
  }) : _locationService = locationService;

  @override
  bool shouldRepaint(_MapPainter oldDelegate) {
    return riderLat != oldDelegate.riderLat ||
        riderLng != oldDelegate.riderLng ||
        customerLat != oldDelegate.customerLat ||
        customerLng != oldDelegate.customerLng;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (isLoading) {
      return;
    }
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw grid
    _drawGrid(canvas, size, paint);

    // Draw rider location
    _drawLocationMarker(
      canvas,
      size,
      Offset(riderLng, riderLat),
      Colors.blue,
      Icons.person,
    );

    // Draw customer location
    _drawLocationMarker(
      canvas,
      size,
      Offset(customerLng, customerLat),
      Colors.red,
      Icons.home,
    );

    // Draw route line if positions are valid
    if (isValidCoordinate(riderLat, riderLng) && isValidCoordinate(customerLat, customerLng)) {
      _drawRoute(canvas, size, paint);
    }
  }

  void _drawGrid(Canvas canvas, Size size, Paint paint) {
    const gridSize = 20.0;

    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  void _drawLocationMarker(Canvas canvas, Size size, Offset position, Color color, IconData icon) {
    if (!isValidCoordinate(position.dy, position.dx)) return;

    // Convert lat/lng to screen coordinates
    final screenPos = _latLngToScreen(position, size);

    // Draw marker circle
    final markerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(screenPos, 8, markerPaint);

    // Draw marker border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(screenPos, 8, borderPaint);

    // Draw icon (simplified as a dot for now)
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(screenPos, 3, iconPaint);
  }

  void _drawRoute(Canvas canvas, Size size, Paint paint) {
    final riderScreenPos = _latLngToScreen(Offset(riderLng, riderLat), size);
    final customerScreenPos = _latLngToScreen(Offset(customerLng, customerLat), size);

    // Draw route line
    final routePaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(riderScreenPos, customerScreenPos, routePaint);

    // Draw route direction arrows (simplified)
    const arrowSize = 8.0;
    final midPoint = Offset(
      (riderScreenPos.dx + customerScreenPos.dx) / 2,
      (riderScreenPos.dy + customerScreenPos.dy) / 2,
    );

    // Calculate direction vector and normalize it manually
    final direction = customerScreenPos - riderScreenPos;
    final length = sqrt(direction.dx * direction.dx + direction.dy * direction.dy);
    final normalizedDirection = length > 0
        ? Offset(direction.dx / length, direction.dy / length)
        : Offset(1.0, 0.0); // Default to right if no length

    final arrowEnd = midPoint + normalizedDirection * arrowSize;

    canvas.drawLine(midPoint, arrowEnd, routePaint);
  }

  Offset _latLngToScreen(Offset latLng, Size size) {
    // Simple projection: scale and translate coordinates
    final x = (latLng.dx - center.dx) * scale * 100 + size.width / 2;
    final y = (center.dy - latLng.dy) * scale * 100 + size.height / 2;

    return Offset(x, y);
  }

  int _getCurrentStepIndex() {
    if (orderData == null) return 0;
    final status = orderData!['status'] as String;
    return statusSteps.indexWhere((step) => step['status'] == status);
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'ready':
        return Colors.purple;
      case 'picked_up':
        return AppConstants.primaryColor;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildDistanceInfo(double riderLat, double riderLng, double customerLat, double customerLng) {
    final distance = _locationService.calculateDistance(
      riderLat,
      riderLng,
      customerLat,
      customerLng,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${distance.toStringAsFixed(1)} km',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.green,
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  bool _isValidCoordinate(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && lat != 0 && lng != 0 && lat.isFinite && lng.isFinite;
  }

  Widget _buildRiderInfo() {
    final rider = orderData!['riders'];
    final riderUser = rider?['users'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery Rider',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppConstants.primaryColor,
                child: const Icon(
                  Icons.person,
                  size: 30,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      riderUser?['name'] ?? 'Rider',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      riderUser?['contact'] ?? 'No contact',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  // TODO: Implement call functionality
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Call rider feature coming soon!')),
                  );
                },
                icon: Icon(
                  Icons.phone,
                  color: AppConstants.primaryColor,
                  size: 28,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryDetails() {
    final merchant = orderData!['merchants'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            Icons.restaurant,
            'Restaurant',
            merchant?['name'] ?? 'Unknown',
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            Icons.location_on,
            'Delivery Address',
            orderData!['delivery_address'] ?? 'Not specified',
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            Icons.payment,
            'Payment Method',
            'Cash on Delivery',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: AppConstants.primaryColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrderItems() {
    final orderItems = orderData!['order_items'] as List<dynamic>?;

    if (orderItems == null || orderItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Items',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Center(
              child: Text(
                'No items found',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Items',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...orderItems.map((item) {
            final food = item['foods'];
            final quantity = item['quantity'] ?? 1;
            final unitPrice = item['unit_price'] ?? 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: food?['image_url'] != null
                        ? Image.network(
                      food['image_url'],
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey[300],
                        child: const Icon(Icons.fastfood),
                      ),
                    )
                        : Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[300],
                      child: const Icon(Icons.fastfood),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          food?['name'] ?? 'Food Item',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Qty: $quantity',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'SAR ${(unitPrice * quantity).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primaryColor,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}


