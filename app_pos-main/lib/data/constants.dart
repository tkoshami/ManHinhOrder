import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';

final NumberFormat appCurrencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

final List<Product> defaultProducts = [
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

final List<String> appCategories = ['Tất cả', 'Cà phê', 'Trà', 'Bánh', 'Đồ ăn', 'Khác'];
final List<String> appOrderTypes = ['Mang về', 'Tại quán', 'Giao hàng'];
