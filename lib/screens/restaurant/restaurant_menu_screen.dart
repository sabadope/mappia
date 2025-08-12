import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../../core/constants/app_constants.dart';
import 'dart:async'; // Added for Timer

class RestaurantMenuScreen extends StatefulWidget {
  final String? userId;
  const RestaurantMenuScreen({super.key, this.userId});

  @override
  State<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends State<RestaurantMenuScreen> {
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  List<Map<String, dynamic>> _foods = [];
  List<Map<String, dynamic>> _filteredFoods = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _userId;
  String _selectedCategoryId = 'all';
  String _selectedSort = 'All';
  
  // Controllers for food form
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  XFile? _pickedImage;
  
  final List<String> _sortOptions = ['All', 'Name', 'Price', 'Date'];

  // Floating notification state
  bool _showNotification = false;
  String _notificationMessage = '';
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
    _fetchCategories();
    _fetchFoods();
  }

  Future<void> _getCurrentUser() async {
    // Check if userId was passed from dashboard
    if (widget.userId != null) {
      _userId = widget.userId;
      print('DEBUG MENU: User ID set from widget: $_userId');
      return;
    }
    
    // Fallback to Supabase Auth (for admin users)
    final user = Supabase.instance.client.auth.currentUser;
    print('DEBUG MENU: Current user: ${user?.id}');
    print('DEBUG MENU: User email: ${user?.email}');
    if (user != null) {
      _userId = user.id;
      print('DEBUG MENU: User ID set from Supabase Auth: $_userId');
    } else {
      print('DEBUG MENU: No user found!');
    }
  }

  Future<void> _fetchCategories() async {
    try {
      print('DEBUG MENU: Fetching categories...');
      final response = await Supabase.instance.client
          .from('categories')
          .select('*')
          .order('name');
      print('DEBUG MENU: Categories response: $response');
      setState(() {
        _categories = List<Map<String, dynamic>>.from(response);
      });
      print('DEBUG MENU: Categories count: ${_categories.length}');
    } catch (e) {
      print('DEBUG MENU: Error fetching categories: $e');
    }
  }

  Future<void> _fetchFoods() async {
    print('DEBUG MENU: Fetching foods for user: $_userId');
    if (_userId == null) {
      print('DEBUG MENU: User ID is null, returning');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      print('DEBUG MENU: Executing Supabase query...');
      final response = await Supabase.instance.client
          .from('foods')
          .select('*, categories(name)')
          .eq('created_by', _userId!)
          .order('created_at', ascending: false);
      
      print('DEBUG MENU: Query response: $response');
      
      print('DEBUG MENU: Foods count: ${response.length}');
      
      // Debug: Check image URLs
      for (final food in response) {
        print('DEBUG MENU: Food "${food['name']}" has image_url: ${food['image_url']}');
      }
      
      setState(() {
        _foods = List<Map<String, dynamic>>.from(response);
        _applySearchAndSort();
        _isLoading = false;
      });
    } catch (e) {
      print('DEBUG MENU: Error fetching foods: $e');
      setState(() => _isLoading = false);
    }
  }

  void _applySearchAndSort() {
    String query = _searchController.text.trim().toLowerCase();
    List<Map<String, dynamic>> filtered = _foods;

    if (query.isNotEmpty) {
      // Score foods based on relevance
      filtered = filtered.map((food) {
        final name = (food['name'] ?? '').toString().toLowerCase();
        final desc = (food['description'] ?? '').toString().toLowerCase();
        int score = 0;
        if (name.startsWith(query)) {
          score += 100;
        } else if (name.contains(query)) {
          score += 50;
        }
        if (desc.contains(query)) {
          score += 25;
        }
        return {...food, '_score': score};
      }).where((food) => food['_score'] > 0).toList();
      
      // Sort by relevance score
      filtered.sort((a, b) => (b['_score'] ?? 0).compareTo(a['_score'] ?? 0));
    }

    // Apply category filter
    if (_selectedCategoryId != 'all') {
      filtered = filtered.where((food) => food['category_id'] == _selectedCategoryId).toList();
    }

    // Apply sorting
    switch (_selectedSort) {
      case 'Name':
        filtered.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
        break;
      case 'Price':
        filtered.sort((a, b) => (a['price'] ?? 0.0).compareTo(b['price'] ?? 0.0));
        break;
      case 'Date':
        filtered.sort((a, b) => (a['created_at'] ?? '').toString().compareTo((b['created_at'] ?? '').toString()));
        break;
    }

    setState(() {
      _filteredFoods = filtered;
    });
  }

