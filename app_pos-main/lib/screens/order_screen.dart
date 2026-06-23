import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/data/constants.dart';
import 'package:pos_fnb/data/order_data.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/screens/login_screen.dart';
import 'package:pos_fnb/services/supabase_service.dart';

class OrderScreen extends StatefulWidget {
  final UserAccount user;
  const OrderScreen({super.key, required this.user});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  List<Product> _allProducts = [];
  bool _isLoadingProducts = true;

  List<Product> _filteredProducts = [];
  List<CartItem> _cart = [];
  List<SavedOrder> get _pendingOrders => globalPendingOrders;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  String _selectedOrderType = appOrderTypes[0];
  final List<String> _orderTypes = appOrderTypes;
  String _selectedCategory = appCategories[0];
  final List<String> _categories = appCategories;

  // VAT: lưu % dạng số (vd: 10 = 10%), mặc định 8
  double _vatPercent = 8;

  // Track đơn đang được mở từ danh sách chờ (null = đơn mới)
  SavedOrder? _currentPendingOrder;

  // Track state of mobile bottom sheet
  StateSetter? _sheetState;
  StateSetter? _pendingSheetState;

  void _syncState(VoidCallback fn) {
    setState(fn);
    _sheetState?.call(() {});
    _pendingSheetState?.call(() {});
  }

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

  // ─── Tính tiền ───
  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get _vatAmount => _subtotal * _vatPercent / 100;
  double get _total => _subtotal + _vatAmount;

  void _filterProducts(String query) {
    _syncState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesSearch = p.name.toLowerCase().contains(
          query.toLowerCase(),
        );
        final matchesCategory =
            _selectedCategory == appCategories[0] ||
            p.categoryName == _selectedCategory;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  // ─── Thêm mới vào cart ───
  void _addToCartWithDiscount(
    Product product,
    double discountPercent,
    String note,
  ) {
    _syncState(() {
      final index = _cart.indexWhere(
        (item) =>
            item.product.id == product.id &&
            item.discountPercent == discountPercent &&
            item.note == note,
      );
      if (index >= 0) {
        if (_cart[index].quantity < 100) _cart[index].quantity++;
      } else {
        _cart.add(
          CartItem(
            product: product,
            discountPercent: discountPercent,
            note: note,
          ),
        );
      }
    });
  }

  // ─── Cập nhật cart item đã có (chỉnh sửa) ───
  void _updateCartItem(
    int cartIndex,
    double discountPercent,
    String note,
    int quantity,
  ) {
    _syncState(() {
      if (quantity <= 0) {
        _cart.removeAt(cartIndex);
      } else {
        _cart[cartIndex] = CartItem(
          product: _cart[cartIndex].product,
          quantity: quantity > 100 ? 100 : quantity,
          discountPercent: discountPercent,
          note: note,
        );
      }
    });
  }

  void _updateQuantity(int index, int delta) {
    _syncState(() {
      final newQty = _cart[index].quantity + delta;
      if (newQty <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index].quantity = newQty > 100 ? 100 : newQty;
      }
    });
  }

