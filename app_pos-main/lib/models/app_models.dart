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
    this.tableOrCustomer = 'Mang về',
    this.source = OrderSource.posStaff,
    this.status = OrderStatus.pending,
  });

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
      'status': status.name,
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
      tableOrCustomer: json['table_or_customer'] ?? 'Mang về',
      source: _sourceFromDatabase(json['source']),
      status: OrderStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => OrderStatus.pending,
      ),
    );
  }

  // Backward compatibility getters
  double get total => totalAmount;
  double get vatPercent => vatRate;
}
