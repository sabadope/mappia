import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'food_list_screen.dart';
import 'admin_dashboard_screen.dart';
import '../auth/login_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../core/constants/app_constants.dart';
import 'dart:async'; // Added for Timer

class AdminMainScreen extends StatefulWidget {
  final int initialTabIndex;
  const AdminMainScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _ManageScreen extends StatefulWidget {
  const _ManageScreen();

  @override
  State<_ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<_ManageScreen> {
  // Add a GlobalKey for the ScaffoldMessenger
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  XFile? _pickedImage;
  bool _isUploading = false;

  List<Map<String, dynamic>> _foods = [];
  List<Map<String, dynamic>> _filteredFoods = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoadingFoods = false;
  bool _isLoadingCategories = false;
  String? _userId;
  String _selectedCategoryId = 'all';
  String _selectedSort = 'All';
  final List<String> _sortOptions = ['All', 'Best Seller', 'Recent', 'Popular', 'Categories'];

  // Floating notification state
  bool _showNotification = false;
  String _notificationMessage = '';
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserId();
    _fetchCategories();
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

  Future<void> _fetchCurrentUserId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      setState(() {
        _userId = user.id;
      });
      _fetchFoods();
    }
  }

  Future<void> _fetchCategories() async {
    setState(() => _isLoadingCategories = true);
    final response = await Supabase.instance.client
        .from('categories')
        .select();
    final categories = List<Map<String, dynamic>>.from(response as List);
    setState(() {
      _categories = categories;
      _isLoadingCategories = false;
    });
  }

