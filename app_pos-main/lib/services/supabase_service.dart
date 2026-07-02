import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pos_fnb/models/app_models.dart';

class SupabaseService {
  static final _supabase = Supabase.instance.client;

  static Map<String, dynamic> _paidOrderMetadataParams(SavedOrder order) => {
    if (order.cashReceivedAmount != null)
      'p_cash_received_amount': order.cashReceivedAmount,
    if (order.cashChangeAmount != null)
      'p_cash_change_amount': order.cashChangeAmount,
    if (order.cashReturnAmount != null)
      'p_cash_return_amount': order.cashReturnAmount,
    if (order.transferMethod != null) 'p_transfer_method': order.transferMethod,
    if (order.paidAmount != null) 'p_paid_amount': order.paidAmount,
    if (order.transactionCode != null) 'p_transaction_code': order.transactionCode,
    if (order.paidAt != null) 'p_paid_at': order.paidAt!.toUtc().toIso8601String(),
    if (order.cashierName != null) 'p_cashier_name': order.cashierName,
  };

  static Future<dynamic> _rpcWithLegacyRetry(
    String functionName,
    Map<String, dynamic> params,
    Set<String> enhancedKeys,
  ) async {
    try {
      return await _supabase.rpc(functionName, params: params);
    } catch (e) {
      if (!enhancedKeys.any(params.containsKey)) rethrow;

      final legacyParams = Map<String, dynamic>.from(params)
        ..removeWhere((key, _) => enhancedKeys.contains(key));
      return await _supabase.rpc(functionName, params: legacyParams);
    }
  }

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
  static Future<SavedOrder?> saveOrder(SavedOrder order) async {
    try {
      // Nếu là đơn từ QR hoặc Kiosk, không bắt buộc shiftId
      int? sId = order.shiftId;
      if (sId == null && order.source == OrderSource.posStaff) {
        final user = _supabase.auth.currentUser;
        if (user != null) {
          sId = await getCurrentShiftId(user.id);
        }
      }

      // Continue without shift_id when no open shift exists.
      final payload = order.toJson();
      if (sId != null) payload['shift_id'] = sId;

      final response = await _supabase
          .from('orders')
          .insert(payload)
          .select()
          .single();
      return SavedOrder.fromJson(response);
    } catch (e) {
      print('Lỗi lưu đơn hàng: $e');
      return null;
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

  static Future<SavedOrder?> savePaidPosOrder(SavedOrder order) async {
    const enhancedKeys = {
      'p_cash_received_amount',
      'p_cash_change_amount',
      'p_cash_return_amount',
      'p_transfer_method',
      'p_paid_amount',
      'p_transaction_code',
      'p_paid_at',
      'p_cashier_name',
    };

    try {
      final response = await _rpcWithLegacyRetry(
        'create_paid_pos_order',
        {
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
          ..._paidOrderMetadataParams(order),
        },
        enhancedKeys,
      );

      if (response is List && response.isNotEmpty) {
        return SavedOrder.fromJson(Map<String, dynamic>.from(response.first));
      }
      if (response is Map) {
        return SavedOrder.fromJson(Map<String, dynamic>.from(response));
      }
    } catch (e) {
      print('Loi luu don POS bang RPC: $e');
    }

    return saveOrder(order);
  }

  static Future<SavedOrder?> savePendingPosOrder(SavedOrder order) async {
    final parsedId = int.tryParse(order.id ?? '');
    final orderId = parsedId != null && parsedId < 1000000000000
        ? parsedId
        : null;

    try {
      final response = await _supabase.rpc(
        'save_pending_pos_order',
        params: {
          'p_order_id': orderId,
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
          'p_table_number': order.tableOrCustomer,
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
      print('Loi luu don tam tinh len database: $e');
      return null;
    }
  }

  static Future<SavedOrder?> completePendingOrder(
    SavedOrder order,
    String paymentMethod, {
    double? cashReceivedAmount,
    double? cashChangeAmount,
    double? cashReturnAmount,
    String? transferMethod,
    double? paidAmount,
    String? transactionCode,
    DateTime? paidAt,
    String? cashierName,
  }) async {
    if (order.id == null) return null;
    const enhancedKeys = {
      'p_cash_received_amount',
      'p_cash_change_amount',
      'p_cash_return_amount',
      'p_transfer_method',
      'p_paid_amount',
      'p_transaction_code',
      'p_paid_at',
      'p_cashier_name',
    };

    try {
      final response = await _rpcWithLegacyRetry(
        'complete_pending_order',
        {
          'p_order_id': int.tryParse(order.id!),
          'p_payment_method': paymentMethod,
          if (cashReceivedAmount != null)
            'p_cash_received_amount': cashReceivedAmount,
          if (cashChangeAmount != null) 'p_cash_change_amount': cashChangeAmount,
          if (cashReturnAmount != null) 'p_cash_return_amount': cashReturnAmount,
          if (transferMethod != null) 'p_transfer_method': transferMethod,
          if (paidAmount != null) 'p_paid_amount': paidAmount,
          if (transactionCode != null) 'p_transaction_code': transactionCode,
          if (paidAt != null) 'p_paid_at': paidAt.toUtc().toIso8601String(),
          if (cashierName != null) 'p_cashier_name': cashierName,
        },
        enhancedKeys,
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

  static Future<SavedOrder?> cancelPendingOrder(
    SavedOrder order, {
    String? cancelledBy,
    String? reason,
  }) async {
    if (order.id == null) return null;

    try {
      final response = await _supabase.rpc(
        'cancel_pending_order',
        params: {
          'p_order_id': int.tryParse(order.id!),
          'p_cancelled_by': cancelledBy,
          'p_cancel_reason': reason,
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
      print('Lỗi hủy đơn đang chờ: $e');
      return null;
    }
  }

  static Future<List<SavedOrder>> getOrderHistory({int limit = 200}) async {
    try {
      final response = await _supabase.rpc(
        'get_order_history',
        params: {'p_limit': limit},
      );

      return (response as List)
          .map((json) => SavedOrder.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      print('Error loading order history: $e');
      return [];
    }
  }

  static Future<List<SavedOrder>> getPendingOrders() async {
    try {
      final response = await _supabase.rpc(
        'get_pending_orders',
        params: {'p_limit': 200},
      );

      return (response as List)
          .map((json) => SavedOrder.fromJson(Map<String, dynamic>.from(json)))
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
