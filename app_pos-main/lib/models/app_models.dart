enum UserRole { admin, cashier, user }

enum OrderSource { kiosk, qrCode, posStaff }

enum OrderStatus { pending, cooking, completed, cancelled }

class UserAccount {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  String? avatarUrl;

  UserAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatarUrl,
  });

  UserAccount copyWith({
    String? id,
    String? name,
    String? email,
    UserRole? role,
    String? avatarUrl,
  }) {
    return UserAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

class Category {
  final int id;
  final String name;
  Category({required this.id, required this.name});
}

/// Một biến thể (size/khối lượng) của sản phẩm, VD "500g" - 150.000đ,
/// "1000g" - 300.000đ. Sản phẩm không có biến thể nào vẫn hoạt động bình
/// thường, dùng thẳng `Product.price`.
class ProductVariant {
  final int? id;
  final String name;
  final double price;

  ProductVariant({this.id, required this.name, required this.price});

  ProductVariant copyWith({int? id, String? name, double? price}) {
    return ProductVariant(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'price': price,
  };

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'] == null ? null : int.tryParse(json['id'].toString()),
      name: (json['name'] ?? '').toString(),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class Product {
  final int id;
  final int? categoryId;
  final String name;
  final double price;
  final String imageUrl;
  final String categoryName;
  final bool isAvailable;
  final List<ProductVariant> variants;

  Product({
    required this.id,
    this.categoryId,
    required this.name,
    required this.price,
    this.imageUrl = '',
    this.categoryName = '',
    this.isAvailable = true,
    this.variants = const [],
  });

  bool get hasVariants => variants.isNotEmpty;

  /// Giá thấp nhất trong các biến thể (dùng để hiển thị "Từ x đ" trên menu
  /// khi sản phẩm có nhiều biến thể).
  double get minVariantPrice =>
      hasVariants ? variants.map((v) => v.price).reduce((a, b) => a < b ? a : b) : price;
}

class CartItem {
  final Product product;
  final ProductVariant? variant;
  int quantity;
  double discountPercent;
  String note;
  String discountReason;

  CartItem({
    required this.product,
    this.variant,
    this.quantity = 1,
    this.discountPercent = 0,
    this.note = '',
    this.discountReason = '',
  });

  /// Đơn giá thực tế: lấy giá biến thể đã chọn nếu có, ngược lại dùng giá
  /// gốc của sản phẩm.
  double get unitPrice => variant?.price ?? product.price;

  /// Tên hiển thị kèm biến thể, VD "Chả thủ (500g)".
  String get displayName => variant != null ? '${product.name} (${variant!.name})' : product.name;

  double get total => (unitPrice * quantity) * (1 - discountPercent / 100);
}

class SavedOrder {
  final String? id;
  final String? orderNumber;
  final int? shiftId;
  final List<CartItem> items;
  final DateTime dateTime;
  final double subtotal;
  final double discountAmount;
  final double vatRate;
  final double vatAmount;
  final double totalAmount;
  final String paymentMethod;
  final double? cashReceivedAmount;
  final double? cashChangeAmount;
  final double? cashReturnAmount;
  final String? transferMethod;
  final double? paidAmount;
  final String? transactionCode;
  final DateTime? paidAt;
  final String? cashierName;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;
  final String tableOrCustomer;
  final OrderSource source;
  final OrderStatus status;
  final bool isEdited;

  SavedOrder({
    this.id,
    this.orderNumber,
    this.shiftId,
    required this.items,
    required this.dateTime,
    required this.subtotal,
    required this.discountAmount,
    required this.vatRate,
    required this.vatAmount,
    required this.totalAmount,
    required this.paymentMethod,
    this.cashReceivedAmount,
    this.cashChangeAmount,
    this.cashReturnAmount,
    this.transferMethod,
    this.paidAmount,
    this.transactionCode,
    this.paidAt,
    this.cashierName,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    this.tableOrCustomer = 'Mang đi',
    this.source = OrderSource.posStaff,
    this.status = OrderStatus.pending,
    this.isEdited = false,
  });

  SavedOrder copyWith({
    String? id,
    String? orderNumber,
    int? shiftId,
    List<CartItem>? items,
    DateTime? dateTime,
    double? subtotal,
    double? discountAmount,
    double? vatRate,
    double? vatAmount,
    double? totalAmount,
    String? paymentMethod,
    double? cashReceivedAmount,
    double? cashChangeAmount,
    double? cashReturnAmount,
    String? transferMethod,
    double? paidAmount,
    String? transactionCode,
    DateTime? paidAt,
    String? cashierName,
    DateTime? cancelledAt,
    String? cancelledBy,
    String? cancelReason,
    String? tableOrCustomer,
    OrderSource? source,
    OrderStatus? status,
    bool? isEdited,
  }) {
    return SavedOrder(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      shiftId: shiftId ?? this.shiftId,
      items: items ?? this.items,
      dateTime: dateTime ?? this.dateTime,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      vatRate: vatRate ?? this.vatRate,
      vatAmount: vatAmount ?? this.vatAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      cashReceivedAmount: cashReceivedAmount ?? this.cashReceivedAmount,
      cashChangeAmount: cashChangeAmount ?? this.cashChangeAmount,
      cashReturnAmount: cashReturnAmount ?? this.cashReturnAmount,
      transferMethod: transferMethod ?? this.transferMethod,
      paidAmount: paidAmount ?? this.paidAmount,
      transactionCode: transactionCode ?? this.transactionCode,
      paidAt: paidAt ?? this.paidAt,
      cashierName: cashierName ?? this.cashierName,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancelReason: cancelReason ?? this.cancelReason,
      tableOrCustomer: tableOrCustomer ?? this.tableOrCustomer,
      source: source ?? this.source,
      status: status ?? this.status,
      isEdited: isEdited ?? this.isEdited,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (shiftId != null) 'shift_id': shiftId,
      if (orderNumber != null) 'order_number': orderNumber,
      'items': items
          .map((item) => {
        'product_id': item.product.id,
        'name': item.product.name,
        'price': item.unitPrice,
        'quantity': item.quantity,
        'discount_percent': item.discountPercent,
        'note': item.note,
        'discount_reason': item.discountReason,
        if (item.variant != null) 'variant_name': item.variant!.name,
        if (item.variant != null) 'variant_price': item.variant!.price,
      })
          .toList(),
      'subtotal_amount': subtotal,
      'discount_amount': discountAmount,
      'vat_rate': vatRate,
      'vat_amount': vatAmount,
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
      if (cashReceivedAmount != null) 'cash_received_amount': cashReceivedAmount,
      if (cashChangeAmount != null) 'cash_change_amount': cashChangeAmount,
      if (cashReturnAmount != null) 'cash_return_amount': cashReturnAmount,
      if (transferMethod != null) 'transfer_method': transferMethod,
      if (paidAmount != null) 'paid_amount': paidAmount,
      if (transactionCode != null) 'transaction_code': transactionCode,
      if (paidAt != null) 'paid_at': paidAt!.toUtc().toIso8601String(),
      if (cashierName != null) 'cashier_name': cashierName,
      if (cancelledAt != null) 'cancelled_at': cancelledAt!.toUtc().toIso8601String(),
      if (cancelledBy != null) 'cancelled_by': cancelledBy,
      if (cancelReason != null) 'cancel_reason': cancelReason,
      'source': _sourceToDatabase(source),
      'status': _statusToDatabase(status),
    };
  }

  static String _sourceToDatabase(OrderSource source) {
    switch (source) {
      case OrderSource.qrCode:
      case OrderSource.kiosk:
        return 'self_order';
      case OrderSource.posStaff:
        return 'cashier';
    }
  }

  static OrderSource _sourceFromDatabase(dynamic value) {
    switch (value?.toString()) {
      case 'self_order':
      case 'qrCode':
      case 'qr_code':
        return OrderSource.qrCode;
      case 'kiosk':
        return OrderSource.kiosk;
      case 'staff':
      case 'cashier':
      case 'posStaff':
      case 'pos_staff':
        return OrderSource.posStaff;
      default:
        return OrderSource.posStaff;
    }
  }

  static String _statusToDatabase(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
      case OrderStatus.cooking:
        return 'pending';
      case OrderStatus.completed:
        return 'paid';
      case OrderStatus.cancelled:
        return 'cancelled';
    }
  }

  static OrderStatus _statusFromDatabase(dynamic value) {
    switch (value?.toString()) {
      case 'pending':
        return OrderStatus.pending;
      case 'paid':
      case 'completed':
        return OrderStatus.completed;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'cooking':
        return OrderStatus.cooking;
      default:
        return OrderStatus.pending;
    }
  }

  static double? _nullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _nullableDateTime(dynamic value) {
    if (value == null) return null;
    final dt = DateTime.tryParse(value.toString());
    return dt?.toLocal();
  }

  factory SavedOrder.fromJson(Map<String, dynamic> json) {
    return SavedOrder(
      id: json['id']?.toString(),
      orderNumber: json['order_number']?.toString() ?? json['orderNumber']?.toString(),
      shiftId: json['shift_id'],
      items: (json['items'] as List)
          .map((i) => CartItem(
        product: Product(
          id: i['product_id'],
          name: i['name'],
          price: (i['price'] as num).toDouble(),
        ),
        variant: i['variant_name'] != null
            ? ProductVariant(
          name: i['variant_name'].toString(),
          price: (i['variant_price'] as num?)?.toDouble() ??
              (i['price'] as num).toDouble(),
        )
            : null,
        quantity: i['quantity'],
        discountPercent: (i['discount_percent'] as num).toDouble(),
        note: i['note'] ?? '',
        discountReason: i['discount_reason'] ?? '',
      ))
          .toList(),
      dateTime: DateTime.parse(
        json['order_date'] ?? json['created_at'],
      ).toLocal(),
      subtotal: (json['subtotal_amount'] as num).toDouble(),
      discountAmount: (json['discount_amount'] as num).toDouble(),
      vatRate: (json['vat_rate'] as num).toDouble(),
      vatAmount: (json['vat_amount'] as num).toDouble(),
      totalAmount: (json['total_amount'] as num).toDouble(),
      paymentMethod: json['payment_method'],
      cashReceivedAmount: _nullableDouble(json['cash_received_amount'] ?? json['cashReceivedAmount']),
      cashChangeAmount: _nullableDouble(json['cash_change_amount'] ?? json['cashChangeAmount']),
      cashReturnAmount: _nullableDouble(json['cash_return_amount'] ?? json['cashReturnAmount']),
      transferMethod: json['transfer_method']?.toString() ?? json['transferMethod']?.toString(),
      paidAmount: _nullableDouble(json['paid_amount'] ?? json['paidAmount']),
      transactionCode: json['transaction_code']?.toString() ?? json['transactionCode']?.toString(),
      paidAt: _nullableDateTime(json['paid_at'] ?? json['paidAt']),
      cashierName: json['cashier_name']?.toString() ?? json['cashierName']?.toString(),
      cancelledAt: _nullableDateTime(json['cancelled_at'] ?? json['cancelledAt']),
      cancelledBy: json['cancelled_by']?.toString() ?? json['cancelledBy']?.toString(),
      cancelReason: json['cancel_reason']?.toString() ?? json['cancelReason']?.toString(),
      tableOrCustomer: json['table_or_customer'] ?? json['table_number'] ?? json['customer_name'] ?? 'Mang đi',
      source: _sourceFromDatabase(json['source']),
      status: _statusFromDatabase(json['status']),
      isEdited: json['is_edited'] == true,
    );
  }

  // Backward compatibility getters
  double get total => totalAmount;
  double get vatPercent => vatRate;
  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);
  String get displayOrderCode => orderNumber ?? (id == null ? '---' : 'ZONZON-$id');
}