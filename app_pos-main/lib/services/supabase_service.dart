import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pos_fnb/models/app_models.dart';

class SupabaseService {
  static final _supabase = Supabase.instance.client;

  // --- CATEGORIES ---
  static Future<List<Category>> getCategories() async {
    try {
      final response = await _supabase.from('categories').select();
      return (response as List)
          .map(
            (json) => Category(
              id: int.tryParse(json['id'].toString()) ?? 0,
              name: json['name'] ?? '',
            ),
          )
          .toList();
    } catch (e) {
      print('Lỗi lấy danh mục: $e');
      return [];
    }
  }

  static Future<List<Category>> getProductCategories() async {
    try {
      final response = await _supabase
          .from('product_categories')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true);

      return (response as List)
          .map(
            (json) => Category(
              id: int.tryParse(json['id'].toString()) ?? 0,
              name: json['name'] ?? '',
            ),
          )
          .toList();
    } catch (e) {
      print('Lỗi lấy danh mục sản phẩm: $e');
      return [];
    }
  }

  // --- PRODUCTS ---
  static Future<List<Product>> getProducts() async {
    try {
      final response = await _supabase
          .from('products')
          .select('*, product_categories(name)')
          .eq('is_available', true)
          .order('display_order', ascending: true);

      final data = response as List;
      return data.map((json) {
        final rawCategoryId =
            json['category_id'] ?? json['product_category_id'];
        final productCategory = json['product_categories'];
        final rawCategoryName =
            productCategory is Map && productCategory['name'] != null
            ? productCategory['name']
            : json['category_name'] ?? json['category'] ?? 'Khác';

        return Product(
          id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
          categoryId: rawCategoryId == null
              ? null
              : int.tryParse(rawCategoryId.toString()),
          name: json['name'] ?? 'Không tên',
          price: (json['price'] as num?)?.toDouble() ?? 0.0,
          categoryName: rawCategoryName.toString(),
          imageUrl:
              (json['image_url'] != null &&
                  json['image_url'].toString().isNotEmpty)
              ? json['image_url']
              : 'https://picsum.photos/200?random=${json['id']}',
        );
      }).toList();
    } catch (e) {
      print('Lỗi lấy sản phẩm từ Supabase: $e');
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
      // Nếu là đơn từ QR hoặc Kiosk, không bắt buộc shiftId
      int? sId = order.shiftId;
      if (sId == null && order.source == OrderSource.posStaff) {
        final user = _supabase.auth.currentUser;
        if (user != null) {
          sId = await getCurrentShiftId(user.id);
        }
      }

      if (sId == null && order.source == OrderSource.posStaff) {
        print('Lỗi: Không tìm thấy ca làm việc đang mở cho nhân viên POS');
        return false;
      }

      final payload = order.toJson();
      if (sId != null) payload['shift_id'] = sId;
      await _supabase.from('orders').insert(payload);
      return true;
    } catch (e) {
      print('Lỗi lưu đơn hàng: $e');
      return false;
    }
  }

  static Future<SavedOrder?> saveSelfOrder(SavedOrder order) async {
    try {
      final response = await _supabase.rpc(
        'create_self_order',
        params: {
          'p_items': order.items
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
          'p_subtotal_amount': order.subtotal,
          'p_discount_amount': order.discountAmount,
          'p_vat_rate': order.vatRate,
          'p_vat_amount': order.vatAmount,
          'p_total_amount': order.totalAmount,
          'p_payment_method': order.paymentMethod,
        },
      );

      if (response is List && response.isNotEmpty) {
        return SavedOrder.fromJson(Map<String, dynamic>.from(response.first));
      }
      if (response is Map) {
        return SavedOrder.fromJson(Map<String, dynamic>.from(response));
      }
      return null;
    } catch (e) {
      print('Lỗi lưu đơn self-order: $e');
      return null;
    }
  }

  static Future<SavedOrder?> completePendingOrder(
    SavedOrder order,
    String paymentMethod,
  ) async {
    if (order.id == null) return null;

    try {
      final response = await _supabase.rpc(
        'complete_pending_order',
        params: {
          'p_order_id': int.tryParse(order.id!),
          'p_payment_method': paymentMethod,
        },
      );

      if (response is List && response.isNotEmpty) {
        return SavedOrder.fromJson(Map<String, dynamic>.from(response.first));
      }
      if (response is Map) {
        return SavedOrder.fromJson(Map<String, dynamic>.from(response));
      }
      return null;
    } catch (e) {
      print('Lỗi thanh toán đơn đang chờ: $e');
      return null;
    }
  }

  static Future<bool> cancelPendingOrder(SavedOrder order) async {
    if (order.id == null) return false;

    try {
      await _supabase.rpc(
        'cancel_pending_order',
        params: {'p_order_id': int.tryParse(order.id!)},
      );
      return true;
    } catch (e) {
      print('Lỗi hủy đơn đang chờ: $e');
      return false;
    }
  }

  static Future<List<SavedOrder>> getPendingOrders() async {
    try {
      final response = await _supabase
          .from('orders')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => SavedOrder.fromJson(json))
          .toList();
    } catch (e) {
      print('Lỗi lấy danh sách đơn đang chờ: $e');
      return [];
    }
  }

  static Stream<List<SavedOrder>> subscribeToOrders() {
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .map((data) => data.map((json) => SavedOrder.fromJson(json)).toList());
  }

  // --- AUTH ---
  static Future<AuthResponse> signIn(String email, String password) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
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