  Future<void> _fetchFoods() async {
    setState(() => _isLoadingFoods = true);
    // Fetch all foods and join with users to get restaurant name
    final response = await Supabase.instance.client
        .from('foods')
        .select('*, users!foods_created_by_fkey(name, email)')
        .order('created_at', ascending: false);
    final foods = List<Map<String, dynamic>>.from(response as List);
    setState(() {
      _foods = foods;
      _applySearchAndSort();
      _isLoadingFoods = false;
    });
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
          score += 20;
        }
        // Optionally, boost by sales/popularity
        score += (food['sales'] ?? 0) as int;
        return {...food, '_searchScore': score};
      }).toList();
      // Only keep foods with score > 0
      filtered = filtered.where((food) => food['_searchScore'] > 0).toList();
      // Sort by score descending
      filtered.sort((a, b) => (b['_searchScore'] as int).compareTo(a['_searchScore'] as int));
    }

    // Category filter
    if (_selectedCategoryId != 'all') {
      filtered = filtered.where((food) => food['category_id'] == _selectedCategoryId).toList();
    }

    // Sorting/filtering
    switch (_selectedSort) {
      case 'Best Seller':
        filtered.sort((a, b) => ((b['sales'] ?? 0) as int).compareTo((a['sales'] ?? 0) as int));
        break;
      case 'Recent':
        filtered.sort((a, b) {
          final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(2000);
          final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(2000);
          return bDate.compareTo(aDate); // Newest first
        });
        break;
      case 'Favorites':
        filtered = filtered.where((food) => food['is_favorite'] == true).toList();
        break;
      case 'Categories':
        filtered.sort((a, b) => ((a['category_id'] ?? '') as String).compareTo((b['category_id'] ?? '') as String));
        break;
      case 'All':
      default:
        break;
    }

    // Remove _searchScore before displaying
    filtered = filtered.map((food) {
      final copy = Map<String, dynamic>.from(food);
      copy.remove('_searchScore');
      return copy;
    }).toList();

    setState(() {
      _filteredFoods = filtered;
    });
  }

  Future<String?> _uploadImage(XFile image) async {
    final fileExt = image.path.split('.').last;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final filePath = 'foods/$fileName';
    final bytes = await image.readAsBytes();
    final response = await Supabase.instance.client.storage
        .from('images')
        .uploadBinary(filePath, bytes, fileOptions: const FileOptions(upsert: true));
    if (response != null && response is String) {
      final publicUrl = Supabase.instance.client.storage
          .from('images')
          .getPublicUrl(filePath);
      return publicUrl;
    }
    return null;
  }

  // Change _showAddOrEditFoodDialog to return a Future<bool?>
  Future<bool?> _showAddOrEditFoodDialog({Map<String, dynamic>? food}) async {
    final isEdit = food != null;
    _nameController.text = food?['name'] ?? '';
    _descController.text = food?['description'] ?? '';
    _priceController.text = food?['price']?.toString() ?? '';
    _pickedImage = null;
    String selectedCategoryId = food?['category_id'] ?? (_categories.isNotEmpty ? _categories.first['id'] : '');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              elevation: 8,
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40), // Increase dialog width
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Move Add/Edit Food text to top
                      Text(isEdit ? 'Edit Food' : 'Add Food', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppConstants.primaryColor)),
                      const SizedBox(height: 18),
                      // Image picker below title
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
                              if (name.isEmpty || price <= 0 || selectedCategoryId.isEmpty) return;
                              final confirmed = await _showConfirmationDialog(
                                isEdit ? 'Update Food' : 'Add Food',
                                isEdit
                                    ? 'Are you sure you want to update "${food!['name']}"?'
                                    : 'Are you sure you want to add "${name}" to your menu?',
                              );
                              if (!confirmed) return;
                              setState(() => _isUploading = true);
                              String? imageUrl = food?['image_url'];
                              if (_pickedImage != null) {
                                imageUrl = await _uploadImage(_pickedImage!);
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
                                  setState(() => _isUploading = false);
                                  Navigator.pop(context, true);
                                  _fetchFoods();
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
                                  setState(() => _isUploading = false);
                                  Navigator.pop(context, true);
                                  _fetchFoods();
                                }
                              } catch (e) {
                                setState(() => _isUploading = false);
                                if (context.mounted) {
                                  _showFloatingNotification('Error ${isEdit ? 'updating' : 'adding'} food: $e', type: 'error');
                                }
                              }
                            },
                            child: _isUploading
                                ? const SizedBox(
                              width: 20,
                              height: 20,
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
            style: ElevatedButton.styleFrom(
              backgroundColor: title.toLowerCase().contains('delete') ? Colors.red : null,
            ),
            child: Text(
              title.toLowerCase().contains('delete') ? 'Delete' : 'Confirm',
              style: TextStyle(
                color: title.toLowerCase().contains('delete') ? Colors.white : null,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteFood(String foodId) async {
    // Find the food item to get its name for the confirmation message
    final food = _foods.firstWhere((f) => f['id'] == foodId);
    final foodName = food['name'] ?? 'this food item';

    // Show confirmation dialog
    final confirmed = await _showConfirmationDialog(
      'Delete Food',
      'Are you sure you want to delete "$foodName"? This action cannot be undone.',
    );

    if (!confirmed) return;

    try {
      await Supabase.instance.client.from('foods').delete().eq('id', foodId);
      _fetchFoods();

      // Show success message
      if (context.mounted) {
        _showFloatingNotification('"$foodName" deleted successfully!', type: 'success');
      }
    } catch (e) {
      if (context.mounted) {
        _showFloatingNotification('Error deleting food: $e', type: 'error');
      }
    }
  }

  Widget _buildFoodDetailSheet(Map<String, dynamic> food) {
    final category = _categories.firstWhere(
      (cat) => cat['id'] == food['category_id'],
      orElse: () => {'name': 'Uncategorized'},
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Drag handle
            Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            // Food image
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: food['image_url'] != null
                  ? Image.network(food['image_url'], width: 160, height: 160, fit: BoxFit.cover)
                  : Container(
                      width: 160,
                      height: 160,
                      color: Colors.grey[200],
                      child: const Icon(Icons.fastfood, size: 64, color: Colors.grey),
                    ),
            ),
            const SizedBox(height: 18),
            // Food name
            Text(
              food['name'] ?? '',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // Price
            Text(
              'SAR ${food['price']?.toStringAsFixed(2) ?? ''}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppConstants.primaryColor),
            ),
            const SizedBox(height: 12),
            // Category
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                category['name'],
                style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            const SizedBox(height: 18),
            // Description
            if ((food['description'] ?? '').toString().isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(
                    food['description'],
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            // Action Buttons
            Row(
              children: [
                // Edit Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context); // Close the bottom sheet
                      final result = await _showAddOrEditFoodDialog(food: food);
                      if (result == true && mounted) {
                        _showFloatingNotification('"${food['name']}" updated successfully!', type: 'success');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.edit, size: 20),
                    label: const Text(
                      'Edit',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Delete Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context); // Close the bottom sheet
                      _deleteFood(food['id']);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.delete, size: 20),
                    label: const Text(
                      'Delete',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
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
            body: _isLoadingFoods
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
                            Builder(
                              builder: (context) {
                                // Group foods by creator
                                final List<Map<String, dynamic>> myFoods = _filteredFoods
                                    .where((food) => food['created_by'] == _userId)
                                    .take(3)
                                    .toList();

                                final Map<String, List<Map<String, dynamic>>> groupedByCreator = {};
                                for (final food in _filteredFoods) {
                                  final creatorId = food['created_by']?.toString();
                                  if (creatorId == null) continue;
                                  if (creatorId == _userId) continue; // skip current admin foods here
                                  groupedByCreator.putIfAbsent(creatorId, () => []);
                                  if (groupedByCreator[creatorId]!.length < 3) {
                                    groupedByCreator[creatorId]!.add(food);
                                  }
                                }

                                Widget foodCard(Map<String, dynamic> food) {
                                  return GestureDetector(
                                    onTap: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (context) => _buildFoodDetailSheet(food),
                                      );
                                    },
                                    child: Container(
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
                                                                    // Restaurant name

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
                                    ),
                                  );
                                }


                                final List<Widget> sectionWidgets = [];

                                // Your Foods section (only if admin has foods in this category)
                                if (myFoods.isNotEmpty) {
                                  sectionWidgets.add(const SizedBox(height: 8));
                                  sectionWidgets.add(
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Your Foods', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                        GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => FoodListScreen(
                                                  title: 'Your Foods',
                                                  creatorId: _userId ?? '',
                                                ),
                                              ),
                                            );
                                          },
                                          child: const Text(
                                            'See more',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppConstants.primaryColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  sectionWidgets.add(const SizedBox(height: 16));
                                  for (final food in myFoods) {
                                    sectionWidgets.add(foodCard(food));
                                  }
                                }

                                // Other restaurants sections
                                groupedByCreator.forEach((creatorId, foods) {
                                  final users = foods.first['users'] as Map<String, dynamic>?;
                                  final creatorName = (users?['name'] as String?)?.trim();
                                  final creatorEmail = (users?['email'] as String?)?.trim();
                                  final header = (creatorName != null && creatorName.isNotEmpty)
                                      ? creatorName
                                      : (creatorEmail != null && creatorEmail.isNotEmpty ? creatorEmail : 'Restaurant');

                                  sectionWidgets.add(const SizedBox(height: 8));
                                  sectionWidgets.add(Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(header, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                      GestureDetector(
                                        onTap: () {
                                          final creatorId = foods.first['created_by']?.toString() ?? '';
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => FoodListScreen(
                                                title: header,
                                                creatorId: creatorId,
                                              ),
                                            ),
                                          );
                                        },
                                        child: const Text(
                                          'See more',
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppConstants.primaryColor),
                                        ),
                                      ),
                                    ],
                                  ));
                                  sectionWidgets.add(const SizedBox(height: 16));
                                  for (final food in foods) {
                                    sectionWidgets.add(foodCard(food));
                                  }
                                });

                                if (myFoods.isEmpty && groupedByCreator.isEmpty) {
                                  sectionWidgets.add(const SizedBox(height: 24));
                                  sectionWidgets.add(
                                    Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.receipt_long,
                                            size: 64,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 16),
                                          Text(
                                            'No foods in this category',
                                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Add foods or choose another category to see items here',
                                            style: TextStyle(color: Colors.grey),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: sectionWidgets,
                                );
                              },
                            ),
                            if (_filteredFoods.isEmpty)
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            floatingActionButton: Padding(
              padding: const EdgeInsets.only(bottom: 86.0), // Move FAB above the bottom nav
              child: FloatingActionButton(
                onPressed: () async {
                  final result = await _showAddOrEditFoodDialog();
                  if (result == true && mounted) {
                    _showFloatingNotification('Food added successfully!', type: 'success');
                  }
                },
                backgroundColor: AppConstants.primaryColor,
                child: const Icon(Icons.add, color: Colors.white),
                tooltip: 'Add Food',
              ),
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
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

// Placeholder screens for other tabs
class _ReportScreen extends StatelessWidget {
  const _ReportScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.assessment,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'Reports',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Coming soon...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Remove FoodManagementScreen and its state class entirely

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen();

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  String _selectedRole = 'rider';
  bool _isLoading = false;

  // Floating notification state
  bool _showNotification = false;
  String _notificationMessage = '';
  Timer? _notificationTimer;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _contactController.dispose();
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

  Future<void> _addUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; });
    try {
      final uuid = Uuid();
      final userId = uuid.v4();
      final bytes = utf8.encode(_passwordController.text);
      final hashedPassword = sha256.convert(bytes).toString();
      final response = await Supabase.instance.client.from('users').insert({
        'id': userId,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'password': hashedPassword,
        'contact': _contactController.text.trim(),
        'role': _selectedRole,
      });
      if (mounted) {
        _showFloatingNotification('User added successfully!', type: 'success');
        _formKey.currentState!.reset();
        _selectedRole = 'rider';
      }
    } catch (e) {
      if (mounted) {
        _showFloatingNotification('Error:  ${e.toString()}', type: 'error');
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
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
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin Settings',
                  style: AppConstants.headingStyle,
                ),
                const SizedBox(height: 24),
                // Add User Form
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Colored header with icon
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
                            Icon(Icons.person_add, color: Colors.white),
                            const SizedBox(width: 12),
                            Text(
                              'Add User (Rider/Restaurant)',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _nameController,
                                decoration: InputDecoration(
                                  labelText: 'Name',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: AppConstants.primaryColor, width: 2),
                                  ),
                                  prefixIcon: const Icon(Icons.person),
                                ),
                                validator: (value) => value == null || value.isEmpty ? 'Enter name' : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _emailController,
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: AppConstants.primaryColor, width: 2),
                                  ),
                                  prefixIcon: const Icon(Icons.email),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  if (value == null || value.isEmpty) return 'Enter email';
                                  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                                  if (!emailRegex.hasMatch(value)) return 'Enter valid email';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: AppConstants.primaryColor, width: 2),
                                  ),
                                  prefixIcon: const Icon(Icons.lock),
                                ),
                                obscureText: true,
                                validator: (value) => value == null || value.isEmpty ? 'Enter password' : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _contactController,
                                decoration: InputDecoration(
                                  labelText: 'Contact',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: AppConstants.primaryColor, width: 2),
                                  ),
                                  prefixIcon: const Icon(Icons.phone),
                                ),
                                validator: (value) => value == null || value.isEmpty ? 'Enter contact' : null,
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: _selectedRole,
                                items: const [
                                  DropdownMenuItem(value: 'rider', child: Text('Rider')),
                                  DropdownMenuItem(value: 'restaurant', child: Text('Restaurant')),
                                ],
                                onChanged: (value) {
                                  if (value != null) setState(() { _selectedRole = value; });
                                },
                                decoration: InputDecoration(
                                  labelText: 'Role',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: AppConstants.primaryColor, width: 2),
                                  ),
                                  prefixIcon: const Icon(Icons.group),
                                ),
                                dropdownColor: Colors.white,
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading ? null : _addUser,
                                  style: AppConstants.primaryButton,
                                  icon: _isLoading
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.person_add, color: Colors.white),
                                  label: Text(
                                    _isLoading ? 'Adding...' : 'Add User',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Settings Card
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.admin_panel_settings, color: AppConstants.primaryColor),
                        title: Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Manage system settings'),
                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                        onTap: () {
                          _showFloatingNotification('Admin Panel coming soon!', type: 'info');
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
                        leading: Icon(Icons.logout, color: Colors.red),
                        title: Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                        subtitle: Text('Sign out of admin account'),
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
        // Floating notification
        if (_showNotification)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              color: AppConstants.primaryColor,
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.white, size: 24),
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

// Restore the _AdminMainScreenState class
class _AdminMainScreenState extends State<AdminMainScreen> {
  late int _currentIndex;

  final List<Widget> _screens = [
    const AdminDashboardScreen(),
    const _ReportScreen(),
    const _ManageScreen(), // Manage tab
    const _SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
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
                        icon: Icon(Icons.home),
                        label: '',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.assessment),
                        label: '',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.assignment),
                        // Clipboard icon for Manage
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