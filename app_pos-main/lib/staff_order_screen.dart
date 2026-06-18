import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'order_screen.dart';
import 'login_screen.dart';

class StaffOrderScreen extends StatefulWidget {
  final UserAccount user;
  const StaffOrderScreen({super.key, required this.user});

  @override
  State<StaffOrderScreen> createState() => _StaffOrderScreenState();
}

class _StaffOrderScreenState extends State<StaffOrderScreen> {
  final List<Product> _allProducts = [
    Product(id: '1',  name: 'Cà Phê Sữa',       price: 29000, imageUrl: 'https://picsum.photos/200?random=1',  category: 'Cà phê'),
    Product(id: '2',  name: 'Trà Đào Cam Sả',    price: 45000, imageUrl: 'https://picsum.photos/200?random=2',  category: 'Trà'),
    Product(id: '3',  name: 'Bánh Mì Thịt',      price: 35000, imageUrl: 'https://picsum.photos/200?random=3',  category: 'Bánh'),
    Product(id: '4',  name: 'Latte',              price: 49000, imageUrl: 'https://picsum.photos/200?random=4',  category: 'Cà phê'),
    Product(id: '5',  name: 'Trà Sữa Trân Châu', price: 55000, imageUrl: 'https://picsum.photos/200?random=5',  category: 'Trà'),
    Product(id: '6',  name: 'Croissant',          price: 32000, imageUrl: 'https://picsum.photos/200?random=6',  category: 'Bánh'),
    Product(id: '7',  name: 'Americano',          price: 39000, imageUrl: 'https://picsum.photos/200?random=7',  category: 'Cà phê'),
    Product(id: '8',  name: 'Mocha',              price: 52000, imageUrl: 'https://picsum.photos/200?random=8',  category: 'Cà phê'),
    Product(id: '9',  name: 'Salad trộn',         price: 38000, imageUrl: 'https://picsum.photos/200?random=9',  category: 'Đồ ăn'),
    Product(id: '10', name: 'Bánh Tiramisu',      price: 42000, imageUrl: 'https://picsum.photos/200?random=10', category: 'Bánh'),
  ];

  List<Product> _filteredProducts = [];
  List<CartItem> _cart = [];
  String _selectedCategory = 'Tất cả';
  final List<String> _categories = ['Tất cả', 'Cà phê', 'Trà', 'Bánh', 'Đồ ăn'];
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final TextEditingController _searchController = TextEditingController();

  double get _subtotal => _cart.fold(0.0, (sum, item) => sum + item.total);

  @override
  void initState() {
    super.initState();
    _filteredProducts = _allProducts;
  }

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
                  vatPercent: 0, // Staff không áp VAT, cashier xử lý
                  total: subtotal,
                  requestedMethod: 'Đợi thu tiền',
                  source: OrderSource.posStaff,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ĐẶT MÓN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const LoginScreen())),
          ),
        ],
      ),
      body: Row(
        children: [
          // ── Panel trái: sản phẩm ──
          Expanded(
            flex: 3,
            child: Column(
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 10, left: 8),
                  child: Row(
                    children: _categories.map((cat) => Padding(
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
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200, childAspectRatio: 0.8,
                        crossAxisSpacing: 12, mainAxisSpacing: 12),
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final p = _filteredProducts[index];
                      return Card(
                        elevation: 2,
                        child: InkWell(
                          onTap: () => _addToCart(p),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Image.network(p.imageUrl,
                                  fit: BoxFit.cover, width: double.infinity)),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(currencyFormat.format(p.price),
                                      style: const TextStyle(color: Colors.blue)),
                                ]),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── Panel phải: giỏ hàng ──
          Container(
            width: 350,
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border(left: BorderSide(color: Colors.grey[200]!))),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('GIỎ HÀNG',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _cart.isEmpty
                      ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('Chưa có món nào', style: TextStyle(color: Colors.grey)),
                      ]))
                      : ListView.separated(
                    itemCount: _cart.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _cart[index];
                      return ListTile(
                        title: Text(item.product.name,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(currencyFormat.format(item.product.price),
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _updateQuantity(index, -1),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text('${item.quantity}',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _updateQuantity(index, 1),
                          ),
                          const SizedBox(width: 8),
                          Text(currencyFormat.format(item.total),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, color: Colors.blue)),
                        ]),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Tổng cộng:', style: TextStyle(fontSize: 16)),
                    Text(currencyFormat.format(_subtotal),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _submitOrder,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      child: const Text('ĐẶT MÓN',
                          style: TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}