  void _resetOrder() {
    _syncState(() {
      _cart = [];
      _vatPercent = 8;
      _currentPendingOrder = null;
      _selectedOrderType = appOrderTypes[0];
      _selectedCategory = appCategories[0];
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
        content: const Text(
          'Bạn có chắc chắn muốn hủy toàn bộ các món trong giỏ hàng không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          ElevatedButton(
            onPressed: () {
              _syncState(() => _cart = []);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('HỦY ĐƠN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openPendingOrder(SavedOrder order) {
    _syncState(() {
      // Tự động lưu đơn hiện tại vào pending nếu đang dở dang
      if (_cart.isNotEmpty) {
        final currentToSave = SavedOrder(
          id:
              _currentPendingOrder?.id ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          shiftId: _currentPendingOrder?.shiftId,
          tableOrCustomer: _selectedOrderType,
          items: List<CartItem>.from(_cart),
          dateTime: DateTime.now(),
          subtotal: _subtotal,
          discountAmount: 0,
          vatRate: _vatPercent,
          vatAmount: _vatAmount,
          totalAmount: _total,
          paymentMethod: _currentPendingOrder?.paymentMethod ?? 'cash',
          source: _currentPendingOrder?.source ?? OrderSource.posStaff,
          status: OrderStatus.pending,
        );
        globalPendingOrders.removeWhere((o) => o.id == currentToSave.id);
        globalPendingOrders.add(currentToSave);
      }

      _cart = List<CartItem>.from(order.items);
      _vatPercent = order.vatRate;
      _selectedOrderType = order.tableOrCustomer;
      _currentPendingOrder = order;
      globalPendingOrders.removeWhere((o) => o.id == order.id);
    });
  }

  void _confirmOrder() async {
    if (_cart.isEmpty) return;

    final newOrder = SavedOrder(
      id:
          _currentPendingOrder?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      shiftId: null,
      tableOrCustomer: _selectedOrderType,
      items: List<CartItem>.from(_cart),
      dateTime: DateTime.now(),
      subtotal: _subtotal,
      discountAmount: 0,
      vatRate: _vatPercent,
      vatAmount: _vatAmount,
      totalAmount: _total,
      paymentMethod: 'cash',
      source: OrderSource.posStaff,
      status: OrderStatus.pending,
    );

    final success = await SupabaseService.saveOrder(newOrder);

    _syncState(() {
      if (_currentPendingOrder != null) {
        globalPendingOrders.removeWhere(
          (o) => o.id == _currentPendingOrder!.id,
        );
      }
      globalPendingOrders.add(newOrder);
      _currentPendingOrder = null;
      _cart = [];
      _vatPercent = 8;
      _selectedOrderType = appOrderTypes[0];
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Đã xác nhận đơn và lưu vào danh sách chờ!'
              : 'Đã lưu cục bộ (Lỗi server)',
        ),
        backgroundColor: success ? Colors.green : Colors.orange,
      ),
    );
  }

  void _completeOrder(SavedOrder order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Center(
          child: Text(
            'Chọn phương thức thanh toán',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.money, color: Colors.green),
              title: const Text('Tiền mặt'),
              onTap: () {
                Navigator.pop(context);
                _showCashPaymentDialog(order);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance, color: Colors.blue),
              title: const Text('Chuyển khoản'),
              onTap: () => _finishPayment(order, 'Chuyển khoản'),
            ),
            ListTile(
              leading: const Icon(Icons.credit_card, color: Colors.orange),
              title: const Text('Thẻ'),
              onTap: () => _finishPayment(order, 'Thẻ'),
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

  void _showCashPaymentDialog(SavedOrder order) {
    String receivedStr = '0';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final double receivedAmount = double.tryParse(receivedStr) ?? 0;
          final double change =
              receivedAmount > order.totalAmount
                  ? receivedAmount - order.totalAmount
                  : 0;

          Widget buildNumBtn(
            String text, {
            VoidCallback? onPressed,
            Color? color,
          }) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: ElevatedButton(
                  onPressed:
                      onPressed ??
                      () {
                        setDialogState(() {
                          if (receivedStr == '0') {
                            receivedStr = text;
                          } else {
                            receivedStr += text;
                          }
                        });
                      },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color ?? Colors.grey[200],
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Column(
              children: [
                const Text(
                  'THANH TOÁN TIỀN MẶT',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Bàn/Khách: ${order.tableOrCustomer}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tổng cộng:',
                              style: TextStyle(fontSize: 16),
                            ),
                            Text(
                              currencyFormat.format(order.totalAmount),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Khách đưa:',
                              style: TextStyle(fontSize: 16),
                            ),
                            Text(
                              currencyFormat.format(receivedAmount),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tiền thừa:',
                              style: TextStyle(fontSize: 16),
                            ),
                            Text(
                              currencyFormat.format(change),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Column(
                    children: [
                      Row(
                        children: [
                          buildNumBtn('7'),
                          buildNumBtn('8'),
                          buildNumBtn('9'),
                        ],
                      ),
                      Row(
                        children: [
                          buildNumBtn('4'),
                          buildNumBtn('5'),
                          buildNumBtn('6'),
                        ],
                      ),
                      Row(
                        children: [
                          buildNumBtn('1'),
                          buildNumBtn('2'),
                          buildNumBtn('3'),
                        ],
                      ),
                      Row(
                        children: [
                          buildNumBtn('0'),
                          buildNumBtn('000'),
                          buildNumBtn(
                            'C',
                            color: Colors.red[100],
                            onPressed: () {
                              setDialogState(() => receivedStr = '0');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Gợi ý tiền mặt:',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      [order.totalAmount, 'Đúng số tiền'],
                      [10000.0, '10k'],
                      [20000.0, '20k'],
                      [50000.0, '50k'],
                      [100000.0, '100k'],
                      [200000.0, '200k'],
                      [500000.0, '500k'],
                    ].map((val) {
                      return ActionChip(
                        label: Text(val[1] as String),
                        onPressed: () {
                          setDialogState(() {
                            receivedStr = (val[0] as double).toStringAsFixed(0);
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'QUAY LẠI',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed:
                            receivedAmount >= order.totalAmount
                                ? () => _finishPayment(order, 'Tiền mặt')
                                : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'XÁC NHẬN ĐÃ THU TIỀN',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _finishPayment(SavedOrder order, String method) async {
    Navigator.pop(context);
    if (method == 'Thẻ') {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang quẹt thẻ...'),
            ],
          ),
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    }

    final completedOrder = SavedOrder(
      id: order.id,
      shiftId: order.shiftId,
      tableOrCustomer: order.tableOrCustomer,
      items: order.items,
      dateTime: DateTime.now(),
      subtotal: order.subtotal,
      discountAmount: order.discountAmount,
      vatRate: order.vatRate,
      vatAmount: order.vatAmount,
      totalAmount: order.totalAmount,
      paymentMethod: method == 'Tiền mặt'
          ? 'cash'
          : (method == 'Chuyển khoản' ? 'qr_code' : 'card'),
      source: order.source,
      status: OrderStatus.completed,
    );

    await SupabaseService.saveOrder(completedOrder);

    _syncState(() {
      globalPendingOrders.removeWhere((o) => o.id == order.id);
      globalCompletedOrders.insert(0, completedOrder);
    });

    _showReceiptDialogForOrder(completedOrder, method);
  }

  void _cancelOrder(SavedOrder order) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận hủy đơn'),
        content: Text(
          'Bạn có chắc chắn muốn hủy đơn hàng tại "${order.tableOrCustomer}" không? Đơn hủy vẫn sẽ được lưu vào lịch sử.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Đóng'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('HỦY ĐƠN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final cancelledOrder = SavedOrder(
        id: order.id,
        shiftId: order.shiftId,
        tableOrCustomer: order.tableOrCustomer,
        items: order.items,
        dateTime: DateTime.now(),
        subtotal: order.subtotal,
        discountAmount: order.discountAmount,
        vatRate: order.vatRate,
        vatAmount: order.vatAmount,
        totalAmount: order.totalAmount,
        paymentMethod: order.paymentMethod,
        source: order.source,
        status: OrderStatus.cancelled,
      );

      await SupabaseService.saveOrder(cancelledOrder);

      _syncState(() {
        globalPendingOrders.removeWhere((o) => o.id == order.id);
        globalCompletedOrders.insert(0, cancelledOrder);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy đơn hàng và lưu vào lịch sử'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showOrderDetailsDialog(SavedOrder order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.receipt, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              'Chi tiết đơn: ${order.tableOrCustomer}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...order.items.map(
                  (item) => ListTile(
                    title: Text(
                      item.product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'x${item.quantity}${item.note.isNotEmpty ? " (${item.note})" : ""}',
                    ),
                    trailing: Text(currencyFormat.format(item.total)),
                    dense: true,
                  ),
                ),
                const Divider(),
                _infoRowDetail(
                  'Tạm tính',
                  currencyFormat.format(order.subtotal),
                ),
                if (order.vatRate > 0)
                  _infoRowDetail(
                    'VAT (${order.vatRate.toStringAsFixed(0)}%)',
                    currencyFormat.format(order.vatAmount),
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TỔNG CỘNG:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      currencyFormat.format(order.totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _infoRowDetail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ],
    ),
  );

  void _showReceiptDialogForOrder(SavedOrder order, String paymentMethod) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('HÓA ĐƠN')),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Loại: ${order.tableOrCustomer}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                Text('Mã đơn: ${order.id}'),
                Text(
                  'Ngày: ${DateFormat('dd/MM/yyyy HH:mm').format(order.dateTime)}',
                ),
                Text('PTTT: $paymentMethod'),
                const Divider(),
                ...order.items.map(
                  (item) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.discountPercent > 0
                              ? '${item.product.name} x${item.quantity} (-${item.discountPercent.toStringAsFixed(0)}%)'
                              : '${item.product.name} x${item.quantity}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(currencyFormat.format(item.total)),
                    ],
                  ),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tạm tính:'),
                    Text(currencyFormat.format(order.subtotal)),
                  ],
                ),
                if (order.vatRate > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('VAT (${order.vatRate.toStringAsFixed(0)}%):'),
                      Text(
                        currencyFormat.format(order.vatAmount),
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ],
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TỔNG CỘNG:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      currencyFormat.format(order.totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => debugPrint('In...'),
            child: const Text('IN HÓA ĐƠN'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _resetOrder();
            },
            child: const Text('ĐÓNG'),
          ),
        ],
      ),
    );
  }

  void _finishStaffOrder(BuildContext ctx, String method) {
    Navigator.pop(ctx);
    _syncState(() {
      final newOrder = SavedOrder(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        shiftId: null,
        tableOrCustomer: _selectedOrderType,
        items: List<CartItem>.from(_cart),
        dateTime: DateTime.now(),
        subtotal: _subtotal,
        discountAmount: 0,
        vatRate: _vatPercent,
        vatAmount: _vatAmount,
        totalAmount: _total,
        paymentMethod: method == 'Tiền mặt' ? 'cash' : 'qr_code',
        source: OrderSource.posStaff,
        status: OrderStatus.pending,
      );
      globalPendingOrders.add(newOrder);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã đặt món thành công! Đơn đã gửi cho Cashier.'),
        backgroundColor: Colors.green,
      ),
    );
    _resetOrder();
  }

  void _showDiscountDialog(
    BuildContext context,
    Product product, {
    double initDiscount = 0,
    String initNote = '',
  }) {
    final discountController = TextEditingController(
      text: initDiscount == 0 ? '0' : initDiscount.toStringAsFixed(0),
    );
    final noteController = TextEditingController(text: initNote);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final discountPercent = double.tryParse(discountController.text) ?? 0;
          final finalPrice = product.price * (1 - discountPercent / 100);

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(Icons.local_offer, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Giá gốc:',
                          style: TextStyle(color: Colors.grey),
                        ),
                        Text(
                          currencyFormat.format(product.price),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Giảm giá (%):',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: discountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'),
                      ),
                    ],
                    decoration: InputDecoration(
                      suffixText: '%',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      hintText: '0 - 100',
                    ),
                    onChanged: (v) {
                      final val = double.tryParse(v) ?? 0;
                      if (val > 100) {
                        discountController.text = '100';
                        discountController.selection =
                            TextSelection.fromPosition(
                              const TextPosition(offset: 3),
                            );
                      }
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [5, 10, 15, 20, 50]
                        .map(
                          (pct) => ActionChip(
                            label: Text('$pct%'),
                            onPressed: () {
                              discountController.text = pct.toString();
                              setDialogState(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ghi chú món:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    maxLength: 100,
                    decoration: InputDecoration(
                      hintText: 'VD: ít đường, không đá...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      counterText: '${noteController.text.length}/100',
                    ),
                    onChanged: (v) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Thành tiền:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        currencyFormat.format(finalPrice),
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
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
                  final discount =
                      (double.tryParse(discountController.text) ?? 0).clamp(
                        0.0,
                        100.0,
                      );
                  Navigator.pop(context);
                  _addToCartWithDiscount(
                    product,
                    discount,
                    noteController.text.trim(),
                  );
                },
                icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
                label: const Text(
                  'Thêm vào đơn',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditCartDialog(BuildContext context, int cartIndex) {
    final item = _cart[cartIndex];
    final discountController = TextEditingController(
      text: item.discountPercent == 0
          ? '0'
          : item.discountPercent.toStringAsFixed(0),
    );
    final noteController = TextEditingController(text: item.note);
    int quantity = item.quantity;
    final qtyController = TextEditingController(text: '$quantity');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final discountPercent = double.tryParse(discountController.text) ?? 0;
          final finalPrice = item.product.price * (1 - discountPercent / 100);

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(Icons.edit, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.product.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Số lượng:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red,
                        ),
                        onPressed: () {
                          if (quantity <= 1) {
                            Navigator.pop(context);
                            _updateCartItem(cartIndex, 0, '', 0);
                            return;
                          }

                          setDialogState(() {
                            quantity--;
                            qtyController.text = '$quantity';
                          });
                        },
                      ),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          controller: qtyController,
                          onChanged: (v) {
                            final val = int.tryParse(v) ?? 0;
                            if (v.isEmpty || val <= 0) {
                              Navigator.pop(context);
                              _updateCartItem(cartIndex, 0, '', 0);
                            } else if (val > 100) {
                              qtyController.text = '100';
                              qtyController.selection =
                                  TextSelection.fromPosition(
                                    const TextPosition(offset: 3),
                                  );
                              setDialogState(() => quantity = 100);
                            } else {
                              // Không ép controller.text ở đây để backspace hoạt động bình thường
                              setDialogState(() => quantity = val);
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: Colors.green,
                        ),
                        onPressed: () => setDialogState(() {
                          if (quantity < 100) {
                            quantity++;
                            qtyController.text = '$quantity';
                          }
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Giảm giá (%):',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: discountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'),
                      ),
                    ],
                    decoration: InputDecoration(
                      suffixText: '%',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (v) {
                      final val = double.tryParse(v) ?? 0;
                      if (val > 100) {
                        discountController.text = '100';
                        discountController.selection =
                            TextSelection.fromPosition(
                              const TextPosition(offset: 3),
                            );
                      }
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ghi chú:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    maxLength: 100,
                    decoration: InputDecoration(
                      hintText: 'Ghi chú món ăn...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      counterText: '${noteController.text.length}/100',
                    ),
                    onChanged: (v) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tổng cộng:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        currencyFormat.format(finalPrice * quantity),
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _updateCartItem(cartIndex, 0, '', 0);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                label: const Text('Xóa', style: TextStyle(color: Colors.white)),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                child: const Text('Hủy', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                onPressed: () {
                  final discount =
                      (double.tryParse(discountController.text) ?? 0).clamp(
                        0.0,
                        100.0,
                      );
                  Navigator.pop(context);
                  _updateCartItem(
                    cartIndex,
                    discount,
                    noteController.text.trim(),
                    quantity,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text(
                  'Lưu thay đổi',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddNewProductDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final imageController = TextEditingController();
    // Loại bỏ "Tất cả" khỏi danh sách chọn danh mục cho món mới
    String selectedCat = _categories.length > 1
        ? _categories[1]
        : _categories[0];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.green, width: 2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_circle, color: Colors.green, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'THÊM SẢN PHẨM MỚI',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thông tin món',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    maxLength: 60,
                    onChanged: (v) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Tên món',
                      hintText: 'VD: Cà phê sữa đá',
                      prefixIcon: const Icon(
                        Icons.fastfood,
                        color: Colors.green,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      counterText: '${nameController.text.length}/60',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: 'Giá bán',
                            hintText: '0',
                            suffixText: '₫',
                            prefixIcon: const Icon(
                              Icons.monetization_on,
                              color: Colors.orange,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedCat,
                          decoration: InputDecoration(
                            labelText: 'Danh mục',
                            prefixIcon: const Icon(
                              Icons.category,
                              color: Colors.blue,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: _categories
                              .where((cat) => cat != _categories[0])
                              .map(
                                (cat) => DropdownMenuItem(
                                  value: cat,
                                  child: Text(
                                    cat,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedCat = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: imageController,
                    decoration: InputDecoration(
                      labelText: 'Link hình ảnh (URL)',
                      hintText: 'https://...',
                      prefixIcon: const Icon(Icons.image, color: Colors.purple),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      helperText: 'Để trống để dùng hình mặc định',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'HỦY',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (nameController.text.trim().isNotEmpty &&
                            priceController.text.isNotEmpty) {
                          final newP = Product(
                            id: DateTime.now().millisecondsSinceEpoch,
                            name: nameController.text.trim(),
                            price: double.tryParse(priceController.text) ?? 0,
                            imageUrl: imageController.text.isNotEmpty
                                ? imageController.text
                                : 'https://picsum.photos/200',
                            categoryName: selectedCat,
                          );
                          _syncState(() => _allProducts.add(newP));
                          _filterProducts('');
                          Navigator.pop(ctx);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'THÊM MÓN',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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
    );
  }

  void _showPendingOrdersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setPendingState) {
          _pendingSheetState = setPendingState;
          return DraggableScrollableSheet(
            initialChildSize: 0.8,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey, width: 0.5),
                    ),
                  ),
                  child: const Text(
                    'DANH SÁCH ĐƠN ĐANG CHỜ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: _pendingOrders.isEmpty
                      ? const Center(
                          child: Text('Không có đơn hàng nào đang chờ'),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: _pendingOrders.length,
                          itemBuilder: (context, index) {
                            final order = _pendingOrders[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.orange[100],
                                      child: const Icon(
                                        Icons.table_restaurant,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    title: Text(
                                      'Bàn/Khách: ${order.tableOrCustomer}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Tổng: ${currencyFormat.format(order.totalAmount)} • ${order.items.length} món',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _showOrderDetailsDialog(order),
                                  ),
                                  const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _completeOrder(order);
                                          },
                                          icon: const Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                          ),
                                          label: const Text(
                                            'Thanh toán',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _openPendingOrder(order);
                                          },
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                          ),
                                          label: const Text(
                                            'Chỉnh sửa',
                                            style: TextStyle(
                                              color: Colors.blue,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: () => _cancelOrder(order),
                                          icon: const Icon(
                                            Icons.cancel,
                                            color: Colors.red,
                                          ),
                                          label: const Text(
                                            'Hủy đơn',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 13,
                                            ),
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
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) => _pendingSheetState = null);
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const Text(
                          'GIỎ HÀNG',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
    final bool isAdmin = widget.user.role == UserRole.admin;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _filterProducts,
                  decoration: InputDecoration(
                    hintText: 'Tìm món...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _showAddNewProductDialog,
                  icon: const Icon(
                    Icons.add_circle,
                    color: Colors.green,
                    size: 32,
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories
                  .map(
                    (cat) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ChoiceChip(
                        label: Text(cat, style: const TextStyle(fontSize: 12)),
                        selected: _selectedCategory == cat,
                        onSelected: (sel) {
                          if (sel) {
                            _syncState(() {
                              _selectedCategory = cat;
                              _filterProducts(_searchController.text);
                            });
                          }
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _filteredProducts.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Không tìm thấy món nào phù hợp',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.9,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _filteredProducts.length,
            itemBuilder: (context, index) {
              final product = _filteredProducts[index];
              final bool isInCart = _cart.any((item) => item.product.id == product.id);

              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _showDiscountDialog(context, product),
                  child: Stack(
                    children: [
                      Opacity(
                        opacity: isInCart ? 0.4 : 1.0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Image.network(
                                product.imageUrl,
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    currencyFormat.format(product.price),
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isInCart)
                        const Center(
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 40,
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
                  style: const TextStyle(fontWeight: FontWeight.bold),
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
    final bool isAdmin = widget.user.role == UserRole.admin;
    final bool isUser = widget.user.role == UserRole.user;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isUser ? 'MENU GỌI MÓN' : (isAdmin ? 'ADMIN - POS' : 'CASHIER - POS'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isUser
            ? Colors.green
            : (isAdmin ? Colors.orangeAccent : Colors.orange),
        actions: [
          if (!isUser)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.receipt_long, size: 28),
                  onPressed: _showPendingOrdersSheet,
                ),
                if (_pendingOrders.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '${_pendingOrders.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                await SupabaseService.signOut();
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'user',
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text('${widget.user.name} (${widget.user.role.name})'),
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Đăng xuất'),
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 15),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(
                  widget.user.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: isMobile
          ? _buildMobileLayout()
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onChanged: _filterProducts,
                                decoration: InputDecoration(
                                  hintText: 'Tìm món...',
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            if (isAdmin) ...[
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _showAddNewProductDialog,
                                icon: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'Thêm món',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 20,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _categories
                                .map(
                                  (cat) => Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: ChoiceChip(
                                      label: Text(cat),
                                      selected: _selectedCategory == cat,
                                      onSelected: (sel) {
                                        if (sel) {
                                          _syncState(() {
                                            _selectedCategory = cat;
                                            _filterProducts(
                                              _searchController.text,
                                            );
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _isLoadingProducts
                            ? const Center(child: CircularProgressIndicator())
                            : (_filteredProducts.isEmpty
                                ? const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.search_off,
                                          size: 80,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'Không tìm thấy món nào phù hợp',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : GridView.builder(
                                padding: const EdgeInsets.all(8),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 5,
                                      childAspectRatio: 0.8,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                itemCount: _filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final product = _filteredProducts[index];
                                  final bool isInCart = _cart.any((item) => item.product.id == product.id);

                                  return Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () =>
                                          _showDiscountDialog(context, product),
                                      child: Stack(
                                        children: [
                                          Opacity(
                                            opacity: isInCart ? 0.4 : 1.0,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Image.network(
                                                    product.imageUrl,
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                  ),
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        product.name,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        currencyFormat.format(
                                                          product.price,
                                                        ),
                                                        style: const TextStyle(
                                                          color: Colors.orange,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 18,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isInCart)
                                            const Center(
                                              child: Icon(
                                                Icons.check_circle,
                                                color: Colors.green,
                                                size: 48,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              )),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Colors.white,
                    child: _buildCartPanel(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCartPanel() {
    final bool isAdmin = widget.user.role == UserRole.admin;
    final bool isCashier = widget.user.role == UserRole.cashier;
    final bool isUser = widget.user.role == UserRole.user;
    final bool canCheckout = isAdmin || isCashier;
    final bool isMobile = _sheetState != null;

    return Column(
      children: [
        if (!isMobile)
          Padding(
            padding: const EdgeInsets.all(16),
            child: const Text(
              'GIỎ HÀNG',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: _orderTypes.map((type) {
              IconData icon;
              switch (type) {
                case 'Mang về':
                  icon = Icons.shopping_bag_outlined;
                  break;
                case 'Tại quán':
                  icon = Icons.restaurant;
                  break;
                case 'Giao hàng':
                  icon = Icons.delivery_dining;
                  break;
                default:
                  icon = Icons.help_outline;
              }
              final isSelected = _selectedOrderType == type;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    label: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: isSelected ? Colors.white : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          type,
                          style: TextStyle(
                            fontSize: 14,
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    selected: isSelected,
                    selectedColor: Colors.orange,
                    backgroundColor: Colors.grey[200],
                    onSelected: (s) =>
                        _syncState(() => _selectedOrderType = type),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(),
        Expanded(
          child: _cart.isEmpty
              ? const Center(child: Text('Chưa có món nào'))
              : ListView.separated(
                  itemCount: _cart.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = _cart[index];
                    return ListTile(
                      leading: IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                        onPressed: () {
                          _syncState(() => _cart.removeAt(index));
                        },
                        tooltip: 'Xóa món này',
                      ),
                      title: Text(
                        item.product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${currencyFormat.format(item.product.price)} x ${item.quantity}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (item.discountPercent > 0)
                            Text(
                              'Giảm: ${item.discountPercent.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (item.note.isNotEmpty)
                            Text(
                              'Ghi chú: ${item.note}',
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.blueGrey,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red,
                              size: 26,
                            ),
                            onPressed: () => _updateQuantity(index, -1),
                          ),
                          _CartItemQuantityInput(
                            key: ValueKey('cart_qty_${item.product.id}_${item.discountPercent}_${item.note}'),
                            quantity: item.quantity,
                            onChanged: (val) {
                              _syncState(() {
                                item.quantity = val;
                              });
                            },
                            onRemove: () {
                              _syncState(() => _cart.removeAt(index));
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Colors.green,
                              size: 26,
                            ),
                            onPressed: () => _updateQuantity(index, 1),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 95,
                            child: Text(
                              currencyFormat.format(item.total),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _showEditCartDialog(context, index),
                    );
                  },
                ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tạm tính:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    currencyFormat.format(_subtotal),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'VAT (%):',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  isAdmin
                      ? _VATInput(
                        vatPercent: _vatPercent,
                        onChanged: (val) => _syncState(() => _vatPercent = val),
                      )
                      : Text(
                        '${_vatPercent.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    currencyFormat.format(_vatAmount),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TỔNG CỘNG:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    currencyFormat.format(_total),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (!isUser) ...[
                    Expanded(
                      flex: 1,
                      child: OutlinedButton(
                        onPressed: _clearCart,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'XÓA GIỎ',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    flex: 1,
                    child: ElevatedButton(
                      onPressed: canCheckout
                          ? (_cart.isEmpty ? null : _confirmOrder)
                          : (_cart.isEmpty
                                ? null
                                : () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Xác nhận đặt món'),
                                        content: const Text(
                                          'Gửi đơn hàng này cho Cashier?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Hủy'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => _finishStaffOrder(
                                              context,
                                              'Đặt món',
                                            ),
                                            child: const Text('XÁC NHẬN'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isUser
                            ? Colors.green
                            : (canCheckout ? Colors.orangeAccent : Colors.blue),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        isUser
                            ? 'GỬI ĐƠN'
                            : (canCheckout ? 'XÁC NHẬN' : 'ĐẶT MÓN'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VATInput extends StatefulWidget {
  final double vatPercent;
  final Function(double) onChanged;

  const _VATInput({required this.vatPercent, required this.onChanged});

  @override
  State<_VATInput> createState() => _VATInputState();
}

class _VATInputState extends State<_VATInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.vatPercent.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(covariant _VATInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vatPercent != oldWidget.vatPercent) {
      if (_controller.text != widget.vatPercent.toStringAsFixed(0)) {
        _controller.text = widget.vatPercent.toStringAsFixed(0);
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
          border: InputBorder.none,
        ),
        controller: _controller,
        onChanged: (v) {
          final val = double.tryParse(v) ?? 0;
          if (val <= 100) {
            widget.onChanged(val);
          } else {
            _controller.text = '100';
            _controller.selection = TextSelection.fromPosition(
              const TextPosition(offset: 3),
            );
            widget.onChanged(100);
          }
        },
      ),
    );
  }
}

class _CartItemQuantityInput extends StatefulWidget {
  final int quantity;
  final Function(int) onChanged;
  final VoidCallback onRemove;

  const _CartItemQuantityInput({
    super.key,
    required this.quantity,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_CartItemQuantityInput> createState() => _CartItemQuantityInputState();
}

class _CartItemQuantityInputState extends State<_CartItemQuantityInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.quantity.toString());
  }

  @override
  void didUpdateWidget(covariant _CartItemQuantityInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.quantity != oldWidget.quantity) {
      if (_controller.text != widget.quantity.toString()) {
        _controller.text = widget.quantity.toString();
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      child: TextField(
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
          border: InputBorder.none,
        ),
        controller: _controller,
        onChanged: (v) {
          if (v.isEmpty || v == '0') {
            widget.onRemove();
          } else {
            final val = int.tryParse(v) ?? 0;
            if (val > 100) {
              _controller.text = '100';
              _controller.selection = TextSelection.fromPosition(
                const TextPosition(offset: 3),
              );
              widget.onChanged(100);
            } else {
              widget.onChanged(val);
            }
          }
        },
      ),
    );
  }
}
