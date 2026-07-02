import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/data/constants.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/screens/self_order_payment_screen.dart';
import 'package:pos_fnb/services/supabase_service.dart';
import 'package:pos_fnb/widgets/product_image.dart';

class SelfOrderScreen extends StatefulWidget {
  const SelfOrderScreen({super.key});

  @override
  State<SelfOrderScreen> createState() => _SelfOrderScreenState();
}

class _SelfOrderScreenState extends State<SelfOrderScreen> {
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  List<CartItem> _cart = [];
  bool _isLoading = true;
  String _selectedCategory = appCategories[0];
  List<String> _categories = [appCategories[0]];
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final products = await SupabaseService.getProducts();
      final productCategories = await SupabaseService.getProductCategories();
      final loadedCategories = productCategories
          .map((category) => category.name.trim())
          .where((name) => name.isNotEmpty)
          .toList();
      final categoryMap = {
        for (final category in productCategories) category.id: category.name,
      };
      final loadedProducts = products.isEmpty
          ? List<Product>.from(defaultProducts)
          : products;
      final syncedProducts = loadedProducts.map((product) {
        final categoryName = product.categoryId == null
            ? product.categoryName
            : categoryMap[product.categoryId] ?? product.categoryName;

        if (categoryName == product.categoryName) return product;

        return Product(
          id: product.id,
          name: product.name,
          price: product.price,
          imageUrl: product.imageUrl,
          categoryId: product.categoryId,
          categoryName: categoryName,
          isAvailable: product.isAvailable,
        );
      }).toList();

