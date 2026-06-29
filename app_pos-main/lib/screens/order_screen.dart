import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/data/constants.dart';
import 'package:pos_fnb/data/order_data.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/screens/profile_screen.dart';
import 'package:pos_fnb/screens/qr_generator_screen.dart';
import 'package:pos_fnb/screens/settings_screen.dart';
import 'package:pos_fnb/services/print_service.dart';
import 'package:pos_fnb/services/supabase_service.dart';
import 'package:pos_fnb/widgets/product_image.dart';
import 'package:pos_fnb/widgets/vietqr_display.dart';

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
  List<String> _categories = [appCategories[0]];

  // VAT: lưu % dạng số (vd: 10 = 10%), mặc định 8
  double _vatPercent = 8;

  // Track đơn đang được mở từ danh sách chờ (null = đơn mới)
  SavedOrder? _currentPendingOrder;

  // Track state of mobile bottom sheet
  StateSetter? _sheetState;
  StateSetter? _pendingSheetState;

  StreamSubscription<List<SavedOrder>>? _orderSubscription;
  bool _hasSyncedInitialOrderStream = false;
  final Set<String> _notifiedQrOrderIds = <String>{};

  void _syncState(VoidCallback fn) {
    setState(fn);
    _sheetState?.call(() {});
    _pendingSheetState?.call(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadPendingOrders();
    _startListeningToOrders();
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadPendingOrders() async {
    final orders = await SupabaseService.getPendingOrders();
    if (!mounted) return;

    _syncState(() {
      _mergePendingOrders(orders);
    });
  }

  void _startListeningToOrders() {
    _orderSubscription = SupabaseService.subscribeToOrders().listen((orders) {
      if (!mounted) return;

      _syncState(() {
        _mergePendingOrders(
          orders,
          notifyQrOrders: _hasSyncedInitialOrderStream,
        );
        _hasSyncedInitialOrderStream = true;
      });
    });
  }

  void _mergePendingOrders(
    List<SavedOrder> orders, {
    bool notifyQrOrders = false,
  }) {
    for (final newOrder in orders) {
      final existingIndex = globalPendingOrders.indexWhere(
        (order) => order.id == newOrder.id,
      );

      if (existingIndex >= 0) {
        globalPendingOrders[existingIndex] = newOrder;
        continue;
      }

      globalPendingOrders.add(newOrder);

      final orderId = newOrder.id;
      final shouldNotify =
          notifyQrOrders &&
          orderId != null &&
          !_notifiedQrOrderIds.contains(orderId) &&
          (newOrder.source == OrderSource.qrCode ||
              newOrder.source == OrderSource.kiosk);

      if (shouldNotify) {
        _notifiedQrOrderIds.add(orderId);
        _printBill(newOrder);
      }
    }
  }

  void _printBill(SavedOrder order) {
    PrintService.printBill(order);

    // Xóa ngay lập tức các snackbar cũ để không bị dồn hàng chờ
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đơn mới từ khách: ${order.id}. Đang in bill...'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating, // Chuyển sang dạng nổi để tách biệt với đáy
        margin: const EdgeInsets.all(10), // Thêm lề để đẹp hơn và dễ đóng
        action: SnackBarAction(
          label: 'Xem',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            _showOrderDetailsDialog(order);
          },
        ),
      ),
    );
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);

    final products = await SupabaseService.getProducts();
    final productCategories = await SupabaseService.getProductCategories();

    if (!mounted) return;

    final loadedProducts = products.isEmpty
        ? List<Product>.from(defaultProducts)
        : products;
    final loadedCategories = productCategories
        .map((category) => category.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final categoryNames = <String>[appCategories[0], ...loadedCategories];
    final categoryMap = {
      for (final category in productCategories) category.id: category.name,
    };
    final singleCategoryName = loadedCategories.length == 1
        ? loadedCategories.first
        : null;

    setState(() {
      _categories = categoryNames;
      _selectedCategory = _categories.first;
      _allProducts = loadedProducts.map((product) {
        final categoryFromId = product.categoryId == null
            ? null
            : categoryMap[product.categoryId];
        final categoryName =
            categoryFromId ??
            (product.categoryName.trim().isNotEmpty &&
                    product.categoryName != 'Khác'
                ? product.categoryName
                : singleCategoryName ?? product.categoryName);

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

  // ─── Tính tiền ───
  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get _vatAmount => _subtotal * _vatPercent / 100;
  double get _total => _subtotal + _vatAmount;

  String _getRoleName(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'Quản trị viên';
      case UserRole.cashier:
        return 'Thu ngân';
      case UserRole.user:
        return 'Nhân viên';
    }
  }

  void _filterProducts(String query) {
    _syncState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesSearch = p.name.toLowerCase().contains(
          query.toLowerCase(),
        );
        final matchesCategory =
            _selectedCategory == _categories[0] ||
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
      _selectedCategory = _categories[0];
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Xác nhận xóa giỏ hàng',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa toàn bộ các món trong giỏ hàng hiện tại không?',
          style: TextStyle(fontSize: 16),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'KHÔNG',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              _syncState(() => _cart = []);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'XÁC NHẬN',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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

    final savedOrder = await SupabaseService.saveOrder(newOrder);

    _syncState(() {
      if (_currentPendingOrder != null) {
        globalPendingOrders.removeWhere(
          (o) => o.id == _currentPendingOrder!.id,
        );
      }
      globalPendingOrders.add(savedOrder ?? newOrder);
      _currentPendingOrder = null;
      _cart = [];
      _vatPercent = 8;
      _selectedOrderType = appOrderTypes[0];
    });

    // In phiếu tạm tính
    _printBill(savedOrder ?? newOrder);

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          savedOrder != null
              ? 'Đã xác nhận đơn và lưu vào danh sách chờ!'
              : 'Đã lưu cục bộ (Lỗi server)',
        ),
        backgroundColor: savedOrder != null ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _completeOrder(SavedOrder order) {
    String selectedMethod = 'Tiền mặt';
    final TextEditingController receivedController = TextEditingController(
      text: '0',
    );
    int totalQty = order.items.fold(0, (sum, item) => sum + item.quantity);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final double receivedAmount =
              double.tryParse(receivedController.text.replaceAll('.', '')) ?? 0;
          final bool isShort = receivedAmount < order.totalAmount;
          final double diff = (receivedAmount - order.totalAmount).abs();

          final bool isMobile = MediaQuery.of(context).size.width < 600;

          return Dialog(
            insetPadding: isMobile
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
                : const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 24,
                  ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              width: isMobile ? double.infinity : 500,
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 500,
              ),
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Stack(
                children: [
                  SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Chọn phương thức thanh toán',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isMobile ? 18 : 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            _paymentMethodTab(
                              'Tiền mặt',
                              Icons.payments_outlined,
                              selectedMethod == 'Tiền mặt',
                              () => setDialogState(
                                  () => selectedMethod = 'Tiền mặt'),
                            ),
                            const SizedBox(width: 8),
                            _paymentMethodTab(
                              'Chuyển khoản',
                              Icons.account_balance_outlined,
                              selectedMethod == 'Chuyển khoản',
                              () => setDialogState(
                                () => selectedMethod = 'Chuyển khoản',
                              ),
                            ),
                            const SizedBox(width: 8),
                            _paymentMethodTab(
                              'Thẻ',
                              Icons.credit_card_outlined,
                              selectedMethod == 'Thẻ',
                              () =>
                                  setDialogState(() => selectedMethod = 'Thẻ'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _paymentInfoRow('Tổng số lượng món:', '$totalQty món'),
                        _paymentInfoRow(
                          'Tạm tính:',
                          currencyFormat.format(order.subtotal),
                        ),
                        if (order.vatRate > 0)
                          _paymentInfoRow(
                            'Thuế VAT (${order.vatRate.toStringAsFixed(0)}%):',
                            currencyFormat.format(order.vatAmount),
                          ),
                        if (order.discountAmount > 0)
                          _paymentInfoRow(
                            'Giảm tiền lẻ:',
                            currencyFormat.format(order.discountAmount),
                            isGrey: true,
                            subtitle: '(Khi thanh toán tiền mặt)',
                          ),
                        const Divider(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Thực thu:',
                              style: TextStyle(
                                fontSize: isMobile ? 18 : 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                currencyFormat.format(order.totalAmount),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: isMobile ? 22 : 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (selectedMethod == 'Tiền mặt') ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Tiền khách đưa',
                              style: TextStyle(
                                color: Colors.brown.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: receivedController,
                            onTap: () =>
                                receivedController.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset: receivedController.text.length,
                                ),
                            onChanged: (v) => setDialogState(() {}),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _ThousandsSeparatorInputFormatter(),
                            ],
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: isMobile ? 20 : 24,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              prefixIcon: Icon(
                                Icons.payments,
                                color: Colors.green.shade600,
                              ),
                              suffixText: '₫',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.brown.shade300,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.brown.shade700,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final chips = [
                                order.totalAmount,
                                50000.0,
                                100000.0,
                                200000.0,
                                500000.0,
                              ].where((amt) => amt >= order.totalAmount).toSet().toList();

                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: isMobile ? 2 : 3,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: isMobile ? 2.8 : 3.2,
                                ),
                                itemCount: chips.length,
                                itemBuilder: (context, index) {
                                  final amt = chips[index];
                                  return InkWell(
                                    onTap: () {
                                      final formatted = NumberFormat.decimalPattern('vi_VN')
                                          .format(amt.toInt());
                                      receivedController.text = formatted;
                                      setDialogState(() {});
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.shade300),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.02),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        currencyFormat.format(amt),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: isMobile ? 15 : 16,
                                          color: Colors.brown.shade800,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: isShort
                                  ? Colors.red.shade50
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isShort
                                    ? Colors.red.shade200
                                    : Colors.green.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    isShort
                                        ? 'Số tiền còn thiếu:'
                                        : 'Tiền thừa trả khách:',
                                    style: TextStyle(
                                      color: isShort
                                          ? Colors.red.shade700
                                          : Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: isMobile ? 14 : 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  currencyFormat.format(diff),
                                  style: TextStyle(
                                    color: isShort
                                        ? Colors.red.shade700
                                        : Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: isMobile ? 20 : 24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (selectedMethod == 'Chuyển khoản') ...[
                          const SizedBox(height: 10),
                          VietQRDisplay(
                            amount: order.totalAmount.toInt(),
                            description: order.id ?? '',
                          ),
                        ],
                        if (selectedMethod == 'Thẻ') ...[
                          const SizedBox(height: 40),
                          Icon(
                            Icons.contactless,
                            size: 100,
                            color: Colors.blue.shade600,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Vui lòng quẹt hoặc chạm thẻ',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 40),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  final pMethod = selectedMethod == 'Tiền mặt'
                                      ? 'cash'
                                      : (selectedMethod == 'Chuyển khoản'
                                          ? 'qr_code'
                                          : 'card');
                                  _printBill(
                                    order.copyWith(paymentMethod: pMethod),
                                  );
                                },
                                icon: const Icon(Icons.print),
                                label: const Text(
                                  'IN BILL',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  side: BorderSide(color: Colors.orange.shade400),
                                  foregroundColor: Colors.orange.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: (selectedMethod == 'Tiền mặt' &&
                                        receivedAmount < order.totalAmount)
                                    ? null
                                    : () => _finishPayment(
                                          order,
                                          selectedMethod,
                                          receivedAmount:
                                              selectedMethod == 'Tiền mặt'
                                                  ? receivedAmount
                                                  : null,
                                        ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'THANH TOÁN',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _paymentMethodTab(
    String title,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.green.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.green.shade400 : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Colors.green.shade700
                    : Colors.grey.shade600,
                size: isMobile ? 24 : 28,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected
                      ? Colors.green.shade700
                      : Colors.grey.shade600,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentInfoRow(
    String label,
    String value, {
    bool isGrey = false,
    String? subtitle,
  }) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isMobile ? 14 : 15,
                    color: isGrey ? Colors.grey.shade600 : Colors.black87,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isMobile ? 10 : 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 14 : 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _finishPayment(
    SavedOrder order,
    String method, {
    double? receivedAmount,
  }) async {
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

    final paymentMethod = method == 'Tiền mặt'
        ? 'cash'
        : (method == 'Chuyển khoản' ? 'qr_code' : 'card');

    SavedOrder localCompletedOrder() => SavedOrder(
      id: order.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      shiftId: order.shiftId,
      tableOrCustomer: order.tableOrCustomer,
      items: List<CartItem>.from(order.items),
      dateTime: DateTime.now(),
      subtotal: order.subtotal,
      discountAmount: order.discountAmount,
      vatRate: order.vatRate,
      vatAmount: order.vatAmount,
      totalAmount: order.totalAmount,
      paymentMethod: paymentMethod,
      source: order.source,
      status: OrderStatus.completed,
    );

    final idInt = int.tryParse(order.id ?? '');
    final isNewLocalOrder = idInt == null || idInt > 1000000000000;
    bool savedToServer = true;
    SavedOrder? currentOrder;

    if (isNewLocalOrder) {
      currentOrder = await SupabaseService.saveOrder(localCompletedOrder());
    } else {
      currentOrder = await SupabaseService.completePendingOrder(
        order,
        paymentMethod,
      );
    }

    if (currentOrder == null) {
      savedToServer = false;
    }

    final completedOrder = currentOrder ?? localCompletedOrder();

    _syncState(() {
      globalPendingOrders.removeWhere((o) => o.id == order.id);
      globalCompletedOrders.insert(0, completedOrder);
    });

    // In hóa đơn tự động khi hoàn tất thanh toán
    _printBill(completedOrder);

    if (!savedToServer && mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã thanh toán cục bộ. Chưa đồng bộ được lên server.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
    }

    _showReceiptDialogForOrder(
      completedOrder,
      method,
      receivedAmount: receivedAmount,
    );
  }

  void _cancelOrder(SavedOrder order) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận hủy đơn'),
        content: Text(
          'Bạn có chắc chắn muốn hủy đơn hàng tại "${order.tableOrCustomer}" không? Đơn sẽ được xóa khỏi danh sách chờ.',
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

    if (confirm != true) return;

    final success = await SupabaseService.cancelPendingOrder(order);
    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể hủy đơn. Vui lòng thử lại.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    _syncState(() {
      globalPendingOrders.removeWhere((o) => o.id == order.id);
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã hủy đơn và xóa khỏi danh sách chờ'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
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
            Expanded(
              child: Text(
                'Chi tiết đơn: ${order.tableOrCustomer}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
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

  void _showReceiptDialogForOrder(
    SavedOrder order,
    String paymentMethod, {
    double? receivedAmount,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFF5EFEB),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'HÓA ĐƠN',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Loại: ${order.tableOrCustomer}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Text(
                  'Mã đơn: ${order.id}',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                Text(
                  'Ngày: ${DateFormat('dd/MM/yyyy HH:mm').format(order.dateTime)}',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                Text(
                  'PTTT: $paymentMethod',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.brown, thickness: 0.2),
                Row(
                  children: const [
                    SizedBox(
                      width: 30,
                      child: Text(
                        'STT',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Tên món',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        'Đơn giá',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        'SL',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        'T.Tiền',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.brown, thickness: 0.2),
                ...order.items.asMap().entries.map((entry) {
                  int idx = entry.key;
                  CartItem item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 30,
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  if (item.discountPercent > 0)
                                    Text(
                                      '-${item.discountPercent.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                currencyFormat.format(item.product.price),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                'x${item.quantity}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                currencyFormat.format(item.total),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.brown, thickness: 0.1),
                      ],
                    ),
                  );
                }),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tạm tính:', style: TextStyle(fontSize: 14)),
                    Text(
                      currencyFormat.format(order.subtotal),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                if (order.vatRate > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'VAT (${order.vatRate.toStringAsFixed(0)}%):',
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          currencyFormat.format(order.vatAmount),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                const Divider(color: Colors.brown, thickness: 0.2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TỔNG CỘNG:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      currencyFormat.format(order.totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.brown, thickness: 0.2),
                if (receivedAmount != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tiền nhận:', style: TextStyle(fontSize: 14)),
                      Text(
                        currencyFormat.format(receivedAmount),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tiền thừa:', style: TextStyle(fontSize: 14)),
                      Text(
                        currencyFormat.format(
                          receivedAmount - order.totalAmount,
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
                if (paymentMethod == 'Chuyển khoản') ...[
                  const SizedBox(height: 16),
                  const Divider(color: Colors.brown, thickness: 0.2),
                  VietQRDisplay(
                    amount: order.totalAmount.toInt(),
                    description: order.id ?? '',
                  ),
                ],
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _printBill(order),
                      child: const Text(
                        'IN HÓA ĐƠN',
                        style: TextStyle(color: Colors.brown, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _resetOrder();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'ĐÓNG',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã đặt món thành công! Đơn đã gửi cho Cashier.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 4),
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
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      onTap: () => discountController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: discountController.text.length,
                      ),
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
                        if (v.length > 1 &&
                            v.startsWith('0') &&
                            !v.startsWith('0.')) {
                          discountController.text = v.substring(1);
                          discountController.selection =
                              TextSelection.fromPosition(
                                TextPosition(
                                  offset: discountController.text.length,
                                ),
                              );
                          v = discountController.text;
                        }
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
                      spacing: 12,
                      runSpacing: 12,
                      children: [5, 10, 15, 20, 50]
                          .map(
                            (pct) => SizedBox(
                              width: 75,
                              height: 45,
                              child: ActionChip(
                                padding: EdgeInsets.zero,
                                label: Center(
                                  child: Text(
                                    '$pct%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                onPressed: () {
                                  discountController.text = pct.toString();
                                  setDialogState(() {});
                                },
                              ),
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
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
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
                    icon: const Icon(
                      Icons.add_shopping_cart,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'THÊM VÀO ĐƠN',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditCartDialog(BuildContext context, int cartIndex) {
    if (cartIndex < 0 || cartIndex >= _cart.length) return;
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
      builder: (dialogCtx) => StatefulBuilder(
        builder: (stateCtx, setDialogState) {
          final discountPercent = double.tryParse(discountController.text) ?? 0;
          final finalPrice = item.product.price * (1 - discountPercent / 100);

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    item.product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  icon: const Icon(Icons.close),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.product.imageUrl.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ProductImage(
                            imageUrl: item.product.imageUrl,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
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
                              Navigator.pop(dialogCtx);
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
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: false,
                              decimal: false,
                            ),
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
                                // Do nothing while typing
                              } else if (val > 100) {
                                qtyController.text = '100';
                                qtyController.selection =
                                    TextSelection.fromPosition(
                                      const TextPosition(offset: 3),
                                    );
                                setDialogState(() => quantity = 100);
                              } else {
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
                      onTap: () => discountController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: discountController.text.length,
                      ),
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
                        if (v.length > 1 &&
                            v.startsWith('0') &&
                            !v.startsWith('0.')) {
                          discountController.text = v.substring(1);
                          discountController.selection =
                              TextSelection.fromPosition(
                                TextPosition(
                                  offset: discountController.text.length,
                                ),
                              );
                          v = discountController.text;
                        }
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
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          _updateCartItem(cartIndex, 0, '', 0);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'XÓA MÓN',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final discount =
                              (double.tryParse(discountController.text) ?? 0)
                                  .clamp(0.0, 100.0);
                          Navigator.pop(dialogCtx);
                          _updateCartItem(
                            cartIndex,
                            discount,
                            noteController.text.trim(),
                            quantity,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'LƯU THAY ĐỔI',
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
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: false,
                            decimal: false,
                          ),
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

                              color: Colors.orange.shade50,
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.white,
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
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _completeOrder(order);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.check_circle,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Thanh toán',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _openPendingOrder(order);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.edit,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Chỉnh sửa',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: () => _cancelOrder(order),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.cancel,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Hủy đơn',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        label: Text(
                          cat,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
                    final bool isInCart = _cart.any(
                      (item) => item.product.id == product.id,
                    );

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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
        if (_cart.isNotEmpty)
          Material(
            elevation: 16,
            color: Colors.white,
            child: InkWell(
              onTap: _showCartBottomSheet,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.shopping_basket_outlined,
                              color: Colors.orange,
                              size: 28,
                            ),
                          ),
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Text(
                                '${_cart.fold<int>(0, (p, c) => p + c.quantity)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Giỏ hàng (${_cart.length} món)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Text(
                              'Nhấn để kiểm tra & thanh toán',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            currencyFormat.format(_total),
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_up,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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
            offset: const Offset(0, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 8,
            onSelected: (value) async {
              if (value == 'user') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(user: widget.user),
                  ),
                );
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              } else if (value == 'qr_gen') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const QrGeneratorScreen(),
                  ),
                );
              } else if (value == 'logout') {
                await SupabaseService.signOut();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/');
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'user',
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.orange.shade100,
                      backgroundImage: widget.user.avatarUrl != null
                          ? NetworkImage(widget.user.avatarUrl!)
                          : null,
                      child: widget.user.avatarUrl == null
                          ? Text(
                              widget.user.name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.user.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _getRoleName(widget.user.role),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 1),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Cài đặt POS'),
                ),
              ),
              const PopupMenuDivider(height: 1),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.logout,
                        color: Colors.red.shade600,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Đăng xuất',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAdmin) ...[
                const PopupMenuDivider(height: 1),
                PopupMenuItem(
                  value: 'qr_gen',
                  child: ListTile(
                    leading: const Icon(Icons.qr_code),
                    title: const Text('Tạo QR Menu'),
                  ),
                ),
              ],
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 15),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: widget.user.avatarUrl != null
                      ? NetworkImage(widget.user.avatarUrl!)
                      : null,
                  child: widget.user.avatarUrl == null
                      ? Text(
                          widget.user.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
                                      label: Text(
                                        cat,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
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
                                        final product =
                                            _filteredProducts[index];
                                        final bool isInCart = _cart.any(
                                          (item) =>
                                              item.product.id == product.id,
                                        );

                                        return Card(
                                          clipBehavior: Clip.antiAlias,
                                          child: InkWell(
                                            onTap: () => _showDiscountDialog(
                                              context,
                                              product,
                                            ),
                                            child: Stack(
                                              children: [
                                                Opacity(
                                                  opacity: isInCart ? 0.4 : 1.0,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Expanded(
                                                        child: Image.network(
                                                          product.imageUrl,
                                                          fit: BoxFit.cover,
                                                          width:
                                                              double.infinity,
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              8,
                                                            ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              product.name,
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 16,
                                                              ),
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            Text(
                                                              currencyFormat
                                                                  .format(
                                                                    product
                                                                        .price,
                                                                  ),
                                                              style: const TextStyle(
                                                                color: Colors
                                                                    .orange,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
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
    final bool isMobile = _sheetState != null || MediaQuery.of(context).size.width < 600;

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
                  itemBuilder: (ctx, index) {
                    final item = _cart[index];
                    return InkWell(
                      onTap: () => _showEditCartDialog(ctx, index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: ProductImage(
                                    imageUrl: item.product.imageUrl,
                                    width: 45,
                                    height: 45,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.product.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
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
                                ),
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                  icon: const Icon(
                                    Icons.delete_sweep_outlined,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _syncState(() => _cart.removeAt(index));
                                  },
                                  tooltip: 'Xóa món này',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${currencyFormat.format(item.product.price)} x ${item.quantity}',
                                        style: const TextStyle(fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
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
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.red,
                                        size: 26,
                                      ),
                                      onPressed: () =>
                                          _updateQuantity(index, -1),
                                    ),
                                    const SizedBox(width: 4),
                                    _CartItemQuantityInput(
                                      key: ValueKey(
                                        'cart_qty_${item.product.id}_${item.discountPercent}_${item.note}',
                                      ),
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
                                    const SizedBox(width: 4),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        color: Colors.green,
                                        size: 26,
                                      ),
                                      onPressed: () => _updateQuantity(index, 1),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      currencyFormat.format(item.total),
                                      textAlign: TextAlign.right,
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
                          ],
                        ),
                      ),
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
                          onChanged: (val) =>
                              _syncState(() => _vatPercent = val),
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
              if (isUser) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _cart.isEmpty
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
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Hủy'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        _finishStaffOrder(context, 'Đặt món'),
                                    child: const Text('XÁC NHẬN'),
                                  ),
                                ],
                              ),
                            );
                          },
                    icon: const Icon(Icons.send, color: Colors.white),
                    label: const Text(
                      'GỬI ĐƠN',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ] else if (!canCheckout) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _cart.isEmpty
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
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Hủy'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        _finishStaffOrder(context, 'Đặt món'),
                                    child: const Text('XÁC NHẬN'),
                                  ),
                                ],
                              ),
                            );
                          },
                    icon: const Icon(
                      Icons.restaurant_menu,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'ĐẶT MÓN',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _cart.isEmpty ? null : _clearCart,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          'XÓA GIỎ HÀNG',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _cart.isEmpty ? null : _confirmOrder,
                        icon: const Icon(
                          Icons.receipt_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          'TẠM TÍNH',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _cart.isEmpty
                        ? null
                        : () {
                            final orderToPayment = SavedOrder(
                              id:
                                  _currentPendingOrder?.id ??
                                  DateTime.now().millisecondsSinceEpoch
                                      .toString(),
                              shiftId: _currentPendingOrder?.shiftId,
                              tableOrCustomer: _selectedOrderType,
                              items: List<CartItem>.from(_cart),
                              dateTime: DateTime.now(),
                              subtotal: _subtotal,
                              discountAmount: 0,
                              vatRate: _vatPercent,
                              vatAmount: _vatAmount,
                              totalAmount: _total,
                              paymentMethod:
                                  _currentPendingOrder?.paymentMethod ?? 'cash',
                              source:
                                  _currentPendingOrder?.source ??
                                  OrderSource.posStaff,
                              status: OrderStatus.pending,
                            );
                            _completeOrder(orderToPayment);
                          },
                    icon: const Icon(Icons.payment, color: Colors.white),
                    label: const Text(
                      'THANH TOÁN',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
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
    _controller = TextEditingController(
      text: widget.vatPercent.toStringAsFixed(0),
    );
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
        keyboardType: const TextInputType.numberWithOptions(
          signed: false,
          decimal: false,
        ),
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

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Xóa tất cả ký tự không phải số
    String chars = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (chars.isEmpty) return newValue.copyWith(text: '');

    double value = double.parse(chars);
    final formatter = NumberFormat.decimalPattern('vi_VN');
    String newText = formatter.format(value);

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
