enum UserRole { admin, user, cashier }

enum OrderSource { kiosk, qrCode, posStaff }

enum OrderStatus { pending, cooking, completed, cancelled }

class UserAccount {
  final String name;
  final String email;
  final String password;
  final UserRole role;

  UserAccount({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
  });
}

class Product {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String category;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.category,
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

  double get originalTotal => product.price * quantity;
  double get total => originalTotal * (1 - discountPercent / 100);
}

class SavedOrder {
  final String id;
  final String tableOrCustomer;
  final List<CartItem> items;
  final DateTime dateTime;
  final double subtotal; // tổng trước VAT
  final double vatPercent; // % VAT đã áp dụng
  final double total; // tổng sau VAT
  final String? requestedMethod;
  final OrderSource source;
  OrderStatus status;

  SavedOrder({
    required this.id,
    required this.tableOrCustomer,
    required this.items,
    required this.dateTime,
    required this.subtotal,
    required this.vatPercent,
    required this.total,
    this.requestedMethod,
    required this.source,
    this.status = OrderStatus.pending,
  });

  double get vatAmount => subtotal * vatPercent / 100;
}