  Future<String?> _uploadImage(XFile image) async {
    try {
      final fileExt = image.path.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'foods/$fileName';
      final bytes = await image.readAsBytes();
      
      print('DEBUG: Uploading image to path: $filePath');
      print('DEBUG: File size: ${bytes.length} bytes');
      print('DEBUG: File extension: $fileExt');
      
      final response = await Supabase.instance.client.storage
          .from('images')
          .uploadBinary(filePath, bytes, fileOptions: const FileOptions(upsert: true));
      
      print('DEBUG: Upload response type: ${response.runtimeType}');
      print('DEBUG: Upload response: $response');
      
      if (response != null && response is String) {
        final imageUrl = Supabase.instance.client.storage
            .from('images')
            .getPublicUrl(filePath);
        
        print('DEBUG: Image uploaded successfully. URL: $imageUrl');
        return imageUrl;
      }
      
      print('DEBUG: Upload response was null or not a string: $response');
      return null;
    } catch (e) {
      print('DEBUG: Error uploading image: $e');
      print('DEBUG: Error stack trace: ${StackTrace.current}');
      return null;
    }
  }

  Future<bool> _showConfirmationDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool?> _showAddOrEditFoodDialog({Map<String, dynamic>? food}) async {
    final isEdit = food != null;
    _nameController.text = food?['name'] ?? '';
    _descController.text = food?['description'] ?? '';
    _priceController.text = food?['price']?.toString() ?? '';
    _pickedImage = null;
    String selectedCategoryId = food?['category_id']?.toString() ?? (_categories.isNotEmpty ? _categories.first['id'].toString() : '');
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              elevation: 8,
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        isEdit ? 'Edit Food' : 'Add Food',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppConstants.primaryColor)
                      ),
                      const SizedBox(height: 18),
                      
                      // Image picker
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 96,
                              height: 96,
                              color: Colors.grey[200],
                              child: _pickedImage != null
                                  ? Image.file(File(_pickedImage!.path), fit: BoxFit.cover)
                                  : (food != null && food['image_url'] != null)
                                      ? Image.network(food['image_url'], fit: BoxFit.cover)
                                      : const Icon(Icons.fastfood, size: 40, color: Colors.grey),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: InkWell(
                              onTap: () async {
                                final ImagePicker picker = ImagePicker();
                                final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                                if (image != null) {
                                  setStateDialog(() {
                                    _pickedImage = image;
                                  });
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppConstants.primaryColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                                ),
                                padding: const EdgeInsets.all(8),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Food name and price fields with same width
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Name',
                                prefixIcon: Icon(Icons.fastfood, color: AppConstants.primaryColor),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _priceController,
                              decoration: InputDecoration(
                                labelText: 'Price',
                                prefixIcon: Icon(Icons.attach_money, color: AppConstants.primaryColor),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _descController,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          prefixIcon: Icon(Icons.description, color: AppConstants.primaryColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                                                                                                                  // Fixed category dropdown - match height with other input fields
                       DropdownButtonFormField<String>(
                         value: selectedCategoryId.isNotEmpty ? selectedCategoryId : null,
                         items: _categories.map((cat) {
                           // Define category colors
                           Color getCategoryColor(String categoryName) {
                             switch (categoryName.toLowerCase()) {
                               case 'main course':
                               case 'main':
                                 return Colors.red.withOpacity(0.1);
                               case 'beverage':
                               case 'drink':
                                 return Colors.blue.withOpacity(0.1);
                               case 'seafood':
                                 return Colors.cyan.withOpacity(0.1);
                               case 'grilled & bbq':
                               case 'grilled':
                               case 'bbq':
                                 return Colors.orange.withOpacity(0.1);
                               case 'pastries':
                               case 'pastry':
                                 return Colors.purple.withOpacity(0.1);
                               case 'desserts':
                               case 'dessert':
                                 return Colors.yellow.withOpacity(0.1);
                               case 'snacks':
                               case 'snack':
                                 return Colors.green.withOpacity(0.1);
                               case 'etc':
                               case 'other':
                                 return Colors.grey.withOpacity(0.1);
                               default:
                                 return Colors.indigo.withOpacity(0.1);
                             }
                           }
                           
                           return DropdownMenuItem<String>(
                             value: cat['id'],
                             child: Container(
                               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                               decoration: BoxDecoration(
                                 color: getCategoryColor(cat['name'] ?? ''),
                                 borderRadius: BorderRadius.circular(8),
                               ),
                               child: Text(
                                 cat['name'] ?? '',
                                 style: TextStyle(
                                   color: AppConstants.primaryColor, 
                                   fontWeight: FontWeight.w500,
                                   fontSize: 14,
                                 ),
                                 overflow: TextOverflow.ellipsis, // Prevent text cutoff
                               ),
                             ),
                           );
                         }).toList(),
                        onChanged: (value) {
                          setStateDialog(() {
                            selectedCategoryId = value ?? '';
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Category',
                          prefixIcon: Icon(Icons.restaurant_menu, color: AppConstants.primaryColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), // Increase vertical padding
                        ),
                        dropdownColor: Colors.white,
                        isExpanded: true, // Make dropdown expand to full width
                        menuMaxHeight: 250, // Limit dropdown height
                      ),
                      const SizedBox(height: 24),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConstants.primaryColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            ),
                            onPressed: _isUploading
                                ? null
                                : () async {
                                    final name = _nameController.text.trim();
                                    final desc = _descController.text.trim();
                                    final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
                                    
                                    if (name.isEmpty || price <= 0 || selectedCategoryId.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please fill all required fields'), backgroundColor: Colors.red),
                                      );
                                      return;
                                    }
                                    
                                    final confirmed = await _showConfirmationDialog(
                                      isEdit ? 'Update Food Item' : 'Add Food Item',
                                      isEdit 
                                        ? 'Are you sure you want to update "$name"?'
                                        : 'Are you sure you want to add "$name" to your menu?',
                                    );
                                    
                                    if (!confirmed) return;
                                    
                                    setState(() => _isUploading = true);
                                    String? imageUrl = food?['image_url'];
                                    
                                                                         if (_pickedImage != null) {
                                       print('DEBUG: Uploading picked image...');
                                       imageUrl = await _uploadImage(_pickedImage!);
                                       print('DEBUG: Upload result - imageUrl: $imageUrl');
                                     }
                                    
                                    try {
                                                                             if (isEdit) {
                                         await Supabase.instance.client
                                             .from('foods')
                                             .update({
                                               'name': name,
                                               'description': desc,
                                               'price': price,
                                               'image_url': imageUrl,
                                               'category_id': selectedCategoryId,
                                             })
                                             .eq('id', food!['id']);
                                       } else {
                                         await Supabase.instance.client
                                             .from('foods')
                                             .insert({
                                               'name': name,
                                               'description': desc,
                                               'price': price,
                                               'image_url': imageUrl,
                                               'created_by': _userId,
                                               'category_id': selectedCategoryId,
                                             });
                                       }
                                      
                                      setState(() => _isUploading = false);
                                      Navigator.pop(context, true);
                                      _fetchFoods();
                                      
                                      if (mounted) {
                                        _showFloatingNotification(
                                          isEdit ? 'Food item updated successfully!' : 'Food item added successfully!',
                                          type: 'success'
                                        );
                                      }
                                    } catch (e) {
                                      setState(() => _isUploading = false);
                                      if (mounted) {
                                        _showFloatingNotification('Error: $e', type: 'error');
                                      }
                                    }
                                  },
                            child: _isUploading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(isEdit ? 'Save' : 'Add', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    return result;
  }

  Future<void> _deleteFood(String foodId) async {
    final food = _foods.firstWhere((f) => f['id'] == foodId);
    final foodName = food['name'] ?? 'this food item';
    
    final confirmed = await _showConfirmationDialog(
      'Delete Food Item',
      'Are you sure you want to delete "$foodName"? This action cannot be undone.',
    );
    
    if (!confirmed) return;
    
    try {
      await Supabase.instance.client.from('foods').delete().eq('id', foodId);
      _fetchFoods();
      
      if (mounted) {
        _showFloatingNotification('"$foodName" deleted successfully!', type: 'success');
      }
    } catch (e) {
      if (mounted) {
        _showFloatingNotification('Error deleting food: $e', type: 'error');
      }
    }
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

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _searchController.dispose();
    _notificationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Exchange the position of 'Beverages' and 'Seafood' in categories
    List<Map<String, dynamic>> reorderedCategories = List<Map<String, dynamic>>.from(_categories);
    int seafoodIdx = reorderedCategories.indexWhere((cat) => (cat['name']?.toLowerCase() ?? '') == 'seafood');
    int beveragesIdx = reorderedCategories.indexWhere((cat) => (cat['name']?.toLowerCase() ?? '') == 'beverages');
    if (seafoodIdx != -1 && beveragesIdx != -1 && seafoodIdx > beveragesIdx) {
      final seafood = reorderedCategories.removeAt(seafoodIdx);
      reorderedCategories.insert(beveragesIdx, seafood);
    }
    final List<Map<String, dynamic>> categories = [
      {'id': 'all', 'name': 'All'},
      ...reorderedCategories
    ];
    
    return Stack(
      children: [
        ScaffoldMessenger(
          key: _scaffoldMessengerKey,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Manage Foods'),
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async => _fetchFoods(),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Column(
                          children: [
                            // --- Search & Filter Container ---
                            Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppConstants.primaryColor,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(0),
                                      topRight: Radius.circular(0),
                                      bottomLeft: Radius.circular(32),
                                      bottomRight: Radius.circular(32),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.10),
                                        blurRadius: 24,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // Search bar with button inside
                                        Expanded(
                                          flex: 3,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller: _searchController,
                                                    decoration: InputDecoration(
                                                      hintText: 'Search food...',
                                                      border: InputBorder.none,
                                                      isCollapsed: false,
                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                                      prefixIcon: const Icon(Icons.search, color: AppConstants.primaryColor),
                                                    ),
                                                    textAlignVertical: TextAlignVertical.center,
                                                    onSubmitted: (value) {
                                                      _applySearchAndSort();
                                                    },
                                                  ),
                                                ),
                                                // Search button with inner border
                                                Container(
                                                  decoration: BoxDecoration(
                                                    color: AppConstants.primaryColor,
                                                    borderRadius: const BorderRadius.only(
                                                      topRight: Radius.circular(12),
                                                      bottomRight: Radius.circular(12),
                                                    ),
                                                    border: Border.all(
                                                      color: Colors.white,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: Material(
                                                    color: Colors.transparent,
                                                    borderRadius: const BorderRadius.only(
                                                      topRight: Radius.circular(12),
                                                      bottomRight: Radius.circular(12),
                                                    ),
                                                    child: InkWell(
                                                      borderRadius: const BorderRadius.only(
                                                        topRight: Radius.circular(12),
                                                        bottomRight: Radius.circular(12),
                                                      ),
                                                      onTap: _applySearchAndSort,
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                                        child: const Icon(Icons.arrow_forward, color: Colors.white),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Sort filter as button with dropdown inside
                                        Expanded(
                                          flex: 2,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: AppConstants.primaryColor.withOpacity(0.2)),
                                            ),
                                            child: DropdownButtonHideUnderline(
                                              child: ButtonTheme(
                                                alignedDropdown: true,
                                                child: DropdownButton<String>(
                                                  value: _selectedSort,
                                                  isExpanded: true,
                                                  icon: const Icon(Icons.arrow_drop_down, color: AppConstants.primaryColor),
                                                  style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.w600),
                                                  dropdownColor: Colors.white,
                                                  borderRadius: BorderRadius.circular(12),
                                                  items: _sortOptions.map((option) {
                                                    return DropdownMenuItem<String>(
                                                      value: option,
                                                      child: Text(option, style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.w600)),
                                                    );
                                                  }).toList(),
                                                  onChanged: (value) {
                                                    if (value != null) {
                                                      setState(() {
                                                        _selectedSort = value;
                                                      });
                                                      _applySearchAndSort();
                                                    }
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4), // 8px gap below the container
                              ],
                            ),
                            // --- Food List and Title ---
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                                children: [
                                  // --- Category Horizontal Scroll ---
                                  const SizedBox(height: 8), // 2 spaces margin above
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: SizedBox(
                                      height: 48,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(horizontal: 0),
                                        itemCount: categories.length,
                                        separatorBuilder: (context, idx) => const SizedBox(width: 8),
                                        itemBuilder: (context, idx) {
                                          final cat = categories[idx];
                                          final bool isSelected = cat['id'] == _selectedCategoryId;
                                          return Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(24),
                                              onTap: () {
                                                setState(() {
                                                  _selectedCategoryId = cat['id'];
                                                  _applySearchAndSort();
                                                });
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                                decoration: BoxDecoration(
                                                  color: isSelected ? AppConstants.primaryColor : Colors.white,
                                                  borderRadius: BorderRadius.circular(24),
                                                  border: Border.all(color: AppConstants.primaryColor.withOpacity(0.15)),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.04),
                                                      blurRadius: 4,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    cat['name'],
                                                    style: TextStyle(
                                                      color: isSelected ? Colors.white : AppConstants.primaryColor,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // Food cards
                                  ...(_filteredFoods.map((food) => Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    child: Material(
                                      elevation: 4,
                                      borderRadius: BorderRadius.circular(20),
                                      color: Colors.white,
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Image left, vertically centered, larger size
                                            Container(
                                              width: 92,
                                              height: 92,
                                              alignment: Alignment.center,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(16),
                                                child: food['image_url'] != null
                                                    ? Image.network(food['image_url'], width: 92, height: 92, fit: BoxFit.cover)
                                                    : Container(
                                                  width: 92,
                                                  height: 92,
                                                  color: Colors.grey[200],
                                                  child: const Icon(Icons.fastfood, size: 44, color: Colors.grey),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 18),
                                            // Main info column
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // Grouped container for food name, restaurant name, 3-dot menu, and details
                                                  Container(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Text(
                                                                    food['name'] ?? '',
                                                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                                                    maxLines: 1,
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                  const SizedBox(height: 1),
                                                                  // Details in one line, ellipsis if overflow
                                                                  Text(
                                                                    food['description'] ?? '',
                                                                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                                                                    maxLines: 1,
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            PopupMenuButton<String>(
                                                              icon: const Icon(Icons.more_vert, color: Colors.grey),
                                                              onSelected: (value) async {
                                                                if (value == 'edit') {
                                                                  final result = await _showAddOrEditFoodDialog(food: food);
                                                                  if (result == true && mounted) {
                                                                    _showFloatingNotification('"${food['name']}" updated successfully!', type: 'success');
                                                                  }
                                                                } else if (value == 'delete') {
                                                                  _deleteFood(food['id']);
                                                                }
                                                              },
                                                              itemBuilder: (context) => const [
                                                                PopupMenuItem(
                                                                  value: 'edit',
                                                                  child: ListTile(
                                                                    leading: Icon(Icons.edit, color: Colors.blue),
                                                                    title: Text('Edit'),
                                                                  ),
                                                                ),
                                                                PopupMenuItem(
                                                                  value: 'delete',
                                                                  child: ListTile(
                                                                    leading: Icon(Icons.delete, color: Colors.red),
                                                                    title: Text('Delete'),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 2),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  // Category and price row beneath the grouped container
                                                  Row(
                                                    children: [
                                                      Builder(
                                                        builder: (context) {
                                                          final category = _categories.firstWhere(
                                                            (cat) => cat['id'] == food['category_id'],
                                                            orElse: () => {'name': 'Uncategorized'},
                                                          );
                                                          Color getCategoryColor(String categoryName) {
                                                            switch (categoryName.toLowerCase()) {
                                                              case 'main course':
                                                              case 'main':
                                                                return Colors.red.withOpacity(0.1);
                                                              case 'beverage':
                                                              case 'drink':
                                                                return Colors.blue.withOpacity(0.1);
                                                              case 'seafood':
                                                                return Colors.cyan.withOpacity(0.1);
                                                              case 'grilled & bbq':
                                                              case 'grilled':
                                                              case 'bbq':
                                                                return Colors.orange.withOpacity(0.1);
                                                              case 'pastries':
                                                              case 'pastry':
                                                                return Colors.purple.withOpacity(0.1);
                                                              case 'desserts':
                                                              case 'dessert':
                                                                return Colors.yellow.withOpacity(0.1);
                                                              case 'snacks':
                                                              case 'snack':
                                                                return Colors.green.withOpacity(0.1);
                                                              case 'etc':
                                                              case 'other':
                                                                return Colors.grey.withOpacity(0.1);
                                                              default:
                                                                return Colors.indigo.withOpacity(0.1);
                                                            }
                                                          }
                                                          return Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                            decoration: BoxDecoration(
                                                              color: getCategoryColor(category['name'] ?? ''),
                                                              borderRadius: BorderRadius.circular(12),
                                                            ),
                                                            child: Text(
                                                              category['name'],
                                                              style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.w600, fontSize: 12),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                      const Spacer(),
                                                      Text(
                                                        'SAR ${food['price']?.toStringAsFixed(2) ?? ''}',
                                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppConstants.primaryColor),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ))),
                                  if (_filteredFoods.isEmpty)
                                    const Center(child: Text('No foods found. Add your first food!')),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => _showAddOrEditFoodDialog(),
              backgroundColor: AppConstants.primaryColor,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ),
        // Floating notification overlay
        if (_showNotification)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              decoration: BoxDecoration(
                color: _getNotificationColor(_notificationType),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
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