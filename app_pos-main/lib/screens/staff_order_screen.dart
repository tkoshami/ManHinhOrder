import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/data/order_data.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/screens/login_screen.dart';
import 'package:pos_fnb/screens/feedback_screen.dart';
import 'package:pos_fnb/data/constants.dart';
import 'package:pos_fnb/services/supabase_service.dart';
import 'package:pos_fnb/widgets/product_card.dart';
import 'package:pos_fnb/widgets/cart_item_tile.dart';

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
    setState(() {
      _allProducts = products.isEmpty ? List.from(defaultProducts) : products;
      _filteredProducts = _allProducts;
      _isLoadingProducts = false;
    });
  }

  double get _subtotal => _cart.fold(0.0, (sum, item) => sum + item.total);

  void _filterProducts(String query) {
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesSearch = p.name.toLowerCase().contains(query.toLowerCase());
        final matchesCategory = _selectedCategory == appCategories[0] || p.categoryName == _selectedCategory;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  void _addToCart(Product product) {
    setState(() {
      final index = _cart.indexWhere((item) => item.product.id == product.id);
      if (index >= 0) {
        _cart[index].quantity++;
      } else {
        _cart.add(CartItem(product: product));
      }
    });
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Số lượng:'),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
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
                      keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) {
                        if (v.isEmpty || v == '0') {
                          // Allow empty during typing, but will remove if saved empty
                        } else {
                          final val = int.tryParse(v) ?? 1;
                          setDialogState(() => quantity = val > 100 ? 100 : val);
                          if (val > 100) {
                            qtyController.text = '100';
                            qtyController.selection = TextSelection.fromPosition(const TextPosition(offset: 3));
                          }
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.green),
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
                decoration: const InputDecoration(labelText: 'Ghi chú', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _cart.removeAt(index));
              },
              child: const Text('XÓA MÓN', style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('HỦY')),
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
        title: const Text('Xác nhận đặt món'),
        content: const Text('Gửi đơn hàng này cho thu ngân?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final subtotal = _subtotal;
              final newOrder = SavedOrder(
                id: (DateTime.now().millisecondsSinceEpoch % 10000000).toString(),
                shiftId: null,
                tableOrCustomer: 'Đơn từ Staff',
                items: List<CartItem>.from(_cart),
                dateTime: DateTime.now(),
                subtotal: subtotal,
                discountAmount: 0,
                vatRate: 0,
                vatAmount: 0,
                totalAmount: subtotal,
                paymentMethod: 'cash',
                source: OrderSource.posStaff,
                status: OrderStatus.pending,
              );

              // Lưu lên Supabase
              await SupabaseService.saveOrder(newOrder);

              setState(() {
                globalPendingOrders.add(newOrder);
                _cart = [];
              });
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã đặt món thành công!'), backgroundColor: Colors.green),
              );
            },
            child: const Text('XÁC NHẬN'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ĐẶT MÓN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FeedbackScreen(currentUser: widget.user)),
            ),
            icon: const Icon(Icons.feedback_outlined, color: Colors.white),
            label: const Text(
              'PHẢN HỒI',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const LoginScreen())),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(flex: 3, child: _buildProductPanel()),
          Container(width: 350, color: Colors.white, child: _buildCartPanel()),
        ],
      ),
    );
  }

  Widget _buildProductPanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            onChanged: _filterProducts,
            decoration: InputDecoration(
              hintText: 'Tìm món...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
        children: appCategories.map((cat) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            label: Text(cat),
            selected: _selectedCategory == cat,
            onSelected: (_) => setState(() {
              _selectedCategory = cat;
              _filterProducts(_searchController.text);
            }),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildProductGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200, childAspectRatio: 0.8, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) => ProductCard(
        product: _filteredProducts[index],
        onTap: () => _addToCart(_filteredProducts[index]),
      ),
    );
  }

  Widget _buildCartPanel() {
    return Column(
      children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('GIỎ HÀNG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
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
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Tổng cộng:', style: TextStyle(fontSize: 16)),
        Text(currencyFormat.format(_subtotal),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
      ]),
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
          child: const Text('ĐẶT MÓN', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
