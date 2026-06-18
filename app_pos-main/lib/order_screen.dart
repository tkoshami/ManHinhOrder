import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'login_screen.dart';
import 'models.dart';

List<SavedOrder> globalPendingOrders = [];
List<SavedOrder> globalCompletedOrders = []; // đơn đã thanh toán

class OrderScreen extends StatefulWidget {
  final UserAccount user;
  const OrderScreen({super.key, required this.user});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
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
  List<SavedOrder> get _pendingOrders => globalPendingOrders;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  String _selectedOrderType = 'Mang về';
  final List<String> _orderTypes = ['Mang về', 'Tại quán', 'Giao hàng'];
  String _selectedCategory = 'Tất cả';
  final List<String> _categories = ['Tất cả', 'Cà phê', 'Trà', 'Bánh', 'Đồ ăn'];

  // VAT: lưu % dạng số (vd: 10 = 10%), mặc định 0
  double _vatPercent = 0;

  // Track đơn đang được mở từ danh sách chờ (null = đơn mới)
  SavedOrder? _currentPendingOrder;

  // Track state of mobile bottom sheet
  StateSetter? _sheetState;

  void _syncState(VoidCallback fn) {
    setState(fn);
    _sheetState?.call(() {});
  }

  @override
  void initState() {
    super.initState();
    _filteredProducts = _allProducts;
  }

  // ─── Tính tiền ───
  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get _vatAmount => _subtotal * _vatPercent / 100;
  double get _total => _subtotal + _vatAmount;

  void _filterProducts(String query) {
    _syncState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesSearch = p.name.toLowerCase().contains(query.toLowerCase());
        final matchesCategory = _selectedCategory == 'Tất cả' || p.category == _selectedCategory;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }


