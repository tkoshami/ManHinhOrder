import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/data/constants.dart';
import 'package:pos_fnb/data/order_data.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/screens/feedback_screen.dart';
import 'package:pos_fnb/screens/login_screen.dart';
import 'package:pos_fnb/services/supabase_service.dart';
import 'package:pos_fnb/widgets/cart_item_tile.dart';
import 'package:pos_fnb/widgets/product_card.dart';
import 'package:pos_fnb/widgets/product_image.dart';
import 'package:pos_fnb/widgets/real_time_clock.dart';
import 'package:pos_fnb/widgets/vietqr_display.dart';

class StaffOrderScreen extends StatefulWidget {
  final UserAccount user;
  const StaffOrderScreen({super.key, required this.user});

  @override
  State<StaffOrderScreen> createState() => _StaffOrderScreenState();
}

class _StaffOrderScreenState extends State<StaffOrderScreen> {
  List<Product> _allProducts = [];
  bool _isLoadingProducts = true;
  List<Product> _filteredProducts = [];
  List<CartItem> _cart = [];

  String _selectedCategory = appCategories[0];
  List<String> _categories = [appCategories[0]];
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);
    final products = await SupabaseService.getProducts();
    final productCategories = await SupabaseService.getProductCategories();
    final loadedCategories = productCategories
        .map((category) => category.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final categoryMap = {
      for (final category in productCategories) category.id: category.name,
    };

    setState(() {
      _categories = [appCategories[0], ...loadedCategories];
      _selectedCategory = _categories.first;
      final loadedProducts = products.isEmpty
          ? List<Product>.from(defaultProducts)
          : products;
      _allProducts = loadedProducts.map((product) {
        final categoryName = product.categoryId == null
            ? product.categoryName
            : categoryMap[product.categoryId] ?? product.categoryName;

        if (categoryName == product.categoryName) return product;

        return Product(
          id: product.id,
          categoryId: product.categoryId,
          name: product.name,
          price: product.price,
          imageUrl: product.imageUrl,
          categoryName: categoryName,
          isAvailable: product.isAvailable,
        );
      }).toList();
      _filteredProducts = _allProducts;
      _isLoadingProducts = false;
    });
  }

  double get _subtotal => _cart.fold(0.0, (sum, item) => sum + item.total);

  double _responsiveDialogWidth(BuildContext context, double desiredWidth) {
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    return desiredWidth.clamp(0, availableWidth).toDouble();
  }

  void _filterProducts(String query) {
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesSearch = p.name.toLowerCase().contains(
          query.toLowerCase(),
        );
        final matchesCategory =
            _selectedCategory == _categories.first ||
            p.categoryName == _selectedCategory;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  void _addToCart(Product product, {int quantity = 1, String note = ''}) {
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

  void _showProductDetailDialog(Product product) {
    int quantity = 1;
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            product.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: _responsiveDialogWidth(context, 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (product.imageUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
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
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Số lượng:'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red,
                        ),
                        onPressed: () {
                          if (quantity > 1) {
                            setDialogState(() => quantity--);
                          }
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '$quantity',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: Colors.green,
                        ),
                        onPressed: () {
                          if (quantity < 100) {
                            setDialogState(() => quantity++);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    decoration: InputDecoration(
                      labelText: 'Ghi chú (ví dụ: ít đá, không đường...)',
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
                        borderSide: const BorderSide(color: Colors.blueAccent, width: 2.2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () {
                _addToCart(
                  product,
                  quantity: quantity,
                  note: noteController.text.trim(),
                );
                Navigator.pop(dialogCtx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
              ),
              child: const Text(
                'THÊM VÀO ĐƠN',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      final newQty = _cart[index].quantity + delta;
      if (newQty <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index].quantity = newQty > 100 ? 100 : newQty;
      }
    });
  }

  void _showEditCartDialog(int index) {
    final item = _cart[index];
    int quantity = item.quantity;
    final qtyController = TextEditingController(text: '$quantity');
    final noteController = TextEditingController(text: item.note);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Chỉnh sửa: ${item.product.name}'),
          content: SizedBox(
            width: _responsiveDialogWidth(context, 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.product.imageUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ProductImage(
                          imageUrl: item.product.imageUrl,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  const Text('Số lượng:'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red,
                        ),
                        onPressed: () {
                          if (quantity > 1) {
                            setDialogState(() {
                              quantity--;
                              qtyController.text = '$quantity';
                            });
                          } else {
                            Navigator.pop(context);
                            setState(() => _cart.removeAt(index));
                          }
                        },
                      ),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: qtyController,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: false,
                            decimal: false,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (v) {
                            if (v.isEmpty || v == '0') {
                              // Allow empty during typing
                            } else {
                              final val = int.tryParse(v) ?? 1;
                              setDialogState(
                                () => quantity = val > 100 ? 100 : val,
                              );
                              if (val > 100) {
                                qtyController.text = '100';
                                qtyController.selection =
                                    TextSelection.fromPosition(
                                      const TextPosition(offset: 3),
                                    );
                              }
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: Colors.green,
                        ),
                        onPressed: () {
                          if (quantity < 100) {
                            setDialogState(() {
                              quantity++;
                              qtyController.text = '$quantity';
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    decoration: InputDecoration(
                      labelText: 'Ghi chú',
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
                        borderSide: const BorderSide(color: Colors.blueAccent, width: 2.2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  if (quantity <= 0) {
                    _cart.removeAt(index);
                  } else {
                    _cart[index].quantity = quantity;
                    _cart[index].note = noteController.text;
                  }
                });
                Navigator.pop(context);
              },
              child: const Text('LƯU'),
            ),
          ],
        ),
      ),
    );
  }

  void _submitOrder() {
    if (_cart.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('Phương thức thanh toán')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.send, color: Colors.blue),
              title: const Text('Gửi thu ngân (Thanh toán sau)'),
              onTap: () {
                Navigator.pop(context);
                _processOrder(null);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code, color: Colors.green),
              title: const Text('Khách chuyển khoản ngay'),
              onTap: () {
                Navigator.pop(context);
                _showVietQRDialog();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );
  }

  void _showVietQRDialog() {
    final subtotal = _subtotal;
    final orderId = (DateTime.now().millisecondsSinceEpoch % 1000000)
        .toString();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Center(
          child: Text(
            'QUÉT MÃ VIETQR',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        content: VietQRDisplay(amount: subtotal.toInt(), description: orderId),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('HỦY'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _processOrder('qr_code', manualId: orderId);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text(
                    'XÁC NHẬN ĐÃ CHUYỂN',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _processOrder(String? paymentMethod, {String? manualId}) async {
    final subtotal = _subtotal;
    final newOrder = SavedOrder(
      id:
          manualId ??
          (DateTime.now().millisecondsSinceEpoch % 10000000).toString(),
      shiftId: null,
      tableOrCustomer: 'Đơn từ Staff',
      items: List<CartItem>.from(_cart),
      dateTime: DateTime.now(),
      subtotal: subtotal,
      discountAmount: 0,
      vatRate: 0,
      vatAmount: 0,
      totalAmount: subtotal,
      paymentMethod: paymentMethod ?? 'cash',
      cashierName: widget.user.name,
      source: OrderSource.posStaff,
      status: paymentMethod == null
          ? OrderStatus.pending
          : OrderStatus.completed,
    );

    final savedOrder = await SupabaseService.saveOrder(newOrder);

    setState(() {
      if (paymentMethod == null) {
        globalPendingOrders.add(savedOrder ?? newOrder);
      }
      _cart = [];
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          paymentMethod == null
              ? 'Đã gửi đơn thành công!'
              : 'Đã thanh toán thành công!',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isCompact = MediaQuery.sizeOf(context).width < 700;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ĐẶT MÓN',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: RealTimeClock(),
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FeedbackScreen(currentUser: widget.user),
              ),
            ),
            icon: const Icon(Icons.feedback_outlined, color: Colors.white),
            label: const Text(
              'PHẢN HỒI',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          ),
        ],
      ),
      body: isCompact
          ? Column(
              children: [
                Expanded(child: _buildProductPanel()),
                Container(
                  height: MediaQuery.sizeOf(context).height * 0.42,
                  color: Colors.white,
                  child: _buildCartPanel(),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: _buildProductPanel()),
                Container(
                  width: 350,
                  color: Colors.white,
                  child: _buildCartPanel(),
                ),
              ],
            ),
    );
  }

  Widget _buildProductPanel() {
    final bool isCompact = MediaQuery.sizeOf(context).width < 700;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(isCompact ? 8 : 12),
          child: TextField(
            controller: _searchController,
            onChanged: _filterProducts,
            decoration: InputDecoration(
              hintText: 'Tìm món...',
              prefixIcon: const Icon(Icons.search),
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
                borderSide: const BorderSide(color: Colors.blueAccent, width: 2.2),
              ),
            ),
          ),
        ),
        _buildCategoryChips(),
        Expanded(
          child: _isLoadingProducts
              ? const Center(child: CircularProgressIndicator())
              : _buildProductGrid(),
        ),
      ],
    );
  }

  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 10, left: 8),
      child: Row(
        children: _categories
            .map(
              (cat) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: _selectedCategory == cat,
                  onSelected: (_) => setState(() {
                    _selectedCategory = cat;
                    _filterProducts(_searchController.text);
                  }),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildProductGrid() {
    final bool isCompact = MediaQuery.sizeOf(context).width < 700;
    return GridView.builder(
      padding: EdgeInsets.all(isCompact ? 8 : 12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isCompact ? 170 : 200,
        childAspectRatio: isCompact ? 0.86 : 0.8,
        crossAxisSpacing: isCompact ? 8 : 12,
        mainAxisSpacing: isCompact ? 8 : 12,
      ),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) => ProductCard(
        product: _filteredProducts[index],
        onTap: () => _showProductDetailDialog(_filteredProducts[index]),
      ),
    );
  }

  Widget _buildCartPanel() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'ĐƠN HÀNG',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildCartList()),
        const Divider(height: 1),
        _buildCartTotal(),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildCartList() {
    if (_cart.isEmpty) return const Center(child: Text('Chưa có món nào'));
    return ListView.separated(
      itemCount: _cart.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => CartItemTile(
        item: _cart[index],
        onIncrement: () => _updateQuantity(index, 1),
        onDecrement: () => _updateQuantity(index, -1),
        onQuantityChanged: (val) {
          setState(() {
            if (val <= 0) {
              _cart.removeAt(index);
            } else {
              _cart[index].quantity = val > 100 ? 100 : val;
            }
          });
        },
        onTap: () => _showEditCartDialog(index),
      ),
    );
  }

  Widget _buildCartTotal() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Tổng cộng:', style: TextStyle(fontSize: 16)),
          Text(
            currencyFormat.format(_subtotal),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton(
          onPressed: _submitOrder,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          child: const Text(
            'ĐẶT MÓN',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
