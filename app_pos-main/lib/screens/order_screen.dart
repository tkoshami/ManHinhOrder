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

  bool _isHandheldPos(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortestSide = size.shortestSide;
    return shortestSide <= 380;
  }

  int _mobileProductColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return 1;
    return 2;
  }

  double _mobileProductAspectRatio(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return 1.05;
    if (_isHandheldPos(context)) return 0.82;
    return 0.9;
  }

  double _responsiveDialogWidth(BuildContext context, double desiredWidth) {
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    return desiredWidth.clamp(0, availableWidth).toDouble();
  }

  String _compactOrderTypeLabel(String type) {
    final index = _orderTypes.indexOf(type);
    switch (index) {
      case 0:
        return 'Di';
      case 1:
        return 'Tai';
      case 2:
        return 'Ship';
      default:
        return type;
    }
  }

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

  void _printBill(
    SavedOrder order, {
    double? receivedAmount,
    String? snackMessage,
  }) {
    PrintService.printBill(order, receivedAmount: receivedAmount);

    // Xóa ngay lập tức các snackbar cũ để không bị dồn hàng chờ
    ScaffoldMessenger.of(context).removeCurrentSnackBar();

    final snackController = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          snackMessage ?? 'Đơn mới từ khách: ${order.id}. Đang in bill...',
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior
            .floating, // Chuyển sang dạng nổi để tách biệt với đáy
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

    var snackClosed = false;
    snackController.closed.then((_) {
      snackClosed = true;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (!snackClosed) {
        snackController.close();
      }
    });
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
                'Xác nhận xóa đơn hàng',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa toàn bộ các món trong đơn hàng hiện tại không?',
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

    final savedOrder = await SupabaseService.savePendingPosOrder(newOrder);

    if (savedOrder == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không lưu được đơn tạm tính lên database. Vui lòng thử lại.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    _syncState(() {
      if (_currentPendingOrder != null) {
        globalPendingOrders.removeWhere(
          (o) => o.id == _currentPendingOrder!.id,
        );
      }
      globalPendingOrders.add(savedOrder);
      _currentPendingOrder = null;
      _cart = [];
      _vatPercent = 8;
      _selectedOrderType = appOrderTypes[0];
    });

    // Bỏ in phiếu tạm tính theo yêu cầu
    // _printBill(savedOrder ?? newOrder);

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã xác nhận đơn và lưu vào danh sách chờ!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 4),
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
                : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
                            _PaymentMethodTab(
                              title: 'Tiền mặt',
                              icon: Icons.payments_outlined,
                              isSelected: selectedMethod == 'Tiền mặt',
                              onTap: () => setDialogState(
                                () => selectedMethod = 'Tiền mặt',
                              ),
                            ),
                            const SizedBox(width: 8),
                            _PaymentMethodTab(
                              title: 'Chuyển khoản',
                              icon: Icons.account_balance_outlined,
                              isSelected: selectedMethod == 'Chuyển khoản',
                              onTap: () => setDialogState(
                                () => selectedMethod = 'Chuyển khoản',
                              ),
                            ),
                            const SizedBox(width: 8),
                            _PaymentMethodTab(
                              title: 'Thẻ',
                              icon: Icons.credit_card_outlined,
                              isSelected: selectedMethod == 'Thẻ',
                              onTap: () =>
                                  setDialogState(() => selectedMethod = 'Thẻ'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _PaymentInfoRow(
                          label: 'Tổng số lượng món:',
                          value: '$totalQty món',
                        ),
                        _PaymentInfoRow(
                          label: 'Tạm tính:',
                          value: currencyFormat.format(order.subtotal),
                        ),
                        if (order.vatRate > 0)
                          _PaymentInfoRow(
                            label: 'Thuế VAT (${order.vatRate.toStringAsFixed(0)}%):',
                            value: currencyFormat.format(order.vatAmount),
                          ),
                        if (order.discountAmount > 0)
                          _PaymentInfoRow(
                            label: 'Giảm tiền lẻ:',
                            value: currencyFormat.format(order.discountAmount),
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
                                borderSide: BorderSide(
                                  color: Colors.brown.shade700,
                                  width: 2.2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final chips =
                                  [
                                        order.totalAmount,
                                        50000.0,
                                        100000.0,
                                        200000.0,
                                        500000.0,
                                      ]
                                      .where((amt) => amt >= order.totalAmount)
                                      .toSet()
                                      .toList();

                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
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
                                      final formatted =
                                          NumberFormat.decimalPattern(
                                            'vi_VN',
                                          ).format(amt.toInt());
                                      receivedController.text = formatted;
                                      setDialogState(() {});
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.02,
                                            ),
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
                                    receivedAmount:
                                        pMethod == 'cash' &&
                                            receivedAmount >= order.totalAmount
                                        ? receivedAmount
                                        : null,
                                    snackMessage:
                                        'Đang in bill đơn ${order.id ?? ''}...',
                                  );
                                },
                                icon: const Icon(Icons.print),
                                label: const Text(
                                  'IN BILL',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  side: BorderSide(
                                    color: Colors.orange.shade400,
                                  ),
                                  foregroundColor: Colors.orange.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed:
                                    (selectedMethod == 'Tiền mặt' &&
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
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
    SavedOrder? currentOrder;

    if (isNewLocalOrder) {
      currentOrder = await SupabaseService.savePaidPosOrder(
        localCompletedOrder(),
      );
    } else {
      currentOrder = await SupabaseService.completePendingOrder(
        order,
        paymentMethod,
      );
    }

    if (currentOrder == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Khong luu duoc don len database. Vui long thu lai truoc khi F5.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    final completedOrder = currentOrder;

    _syncState(() {
      globalPendingOrders.removeWhere((o) => o.id == order.id);
      globalCompletedOrders.insert(0, completedOrder);
    });

    // In hóa đơn tự động khi hoàn tất thanh toán
    _printBill(
      completedOrder,
      receivedAmount: receivedAmount,
      snackMessage: 'Đang in bill đơn ${completedOrder.id ?? ''}...',
    );

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Xác nhận hủy đơn',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn hủy đơn hàng này không? Đơn sẽ được xóa khỏi danh sách chờ.',
          style: TextStyle(fontSize: 16),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context, false),
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
            onPressed: () => Navigator.pop(context, true),
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

    if (confirm != true) return;

    final cancelledOrder = await SupabaseService.cancelPendingOrder(order);
    if (!mounted) return;

    if (cancelledOrder == null) {
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
      globalCompletedOrders.removeWhere((o) => o.id == cancelledOrder.id);
      globalCompletedOrders.insert(0, cancelledOrder);
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
        backgroundColor: const Color(0xFFFDF1E8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        title: Row(
          children: [
            const Icon(Icons.receipt, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Mã đơn: ${order.id ?? '---'}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4E342E),
                ),
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: SizedBox(
          width: _responsiveDialogWidth(context, 450),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _InfoRowDetail(
                  label: 'Hình thức:',
                  value: order.tableOrCustomer,
                ),
                const Divider(height: 32, thickness: 1),
                ...order.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF2E1C16),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'x${item.quantity}${item.note.isNotEmpty ? " (${item.note})" : ""}',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          currencyFormat.format(item.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF2E1C16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 32, thickness: 1),
                _InfoRowDetail(
                  label: 'Tạm tính',
                  value: currencyFormat.format(order.subtotal),
                ),
                if (order.vatRate > 0)
                  _InfoRowDetail(
                    label: 'VAT (${order.vatRate.toStringAsFixed(0)}%)',
                    value: currencyFormat.format(order.vatAmount),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TỔNG CỘNG:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF2E1C16),
                      ),
                    ),
                    Text(
                      currencyFormat.format(order.totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        actionsPadding: EdgeInsets.zero,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
              ),
              child: const Text(
                'Đóng',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }





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
          width: _responsiveDialogWidth(context, 500),
          padding: EdgeInsets.all(_isHandheldPos(context) ? 16 : 24),
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
                  'Hình thức: ${order.tableOrCustomer}',
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
                _ReceiptItemsTable(
                  items: order.items,
                  isCompact: _isHandheldPos(context),
                  currencyFormat: currencyFormat,
                ),
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _resetOrder();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'ĐÓNG',
                          style: TextStyle(
                            fontSize: 18,
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
        content: Text('Đã đặt món thành công! Đơn đã gửi cho thu ngân.'),
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
              width: _responsiveDialogWidth(context, 450),
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
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.orange, width: 2.2),
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
                        hintText: 'VD: không rau, thêm chả...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.orange, width: 2.2),
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
              width: _responsiveDialogWidth(context, 400),
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
                                horizontal: 12,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: const BorderSide(color: Colors.blue, width: 2.2),
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
                          borderSide: const BorderSide(color: Colors.blue, width: 2.2),
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
                        hintText: 'VD: không rau, thêm chả...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.orange, width: 2.2),
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
            width: _responsiveDialogWidth(context, 450),
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
                            _ThousandsSeparatorInputFormatter(),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Giá bán',
                            hintText: '0',
                            suffixText: '₫',
                            prefixIcon: const Icon(
                              Icons.monetization_on,
                              color: Colors.orange,
                            ),
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
                              borderSide: const BorderSide(color: Colors.orange, width: 2.2),
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
                              borderSide: const BorderSide(color: Colors.blue, width: 2.2),
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
                        borderSide: const BorderSide(color: Colors.purple, width: 2.2),
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
                            price: double.tryParse(priceController.text.replaceAll('.', '')) ?? 0,
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
      builder: (context) => DefaultTabController(
        length: 2,
        child: StatefulBuilder(
          builder: (context, setPendingState) {
            _pendingSheetState = setPendingState;
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                final selfOrders = _pendingOrders
                    .where(
                      (o) =>
                          o.source == OrderSource.qrCode ||
                          o.source == OrderSource.kiosk,
                    )
                    .toList();
                final staffOrders = _pendingOrders
                    .where((o) => o.source == OrderSource.posStaff)
                    .toList();

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey, width: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'DANH SÁCH ĐƠN ĐANG CHỜ',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    TabBar(
                      labelColor: Colors.orange,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.orange,
                      tabs: [
                        Tab(text: 'Tự đặt (${selfOrders.length})'),
                        Tab(text: 'Tạm tính (${staffOrders.length})'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildPendingOrderList(
                            selfOrders,
                            scrollController,
                            'Không có đơn tự đặt nào',
                          ),
                          _buildPendingOrderList(
                            staffOrders,
                            scrollController,
                            'Không có đơn tạm tính nào',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ).then((_) => _pendingSheetState = null);
  }

  Widget _buildPendingOrderList(
    List<SavedOrder> orders,
    ScrollController scrollController,
    String emptyMessage,
  ) {
    if (orders.isEmpty) {
      return Center(
        child: Text(emptyMessage),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          color: Colors.orange.shade50,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  'Mã đơn: ${order.id ?? '---'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('Hình thức: ${order.tableOrCustomer}'),
                    Text(
                      'Tổng: ${currencyFormat.format(order.totalAmount)}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text('Số món: ${order.items.length}'),
                  ],
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
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
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
                          borderRadius: BorderRadius.circular(8),
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
                          borderRadius: BorderRadius.circular(8),
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
                          borderRadius: BorderRadius.circular(8),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const Text(
                          'ĐƠN HÀNG',
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
    final bool isHandheldPos = _isHandheldPos(context);
    final int productColumns = _mobileProductColumns(context);
    final double productAspectRatio = _mobileProductAspectRatio(context);
    final double horizontalPadding = isHandheldPos ? 6 : 8;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            8,
            horizontalPadding,
            isHandheldPos ? 8 : 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _filterProducts,
                  decoration: InputDecoration(
                    hintText: 'Tìm món...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.orange, width: 2.2),
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
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories
                  .map(
                    (cat) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _CategoryChip(
                        category: cat,
                        isHandheldPos: isHandheldPos,
                        isSelected: _selectedCategory == cat,
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
                  padding: EdgeInsets.all(isHandheldPos ? 6 : 8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: productColumns,
                    childAspectRatio: productAspectRatio,
                    crossAxisSpacing: isHandheldPos ? 6 : 8,
                    mainAxisSpacing: isHandheldPos ? 6 : 8,
                  ),
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = _filteredProducts[index];
                    final bool isInCart = _cart.any(
                      (item) => item.product.id == product.id,
                    );

                    return _ProductCard(
                      product: product,
                      isInCart: isInCart,
                      isHandheldPos: isHandheldPos,
                      currencyFormat: currencyFormat,
                      onTap: () => _showDiscountDialog(context, product),
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
                padding: EdgeInsets.fromLTRB(
                  isHandheldPos ? 10 : 16,
                  isHandheldPos ? 8 : 12,
                  isHandheldPos ? 10 : 16,
                  isHandheldPos ? 12 : 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
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
                            child: Icon(
                              Icons.shopping_basket_outlined,
                              color: Colors.orange,
                              size: isHandheldPos ? 24 : 28,
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
                      SizedBox(width: isHandheldPos ? 10 : 16),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Đơn hàng (${_cart.length} món)',
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
                      color: Colors.black.withValues(alpha: 0.1),
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
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Colors.black54, width: 1.5),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Colors.orange, width: 2.2),
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
                                    child: _CategoryChip(
                                      category: cat,
                                      isHandheldPos: false,
                                      isSelected: _selectedCategory == cat,
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

                                        return _ProductCard(
                                          product: product,
                                          isInCart: isInCart,
                                          isHandheldPos: false,
                                          currencyFormat: currencyFormat,
                                          onTap: () => _showDiscountDialog(
                                            context,
                                            product,
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
    final bool isMobile =
        _sheetState != null || MediaQuery.of(context).size.width < 600;
    final bool isHandheldPos = _isHandheldPos(context);
    final double panelPadding = isHandheldPos ? 8 : 12;

    return Column(
      children: [
        if (!isMobile)
          Padding(
            padding: EdgeInsets.all(isHandheldPos ? 8 : 16),
            child: Text(
              'ĐƠN HÀNG',
              style: TextStyle(
                  fontSize: isHandheldPos ? 16 : 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
        Container(
          margin: EdgeInsets.symmetric(
            horizontal: panelPadding,
            vertical: isHandheldPos ? 4 : 10,
          ),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Row(
            children: _orderTypes.map((type) {
              IconData icon;
              switch (type) {
                case 'Mang đi':
                  icon = Icons.shopping_bag_outlined;
                  break;
                case 'Tại chỗ':
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
                child: GestureDetector(
                  onTap: () => _syncState(() => _selectedOrderType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(
                      vertical: isHandheldPos ? 10 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.orange : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: isSelected
                          ? [
                            BoxShadow(
                              color: Colors.orange.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: isHandheldPos ? 18 : 20,
                          color: isSelected ? Colors.white : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            isHandheldPos ? _compactOrderTypeLabel(type) : type,
                            style: TextStyle(
                              fontSize: isHandheldPos ? 11 : 13,
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(),
        Expanded(
          child: _cart.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.all(isHandheldPos ? 16 : 24),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.shopping_basket_outlined,
                            size: isHandheldPos ? 48 : 64,
                            color: Colors.grey[300],
                          ),
                        ),
                        SizedBox(height: isHandheldPos ? 12 : 24),
                        Text(
                          'Chưa có món nào',
                          style: TextStyle(
                            fontSize: isHandheldPos ? 16 : 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Vui lòng chọn món từ menu để thêm vào đơn hàng',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isHandheldPos ? 12 : 14,
                              color: Colors.grey[400],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _cart.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (ctx, index) {
                    final item = _cart[index];
                    return _CartItemTile(
                      item: item,
                      index: index,
                      isHandheldPos: isHandheldPos,
                      panelPadding: panelPadding,
                      currencyFormat: currencyFormat,
                      onTap: () => _showEditCartDialog(ctx, index),
                      onDelete: () => _syncState(() => _cart.removeAt(index)),
                      onUpdateQuantity: (delta) => _updateQuantity(index, delta),
                      onQuantityChanged: (val) =>
                          _syncState(() => item.quantity = val),
                      onRemove: () => _syncState(() => _cart.removeAt(index)),
                    );
                  },
                ),
        ),
        const Divider(),
        _CartSummary(
          subtotal: _subtotal,
          vatPercent: _vatPercent,
          vatAmount: _vatAmount,
          total: _total,
          isAdmin: isAdmin,
          isUser: isUser,
          canCheckout: canCheckout,
          isHandheldPos: isHandheldPos,
          currencyFormat: currencyFormat,
          vatInput: _VATInput(
            vatPercent: _vatPercent,
            onChanged: (val) => _syncState(() => _vatPercent = val),
          ),
          onClearCart: _cart.isEmpty ? null : _clearCart,
          onConfirmOrder: _cart.isEmpty ? null : _confirmOrder,
          onCheckout: _cart.isEmpty
              ? null
              : () {
                  final orderToPayment = SavedOrder(
                    id: _currentPendingOrder?.id ??
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
                    paymentMethod:
                        _currentPendingOrder?.paymentMethod ?? 'cash',
                    source: _currentPendingOrder?.source ?? OrderSource.posStaff,
                    status: OrderStatus.pending,
                  );
                  _completeOrder(orderToPayment);
                },
          onSendOrder: _cart.isEmpty
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
    return SizedBox(
      width: 70,
      child: TextField(
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.black54, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.black54, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.orange, width: 2.2),
          ),
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
    final bool isHandheldPos = MediaQuery.sizeOf(context).shortestSide <= 380;
    return SizedBox(
      width: isHandheldPos ? 45 : 55,
      child: TextField(
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(
          signed: false,
          decimal: false,
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: isHandheldPos ? 8 : 10, horizontal: 4),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Colors.black54, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Colors.black54, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Colors.green, width: 2.2),
          ),
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

// ─── Refactored Widgets ───

class _PaymentMethodTab extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodTab({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                color: isSelected ? Colors.green.shade700 : Colors.grey.shade600,
                size: isMobile ? 24 : 28,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                      isSelected ? Colors.green.shade700 : Colors.grey.shade600,
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
}

class _PaymentInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isGrey;
  final String? subtitle;

  const _PaymentInfoRow({
    required this.label,
    required this.value,
    this.isGrey = false,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
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
                    subtitle!,
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
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final int index;
  final bool isHandheldPos;
  final double panelPadding;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Function(int) onUpdateQuantity;
  final Function(int) onQuantityChanged;
  final VoidCallback onRemove;

  const _CartItemTile({
    required this.item,
    required this.index,
    required this.isHandheldPos,
    required this.panelPadding,
    required this.currencyFormat,
    required this.onTap,
    required this.onDelete,
    required this.onUpdateQuantity,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: panelPadding,
          vertical: isHandheldPos ? 6 : 8,
        ),
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
                    width: isHandheldPos ? 38 : 45,
                    height: isHandheldPos ? 38 : 45,
                    fit: BoxFit.cover,
                  ),
                ),
                SizedBox(width: isHandheldPos ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isHandheldPos ? 14 : 16,
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
                  onPressed: onDelete,
                  tooltip: 'Xóa món này',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${currencyFormat.format(item.product.price)} x ${item.quantity}',
                        style: TextStyle(
                          fontSize: isHandheldPos ? 12 : 14,
                        ),
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
                      onPressed: () => onUpdateQuantity(-1),
                    ),
                    SizedBox(width: isHandheldPos ? 2 : 4),
                    _CartItemQuantityInput(
                      key: ValueKey(
                        'cart_qty_${item.product.id}_${item.discountPercent}_${item.note}',
                      ),
                      quantity: item.quantity,
                      onChanged: onQuantityChanged,
                      onRemove: onRemove,
                    ),
                    SizedBox(width: isHandheldPos ? 2 : 4),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.green,
                        size: 26,
                      ),
                      onPressed: () => onUpdateQuantity(1),
                    ),
                    SizedBox(width: isHandheldPos ? 4 : 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isHandheldPos ? 82 : 120,
                      ),
                      child: Text(
                        currencyFormat.format(item.total),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: isHandheldPos ? 14 : 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
  }
}

class _CartSummary extends StatelessWidget {
  final double subtotal;
  final double vatPercent;
  final double vatAmount;
  final double total;
  final bool isAdmin;
  final bool isUser;
  final bool canCheckout;
  final bool isHandheldPos;
  final NumberFormat currencyFormat;
  final Widget vatInput;
  final VoidCallback? onClearCart;
  final VoidCallback? onConfirmOrder;
  final VoidCallback? onCheckout;
  final VoidCallback? onSendOrder;

  const _CartSummary({
    required this.subtotal,
    required this.vatPercent,
    required this.vatAmount,
    required this.total,
    required this.isAdmin,
    required this.isUser,
    required this.canCheckout,
    required this.isHandheldPos,
    required this.currencyFormat,
    required this.vatInput,
    required this.onClearCart,
    required this.onConfirmOrder,
    required this.onCheckout,
    required this.onSendOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(isHandheldPos ? 10 : 16),
      child: Column(
        children: [
          _summaryRow('Tạm tính:', currencyFormat.format(subtotal)),
          SizedBox(height: isHandheldPos ? 4 : 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'VAT (%):',
                style: TextStyle(
                    fontSize: isHandheldPos ? 14 : 16,
                    fontWeight: FontWeight.w500),
              ),
              isAdmin
                  ? vatInput
                  : Text(
                      '${vatPercent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: isHandheldPos ? 14 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                currencyFormat.format(vatAmount),
                style: TextStyle(
                  fontSize: isHandheldPos ? 12 : 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Divider(),
          _summaryRow('TỔNG CỘNG:', currencyFormat.format(total), isTotal: true),
          SizedBox(height: isHandheldPos ? 8 : 16),
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isHandheldPos ? 14 : 16,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isHandheldPos ? (isTotal ? 18 : 14) : (isTotal ? 20 : 16),
            fontWeight: FontWeight.bold,
            color: isTotal ? Colors.red : null,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    if (isUser) {
      return _actionButton(
        onPressed: onSendOrder,
        icon: Icons.send,
        label: 'GỬI ĐƠN',
        color: Colors.green,
      );
    } else if (!canCheckout) {
      return _actionButton(
        onPressed: onSendOrder,
        icon: Icons.restaurant_menu,
        label: 'ĐẶT MÓN',
        color: Colors.blue,
      );
    } else {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  onPressed: onClearCart,
                  icon: Icons.delete_outline,
                  label: 'XÓA ĐƠN HÀNG',
                  color: Colors.red,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  onPressed: onConfirmOrder,
                  icon: Icons.receipt_outlined,
                  label: 'TẠM TÍNH',
                  color: Colors.orangeAccent,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _actionButton(
            onPressed: onCheckout,
            icon: Icons.payment,
            label: 'THANH TOÁN',
            color: Colors.green,
            large: true,
          ),
        ],
      );
    }
  }

  Widget _actionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required Color color,
    bool compact = false,
    bool large = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: compact ? 18 : 24),
        label: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: compact ? 13 : (large ? 16 : 14),
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: EdgeInsets.symmetric(
            vertical: isHandheldPos ? (compact ? 10 : 12) : (large ? 16 : 14),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: large ? 2 : 0,
        ),
      ),
    );
  }
}

class _InfoRowDetail extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRowDetail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF2E1C16),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptItemsTable extends StatelessWidget {
  final List<CartItem> items;
  final bool isCompact;
  final NumberFormat currencyFormat;

  const _ReceiptItemsTable({
    required this.items,
    required this.isCompact,
    required this.currencyFormat,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return Column(
        children: [
          const Divider(color: Colors.brown, thickness: 0.2),
          ...items.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final item = entry.value;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '$index.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.product.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 82),
                        child: Text(
                          currencyFormat.format(item.total),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 2),
                    child: Text(
                      '${currencyFormat.format(item.product.price)} x ${item.quantity}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  if (item.discountPercent > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 24, top: 2),
                      child: Text(
                        '-${item.discountPercent.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const Divider(color: Colors.brown, thickness: 0.1),
                ],
              ),
            );
          }),
        ],
      );
    }

    return Column(
      children: [
        const Divider(color: Colors.brown, thickness: 0.2),
        Row(
          children: const [
            SizedBox(
              width: 30,
              child: Text(
                'STT',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            Expanded(
              child: Text(
                'Tên món',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                'Đơn giá',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                'SL',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                'T.Tiền',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        const Divider(color: Colors.brown, thickness: 0.2),
        ...items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;

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
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isInCart;
  final bool isHandheldPos;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.isInCart,
    required this.isHandheldPos,
    required this.currencyFormat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                    padding: EdgeInsets.all(isHandheldPos ? 6 : 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isHandheldPos ? 14 : 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: isHandheldPos ? 2 : 4),
                        Text(
                          currencyFormat.format(product.price),
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: isHandheldPos ? 15 : 18,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isInCart)
              Center(
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: isHandheldPos ? 40 : 48,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;
  final bool isSelected;
  final bool isHandheldPos;
  final Function(bool) onSelected;

  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.isHandheldPos,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      padding: EdgeInsets.symmetric(
        horizontal: isHandheldPos ? 12 : 20,
        vertical: isHandheldPos ? 8 : 12,
      ),
      label: Text(
        category,
        style: TextStyle(
          fontSize: isHandheldPos ? 13 : 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      selected: isSelected,
      onSelected: onSelected,
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

    // Giới hạn tối đa 9.999.999.999
    if (value > 9999999999) {
      value = 9999999999;
    }

    final formatter = NumberFormat.decimalPattern('vi_VN');
    String newText = formatter.format(value);

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
