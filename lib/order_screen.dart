import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'login_screen.dart';
import 'models.dart';
import 'constants.dart';
import 'widgets/product_card.dart';
import 'widgets/cart_item_tile.dart';

List<SavedOrder> globalPendingOrders = [];
List<SavedOrder> globalCompletedOrders = [];

class OrderScreen extends StatefulWidget {
  final UserAccount user;
  const OrderScreen({super.key, required this.user});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  // --- Data ---
  final List<Product> _allProducts = List.from(defaultProducts);
  List<Product> _filteredProducts = [];
  List<CartItem> _cart = [];
  
  // --- UI State ---
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  String _selectedOrderType = appOrderTypes[0];
  String _selectedCategory = appCategories[0];
  double _vatPercent = 0;
  SavedOrder? _currentPendingOrder;

  @override
  void initState() {
    super.initState();
    _filteredProducts = _allProducts;
  }

  // --- Computed Properties ---
  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get _vatAmount => _subtotal * _vatPercent / 100;
  double get _total => _subtotal + _vatAmount;
  List<SavedOrder> get _pendingOrders => globalPendingOrders;

  // --- Logic Methods ---
  void _filterProducts(String query) {
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesSearch = p.name.toLowerCase().contains(query.toLowerCase());
        final matchesCategory = _selectedCategory == 'Tất cả' || p.category == _selectedCategory;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  void _addToCartWithDiscount(Product product, double discountPercent, String note) {
    setState(() {
      final index = _cart.indexWhere(
        (item) => item.product.id == product.id && 
                  item.discountPercent == discountPercent && 
                  item.note == note,
      );
      if (index >= 0) {
        _cart[index].quantity++;
      } else {
        _cart.add(CartItem(product: product, discountPercent: discountPercent, note: note));
      }
    });
  }

  void _updateCartItem(int cartIndex, double discountPercent, String note, int quantity) {
    setState(() {
      if (quantity <= 0) {
        _cart.removeAt(cartIndex);
      } else {
        _cart[cartIndex] = CartItem(
          product: _cart[cartIndex].product,
          quantity: quantity,
          discountPercent: discountPercent,
          note: note,
        );
      }
    });
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      _cart[index].quantity += delta;
      if (_cart[index].quantity <= 0) _cart.removeAt(index);
    });
  }

  void _resetOrder() {
    setState(() {
      _cart = [];
      _vatPercent = 0;
      _currentPendingOrder = null;
      _selectedOrderType = appOrderTypes[0];
      _selectedCategory = appCategories[0];
      _searchController.clear();
      _filteredProducts = _allProducts;
    });
    _searchFocusNode.requestFocus();
  }

  // --- Action Handlers ---
  void _clearCart() {
    if (_cart.isEmpty) return;
    _showConfirmDialog(
      title: 'Xác nhận hủy',
      content: 'Bạn có chắc chắn muốn hủy toàn bộ các món trong giỏ hàng không?',
      onConfirm: () => setState(() => _cart = []),
      confirmText: 'HỦY ĐƠN',
      isDanger: true,
    );
  }

  void _savePending() {
    if (_cart.isEmpty) return;
    setState(() {
      if (_currentPendingOrder != null) {
        globalPendingOrders.remove(_currentPendingOrder);
      }
      globalPendingOrders.add(SavedOrder(
        id: _currentPendingOrder?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        tableOrCustomer: _selectedOrderType,
        items: List<CartItem>.from(_cart),
        dateTime: DateTime.now(),
        subtotal: _subtotal,
        vatPercent: _vatPercent,
        total: _total,
        source: OrderSource.pos_staff,
      ));
      _resetOrder();
    });
    _showSnackBar('Đã lưu tạm đơn hàng vào danh sách chờ', Colors.blue);
  }

  void _handlePayment(String method) async {
    Navigator.pop(context);
    if (method == 'Thẻ') {
      _showLoadingDialog('Đang quẹt thẻ...');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    }
    _showReceiptDialog(method);
  }

  // --- UI Helpers ---
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
    ));
  }

  String _formatPrice(double price) => currencyFormat.format(price);

  // --- Dialogs ---
  void _showConfirmDialog({
    required String title,
    required String content,
    required VoidCallback onConfirm,
    String confirmText = 'XÁC NHẬN',
    bool isDanger = false,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
          ElevatedButton(
            onPressed: () { onConfirm(); Navigator.pop(context); },
            style: ElevatedButton.styleFrom(backgroundColor: isDanger ? Colors.red : Colors.orange),
            child: Text(confirmText, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      )
    );
  }

  // (The rest of the dialogs like _showDiscountDialog, _showEditCartDialog etc. 
  // will be kept but simplified using common styles if possible)

  void _showDiscountDialog(BuildContext context, Product product) {
    final discountController = TextEditingController(text: '0');
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final discountPercent = double.tryParse(discountController.text) ?? 0;
          final finalPrice = product.price * (1 - discountPercent / 100);

          return AlertDialog(
            title: Text(product.name),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: discountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Giảm giá (%)', suffixText: '%'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Ghi chú'),
                  ),
                  const SizedBox(height: 16),
                  Text('Thành tiền: ${_formatPrice(finalPrice)}', 
                       style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
              ElevatedButton(
                onPressed: () {
                  _addToCartWithDiscount(product, double.tryParse(discountController.text) ?? 0, noteController.text);
                  Navigator.pop(context);
                },
                child: const Text('Thêm'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showReceiptDialog(String paymentMethod) {
    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final itemsCopy = List<CartItem>.from(_cart);
    
    globalCompletedOrders.insert(0, SavedOrder(
      id: orderId,
      tableOrCustomer: _selectedOrderType,
      items: itemsCopy,
      dateTime: DateTime.now(),
      subtotal: _subtotal,
      vatPercent: _vatPercent,
      total: _total,
      requestedMethod: paymentMethod,
      source: OrderSource.pos_staff,
      status: OrderStatus.completed,
    ));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('HÓA ĐƠN')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mã đơn: $orderId'),
            Text('PTTT: $paymentMethod'),
            const Divider(),
            ...itemsCopy.map((item) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${item.product.name} x${item.quantity}'),
                Text(_formatPrice(item.total)),
              ],
            )),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('TỔNG CỘNG:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_formatPrice(_total), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            ]),
          ],
        ),
        actions: [
          ElevatedButton(onPressed: () { Navigator.pop(context); _resetOrder(); }, child: const Text('Xong')),
        ],
      ),
    );
  }

  void _showCheckoutDialog() {
    if (_cart.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Phương thức thanh toán'),
        children: [
          SimpleDialogOption(onPressed: () => _handlePayment('Tiền mặt'), child: const Text('Tiền mặt')),
          SimpleDialogOption(onPressed: () => _handlePayment('Chuyển khoản'), child: const Text('Chuyển khoản')),
          SimpleDialogOption(onPressed: () => _handlePayment('Thẻ'), child: const Text('Thẻ')),
        ],
      ),
    );
  }

  // --- Main Build ---
  @override
  Widget build(BuildContext context) {
    final bool canCheckout = widget.user.role != UserRole.user;
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS F&B'),
        backgroundColor: Colors.orangeAccent,
        actions: [
          _buildPendingOrdersBadge(),
          _buildUserAvatar(),
        ],
      ),
      body: isMobile ? _buildMobileLayout() : _buildDesktopLayout(canCheckout),
    );
  }

  Widget _buildPendingOrdersBadge() {
    return Stack(alignment: Alignment.center, children: [
      IconButton(icon: const Icon(Icons.receipt_long), onPressed: _showPendingOrdersSheet),
      if (_pendingOrders.isNotEmpty)
        Positioned(right: 8, top: 8, child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
          child: Text('${_pendingOrders.length}', style: const TextStyle(color: Colors.white, fontSize: 10), textAlign: TextAlign.center),
        )),
    ]);
  }

  Widget _buildUserAvatar() {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'logout') Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      },
      itemBuilder: (context) => [
        PopupMenuItem(enabled: false, child: Text('${widget.user.name} (${widget.user.role.name})')),
        const PopupMenuItem(value: 'logout', child: Text('Đăng xuất')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: CircleAvatar(backgroundColor: Colors.white, child: Text(widget.user.name[0])),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(children: [
      Expanded(child: _buildProductGrid()),
      _buildMobileCartSummary(),
    ]);
  }

  Widget _buildDesktopLayout(bool canCheckout) {
    return Row(children: [
      Expanded(flex: 2, child: _buildProductSide()),
      Container(width: 400, color: Colors.white, child: _buildCartSide(canCheckout)),
    ]);
  }

  Widget _buildProductSide() {
    return Column(children: [
      _buildSearchBar(),
      _buildCategorySelector(),
      Expanded(child: _buildProductGrid()),
    ]);
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: _filterProducts,
        decoration: InputDecoration(
          hintText: 'Tìm món...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: appCategories.map((cat) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            label: Text(cat),
            selected: _selectedCategory == cat,
            onSelected: (sel) { if (sel) setState(() { _selectedCategory = cat; _filterProducts(_searchController.text); }); },
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildProductGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, childAspectRatio: 0.75, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) => ProductCard(
        product: _filteredProducts[index],
        onTap: () => _showDiscountDialog(context, _filteredProducts[index]),
      ),
    );
  }

  Widget _buildCartSide(bool canCheckout) {
    return Column(children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('GIỎ HÀNG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      _buildOrderTypeSelector(),
      Expanded(child: _buildCartList()),
      _buildCartSummary(),
      _buildCartActions(canCheckout),
    ]);
  }

  Widget _buildOrderTypeSelector() {
    return Row(children: appOrderTypes.map((type) => Expanded(
      child: RadioListTile<String>(
        title: Text(type, style: const TextStyle(fontSize: 10)),
        value: type,
        groupValue: _selectedOrderType,
        onChanged: (v) => setState(() => _selectedOrderType = v!),
      )
    )).toList());
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
        onTap: () {}, // Could open edit dialog here
      ),
    );
  }

  Widget _buildCartSummary() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Tạm tính:'), Text(_formatPrice(_subtotal))]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('VAT:'), Text(_formatPrice(_vatAmount))]),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('TỔNG CỘNG:', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(_formatPrice(_total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
        ]),
      ]),
    );
  }

  Widget _buildCartActions(bool canCheckout) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _clearCart, child: const Text('HỦY'))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton(onPressed: _savePending, child: const Text('LƯU TẠM'))),
        ]),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: canCheckout ? _showCheckoutDialog : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
          child: Text(canCheckout ? 'THANH TOÁN' : 'ĐẶT MÓN'),
        )),
      ]),
    );
  }

  Widget _buildMobileCartSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Row(children: [
        Text('${_cart.length} món - ${_formatPrice(_total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        ElevatedButton(onPressed: () {}, child: const Text('Xem giỏ hàng')),
      ]),
    );
  }

  void _showPendingOrdersSheet() {
    // Simplified pending orders sheet
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('ĐƠN CHỜ')),
          Expanded(child: ListView.builder(
            itemCount: _pendingOrders.length,
            itemBuilder: (context, index) => ListTile(
              title: Text(_pendingOrders[index].tableOrCustomer),
              trailing: Text(_formatPrice(_pendingOrders[index].total)),
              onTap: () {
                setState(() {
                  _cart = List.from(_pendingOrders[index].items);
                  _currentPendingOrder = _pendingOrders[index];
                  globalPendingOrders.removeAt(index);
                });
                Navigator.pop(context);
              },
            ),
          )),
        ],
      ),
    );
  }
}