  // ─── Thêm mới vào cart ───
  void _addToCartWithDiscount(Product product, double discountPercent, String note) {
    _syncState(() {
      final index = _cart.indexWhere(
            (item) =>
        item.product.id == product.id &&
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

  // ─── Cập nhật cart item đã có (chỉnh sửa) ───
  void _updateCartItem(int cartIndex, double discountPercent, String note, int quantity) {
    _syncState(() {
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
    _syncState(() {
      _cart[index].quantity += delta;
      if (_cart[index].quantity <= 0) _cart.removeAt(index);
    });
  }

  void _resetOrder() {
    _syncState(() {
      _cart = [];
      _vatPercent = 0;
      _currentPendingOrder = null;
      _selectedOrderType = 'Mang về';
      _selectedCategory = 'Tất cả';
      _searchController.clear();
      _filteredProducts = _allProducts;
    });
    _searchFocusNode.requestFocus();
  }

  void _clearCart() {
    if (_cart.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận hủy'),
        content: const Text('Bạn có chắc chắn muốn hủy toàn bộ các món trong giỏ hàng không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
          ElevatedButton(
            onPressed: () { _syncState(() => _cart = []); Navigator.pop(context); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('HỦY ĐƠN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openPendingOrder(SavedOrder order) {
    _syncState(() {
      _cart = List<CartItem>.from(order.items);
      _vatPercent = order.vatPercent;
      _selectedOrderType = order.tableOrCustomer;
      _currentPendingOrder = order; // nhớ đơn đang chỉnh
      globalPendingOrders.remove(order);
    });
  }

  void _finishStaffOrder(BuildContext ctx, String method) {
    Navigator.pop(ctx);
    _syncState(() {
      globalPendingOrders.add(SavedOrder(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        tableOrCustomer: _selectedOrderType,
        items: List<CartItem>.from(_cart),
        dateTime: DateTime.now(),
        subtotal: _subtotal,
        vatPercent: _vatPercent,
        total: _total,
        requestedMethod: method,
        source: OrderSource.posStaff,
      ));
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Đã đặt món thành công! Hình thức: $method. Đơn đã gửi cho Cashier.'),
      backgroundColor: Colors.green,
    ));
    _resetOrder();
  }

  // ── Nút Tạm tính: lưu đơn vào pending rồi xóa giỏ ──
  void _savePending() {
    if (_cart.isEmpty) return;
    _syncState(() {
      // Nếu đang chỉnh đơn pending cũ thì xóa bản cũ trước
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
        requestedMethod: null,
        source: OrderSource.posStaff,
        status: OrderStatus.pending,
      ));
      _currentPendingOrder = null;
      _cart = [];
      _vatPercent = 0;
      _selectedOrderType = 'Mang về';
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Đã lưu tạm đơn hàng vào danh sách chờ'),
      backgroundColor: Colors.blue,
      duration: Duration(seconds: 2),
    ));
  }

  // ══════════════════════════════════════════════
  // DIALOG: Thêm sản phẩm mới (từ menu)
  // ══════════════════════════════════════════════
  void _showDiscountDialog(BuildContext context, Product product,
      {double initDiscount = 0, String initNote = ''}) {
    final discountController = TextEditingController(text: initDiscount == 0 ? '0' : initDiscount.toStringAsFixed(0));
    final noteController = TextEditingController(text: initNote);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final discountPercent = double.tryParse(discountController.text) ?? 0;
          final discountAmount = product.price * discountPercent / 100;
          final finalPrice = product.price - discountAmount;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.local_offer, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(product.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis)),
            ]),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Giá gốc
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Giá gốc:', style: TextStyle(color: Colors.grey)),
                      Text('${_formatPrice(product.price)} ₫', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // % Giảm giá
                  const Text('Nhập % giảm giá:', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: discountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      suffixText: '%',
                      suffixStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.orange, width: 2)),
                      hintText: '0 - 100',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [5, 10, 15, 20, 50].map((pct) => ActionChip(
                      label: Text('$pct%'),
                      backgroundColor: Colors.orange[50],
                      labelStyle: const TextStyle(color: Colors.orange),
                      onPressed: () {
                        discountController.text = pct.toString();
                        setDialogState(() {});
                      },
                    )).toList(),
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Ghi chú
                  const Text('Ghi chú:', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'VD: ít đường, không đá, dị ứng...',
                      hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                      prefixIcon: const Icon(Icons.edit_note, color: Colors.orange),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.orange, width: 2)),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Preview
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Giảm:', style: TextStyle(color: Colors.red)),
                    Text('- ${_formatPrice(discountAmount)} ₫',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Thành tiền:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${_formatPrice(finalPrice)} ₫',
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 18)),
                  ]),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final discount = (double.tryParse(discountController.text) ?? 0).clamp(0.0, 100.0);
                  final note = noteController.text.trim();
                  Navigator.pop(context);
                  _addToCartWithDiscount(product, discount, note);
                },
                icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
                label: const Text('Thêm vào đơn', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════
  // DIALOG: Chỉnh sửa cart item đã có
  // ══════════════════════════════════════════════
  void _showEditCartDialog(BuildContext context, int cartIndex) {
    final item = _cart[cartIndex];
    final discountController = TextEditingController(
        text: item.discountPercent == 0 ? '0' : item.discountPercent.toStringAsFixed(0));
    final noteController = TextEditingController(text: item.note);
    int quantity = item.quantity;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final discountPercent = double.tryParse(discountController.text) ?? 0;
          final discountAmount = item.product.price * discountPercent / 100;
          final finalPrice = item.product.price - discountAmount;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.edit, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(item.product.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis)),
            ]),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Số lượng
                  const Text('Số lượng:', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        onPressed: () => setDialogState(() { if (quantity > 1) quantity--; }),
                      ),
                      Text('$quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                        onPressed: () => setDialogState(() => quantity++),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 16),

                  // Giá gốc
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Giá gốc:', style: TextStyle(color: Colors.grey)),
                      Text('${_formatPrice(item.product.price)} ₫',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // % Giảm giá
                  const Text('% Giảm giá:', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: discountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      suffixText: '%',
                      suffixStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.orange, width: 2)),
                      hintText: '0 - 100',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [0, 5, 10, 15, 20, 50].map((pct) => ActionChip(
                      label: Text(pct == 0 ? 'Bỏ giảm' : '$pct%'),
                      backgroundColor: pct == 0 ? Colors.grey[100] : Colors.orange[50],
                      labelStyle: TextStyle(color: pct == 0 ? Colors.grey : Colors.orange),
                      onPressed: () {
                        discountController.text = pct.toString();
                        setDialogState(() {});
                      },
                    )).toList(),
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Ghi chú
                  const Text('Ghi chú:', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'VD: ít đường, không đá...',
                      hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                      prefixIcon: const Icon(Icons.edit_note, color: Colors.orange),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.orange, width: 2)),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Preview
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Giảm/món:', style: TextStyle(color: Colors.red)),
                    Text('- ${_formatPrice(discountAmount)} ₫',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Giá/món:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('${_formatPrice(finalPrice)} ₫',
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Tổng ($quantity món):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${_formatPrice(finalPrice * quantity)} ₫',
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 18)),
                  ]),
                ],
              ),
            ),
            actions: [
              // Nút xóa khỏi giỏ
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _updateCartItem(cartIndex, 0, '', 0);
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Xóa món', style: TextStyle(color: Colors.red)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final discount = (double.tryParse(discountController.text) ?? 0).clamp(0.0, 100.0);
                  final note = noteController.text.trim();
                  Navigator.pop(context);
                  _updateCartItem(cartIndex, discount, note, quantity);
                },
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text('Lưu', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════
  // DIALOG: Chọn sản phẩm để thêm (từ giỏ hàng)
  // ══════════════════════════════════════════════
  // ══════════════════════════════════════════════
  // DIALOG: VAT
  // ══════════════════════════════════════════════
  void _showVatDialog() {
    final vatController = TextEditingController(
        text: _vatPercent == 0 ? '0' : _vatPercent.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final vat = double.tryParse(vatController.text) ?? 0;
          final vatAmt = _subtotal * vat / 100;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.receipt, color: Colors.orange),
              SizedBox(width: 8),
              Text('Cài đặt VAT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nhập % VAT:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: vatController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    suffixText: '%',
                    suffixStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.orange, width: 2)),
                    hintText: '0 - 100',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [0, 5, 8, 10].map((pct) => ActionChip(
                    label: Text(pct == 0 ? 'Không VAT' : '$pct%'),
                    backgroundColor: pct == 0 ? Colors.grey[100] : Colors.blue[50],
                    labelStyle: TextStyle(color: pct == 0 ? Colors.grey : Colors.blue),
                    onPressed: () {
                      vatController.text = pct.toString();
                      setDialogState(() {});
                    },
                  )).toList(),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Tạm tính:'),
                  Text('${_formatPrice(_subtotal)} ₫'),
                ]),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('VAT ($vat%):'),
                  Text('+ ${_formatPrice(vatAmt)} ₫',
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Tổng sau VAT:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('${_formatPrice(_subtotal + vatAmt)} ₫',
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 18)),
                ]),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: () {
                  _syncState(() => _vatPercent = (double.tryParse(vatController.text) ?? 0).clamp(0, 100));
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Áp dụng', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════
  // DIALOG: Thêm sản phẩm mới vào danh sách
  // ══════════════════════════════════════════════
  void _showAddNewProductDialog() {
    final nameController    = TextEditingController();
    final priceController   = TextEditingController();
    final imageController   = TextEditingController();
    final formKey           = GlobalKey<FormState>();
    String selectedCategory = _categories.firstWhere((c) => c != 'Tất cả', orElse: () => 'Cà phê');
    String previewImage     = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.add_box, color: Colors.orange),
              SizedBox(width: 8),
              Text('Thêm sản phẩm mới', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Preview ảnh
                    if (previewImage.isNotEmpty)
                      Container(
                        height: 120,
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[100],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(
                          previewImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.broken_image, color: Colors.grey, size: 36),
                              Text('URL ảnh không hợp lệ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ]),
                          ),
                        ),
                      )
                    else
                      Container(
                        height: 80,
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[100],
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.image_outlined, color: Colors.grey, size: 32),
                          Text('Preview ảnh', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ])),
                      ),

                    // Tên sản phẩm
                    const Text('Tên sản phẩm *', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(
                        hintText: 'VD: Cà Phê Muối',
                        prefixIcon: const Icon(Icons.fastfood_outlined, color: Colors.orange),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.orange, width: 2)),
                        isDense: true,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên' : null,
                    ),
                    const SizedBox(height: 12),

                    // Giá
                    const Text('Giá (₫) *', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'VD: 35000',
                        prefixIcon: const Icon(Icons.attach_money, color: Colors.orange),
                        suffixText: '₫',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.orange, width: 2)),
                        isDense: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Vui lòng nhập giá';
                        if (double.tryParse(v.trim()) == null) return 'Giá không hợp lệ';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Danh mục
                    const Text('Danh mục *', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.category_outlined, color: Colors.orange),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.orange, width: 2)),
                        isDense: true,
                      ),
                      items: _categories
                          .where((c) => c != 'Tất cả')
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setDlg(() => selectedCategory = v!),
                    ),
                    const SizedBox(height: 12),

                    // URL ảnh
                    const Text('URL ảnh', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: imageController,
                      decoration: InputDecoration(
                        hintText: 'https://example.com/image.jpg',
                        prefixIcon: const Icon(Icons.link, color: Colors.orange),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.visibility, color: Colors.grey),
                          tooltip: 'Preview ảnh',
                          onPressed: () => setDlg(() => previewImage = imageController.text.trim()),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.orange, width: 2)),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        // Auto-preview khi dừng nhập
                        Future.delayed(const Duration(milliseconds: 800), () {
                          if (imageController.text == v) setDlg(() => previewImage = v.trim());
                        });
                      },
                    ),
                    const SizedBox(height: 4),
                    const Text('Để trống sẽ dùng ảnh mặc định',
                        style: TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final newId = DateTime.now().millisecondsSinceEpoch.toString();
                  final imageUrl = imageController.text.trim().isNotEmpty
                      ? imageController.text.trim()
                      : 'https://picsum.photos/200?random=$newId';
                  final newProduct = Product(
                    id: newId,
                    name: nameController.text.trim(),
                    price: double.parse(priceController.text.trim()),
                    imageUrl: imageUrl,
                    category: selectedCategory,
                  );
                  _syncState(() {
                    _allProducts.add(newProduct);
                    _filterProducts(_searchController.text); // refresh lưới
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Đã thêm "${newProduct.name}" vào danh sách!'),
                    backgroundColor: Colors.green,
                  ));
                },
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text('Thêm sản phẩm', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCheckoutDialog() {
    if (_cart.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('Chọn phương thức thanh toán',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.money, color: Colors.green),
                title: const Text('Tiền mặt'), onTap: () => _handlePayment('Tiền mặt')),
            ListTile(leading: const Icon(Icons.account_balance, color: Colors.blue),
                title: const Text('Chuyển khoản'), onTap: () => _handlePayment('Chuyển khoản')),
            ListTile(leading: const Icon(Icons.credit_card, color: Colors.orange),
                title: const Text('Thẻ'), onTap: () => _handlePayment('Thẻ')),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy'))],
      ),
    );
  }

  void _handlePayment(String method) async {
    Navigator.pop(context);
    if (method == 'Thẻ') {
      showDialog(context: context, barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(), SizedBox(height: 16), Text('Đang quẹt thẻ...'),
            ]),
          ));
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    }
    _showReceiptDialog(method);
  }

  void _showReceiptDialog(String paymentMethod) {
    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final itemsCopy = List<CartItem>.from(_cart);
    final subtotalCopy = _subtotal;
    final vatAmtCopy = _vatAmount;
    final totalCopy = _total;
    final vatPctCopy = _vatPercent;
    final orderTypeCopy = _selectedOrderType;

    // Nếu đơn được mở từ pending → xóa khỏi danh sách chờ
    if (_currentPendingOrder != null) {
      globalPendingOrders.remove(_currentPendingOrder);
      _currentPendingOrder = null;
    }

    // Lưu vào lịch sử đơn đã thanh toán
    globalCompletedOrders.insert(0, SavedOrder(
      id: orderId,
      tableOrCustomer: orderTypeCopy,
      items: itemsCopy,
      dateTime: DateTime.now(),
      subtotal: subtotalCopy,
      vatPercent: vatPctCopy,
      total: totalCopy,
      requestedMethod: paymentMethod,
      source: OrderSource.posStaff,
      status: OrderStatus.completed,
    ));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('HÓA ĐƠN')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Loại: $orderTypeCopy', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Divider(),
              Text('Mã đơn: $orderId'),
              Text('Ngày: $dateStr'),
              Text('PTTT: $paymentMethod'),
              const Divider(),
              ...itemsCopy.map((item) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(
                    item.discountPercent > 0
                        ? '${item.product.name} x${item.quantity} (-${item.discountPercent.toStringAsFixed(0)}%)'
                        : '${item.product.name} x${item.quantity}',
                    style: const TextStyle(fontSize: 13),
                  )),
                  Text(currencyFormat.format(item.total)),
                ],
              )),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Tạm tính:'),
                Text(currencyFormat.format(subtotalCopy)),
              ]),
              if (vatPctCopy > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('VAT (${vatPctCopy.toStringAsFixed(0)}%):'),
                Text(currencyFormat.format(vatAmtCopy), style: const TextStyle(color: Colors.blue)),
              ]),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('TỔNG CỘNG:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(currencyFormat.format(totalCopy),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => debugPrint('In...'), child: const Text('IN HÓA ĐƠN')),
          ElevatedButton(
              onPressed: () { Navigator.pop(context); _resetOrder(); },
              child: const Text('TẠO ĐƠN MỚI')),
        ],
      ),
    );
  }

  String _formatPrice(double price) => price.toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  void _showPendingOrdersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(padding: EdgeInsets.all(16),
                child: Text('ĐƠN ĐANG CHỜ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            Expanded(
              child: _pendingOrders.isEmpty
                  ? const Center(child: Text('Không có đơn hàng nào đang chờ'))
                  : ListView.builder(
                controller: scrollController,
                itemCount: _pendingOrders.length,
                itemBuilder: (context, index) {
                  final order = _pendingOrders[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.table_restaurant)),
                    title: Text('Bàn: ${order.tableOrCustomer}'),
                    subtitle: Text('HTTT: ${order.requestedMethod ?? "Chưa chọn"}'),
                    trailing: Text(currencyFormat.format(order.total),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () { Navigator.pop(context); _openPendingOrder(order); },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  void _showCartBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            _sheetState = setSheetState;
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const Text('GIỎ HÀNG',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _buildCartPanel()),
                ],
              ),
            );
          },
        );
      },
    ).then((_) => _sheetState = null);
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.75,
            ),
            itemCount: _filteredProducts.length,
            itemBuilder: (context, index) {
              final product = _filteredProducts[index];

              return Card(
                child: InkWell(
                  onTap: () => _showDiscountDialog(context, product),
                  child: Column(
                    children: [
                      Expanded(
                        child: Image.network(
                          product.imageUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Text(product.name),
                      Text(
                        currencyFormat.format(product.price),
                        style: const TextStyle(
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_cart.length} món - ${currencyFormat.format(_total)}',
                ),
              ),
              ElevatedButton(
                onPressed: _showCartBottomSheet,
                child: const Text('Giỏ hàng'),
              ),
            ],
          ),
        ),
      ],
    );
  }
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS F&B', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        actions: [
          Stack(alignment: Alignment.center, children: [
            IconButton(icon: const Icon(Icons.receipt_long, size: 28), onPressed: _showPendingOrdersSheet),
            if (_pendingOrders.isNotEmpty)
              Positioned(right: 8, top: 8, child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text('${_pendingOrders.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 10), textAlign: TextAlign.center),
              )),
          ]),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'user', child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text('${widget.user.name} (${widget.user.role.name})'))),
              const PopupMenuItem(value: 'logout', child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red), title: Text('Đăng xuất'))),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 15),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(widget.user.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
      body: isMobile ? _buildMobileLayout()
      :Row(children: [
        // ── Panel trái: menu sản phẩm ──
        Expanded(
          flex: 2,
          child: Column(children: [
            // ── Search + nút thêm sản phẩm mới ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _filterProducts,
                    decoration: InputDecoration(
                        hintText: 'Tìm món...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showAddNewProductDialog,
                  icon: const Icon(Icons.add, color: Colors.white, size: 18),
                  label: const Text('Sản phẩm mới', style: TextStyle(color: Colors.white, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ]),
            ),

            // ── Category chips ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categories.map((cat) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: _selectedCategory == cat,
                      onSelected: (sel) {
                        if (sel) _syncState(() { _selectedCategory = cat; _filterProducts(_searchController.text); });
                      },
                    ),
                  )).toList(),
                ),
              ),
            ),

            // ── Grid sản phẩm + card placeholder cuối ──
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200, childAspectRatio: 0.75, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: _filteredProducts.length + 1,
                itemBuilder: (context, index) {
                  // Card placeholder cuối cùng
                  if (index == _filteredProducts.length) {
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.green.shade200, width: 2),
                      ),
                      color: Colors.green[50],
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _showAddNewProductDialog,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline, size: 40, color: Colors.green),
                            SizedBox(height: 8),
                            Text('Thêm sản phẩm\nmới', textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  }

                  final product = _filteredProducts[index];
                  return Card(
                    child: InkWell(
                      onTap: () => _showDiscountDialog(context, product),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Image.network(product.imageUrl, fit: BoxFit.cover, width: double.infinity)),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(currencyFormat.format(product.price), style: const TextStyle(color: Colors.orange)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),

        // ── Panel phải: giỏ hàng ──
        Container(
          width: 400,
          color: Colors.white,
          child: _buildCartPanel(),
        ),
      ]),
    );
  }

  Widget _buildCartPanel() {
    final bool canCheckout =
        widget.user.role == UserRole.admin || widget.user.role == UserRole.cashier;
    final bool isMobile = _sheetState != null;

    return Column(children: [
      if (!isMobile)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            const Text('GIỎ HÀNG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
          ]),
        ),

      // ── Chọn hình thức dùng ──
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: _orderTypes.map((type) {
            final icons = {
              'Mang về': Icons.shopping_bag_outlined,
              'Tại quán': Icons.table_restaurant,
              'Giao hàng': Icons.delivery_dining,
            };
            final selected = _selectedOrderType == type;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => _syncState(() => _selectedOrderType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? Colors.orange : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? Colors.orange : Colors.grey.shade300,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icons[type], size: 20,
                            color: selected ? Colors.white : Colors.grey[600]),
                        const SizedBox(height: 2),
                        Text(type,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: selected ? Colors.white : Colors.grey[600],
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),

      const Divider(height: 1),

      // Danh sách cart — bấm để chỉnh sửa
      Expanded(
        child: _cart.isEmpty
            ? const Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('Chưa có món nào', style: TextStyle(color: Colors.grey)),
          ],
        ))
            : ListView.separated(
          itemCount: _cart.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = _cart[index];
            return InkWell(
              onTap: () => _showEditCartDialog(context, index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  // Thông tin sản phẩm
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (item.discountPercent > 0) ...[
                      Text(currencyFormat.format(item.product.price),
                          style: const TextStyle(decoration: TextDecoration.lineThrough,
                              color: Colors.grey, fontSize: 12)),
                      Text('-${item.discountPercent.toStringAsFixed(0)}%  →  '
                          '${currencyFormat.format(item.product.price * (1 - item.discountPercent / 100))}',
                          style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ] else
                      Text(currencyFormat.format(item.product.price),
                          style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    if (item.note.isNotEmpty)
                      Row(children: [
                        const Icon(Icons.sticky_note_2, size: 12, color: Colors.orange),
                        const SizedBox(width: 4),
                        Expanded(child: Text(item.note,
                            style: const TextStyle(fontSize: 11, color: Colors.orange,
                                fontStyle: FontStyle.italic),
                            overflow: TextOverflow.ellipsis)),
                      ]),
                  ])),

                  // Số lượng + tổng
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _updateQuantity(index, -1),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('${item.quantity}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _updateQuantity(index, 1),
                      ),
                    ]),
                    Text(currencyFormat.format(item.total),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ]),
                ]),
              ),
            );
          },
        ),
      ),

      const Divider(height: 1),

      // Tổng tiền + VAT
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Tạm tính:'),
            Text(currencyFormat.format(_subtotal)),
          ]),
          const SizedBox(height: 4),
          InkWell(
            onTap: _showVatDialog,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Text('VAT (${_vatPercent.toStringAsFixed(0)}%)  ',
                    style: const TextStyle(color: Colors.blue)),
                const Icon(Icons.edit, size: 14, color: Colors.blue),
              ]),
              Text(currencyFormat.format(_vatAmount),
                  style: const TextStyle(color: Colors.blue)),
            ]),
          ),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('TỔNG CỘNG:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(currencyFormat.format(_total),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
          ]),
        ]),
      ),

      // Nút hành động
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(children: [
          // Hàng 1: Hủy đơn + Tạm tính
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _clearCart,
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
              label: const Text('HỦY ĐƠN', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(
              onPressed: _cart.isEmpty ? null : _savePending,
              icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white, size: 16),
              label: const Text('TẠM TÍNH', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                disabledBackgroundColor: Colors.grey[300],
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            )),
          ]),
          const SizedBox(height: 8),
          // Hàng 2: Thanh toán / Đặt món (full width)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canCheckout
                  ? _showCheckoutDialog
                  : () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Xác nhận đặt món'),
                    content: const Text('Gửi đơn hàng này cho Cashier?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                      ElevatedButton(
                          onPressed: () => _finishStaffOrder(context, 'Chờ thanh toán'),
                          child: const Text('XÁC NHẬN')),
                    ],
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: canCheckout ? Colors.orangeAccent : Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: Text(canCheckout ? 'THANH TOÁN' : 'ĐẶT MÓN',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ]),
      ),
    ]);
  }
}
