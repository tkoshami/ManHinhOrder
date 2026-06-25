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

  // Backward compatibility getters
  double get total => totalAmount;
  double get vatPercent => vatRate;
}
