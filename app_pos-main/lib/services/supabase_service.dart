import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pos_fnb/models/app_models.dart';

class SupabaseService {
  static final _supabase = Supabase.instance.client;

  // --- CATEGORIES ---
  static Future<List<Category>> getCategories() async {
    final response = await _supabase.from('categories').select().order('display_order');
    return (response as List).map((json) => Category(
      id: json['id'],
      name: json['name'],
    )).toList();
  }

  // --- PRODUCTS ---
  static Future<List<Product>> getProducts() async {
    try {
      // Lấy product và join với category để lấy tên category
      final response = await _supabase.from('products')
          .select('*, categories(name)')
          .eq('is_available', true);
      
      return (response as List).map((json) {
        final categoryData = json['categories'];
        return Product(
          id: json['id'],
          categoryId: json['category_id'],
          name: json['name'],
          price: (json['price'] as num).toDouble(),
          categoryName: categoryData != null ? categoryData['name'] : 'Khác',
          // Vì table product của bạn chưa có image_url, ta dùng ảnh tạm
          imageUrl: 'https://picsum.photos/200?random=${json['id']}',
        );
      }).toList();
    } catch (e) {
      print('Lỗi lấy sản phẩm: $e');
      return [];
    }
  }

  // --- SHIFTS (Quản lý ca) ---
  static Future<int?> getCurrentShiftId(String staffId) async {
    try {
      final response = await _supabase
          .from('shifts')
          .select('id')
          .eq('staff_id', staffId)
          .eq('status', 'open')
          .maybeSingle();
      return response?['id'];
    } catch (e) {
      return null;
    }
  }

  // --- ORDERS ---
  static Future<bool> saveOrder(SavedOrder order) async {
    try {
      // Nếu không có shiftId, thử lấy shift đang mở (đề phòng)
      int? sId = order.shiftId;
      if (sId == null) {
        final user = _supabase.auth.currentUser;
        if (user != null) {
          sId = await getCurrentShiftId(user.id);
        }
      }

      if (sId == null) {
        print('Lỗi: Không tìm thấy ca làm việc đang mở');
        return false;
      }

      final List<Map<String, dynamic>> itemsJson = order.items.map((item) => {
        'product_id': item.product.id,
        'name': item.product.name,
        'price': item.product.price,
        'quantity': item.quantity,
        'discount_percent': item.discountPercent,
        'note': item.note,
      }).toList();

      await _supabase.from('orders').insert({
        'shift_id': sId,
        'items': itemsJson,
        'subtotal_amount': order.subtotal,
        'discount_amount': order.discountAmount,
        'vat_rate': order.vatRate,
        'vat_amount': order.vatAmount,
        'total_amount': order.totalAmount,
        'payment_method': order.paymentMethod,
      });
      return true;
    } catch (e) {
      print('Lỗi lưu đơn hàng: $e');
      return false;
    }
  }

  // --- AUTH ---
  static Future<AuthResponse> signIn(String email, String password) async {
    return await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('role, full_name')
          .eq('id', userId)
          .single();
      return response;
    } catch (e) {
      print('Lỗi lấy profile: $e');
      return null;
    }
  }

  // --- SHOP SETTINGS ---
  static Future<Map<String, dynamic>?> getShopPaymentSettings() async {
    try {
      final response = await _supabase
          .from('shop_settings')
          .select()
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      print('Lỗi lấy cấu hình ngân hàng: $e');
      return null;
    }
  }
}
