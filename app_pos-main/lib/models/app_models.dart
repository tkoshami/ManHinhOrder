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

class Product {
  final int id;
  final int? categoryId;
  final String name;
  final double price;
  final String imageUrl;
  final String categoryName;
  final bool isAvailable;

  Product({
    required this.id,
    this.categoryId,
    required this.name,
    required this.price,
    this.imageUrl = '',
    this.categoryName = '',
    this.isAvailable = true,
  });
}

class CartItem {
  final Product product;
  int quantity;
  double discountPercent;
  String note;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.discountPercent = 0,
    this.note = '',
  });

  double get total => (product.price * quantity) * (1 - discountPercent / 100);
}

class SavedOrder {
  final String? id;
  final int? shiftId;
  final List<CartItem> items;
  final DateTime dateTime;
  final double subtotal;
  final double discountAmount;
  final double vatRate; // %
  final double vatAmount;
  final double totalAmount;
  final String paymentMethod;
  final String tableOrCustomer;
  final OrderSource source;
  final OrderStatus status;

  SavedOrder({
    this.id,
    this.shiftId,
    required this.items,
    required this.dateTime,
    required this.subtotal,
    required this.discountAmount,
    required this.vatRate,
    required this.vatAmount,
    required this.totalAmount,
    required this.paymentMethod,
    this.tableOrCustomer = 'Mang đi',
    this.source = OrderSource.posStaff,
    this.status = OrderStatus.pending,
  });

  SavedOrder copyWith({
    String? id,
    int? shiftId,
    List<CartItem>? items,
    DateTime? dateTime,
    double? subtotal,
    double? discountAmount,
    double? vatRate,
    double? vatAmount,
    double? totalAmount,
    String? paymentMethod,
    String? tableOrCustomer,
    OrderSource? source,
    OrderStatus? status,
  }) {
    return SavedOrder(
      id: id ?? this.id,
      shiftId: shiftId ?? this.shiftId,
      items: items ?? this.items,
      dateTime: dateTime ?? this.dateTime,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      vatRate: vatRate ?? this.vatRate,
      vatAmount: vatAmount ?? this.vatAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      tableOrCustomer: tableOrCustomer ?? this.tableOrCustomer,
      source: source ?? this.source,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (shiftId != null) 'shift_id': shiftId,
      'items': items
          .map(
            (item) => {
              'product_id': item.product.id,
              'name': item.product.name,
              'price': item.product.price,
              'quantity': item.quantity,
              'discount_percent': item.discountPercent,
              'note': item.note,
            },
          )
          .toList(),
      'subtotal_amount': subtotal,
      'discount_amount': discountAmount,
      'vat_rate': vatRate,
      'vat_amount': vatAmount,
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
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
  factory SavedOrder.fromJson(Map<String, dynamic> json) {
    return SavedOrder(
      id: json['id']?.toString(),
      shiftId: json['shift_id'],
      items: (json['items'] as List)
          .map(
            (i) => CartItem(
              product: Product(
                id: i['product_id'],
                name: i['name'],
                price: (i['price'] as num).toDouble(),
              ),
              quantity: i['quantity'],
              discountPercent: (i['discount_percent'] as num).toDouble(),
              note: i['note'] ?? '',
            ),
          )
          .toList(),
      dateTime: DateTime.parse(json['order_date'] ?? json['created_at']),
      subtotal: (json['subtotal_amount'] as num).toDouble(),
      discountAmount: (json['discount_amount'] as num).toDouble(),
      vatRate: (json['vat_rate'] as num).toDouble(),
      vatAmount: (json['vat_amount'] as num).toDouble(),
      totalAmount: (json['total_amount'] as num).toDouble(),
      paymentMethod: json['payment_method'],
      tableOrCustomer:
          json['table_or_customer'] ??
          json['table_number'] ??
          json['customer_name'] ??
          'Mang đi',
      source: _sourceFromDatabase(json['source']),
      status: _statusFromDatabase(json['status']),
    );
  }

  // Backward compatibility getters
  double get total => totalAmount;
  double get vatPercent => vatRate;
}
