import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import 'view_all_screen.dart';
import 'merchant_products_screen.dart';
import '../auth/login_screen.dart';
import 'order_confirmation_screen.dart';
import 'my_orders_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MenuScreen extends StatefulWidget {
  final String userName;
  final String? userId;
  const MenuScreen({super.key, required this.userName, this.userId});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final TextEditingController _locationController = TextEditingController();

  final List<String> _carouselImages = [
    'assets/images/Lumpia.jpg',
    'assets/images/friedChicken.jpg',
    'assets/images/Burger.jpg',
  ];

  // Add state for dynamic favorites if needed
  List<Map<String, dynamic>> _favoriteFoods = [];

  // Add state for dynamic merchants
  List<Map<String, dynamic>> _dynamicMerchants = [];
  bool _isLoadingDynamicMerchants = true;

  late final PageController _pageController;
  int _currentPage = 0;
  int _currentIndex = 0; // For bottom navigation
  Timer? _carouselTimer;

  // Cart functionality
  final List<Map<String, dynamic>> _cartItems = [];
  int _cartCount = 0; // For cart badge

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1000); // Start from middle for infinite scroll
    _startCarouselTimer();
    // Show welcome notification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Welcome, ${widget.userName}!')),
      );
    });
    _fetchDynamicMerchants();
    _fetchFavoriteFoods();
    _loadCartFromDatabase(); // Load cart items from database
  }

  Future<void> _fetchFavoriteFoods() async {
    // Fetch favorite foods from Supabase if you have a favorites table or logic
    // For now, leave as empty or implement as needed
    if (mounted) {
      setState(() {
        _favoriteFoods = [];
      });
    }
  }

  Future<void> _loadCartFromDatabase() async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) {
        print('DEBUG: No user ID found for loading cart');
        return;
      }

      print('DEBUG: Loading cart from database for user: $userId');

      final response = await Supabase.instance.client
          .from('cart_items')
          .select('''
            *,
            foods(
              id,
              name,
              description,
              price,
              image_url,
              created_by
            )
          ''')
          .eq('customer_id', userId);

      if (!mounted) return;

      print('DEBUG: Cart items from database: $response');

      final List<Map<String, dynamic>> cartItems = [];
      int cartCount = 0;

      for (final item in response) {
        if (!mounted) return;

        final food = item['foods'] as Map<String, dynamic>?;
        if (food != null) {
          cartItems.add({
            'id': food['id'],
            'name': food['name'],
            'image_url': food['image_url'],
            'price': food['price'],
            'created_by': food['created_by'],
            'addOns': List<Map<String, dynamic>>.from(item['add_ons'] ?? []),
            'quantity': item['quantity'] ?? 1,
          });
          cartCount += (item['quantity'] ?? 1) as int;
        }
      }

      if (mounted) {
        setState(() {
          _cartItems.clear();
          _cartItems.addAll(cartItems);
          _cartCount = cartCount;
        });
      }

      print('DEBUG: Loaded ${cartItems.length} items from cart, total count: $cartCount');
    } catch (e) {
      print('DEBUG: Error loading cart from database: $e');
    }
  }

  Future<String?> _getCurrentUserId() async {
    try {
      // First check if we have a userId passed from login
      if (widget.userId != null) {
        print('DEBUG: Using userId from widget: ${widget.userId}');
        return widget.userId;
      }

      // Fallback to Supabase Auth
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        print('DEBUG: Using Supabase Auth user: ${user.id}');
        return user.id;
      }

      print('DEBUG: No user ID found');
      return null;
    } catch (e) {
      print('DEBUG: Error getting current user: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _createOrder(String deliveryAddress, String paymentMethod) async {
    try {
      print('DEBUG: Creating order...');

      // Get current user ID
      final userId = await _getCurrentUserId();
      if (userId == null) {
        print('DEBUG: No user ID found');
        return null;
      }

      // Calculate total amount (already includes delivery fee)
      double totalAmount = _getTotalPrice();
      const deliveryFee = 3.0;

      print('DEBUG: Total amount: $totalAmount');
      print('DEBUG: Cart items: ${_cartItems.length}');

      // Debug: Print all cart items
      for (int i = 0; i < _cartItems.length; i++) {
        print('DEBUG: Cart item $i: ${_cartItems[i]}');
      }

      // Group items by merchant (restaurant)
      Map<String, List<Map<String, dynamic>>> merchantOrders = {};

      for (final item in _cartItems) {
        print('DEBUG: Cart item: ${item['name']}, created_by: ${item['created_by']}');
        final merchantId = item['created_by'];
        if (merchantId != null) {
          if (!merchantOrders.containsKey(merchantId)) {
            merchantOrders[merchantId] = [];
          }
          merchantOrders[merchantId]!.add(item);
        } else {
          print('DEBUG: Warning - item ${item['name']} has no created_by field');
        }
      }

      print('DEBUG: Merchant orders: ${merchantOrders.keys.length}');

      // Store the first order ID to return
      String? firstOrderId;

      // Create orders for each merchant
      for (final merchantId in merchantOrders.keys) {
        final items = merchantOrders[merchantId]!;
        double merchantTotal = 0;

        for (final item in items) {
          merchantTotal += (item['price'] ?? 0.0) * (item['quantity'] ?? 1);
        }

        // Add proportional delivery fee
        final proportionalDeliveryFee = (deliveryFee * items.length) / _cartItems.length;
        merchantTotal += proportionalDeliveryFee;

        print('DEBUG: Creating order for merchant $merchantId, total: $merchantTotal');

        // Create order
        final orderResponse = await Supabase.instance.client
            .from('orders')
            .insert({
          'customer_id': userId,
          'merchant_id': merchantId,
          'status': 'pending',
          'total_amount': merchantTotal,
          'delivery_fee': proportionalDeliveryFee,
          'tip_amount': 0.0,
          'pickup_address': 'Restaurant Location', // You might want to get this from merchant data
          'delivery_address': deliveryAddress,
          'estimated_distance': 2.5, // You might want to calculate this
          'estimated_time': 15, // You might want to calculate this
        })
            .select()
            .single();

        print('DEBUG: Order created: ${orderResponse['id']}');

        // Store the first order ID
        firstOrderId ??= orderResponse['id'];

        // Create order items
        for (final item in items) {
          await Supabase.instance.client
              .from('order_items')
              .insert({
            'order_id': orderResponse['id'],
            'food_id': item['id'],
            'quantity': item['quantity'] ?? 1,
            'unit_price': item['price'] ?? 0.0,
            'add_ons': item['addOns'] ?? [],
          });
        }

        print('DEBUG: Order items created for order ${orderResponse['id']}');
      }

      print('DEBUG: All orders created successfully');
      return {
        'orderId': firstOrderId,
        'totalAmount': totalAmount,
        'deliveryAddress': deliveryAddress,
        'paymentMethod': paymentMethod,
      };
    } catch (e) {
      print('DEBUG: Error creating order: $e');
      return null;
    }
  }

  Future<void> _fetchDynamicMerchants() async {
    try {
      print('DEBUG: Fetching merchants...');

      // Fetch all users who are admins or restaurants (merchants)
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .or('role.eq.admin,role.eq.restaurant');

      if (!mounted) return;

      print('DEBUG: Users response: $response');
      final allMerchants = List<Map<String, dynamic>>.from(response as List);
      print('DEBUG: Found ${allMerchants.length} potential merchants');

      // Only include merchants who have at least one food
      List<Map<String, dynamic>> dynamicMerchants = [];
      for (final merchant in allMerchants) {
        if (!mounted) return;

        final foods = await Supabase.instance.client
            .from('foods')
            .select('id')
            .eq('created_by', merchant['id']);

        if (!mounted) return;

        if (foods.isNotEmpty) {
          print('DEBUG: Merchant ${merchant['name']} has ${foods.length} foods');
          dynamicMerchants.add(merchant);
        }
      }

      if (!mounted) return;

      print('DEBUG: Final merchants count: ${dynamicMerchants.length}');
      setState(() {
        _dynamicMerchants = dynamicMerchants;
        _isLoadingDynamicMerchants = false;
      });
    } catch (e) {
      print('DEBUG: Error fetching merchants: $e');
      if (mounted) {
        setState(() {
          _isLoadingDynamicMerchants = false;
        });
      }
    }
  }

  void _startCarouselTimer() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pageController.hasClients && mounted) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _onCarouselIndexChanged(int index) {
    if (mounted) {
      setState(() {
        _currentPage = index % _carouselImages.length;
      });
    }
  }

  @override
  void dispose() {
    _locationController.dispose();
    _carouselTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onCartPressed() {
    _showCartPage();
  }

  Future<void> _addToCart(Map<String, dynamic> item, List<Map<String, dynamic>> addOns) async {
    print('DEBUG: Adding to cart - item: ${item['name']}, id: ${item['id']}, created_by: ${item['created_by']}');

    final userId = await _getCurrentUserId();
    if (userId == null) {
      print('DEBUG: No user ID found for adding to cart');
      return;
    }

    // Check if item with same add-ons exists
    final existingIndex = _cartItems.indexWhere((cartItem) {
      if (cartItem['name'] != item['name']) return false;
      final cartAddOns = cartItem['addOns'] as List<Map<String, dynamic>>? ?? [];
      if (cartAddOns.length != addOns.length) return false;
      for (int i = 0; i < cartAddOns.length; i++) {
        if (cartAddOns[i]['name'] != addOns[i]['name'] || cartAddOns[i]['price'] != addOns[i]['price']) {
          return false;
        }
      }
      return true;
    });

    try {
      if (existingIndex != -1) {
        // Update quantity in database
        final cartItem = _cartItems[existingIndex];
        final newQuantity = (cartItem['quantity'] ?? 1) + 1;

        await Supabase.instance.client
            .from('cart_items')
            .update({'quantity': newQuantity})
            .eq('customer_id', userId)
            .eq('food_id', item['id'])
            .eq('add_ons', addOns);

        setState(() {
          _cartItems[existingIndex]['quantity'] = newQuantity;
          _cartCount++;
        });

        // Show notification for quantity increase
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item['name'] ?? 'Food Item'} quantity increased in cart'),
            backgroundColor: AppConstants.primaryColor,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        // Add new item to database
        await Supabase.instance.client
            .from('cart_items')
            .insert({
          'customer_id': userId,
          'food_id': item['id'],
          'quantity': 1,
          'add_ons': addOns,
        });

        setState(() {
          _cartItems.add({
            'id': item['id'],
            'name': item['name'],
            'image_url': item['image_url'],
            'image': item['image'],
            'price': item['price'],
            'created_by': item['created_by'],
            'addOns': List<Map<String, dynamic>>.from(addOns),
            'quantity': 1,
          });
          _cartCount++;
        });

        // Show notification for new item added
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item['name'] ?? 'Food Item'} added to cart'),
            backgroundColor: AppConstants.primaryColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Error adding to cart: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding item to cart'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _updateCartItemQuantity(int index, int newQuantity) async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) return;

      final item = _cartItems[index];

      if (newQuantity <= 0) {
        // Remove item from database
        await Supabase.instance.client
            .from('cart_items')
            .delete()
            .eq('customer_id', userId)
            .eq('food_id', item['id'])
            .eq('add_ons', item['addOns']);

        setState(() {
          _cartItems.removeAt(index);
          _cartCount = _cartCount > 0 ? _cartCount - 1 : 0;
        });
      } else {
        // Update quantity in database
        await Supabase.instance.client
            .from('cart_items')
            .update({'quantity': newQuantity})
            .eq('customer_id', userId)
            .eq('food_id', item['id'])
            .eq('add_ons', item['addOns']);

        setState(() {
          _cartItems[index]['quantity'] = newQuantity;
          if (newQuantity > (item['quantity'] ?? 1)) {
            _cartCount++;
          } else {
            _cartCount = _cartCount > 0 ? _cartCount - 1 : 0;
          }
        });
      }
    } catch (e) {
      print('DEBUG: Error updating cart item quantity: $e');
    }
  }

  Future<void> _clearCart() async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) return;

      // Clear cart from database
      await Supabase.instance.client
          .from('cart_items')
          .delete()
          .eq('customer_id', userId);

      setState(() {
        _cartItems.clear();
        _cartCount = 0;
      });
    } catch (e) {
      print('DEBUG: Error clearing cart: $e');
    }
  }

  double _getTotalPrice() {
    double subtotal = _cartItems.fold(0.0, (total, item) {
      double itemTotal = item['price'] * (item['quantity'] ?? 1);
      final addOns = item['addOns'] as List<Map<String, dynamic>>? ?? [];
      double addOnsTotal = addOns.fold(0.0, (addOnTotal, addOn) => addOnTotal + addOn['price']) * (item['quantity'] ?? 1);
      return total + itemTotal + addOnsTotal;
    });

    // Add delivery fee
    const deliveryFee = 3.0;
    return subtotal + deliveryFee;
  }

  void _onAvatarPressed() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profile pressed!')));
  }

  // Toggle favorite functionality
  void _toggleFavorite(Map<String, dynamic> food) {
    setState(() {
      final existingIndex = _favoriteFoods.indexWhere((fav) => fav['id'] == food['id']);
      if (existingIndex != -1) {
        // Remove from favorites
        _favoriteFoods.removeAt(existingIndex);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${food['name'] ?? 'Food Item'} removed from favorites'),
            backgroundColor: Colors.grey[600],
          ),
        );
      } else {
        // Add to favorites
        _favoriteFoods.add(food);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${food['name'] ?? 'Food Item'} added to favorites'),
            backgroundColor: AppConstants.primaryColor,
          ),
        );
      }
    });
  }

  bool _isFavorite(Map<String, dynamic> food) {
    return _favoriteFoods.any((fav) => fav['id'] == food['id']);
  }

  void _onNavigationTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    if (index == 1) {
      // Favorites page
      _showFavoritesPage();
    } else if (index == 2) {
      // My Orders page - navigate to My Orders screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MyOrdersScreen(userId: widget.userId),
        ),
      );
    } else if (index == 3) {
      // Profile page
      _showProfilePage();
    }
  }

  void _showFavoritesPage() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'My Favorites',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_favoriteFoods.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                        'No favorites yet!\nTap the heart icon to add items to your favorites.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _favoriteFoods.length,
                      itemBuilder: (context, index) {
                        final item = _favoriteFoods[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: item['image_url'] != null && item['image_url'].toString().isNotEmpty
                                  ? Image.network(
                                item['image_url'],
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image),
                                ),
                              )
                                  : Container(
                                width: 60,
                                height: 60,
                                color: Colors.grey[200],
                                child: const Icon(Icons.fastfood, size: 40),
                              ),
                            ),
                            title: Text(
                              item['name'] ?? 'Food Item',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('SAR ${item['price']?.toStringAsFixed(2) ?? ''}'),
                            trailing: IconButton(
                              onPressed: () {
                                _toggleFavorite(item);
                                setModalState(() {}); // Refresh the modal
                              },
                              icon: const Icon(
                                Icons.favorite,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showProfilePage() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppConstants.primaryColor,
                    child: Icon(
                      Icons.person,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.userName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Mappia User',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings coming soon!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.help),
              title: const Text('Help & Support'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Help & Support coming soon!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              trailing: const Icon(Icons.arrow_forward_ios, color: Colors.red),
              onTap: () {
                Navigator.pop(context);
                _showLogoutConfirmation();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmation() {
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
                _performLogout();
              },
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _performLogout() async {
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logged out successfully!'),
            backgroundColor: AppConstants.primaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging out: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCartPage() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'My Cart',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_cartItems.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Your cart is empty!\nAdd some delicious items to get started.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            itemCount: _cartItems.length,
                            itemBuilder: (context, index) {
                              final item = _cartItems[index];
                              final quantity = item['quantity'] ?? 1;
                              final addOns = item['addOns'] as List<Map<String, dynamic>>? ?? [];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: item['image_url'] != null && item['image_url'].toString().isNotEmpty
                                            ? Image.network(
                                          item['image_url'],
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            width: 60,
                                            height: 60,
                                            color: Colors.grey[200],
                                            child: const Icon(Icons.broken_image),
                                          ),
                                        )
                                            : Image.asset(
                                          item['image'] ?? 'assets/images/food_image_1.jpg',
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            width: 60,
                                            height: 60,
                                            color: Colors.grey[200],
                                            child: const Icon(Icons.broken_image),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item['name'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            if (addOns.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: addOns.map((addOn) => Padding(
                                                    padding: const EdgeInsets.only(bottom: 2),
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            '+ ${addOn['name']}',
                                                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          'SAR ${addOn['price'].toStringAsFixed(2)}',
                                                          style: TextStyle(fontSize: 13, color: AppConstants.primaryColor),
                                                        ),
                                                      ],
                                                    ),
                                                  )).toList(),
                                                ),
                                              ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'SAR ${(item['price'] + addOns.fold(0.0, (total, addOn) => total + addOn['price'])).toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: AppConstants.primaryColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            onPressed: () async {
                                              await _updateCartItemQuantity(index, quantity - 1);
                                              setModalState(() {});
                                            },
                                            icon: const Icon(Icons.remove_circle_outline),
                                            color: AppConstants.primaryColor,
                                          ),
                                          Text(
                                            '$quantity',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () async {
                                              await _updateCartItemQuantity(index, quantity + 1);
                                              setModalState(() {});
                                            },
                                            icon: const Icon(Icons.add_circle_outline),
                                            color: AppConstants.primaryColor,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Total and checkout section
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total:',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'SAR ${_getTotalPrice().toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppConstants.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context); // Close cart modal first
                                    Future.delayed(const Duration(milliseconds: 300), () {
                                      _showCheckoutDetailsModal();
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppConstants.primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Checkout',
                                    style: TextStyle(
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
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showFoodDetailsModal(Map<String, dynamic> foodItem) {
    List<Map<String, dynamic>> selectedAddOns = [];
    double totalPrice = foodItem['price'];
    void addAddOn(Map<String, dynamic> addOn) {
      selectedAddOns.add(addOn);
      totalPrice += addOn['price'];
      Navigator.of(context).pop();
      _showFoodDetailsModalWithAddOns(foodItem, selectedAddOns, totalPrice, addAddOn: addAddOn);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${addOn['name']} to cart!'),
          backgroundColor: AppConstants.primaryColor,
        ),
      );
    }
    _showFoodDetailsModalWithAddOns(foodItem, selectedAddOns, totalPrice, addAddOn: addAddOn);
  }

  void _showFoodDetailsModalWithAddOns(
      Map<String, dynamic> foodItem,
      List<Map<String, dynamic>> selectedAddOns,
      double totalPrice, {
        void Function(Map<String, dynamic>)? addAddOn,
      }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final double modalHeight = MediaQuery.of(context).size.height;
        final double imageHeight = modalHeight * 0.6;
        return Container(
          height: modalHeight,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: imageHeight,
                width: double.infinity,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.zero,
                      child: foodItem['image_url'] != null && foodItem['image_url'].toString().isNotEmpty
                          ? Image.network(
                        foodItem['image_url'],
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.grey[200],
                          width: double.infinity,
                          height: double.infinity,
                          child: const Center(child: Icon(Icons.broken_image)),
                        ),
                      )
                          : Image.asset(
                        foodItem['image'] ?? 'assets/images/food_image_1.jpg',
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.grey[200],
                          width: double.infinity,
                          height: double.infinity,
                          child: const Center(child: Icon(Icons.broken_image)),
                        ),
                      ),
                    ),
                    // Overlay Row with only the close button on the right
                    Positioned(
                      top: 32,
                      right: 16,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () {
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha((255 * 0.08).round()),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.close, color: Colors.black87, size: 22),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              foodItem['name'] ?? 'Food Item',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.star,
                            size: 20,
                            color: Colors.amber[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${foodItem['rating'] ?? 4.5} (${foodItem['reviewCount'] ?? 50})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        foodItem['description'] ?? 'No description available',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                      ),
                      if (selectedAddOns.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Add-ons:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        ...selectedAddOns.map((addOn) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                addOn['name'],
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                '+ SAR ${addOn['price'].toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFFd00000),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _showCustomizeOptions(foodItem, addAddOn: addAddOn);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[100],
                            foregroundColor: AppConstants.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: AppConstants.primaryColor,
                                width: 1,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.tune),
                          label: const Text(
                            'Customize',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Price',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                'SAR ${totalPrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppConstants.primaryColor,
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: () async {
                              await _addToCart(foodItem, selectedAddOns);

                              // Close modal first
                              Navigator.pop(context);

                              // Use a post-frame callback to ensure the modal is closed
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Added ${foodItem['name'] ?? 'Food Item'} to cart!'),
                                      backgroundColor: AppConstants.primaryColor,
                                    ),
                                  );

                                  // Navigate to home screen safely
                                  Navigator.of(context).popUntil((route) => route.isFirst);
                                }
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFd00000),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.shopping_cart),
                            label: const Text(
                              'Add to Cart',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const SizedBox(height: 20), // Extra bottom padding
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCustomizeOptions(Map<String, dynamic> foodItem, {void Function(Map<String, dynamic>)? addAddOn}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Customize Your Order',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildAddOnItem('Dessert', 'Chocolate Cake', 8.50, addAddOn),
                  _buildAddOnItem('Dessert', 'Ice Cream', 5.00, addAddOn),
                  _buildAddOnItem('Drink', 'Soft Drink', 3.50, addAddOn),
                  _buildAddOnItem('Drink', 'Fresh Juice', 6.00, addAddOn),
                  _buildAddOnItem('Side', 'French Fries', 4.50, addAddOn),
                  _buildAddOnItem('Side', 'Onion Rings', 5.50, addAddOn),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOnItem(String category, String name, double price, [void Function(Map<String, dynamic>)? addAddOn]) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            category == 'Dessert' ? Icons.cake :
            category == 'Drink' ? Icons.local_drink : Icons.fastfood,
            color: AppConstants.primaryColor,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(category),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SAR ${price.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppConstants.primaryColor,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: addAddOn != null
                  ? () => addAddOn({'name': name, 'price': price})
                  : null,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Add the new method to show the checkout details modal
  void _showCheckoutDetailsModal() {
    final addressController = TextEditingController();
    String paymentMethod = '';
    String onlinePaymentType = '';
    String error = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final double totalPrice = _getTotalPrice();
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Stack(
              children: [
                Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Checkout Details',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Delivery Address',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: addressController,
                          decoration: const InputDecoration(
                            hintText: 'Enter your delivery address',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Payment Method',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Radio<String>(
                              value: 'Online',
                              groupValue: paymentMethod,
                              onChanged: (val) {
                                setModalState(() {
                                  paymentMethod = val!;
                                  onlinePaymentType = '';
                                });
                              },
                            ),
                            const Text('Online'),
                            const SizedBox(width: 16),
                            Radio<String>(
                              value: 'Cash on Delivery',
                              groupValue: paymentMethod,
                              onChanged: (val) {
                                setModalState(() {
                                  paymentMethod = val!;
                                  onlinePaymentType = '';
                                });
                              },
                            ),
                            const Text('Cash on Delivery'),
                          ],
                        ),
                        if (paymentMethod == 'Online') ...[
                          const SizedBox(height: 8),
                          const Text('Select Online Payment Type:', style: TextStyle(fontWeight: FontWeight.w500)),
                          Wrap(
                            spacing: 12,
                            children: [
                              ChoiceChip(
                                label: const Text('Card'),
                                selected: onlinePaymentType == 'Card',
                                onSelected: (selected) {
                                  setModalState(() {
                                    onlinePaymentType = 'Card';
                                  });
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Mada'),
                                selected: onlinePaymentType == 'Mada',
                                onSelected: (selected) {
                                  setModalState(() {
                                    onlinePaymentType = 'Mada';
                                  });
                                },
                              ),
                              ChoiceChip(
                                label: const Text('STC Pay'),
                                selected: onlinePaymentType == 'STC Pay',
                                onSelected: (selected) {
                                  setModalState(() {
                                    onlinePaymentType = 'STC Pay';
                                  });
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Bank Transfer'),
                                selected: onlinePaymentType == 'Bank Transfer',
                                onSelected: (selected) {
                                  setModalState(() {
                                    onlinePaymentType = 'Bank Transfer';
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),
                        const Text(
                          'Order Summary',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200, // Fixed height for the order summary list
                          child: ListView.builder(
                            itemCount: _cartItems.length,
                            itemBuilder: (context, index) {
                              final item = _cartItems[index];
                              final addOns = item['addOns'] as List<Map<String, dynamic>>? ?? [];
                              final quantity = item['quantity'] ?? 1;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: item['image_url'] != null && item['image_url'].toString().isNotEmpty
                                        ? Image.network(
                                      item['image_url'],
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        width: 48,
                                        height: 48,
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.broken_image, size: 24),
                                      ),
                                    )
                                        : Image.asset(
                                      item['image'] ?? 'assets/images/food_image_1.jpg',
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        width: 48,
                                        height: 48,
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.broken_image, size: 24),
                                      ),
                                    ),
                                  ),
                                  title: Text(item['name'] ?? 'Food Item', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (addOns.isNotEmpty)
                                        ...addOns.map((addOn) => Text(
                                          '+ ${addOn['name']} (SAR ${addOn['price'].toStringAsFixed(2)})',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        )),
                                      Text('Qty: $quantity', style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                  trailing: Text(
                                    'SAR ${((item['price'] + addOns.fold(0.0, (total, addOn) => total + addOn['price'])) * quantity).toStringAsFixed(2)}',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: AppConstants.primaryColor),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Delivery fee breakdown
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Subtotal:',
                              style: TextStyle(fontSize: 16),
                            ),
                            Text(
                              'SAR ${(totalPrice - 3.0).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Delivery Fee:',
                              style: TextStyle(fontSize: 16),
                            ),
                            Text(
                              'SAR 3.00',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total:',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'SAR ${totalPrice.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppConstants.primaryColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (addressController.text.trim().isEmpty) {
                                setModalState(() {
                                  error = 'Please enter your delivery address.';
                                });
                                return;
                              }
                              if (paymentMethod.isEmpty) {
                                setModalState(() {
                                  error = 'Please select a payment method.';
                                });
                                return;
                              }
                              if (paymentMethod == 'Online' && onlinePaymentType.isEmpty) {
                                setModalState(() {
                                  error = 'Please select an online payment type.';
                                });
                                return;
                              }
                              if (paymentMethod == 'Online') {
                                Navigator.pop(context); // Close checkout modal
                                Future.delayed(const Duration(milliseconds: 300), () {
                                  _showOnlinePaymentModal(onlinePaymentType);
                                });
                                return;
                              }
                              // Cash on Delivery: Place order directly
                              setModalState(() {
                                error = 'Processing order...';
                              });

                              final orderData = await _createOrder(
                                addressController.text.trim(),
                                paymentMethod,
                              );

                              if (orderData != null) {
                                setModalState(() {
                                  error = '';
                                });

                                // Save cart items before clearing
                                final orderItemsCopy = List<Map<String, dynamic>>.from(_cartItems);

                                // Clear cart
                                await _clearCart();

                                // Close checkout modal first
                                Navigator.pop(context);

                                // Navigate to order confirmation screen
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => OrderConfirmationScreen(
                                      orderId: orderData['orderId'],
                                      orderItems: orderItemsCopy,
                                      totalAmount: orderData['totalAmount'],
                                      deliveryAddress: orderData['deliveryAddress'],
                                      paymentMethod: orderData['paymentMethod'],
                                    ),
                                  ),
                                );
                              } else {
                                setModalState(() {
                                  error = 'Failed to place order. Please try again.';
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConstants.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Place Your Order',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (error.isNotEmpty)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.25), // Dim background
                      child: Center(
                        child: Container(
                          width: 220,
                          height: 100,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppConstants.primaryColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha((255 * 0.08).round()),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: Text(
                                    error,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      error = '';
                                    });
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.close, size: 18, color: Color(0xFFd00000)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // Add the new method for online payment modal
  void _showOnlinePaymentModal(String paymentType) {
    final cardController = TextEditingController();
    final expiryController = TextEditingController();
    final cvvController = TextEditingController();
    final nameController = TextEditingController();
    bool isProcessing = false;
    String error = '';
    final double totalPrice = _getTotalPrice();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.7,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          paymentType == 'Card'
                              ? 'Card Payment'
                              : paymentType == 'Mada'
                              ? 'Mada Payment'
                              : paymentType == 'STC Pay'
                              ? 'STC Pay Payment'
                              : 'Bank Transfer',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Show total amount to pay
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Amount to Pay: SAR ${totalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFd00000),
                        ),
                      ),
                    ),
                    if (paymentType == 'Card' || paymentType == 'Mada') ...[
                      TextField(
                        controller: cardController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Card Number',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: expiryController,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: 'Expiry (MM/YY)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: cvvController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'CVV',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Cardholder Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ] else if (paymentType == 'STC Pay') ...[
                      const Text('You will be redirected to STC Pay to complete your payment.', style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 24),
                    ] else if (paymentType == 'Bank Transfer') ...[
                      const Text('Please transfer the total amount to the following bank account:', style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 12),
                      const Text('Bank: Mappia Bank\nAccount: 1234567890\nIBAN: SA0000000000000000000000', style: TextStyle(fontSize: 15)),
                      const SizedBox(height: 24),
                    ],
                    if (error.isNotEmpty) ...[
                      Text(error, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isProcessing
                            ? null
                            : () async {
                          setModalState(() {
                            isProcessing = true;
                            error = '';
                          });
                          await Future.delayed(const Duration(seconds: 2)); // Simulate payment
                          // Simulate validation
                          if (paymentType == 'Card' || paymentType == 'Mada') {
                            if (cardController.text.length < 12 || expiryController.text.isEmpty || cvvController.text.length < 3 || nameController.text.isEmpty) {
                              setModalState(() {
                                error = 'Please enter valid card details.';
                                isProcessing = false;
                              });
                              return;
                            }
                          }
                          // Simulate random payment failure (10% chance)
                          if (DateTime.now().millisecondsSinceEpoch % 10 == 0) {
                            setModalState(() {
                              error = 'Payment failed. Please try again.';
                              isProcessing = false;
                            });
                            return;
                          }
                          // Success
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Payment successful! Your order has been placed.'),
                                backgroundColor: AppConstants.primaryColor,
                              ),
                            );

                            // Close modal first
                            Navigator.pop(context);

                            // Use a post-frame callback to ensure the modal is closed
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                // Navigate to home screen safely
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              }
                            });

                            await _clearCart();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFd00000),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isProcessing
                            ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                            : Text(
                          paymentType == 'STC Pay'
                              ? 'Continue to STC Pay'
                              : paymentType == 'Bank Transfer'
                              ? 'I have transferred'
                              : 'Pay Now',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Helper function to fetch up to 4 foods for a merchant
  Future<List<Map<String, dynamic>>> fetchPreviewFoods(String merchantId) async {
    try {
      final response = await Supabase.instance.client
          .from('foods')
          .select()
          .eq('created_by', merchantId)
          .order('created_at', ascending: false)
          .limit(4);

      final foods = List<Map<String, dynamic>>.from(response as List);
      return foods;
    } catch (e) {
      return [];
    }
  }

  // Updated food preview card for merchant preview grid - matching View All layout
  Widget buildFoodPreviewCard(Map<String, dynamic> food, int index, {VoidCallback? onAddToCart, VoidCallback? onToggleFavorite, bool isFavorite = false}) {
    return GestureDetector(
      onTap: () => _showFoodDetailsModal(food),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((255 * 0.1).round()),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 120, // Match the Admin Products layout
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                    child: food['image_url'] != null && food['image_url'].toString().isNotEmpty
                        ? Image.network(
                      food['image_url'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.broken_image)),
                      ),
                    )
                        : Container(
                      color: Colors.grey[200],
                      child: const Center(child: Icon(Icons.fastfood)),
                    ),
                  ),
                ),
                // Heart icon overlay
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onToggleFavorite,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha((255 * 0.9).round()),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color: AppConstants.primaryColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food['name'] ?? 'Food Item',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      food['description'] ?? 'No description available',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'SAR ${(food['price'] ?? 0.0).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppConstants.primaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: onAddToCart,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget to display merchant preview with 2x2 grid of food images
  Widget buildMerchantPreview(Map<String, dynamic> merchant) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Merchant name
          Text(
            merchant['name'] ?? merchant['email'] ?? 'Merchant',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          // Food preview grid (2x2)
          FutureBuilder<List<Map<String, dynamic>>>(
            future: fetchPreviewFoods(merchant['id']),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox(
                  height: 180,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fastfood, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          'No products available',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final foods = snapshot.data!;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.62,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: foods.length > 4 ? 4 : foods.length,
                itemBuilder: (context, index) {
                  return buildFoodPreviewCard(
                    foods[index],
                    index,
                    onAddToCart: () async => await _addToCart(foods[index], []),
                    onToggleFavorite: () => _toggleFavorite(foods[index]),
                    isFavorite: _isFavorite(foods[index]),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          // Show more products button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                if (!mounted) return;
                final merchantId = merchant['id']!;
                final merchantName = merchant['name'] ?? merchant['email'] ?? 'Merchant';
                final response = await Supabase.instance.client
                    .from('foods')
                    .select()
                    .eq('created_by', merchantId)
                    .order('created_at', ascending: false);
                if (!mounted) return;
                final merchantFoods = List<Map<String, dynamic>>.from(response as List);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MerchantProductsScreen(
                      merchantName: merchantName,
                      items: merchantFoods,
                      cartItems: _cartItems,
                      onAddToCart: _addToCart,
                      onToggleFavorite: _toggleFavorite,
                      isFavorite: _isFavorite,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 2,
              ),
              child: const Text(
                'View Products',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Fetch all admins/merchants from Supabase who have foods
  Future<List<Map<String, dynamic>>> fetchMerchants() async {
    try {
      // Get all admin users
      final usersResponse = await Supabase.instance.client
          .from('users')
          .select()
          .eq('role', 'admin');
      final allAdmins = List<Map<String, dynamic>>.from(usersResponse as List);

      if (allAdmins.isEmpty) {
        return [];
      }

      // Get all foods with their created_by IDs
      final foodsResponse = await Supabase.instance.client
          .from('foods')
          .select('created_by')
          .not('created_by', 'is', null);
      final allFoods = List<Map<String, dynamic>>.from(foodsResponse as List);

      // Create a set of user IDs who have foods
      final usersWithFoods = allFoods
          .map((food) => food['created_by']?.toString())
          .where((id) => id != null)
          .toSet();

      // Filter admins who have foods
      final merchantsWithFoods = allAdmins
          .where((admin) => usersWithFoods.contains(admin['id']?.toString()))
          .toList();

      return merchantsWithFoods;
    } catch (e) {
      return [];
    }
  }

  // Add fetch functions for dynamic data from Supabase
  Future<List<Map<String, dynamic>>> fetchFoodsPreview() async {
    final response = await Supabase.instance.client
        .from('foods')
        .select()
        .order('created_at', ascending: false)
        .limit(8);
    return List<Map<String, dynamic>>.from(response as List);
  }

  // Update fetchRecommendedFoods to fetch the 6 most recent foods
  Future<List<Map<String, dynamic>>> fetchRecommendedFoods() async {
    final response = await Supabase.instance.client
        .from('foods')
        .select()
        .order('created_at', ascending: false)
        .limit(6);
    return List<Map<String, dynamic>>.from(response as List);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top section with red background
              Container(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingMedium,
                    vertical: AppConstants.paddingMedium,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              AppConstants.borderRadiusMedium,
                            ),
                            border: Border.all(
                              color: AppConstants.primaryColor,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha((255 * 0.04).round()),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _locationController,
                            decoration: InputDecoration(
                              hintText: 'Enter your location',
                              prefixIcon: Icon(
                                Icons.location_on_outlined,
                                color: AppConstants.primaryColor,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: (value) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Searching near: $value')),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.paddingMedium),
                      GestureDetector(
                        onTap: _onAvatarPressed,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.person,
                            color: AppConstants.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.paddingMedium),
                      GestureDetector(
                        onTap: _onCartPressed,
                        child: Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppConstants.primaryColor,
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha((255 * 0.04).round()),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.shopping_cart_outlined,
                                color: Color(0xFFd00000),
                              ),
                            ),
                            if (_cartCount > 0)
                              Positioned(
                                right: 2,
                                top: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFd00000),
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  child: Text(
                                    '$_cartCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 264,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      onPageChanged: _onCarouselIndexChanged,
                      itemCount: null, // Infinite scroll
                      itemBuilder: (context, index) {
                        final imageIndex = index % _carouselImages.length;
                        return Container(
                          width: MediaQuery.of(context).size.width,
                          height: 264,
                          child: Stack(
                            children: [
                              Image.asset(
                                _carouselImages[imageIndex],
                                width: MediaQuery.of(context).size.width,
                                height: 264,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: Colors.grey[200],
                                  child: const Center(child: Icon(Icons.broken_image)),
                                ),
                              ),
                              Container(
                                width: MediaQuery.of(context).size.width,
                                height: 264,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomLeft,
                                    end: Alignment.topRight,
                                    colors: [
                                      Colors.black.withAlpha((255 * 0.6).round()),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    // Text overlay on bottom left
                    Positioned(
                      bottom: 40,
                      left: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Craving something?",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              shadows: [
                                Shadow(
                                  offset: const Offset(1, 1),
                                  blurRadius: 3,
                                  color: Colors.black.withAlpha((255 * 0.8).round()),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              "Let Mappia deliver it fast!",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(
                                    offset: const Offset(1, 1),
                                    blurRadius: 3,
                                    color: Colors.black.withAlpha((255 * 0.8).round()),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Indicator dots
                    Positioned(
                      bottom: 12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _carouselImages.length,
                              (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentPage == index ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index
                                  ? AppConstants.primaryColor
                                  : const Color.fromRGBO(255, 255, 255, 0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // We offer section
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.paddingMedium,
                  vertical: AppConstants.paddingMedium,
                ),
                child: Column(
                  children: [
                    // Header row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'We offer',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ViewAllScreen(
                                  cartItems: _cartItems,
                                  onAddToCart: _addToCart,
                                  favoriteFoods: _favoriteFoods,
                                  onToggleFavorite: _toggleFavorite,
                                  isFavorite: _isFavorite,
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'View all',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Horizontal scrollable food cards
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: buildFoodOfferPreview(),
                    ),
                  ],
                ),
              ),
              // Recommended for you section
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingMedium,
                    vertical: AppConstants.paddingMedium,
                  ),
                  child: Column(
                    children: [
                      // Header row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recommended for you',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Horizontal scrollable recommended food cards
                      buildRecommendedFoods(),
                      const SizedBox(height: 16),
                      // See more button below the cards
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('See more pressed!')),
                            );
                          },
                          child: const Text(
                            'See more',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Merchants section (new, under recommendations)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.paddingMedium,
                  vertical: AppConstants.paddingMedium,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Merchants',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _isLoadingDynamicMerchants
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                        : _dynamicMerchants.isEmpty
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.store, size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No merchants available',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Check back later for new merchants',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                        : Column(
                      children: _dynamicMerchants.map((merchant) {
                        return buildMerchantPreview(merchant);
                      }).toList(),
                    ),
                  ],
                ),
              ),
              // Add bottom padding for navigation bar
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppConstants.primaryColor,
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onNavigationTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppConstants.primaryColor,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white.withAlpha((255 * 0.7).round()),
          elevation: 0,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          iconSize: 20,
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
      ),
    );
  }

  Widget buildFoodOfferPreview() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchFoodsPreview(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
        final foods = snapshot.data!;
        return SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: foods.length,
            itemBuilder: (context, index) {
              final food = foods[index];
              return Container(
                width: 115,
                margin: const EdgeInsets.only(right: 5),
                child: Column(
                  children: [
                    Container(
                      width: 95,
                      height: 95,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha((255 * 0.1).round()),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: food['image_url'] != null && food['image_url'].toString().isNotEmpty
                            ? Image.network(
                          food['image_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: Colors.grey[200],
                            child: const Center(child: Icon(Icons.broken_image)),
                          ),
                        )
                            : Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.fastfood)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      food['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget buildRecommendedFoods() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchRecommendedFoods(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
        final foods = snapshot.data!;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.75,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: foods.length,
          itemBuilder: (context, index) {
            final food = foods[index];
            return GestureDetector(
              onTap: () => _showFoodDetailsModal(food),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((255 * 0.1).round()),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                            child: food['image_url'] != null && food['image_url'].toString().isNotEmpty
                                ? Image.network(
                              food['image_url'],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey[200],
                                child: const Center(child: Icon(Icons.broken_image)),
                              ),
                            )
                                : Container(
                              color: Colors.grey[200],
                              child: const Center(child: Icon(Icons.fastfood)),
                            ),
                          ),
                        ),
                        // Heart icon overlay
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => _toggleFavorite(food),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha((255 * 0.9).round()),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isFavorite(food) ? Icons.favorite : Icons.favorite_border,
                                size: 16,
                                color: AppConstants.primaryColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              food['name'] ?? 'Food Item',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: Text(
                                food['description'] ?? 'No description available',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.black54,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'SAR ${(food['price'] ?? 0.0).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppConstants.primaryColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () async => await _addToCart(food, []),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppConstants.primaryColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

