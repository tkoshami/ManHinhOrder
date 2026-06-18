import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'order_screen.dart';
import 'login_screen.dart';
import 'constants.dart';
import 'widgets/product_card.dart';
import 'widgets/cart_item_tile.dart';

class StaffOrderScreen extends StatefulWidget {
  final UserAccount user;
  const StaffOrderScreen({super.key, required this.user});

  @override
  State<StaffOrderScreen> createState() => _StaffOrderScreenState();
}

class _StaffOrderScreenState extends State<StaffOrderScreen> {
  // --- Data ---
  final List<Product> _allProducts = List.from(defaultProducts);
  List<Product> _filteredProducts = [];
  List<CartItem> _cart = [];
  
  // --- UI State ---
  String _selectedCategory = appCategories[0];
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredProducts = _allProducts;
  }

  // --- Computed ---
  double get _subtotal => _cart.fold(0.0, (sum, item) => sum + item.total);

  // --- Logic ---
  void _filterProducts(String query) {
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesSearch = p.name.toLowerCase().contains(query.toLowerCase());
        final matchesCategory = _selectedCategory == 'Tất cả' || p.category == _selectedCategory;
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
      _cart[index].quantity += delta;
      if (_cart[index].quantity <= 0) _cart.removeAt(index);
    });
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
            onPressed: () {
              final subtotal = _subtotal;
              setState(() {
                globalPendingOrders.add(SavedOrder(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  tableOrCustomer: 'Đơn từ Staff',
                  items: List<CartItem>.from(_cart),
                  dateTime: DateTime.now(),
                  subtotal: subtotal,
                  vatPercent: 0,
                  total: subtotal,
                  requestedMethod: 'Đợi thu tiền',
                  source: OrderSource.pos_staff,
                ));
                _cart = [];
              });
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

  // --- Build ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ĐẶT MÓN'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
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
        Expanded(child: _buildProductGrid()),
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
        onTap: () {},
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