      setState(() {
        _categories = [appCategories[0], ...loadedCategories];
        _selectedCategory = _categories.contains(_selectedCategory)
            ? _selectedCategory
            : _categories.first;
        _allProducts = syncedProducts;
        _filteredProducts = _filterProductList(
          _selectedCategory,
          _searchController.text,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _allProducts = List.from(defaultProducts);
        _categories = [appCategories[0]];
        _selectedCategory = _categories.first;
        _filteredProducts = _allProducts;
        _isLoading = false;
      });
    }
  }

  List<Product> _filterProductList(String category, [String query = '']) {
    return _allProducts.where((p) {
      final matchesCategory =
          category == appCategories[0] || p.categoryName == category;
      final matchesSearch = p.name.toLowerCase().contains(query.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  void _filterProducts(String category, [String query = '']) {
    setState(() {
      _selectedCategory = category;
      _filteredProducts = _filterProductList(category, query);
    });
  }

  void _showProductDetailDialog(Product product, {CartItem? existingItem}) {
    int quantity = existingItem?.quantity ?? 1;
    final noteController = TextEditingController(
      text: existingItem?.note ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      existingItem == null
                          ? product.name
                          : 'Chỉnh sửa: ${product.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (product.imageUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ProductImage(
                              imageUrl: product.imageUrl,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      Text(
                        currencyFormat.format(product.price),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 32,
                              color: Colors.green,
                            ),
                            onPressed: quantity > 1
                                ? () => setDialogState(() => quantity--)
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              '$quantity',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 32,
                              color: Colors.green,
                            ),
                            onPressed: () => setDialogState(() => quantity++),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Ghi chú món:',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: noteController,
                        maxLines: 2,
                        maxLength: 100,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          hintText: 'VD: không rau, thêm chả...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.green, width: 2.2),
                          ),
                          counterText: '${noteController.text.length}/100',
                        ),
                        onChanged: (v) => setDialogState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              actions: [
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      if (existingItem != null) {
                        setState(() {
                          existingItem.quantity = quantity;
                          existingItem.note = noteController.text;
                        });
                      } else {
                        _addToCart(product, quantity, noteController.text);
                      }
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      existingItem == null ? 'THÊM VÀO ĐƠN' : 'CẬP NHẬT',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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

  void _addToCart(Product product, int quantity, String note) {
    setState(() {
      final index = _cart.indexWhere(
        (item) => item.product.id == product.id && item.note == note,
      );
      if (index >= 0) {
        _cart[index].quantity += quantity;
      } else {
        _cart.add(CartItem(product: product, quantity: quantity, note: note));
      }
    });
  }

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get _total => _subtotal * 1.08; // 8% VAT default

  void _placeOrder() async {
    if (_cart.isEmpty) return;

    final order = SavedOrder(
      items: List.from(_cart),
      dateTime: DateTime.now(),
      subtotal: _subtotal,
      discountAmount: 0,
      vatRate: 8,
      vatAmount: _subtotal * 0.08,
      totalAmount: _total,
      paymentMethod: 'qr_code',
      tableOrCustomer: 'Khách QR (Mang đi)',
      source: OrderSource.qrCode,
      status: OrderStatus.pending,
    );

    final savedOrder = await SupabaseService.saveSelfOrder(order);
    if (savedOrder != null && mounted) {
      setState(() {
        _cart.clear();
        _selectedCategory = _categories.first;
        _searchController.clear();
        _filteredProducts = List.from(_allProducts);
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SelfOrderPaymentScreen(order: savedOrder),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Có lỗi xảy ra khi đặt món. Vui lòng thử lại.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MENU GỌI MÓN',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.green,
        centerTitle: true,
        automaticallyImplyLeading: false, // Bỏ nút back
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) =>
                        _filterProducts(_selectedCategory, value),
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm món ăn...',
                      prefixIcon: const Icon(Icons.search, color: Colors.green),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 2.2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 16,
                      ),
                    ),
                  ),
                ),
                _buildCategoryList(),
                Expanded(child: _buildProductGrid()),
                if (_cart.isNotEmpty) _buildBottomCart(),
              ],
            ),
    );
  }

  Widget _buildCategoryList() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              onSelected: (selected) =>
                  _filterProducts(cat, _searchController.text),
              selectedColor: Colors.green,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        final isInCart = _cart.any((item) => item.product.id == product.id);

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showProductDetailDialog(product),
            child: Stack(
              children: [
                Opacity(
                  opacity: isInCart ? 0.4 : 1.0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ProductImage(
                          imageUrl: product.imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              currencyFormat.format(product.price),
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isInCart)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 60,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCartDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ĐƠN HÀNG CỦA BẠN',
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
                  const Divider(),
                  Expanded(
                    child: _cart.isEmpty
                        ? const Center(child: Text('Đơn hàng trống'))
                        : ListView.separated(
                            itemCount: _cart.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final item = _cart[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                onTap: () async {
                                  Navigator.pop(context);
                                  _showProductDetailDialog(
                                    item.product,
                                    existingItem: item,
                                  );
                                },
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: ProductImage(
                                    imageUrl: item.product.imageUrl,
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                title: Text(
                                  item.product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (item.note.isNotEmpty)
                                      Text(
                                        'Ghi chú: ${item.note}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    Text(
                                      currencyFormat.format(item.product.price),
                                      style: const TextStyle(
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.green,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          if (item.quantity > 1) {
                                            item.quantity--;
                                          } else {
                                            _cart.removeAt(index);
                                          }
                                        });
                                        setModalState(() {});
                                      },
                                    ),
                                    Text(
                                      '${item.quantity}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        color: Colors.green,
                                      ),
                                      onPressed: () {
                                        setState(() => item.quantity++);
                                        setModalState(() {});
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _cart.removeAt(index);
                                        });
                                        setModalState(() {});
                                        if (_cart.isEmpty) {
                                          Navigator.pop(context);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tạm tính:', style: TextStyle(fontSize: 16)),
                        Text(
                          currencyFormat.format(_subtotal),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(
                        'CẬP NHẬT ĐƠN HÀNG',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomCart() {
    return GestureDetector(
      onTap: _showCartDialog,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shopping_cart, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        '${_cart.length} loại - ${_cart.fold<int>(0, (p, c) => p + c.quantity)} món',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Tổng: ${currencyFormat.format(_total)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Nhấn để xem chi tiết đơn hàng',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _placeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'ĐẶT MÓN & THANH TOÁN',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
