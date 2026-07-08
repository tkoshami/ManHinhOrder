import 'dart:io';

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

  // ─── CATEGORIES ───────────────────────────────────────
  static Future<List<Category>> getCategories() async {
    try {
      final response = await _supabase.from('categories').select();
      return (response as List)
          .map((json) => Category(
        id: int.tryParse(json['id'].toString()) ?? 0,
        name: json['name'] ?? '',
      ))
          .toList();
    } catch (e) {
      print('Lỗi lấy danh mục: $e');
      return [];
    }
  }

  /// Tạo danh mục món ăn mới, dùng trong dialog Thêm món.
  /// Tự tính display_order = lớn nhất hiện có + 1, để danh mục mới
  /// luôn xếp cuối danh sách thay vì nhảy lên đầu (mặc định 0).
  static Future<Category?> createProductCategory(String name) async {
    try {
      final existing = await _supabase
          .from('product_categories')
          .select('display_order')
          .order('display_order', ascending: false)
          .limit(1);
      final maxOrder = (existing as List).isNotEmpty
          ? (existing.first['display_order'] as num?)?.toInt() ?? 0
          : 0;
      final response = await _supabase
          .from('product_categories')
          .insert({
        'name': name,
        'is_active': true,
        'display_order': maxOrder + 1,
      })
          .select()
          .single();
      return Category(
        id: int.tryParse(response['id'].toString()) ?? 0,
        name: response['name'] ?? name,
      );
    } catch (e) {
      print('Lỗi tạo danh mục: $e');
      return null;
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
          .map((json) => Category(
        id: int.tryParse(json['id'].toString()) ?? 0,
        name: json['name'] ?? '',
      ))
          .toList();
    } catch (e) {
      print('Lỗi lấy danh mục sản phẩm: $e');
      return [];
    }
  }

  // ─── PRODUCTS ─────────────────────────────────────────
  static const String productImagesBucket = 'product-images';

  static Future<String?> uploadProductImage(File imageFile) async {
    try {
      final fileExt = imageFile.path.contains('.')
          ? imageFile.path.substring(imageFile.path.lastIndexOf('.') + 1)
          : 'jpg';
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${imageFile.hashCode}.$fileExt';
      await _supabase.storage
          .from(productImagesBucket)
          .upload(fileName, imageFile,
          fileOptions: const FileOptions(upsert: true));
      return _supabase.storage
          .from(productImagesBucket)
          .getPublicUrl(fileName);
    } catch (e) {
      print('Lỗi upload ảnh sản phẩm: $e');
      return null;
    }
  }

  static Future<List<Product>> getProducts() async {
    try {
      final response = await _supabase
          .from('products')
          .select('*, product_categories(name), product_variants(id, name, price, display_order)')
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
          imageUrl: (json['image_url'] != null &&
              json['image_url'].toString().isNotEmpty)
              ? json['image_url']
              : 'https://picsum.photos/200?random=${json['id']}',
          variants: _parseVariants(json['product_variants']),
        );
      }).toList();
    } catch (e) {
      print('Lỗi lấy sản phẩm từ Supabase: $e');
      return [];
    }
  }

  /// Chuyển dữ liệu thô `product_variants` (join từ bảng con) thành
  /// `List<ProductVariant>`, sắp theo `display_order`.
  static List<ProductVariant> _parseVariants(dynamic raw) {
    if (raw is! List) return [];
    final list = raw.map((v) {
      final map = Map<String, dynamic>.from(v as Map);
      return {
        'variant': ProductVariant(
          id: int.tryParse(map['id']?.toString() ?? ''),
          name: (map['name'] ?? '').toString(),
          price: (map['price'] as num?)?.toDouble() ?? 0.0,
        ),
        'order': (map['display_order'] as num?)?.toInt() ?? 0,
      };
    }).toList();
    list.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return list.map((e) => e['variant'] as ProductVariant).toList();
  }

  static Future<bool> saveProduct(Product product) async {
    try {
      print('Saving product: ${product.name}, categoryId: ${product.categoryId}');
      final inserted = await _supabase.from('products').insert({
        'name': product.name,
        'price': product.price,
        'image_url': product.imageUrl,
        'product_category_id': product.categoryId,
        'is_available': true,
        'display_order': 0,
      }).select('id').single();
      final newProductId = int.tryParse(inserted['id'].toString());
      if (newProductId != null && product.variants.isNotEmpty) {
        await _replaceVariants(newProductId, product.variants);
      }
      return true;
    } catch (e) {
      print('Lỗi lưu sản phẩm chi tiết: $e');
      print('Lỗi type: ${e.runtimeType}');
      return false;
    }
  }

  /// Cập nhật sản phẩm đã có (dùng cho màn hình Quản lý món ăn của admin).
  static Future<bool> updateProduct(Product product) async {
    try {
      await _supabase.from('products').update({
        'name': product.name,
        'price': product.price,
        'image_url': product.imageUrl,
        'product_category_id': product.categoryId,
      }).eq('id', product.id);
      await _replaceVariants(product.id, product.variants);
      return true;
    } catch (e) {
      print('Lỗi cập nhật sản phẩm: $e');
      return false;
    }
  }

  /// Đồng bộ danh sách biến thể của 1 sản phẩm: xóa hết biến thể cũ rồi
  /// thêm lại theo danh sách hiện tại trên form. Đơn giản và an toàn cho
  /// quy mô nhỏ (vài biến thể mỗi món), tránh phải so khớp từng dòng.
  static Future<void> _replaceVariants(int productId, List<ProductVariant> variants) async {
    try {
      await _supabase.from('product_variants').delete().eq('product_id', productId);
      if (variants.isEmpty) return;
      await _supabase.from('product_variants').insert(
        variants
            .asMap()
            .entries
            .map((e) => {
          'product_id': productId,
          'name': e.value.name,
          'price': e.value.price,
          'display_order': e.key,
        })
            .toList(),
      );
    } catch (e) {
      print('Lỗi đồng bộ biến thể sản phẩm: $e');
    }
  }

  /// Xóa sản phẩm (soft delete): đặt `is_available = false` thay vì xóa
  /// hẳn record, để không phá vỡ các đơn hàng cũ đang tham chiếu tới
  /// `product_id` này. `getProducts()` chỉ lấy sản phẩm có
  /// `is_available = true` nên sản phẩm sẽ biến mất khỏi màn hình order
  /// ngay sau khi xóa.
  static Future<bool> deleteProduct(int productId) async {
    try {
      await _supabase
          .from('products')
          .update({'is_available': false}).eq('id', productId);
      return true;
    } catch (e) {
      print('Lỗi xóa sản phẩm: $e');
      return false;
    }
  }

  /// Lấy toàn bộ sản phẩm kể cả những món đã bị ẩn (`is_available = false`).
  /// Dùng cho màn hình Quản lý món ăn của admin, để có thể sửa hoặc bật lại
  /// món đã xóa mềm trước đó.
  static Future<List<Product>> getAllProductsForAdmin() async {
    try {
      final response = await _supabase
          .from('products')
          .select('*, product_categories(name), product_variants(id, name, price, display_order)')
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
          imageUrl: (json['image_url'] != null &&
              json['image_url'].toString().isNotEmpty)
              ? json['image_url']
              : 'https://picsum.photos/200?random=${json['id']}',
          isAvailable: json['is_available'] as bool? ?? true,
          variants: _parseVariants(json['product_variants']),
        );
      }).toList();
    } catch (e) {
      print('Lỗi lấy danh sách món (admin): $e');
      return [];
    }
  }

  /// Bật/tắt hiển thị món ăn (is_available) — dùng để khôi phục món đã xóa.
  static Future<bool> setProductAvailability(int productId, bool isAvailable) async {
    try {
      await _supabase
          .from('products')
          .update({'is_available': isAvailable}).eq('id', productId);
      return true;
    } catch (e) {
      print('Lỗi cập nhật hiển thị món: $e');
      return false;
    }
  }

  /// Lấy ca đang mở (nếu có) của một nhân viên, trả về đầy đủ thông tin
  /// (không chỉ id) để hiển thị trên màn hình Mở ca / Kết ca.
  static Future<Map<String, dynamic>?> getOpenShiftForStaff(String staffId) async {
    try {
      final response = await _supabase
          .from('shifts')
          .select()
          .eq('staff_id', staffId)
          .eq('status', 'open')
          .maybeSingle();
      return response == null ? null : Map<String, dynamic>.from(response);
    } catch (e) {
      print('Lỗi lấy ca đang mở: $e');
      return null;
    }
  }

  /// Mở ca làm việc mới với số tiền quỹ đầu ca.
  static Future<Map<String, dynamic>?> openShift({
    required String staffId,
    required double startCash,
  }) async {
    try {
      final response = await _supabase
          .from('shifts')
          .insert({
        'staff_id': staffId,
        'start_cash': startCash,
        'status': 'open',
      })
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    } catch (e) {
      print('Lỗi mở ca: $e');
      return null;
    }
  }

  /// Kết ca: ghi nhận quỹ tiền mặt đếm thực tế, tiền mặt dự kiến hệ thống
  /// tính (quỹ đầu ca + doanh thu tiền mặt trong ca) và chênh lệch.
  static Future<bool> closeShift({
    required int shiftId,
    required double endCash,
    required double expectedCash,
    String? notes,
  }) async {
    try {
      await _supabase.from('shifts').update({
        'end_at': DateTime.now().toUtc().toIso8601String(),
        'end_cash': endCash,
        'expected_cash': expectedCash,
        'cash_difference': endCash - expectedCash,
        'status': 'closed',
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      }).eq('id', shiftId);
      return true;
    } catch (e) {
      print('Lỗi kết ca: $e');
      return false;
    }
  }

  /// Tổng hợp doanh thu (tiền mặt / chuyển khoản / khác) và số đơn của
  /// một ca, dùng để tính tiền mặt dự kiến khi kết ca và hiển thị báo cáo.
  static Future<Map<String, dynamic>> getShiftOrdersSummary(int shiftId) async {
    try {
      final response = await _supabase
          .from('orders')
          .select('total_amount, payment_method')
          .eq('shift_id', shiftId)
          .filter('cancelled_at', 'is', null);
      double cash = 0, transfer = 0, other = 0;
      int count = 0;
      for (final row in (response as List)) {
        final amt = (row['total_amount'] as num?)?.toDouble() ?? 0;
        final pm = row['payment_method']?.toString();
        count++;
        if (pm == 'cash') {
          cash += amt;
        } else if (pm == 'qr_code') {
          transfer += amt;
        } else {
          other += amt;
        }
      }
      return {'cash': cash, 'transfer': transfer, 'other': other, 'count': count};
    } catch (e) {
      print('Lỗi lấy tổng hợp đơn hàng theo ca: $e');
      return {'cash': 0.0, 'transfer': 0.0, 'other': 0.0, 'count': 0};
    }
  }

  // ─── SHIFTS ───────────────────────────────────────────
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

  /// Lấy lịch sử các ca làm việc (mới nhất trước) để hiển thị báo cáo
  /// đầu ca / kết ca cho admin. Cột thực tế trong bảng `shifts`: id,
  /// staff_id, start_at, end_at, start_cash, end_cash, expected_cash,
  /// cash_difference, notes, status.
  static Future<List<Map<String, dynamic>>> getShiftsHistory({int limit = 100}) async {
    try {
      final response = await _supabase
          .from('shifts')
          .select('*, profiles(full_name)')
          .order('start_at', ascending: false)
          .limit(limit);
      return (response as List).map((json) {
        final map = Map<String, dynamic>.from(json);
        final profile = map['profiles'];
        map['staff_name'] = profile is Map ? profile['full_name'] : null;
        return map;
      }).toList();
    } catch (e) {
      print('Lỗi lấy lịch sử ca làm việc: $e');
      return [];
    }
  }

  /// Lấy toàn bộ ca đang mở (status = 'open') của mọi nhân viên, kèm tên
  /// nhân viên, dùng cho admin dashboard để biết ai đang trực / ca nào
  /// đang hoạt động. Sắp xếp ca mở lâu nhất lên trước để dễ phát hiện
  /// ca bị bỏ quên (quên kết ca).
  static Future<List<Map<String, dynamic>>> getAllOpenShifts() async {
    try {
      final response = await _supabase
          .from('shifts')
          .select('*, profiles(full_name)')
          .eq('status', 'open')
          .order('start_at', ascending: true);
      return (response as List).map((json) {
        final map = Map<String, dynamic>.from(json);
        final profile = map['profiles'];
        map['staff_name'] = profile is Map ? profile['full_name'] : null;
        return map;
      }).toList();
    } catch (e) {
      print('Lỗi lấy danh sách ca đang mở: $e');
      return [];
    }
  }

  /// Admin đóng ca hộ nhân viên (VD: nhân viên quên kết ca khi ra về).
  /// Vì không có ai đếm quỹ thực tế tại quầy, hệ thống tự lấy quỹ đầu ca
  /// + doanh thu tiền mặt trong ca làm số tiền mặt cuối ca (chênh lệch = 0),
  /// và ghi rõ trong `notes` rằng đây là admin đóng hộ để phân biệt với
  /// ca do chính nhân viên tự kết ca.
  static Future<bool> forceCloseShift({
    required int shiftId,
    String? notes,
  }) async {
    try {
      final shift = await _supabase
          .from('shifts')
          .select('start_cash')
          .eq('id', shiftId)
          .single();
      final startCash = (shift['start_cash'] as num?)?.toDouble() ?? 0;
      final summary = await getShiftOrdersSummary(shiftId);
      final cashRevenue = (summary['cash'] as num?)?.toDouble() ?? 0;
      final expectedCash = startCash + cashRevenue;
      await _supabase.from('shifts').update({
        'end_at': DateTime.now().toUtc().toIso8601String(),
        'end_cash': expectedCash,
        'expected_cash': expectedCash,
        'cash_difference': 0,
        'status': 'closed',
        'notes': (notes != null && notes.trim().isNotEmpty)
            ? 'Admin đóng ca hộ. ${notes.trim()}'
            : 'Admin đóng ca hộ (nhân viên không tự kết ca).',
      }).eq('id', shiftId);
      return true;
    } catch (e) {
      print('Lỗi admin đóng ca hộ: $e');
      return false;
    }
  }

  // ─── ORDERS ───────────────────────────────────────────
  static Future<SavedOrder?> saveOrder(SavedOrder order) async {
    try {
      int? sId = order.shiftId;
      if (sId == null && order.source == OrderSource.posStaff) {
        final user = _supabase.auth.currentUser;
        if (user != null) sId = await getCurrentShiftId(user.id);
      }
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
      final response = await _supabase.rpc('create_self_order', params: {
        'p_items': order.items
            .map((item) => {
          'product_id': item.product.id,
          'name': item.product.name,
          'price': item.product.price,
          'quantity': item.quantity,
          'discount_percent': item.discountPercent,
          'note': item.note,
        })
            .toList(),
        'p_subtotal_amount': order.subtotal,
        'p_discount_amount': order.discountAmount,
        'p_vat_rate': order.vatRate,
        'p_vat_amount': order.vatAmount,
        'p_total_amount': order.totalAmount,
        'p_payment_method': order.paymentMethod,
      });
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
      'p_cash_received_amount', 'p_cash_change_amount',
      'p_cash_return_amount', 'p_transfer_method',
      'p_paid_amount', 'p_transaction_code', 'p_paid_at', 'p_cashier_name',
    };
    try {
      final response = await _rpcWithLegacyRetry(
        'create_paid_pos_order',
        {
          'p_items': order.items
              .map((item) => {
            'product_id': item.product.id,
            'name': item.product.name,
            'price': item.product.price,
            'quantity': item.quantity,
            'discount_percent': item.discountPercent,
            'note': item.note,
          })
              .toList(),
          'p_subtotal_amount': order.subtotal,
          'p_discount_amount': order.discountAmount,
          'p_vat_rate': order.vatRate,
          'p_vat_amount': order.vatAmount,
          'p_total_amount': order.totalAmount,
          'p_payment_method': order.paymentMethod,
          if (order.shiftId != null) 'p_shift_id': order.shiftId,
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
    final orderId =
    parsedId != null && parsedId < 1000000000000 ? parsedId : null;

    // Lấy shift_id hiện tại
    final user = _supabase.auth.currentUser;
    final shiftId = user != null ? await getCurrentShiftId(user.id) : null;

    try {
      final response = await _supabase.rpc('save_pending_pos_order', params: {
        'p_order_id': orderId,
        if (shiftId != null) 'p_shift_id': shiftId,
        'p_items': order.items
            .map((item) => {
          'product_id': item.product.id,
          'name': item.product.name,
          'price': item.product.price,
          'quantity': item.quantity,
          'discount_percent': item.discountPercent,
          'note': item.note,
        })
            .toList(),
        'p_subtotal_amount': order.subtotal,
        'p_discount_amount': order.discountAmount,
        'p_vat_rate': order.vatRate,
        'p_vat_amount': order.vatAmount,
        'p_total_amount': order.totalAmount,
        'p_payment_method': order.paymentMethod,
        'p_table_number': order.tableOrCustomer,
      });
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
      'p_cash_received_amount', 'p_cash_change_amount',
      'p_cash_return_amount', 'p_transfer_method',
      'p_paid_amount', 'p_transaction_code', 'p_paid_at', 'p_cashier_name',
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

  /// Admin sửa lại danh sách món trong 1 đơn hàng, tự tính lại
  /// subtotal/vat/total, và đánh dấu `is_edited = true` (chỉ hiện
  /// nhãn "Đã sửa" ở màn Báo cáo dành cho admin).
  static Future<bool> updateOrderItems({
    required String orderId,
    required List<CartItem> items,
    required double vatRate,
    double discountAmount = 0,
  }) async {
    final id = int.tryParse(orderId);
    if (id == null) return false;
    try {
      final subtotal = items.fold(0.0, (s, i) => s + (i.product.price * i.quantity));
      final vatAmount = (subtotal - discountAmount) * vatRate / 100;
      final totalAmount = subtotal - discountAmount + vatAmount;
      await _supabase.from('orders').update({
        'items': items.map((i) => {
          'product_id': i.product.id,
          'name': i.product.name,
          'price': i.product.price,
          'quantity': i.quantity,
          'discount_percent': i.discountPercent,
          'note': i.note,
        }).toList(),
        'subtotal_amount': subtotal,
        'vat_amount': vatAmount,
        'total_amount': totalAmount,
        'is_edited': true,
      }).eq('id', id);
      return true;
    } catch (e) {
      print('Lỗi cập nhật đơn hàng: $e');
      return false;
    }
  }

  /// Xóa vĩnh viễn một đơn hàng (dùng cho màn Báo cáo của admin).
  /// Vì `order_items`, `receipts`, `order_status_logs` đều có khóa ngoại
  /// tới `orders.id`, cần xóa các bảng con trước rồi mới xóa đơn hàng gốc,
  /// nếu không sẽ bị chặn bởi ràng buộc khóa ngoại.
  static Future<bool> deleteOrder(String orderId) async {
    final id = int.tryParse(orderId);
    if (id == null) return false;
    try {
      await _supabase.from('order_items').delete().eq('order_id', id);
      await _supabase.from('receipts').delete().eq('order_id', id);
      await _supabase.from('order_status_logs').delete().eq('order_id', id);
      // .select() sau delete để biết CHÍNH XÁC có dòng nào bị xóa không.
      // Nếu RLS âm thầm chặn (không ném lỗi nhưng cũng không xóa được gì),
      // kết quả trả về sẽ rỗng — ta coi đó là thất bại thay vì báo thành công nhầm.
      final deletedRows = await _supabase
          .from('orders')
          .delete()
          .eq('id', id)
          .select();
      if ((deletedRows as List).isEmpty) {
        print('Lỗi xóa đơn hàng: RLS chặn hoặc không tìm thấy đơn #$id (0 dòng bị xóa)');
        return false;
      }
      return true;
    } catch (e) {
      print('Lỗi xóa đơn hàng: $e');
      return false;
    }
  }

  static Future<List<SavedOrder>> getOrderHistory({int limit = 200}) async {
    try {
      final response = await _supabase
          .rpc('get_order_history', params: {'p_limit': limit});
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
      final response = await _supabase
          .rpc('get_pending_orders', params: {'p_limit': 200});
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

  // ─── AUTH ─────────────────────────────────────────────
  static Future<AuthResponse> signIn(String email, String password) async {
    return await _supabase.auth
        .signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('role, full_name, role_id, roles(name)')
          .eq('id', userId)
          .single();
      return response;
    } catch (e) {
      print('Lỗi lấy profile: $e');
      return null;
    }
  }

  // ─── SHOP SETTINGS ────────────────────────────────────
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

  // ─── USER MANAGEMENT (Admin only) ─────────────────────
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final profiles = await _supabase
          .from('profiles')
          .select('id, full_name, role, email, created_at, role_id, roles(name)')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(profiles);
    } catch (e) {
      print('getAllUsers error: $e');
      return [];
    }
  }

  static Future<bool> createUser({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'admin-user-actions',
        body: {
          'action': 'createUser',
          'email': email,
          'password': password,
          'fullName': fullName,
          'role': role,
        },
      );
      return response.status == 200;
    } catch (e) {
      print('createUser error: $e');
      return false;
    }
  }

  static Future<bool> updateUserProfile({
    required String userId,
    required String fullName,
    required String role,
  }) async {
    try {
      await _supabase
          .from('profiles')
          .update({'full_name': fullName, 'role': role}).eq('id', userId);
      return true;
    } catch (e) {
      print('updateUserProfile error: $e');
      return false;
    }
  }

  static Future<bool> changeUserPassword({
    required String userId,
    required String newPassword,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'admin-user-actions',
        body: {
          'action': 'changePassword',
          'userId': userId,
          'password': newPassword,
        },
      );
      return response.status == 200;
    } catch (e) {
      print('changeUserPassword error: $e');
      return false;
    }
  }

  static Future<bool> deleteUser({required String userId}) async {
    try {
      final response = await _supabase.functions.invoke(
        'admin-user-actions',
        body: {'action': 'deleteUser', 'userId': userId},
      );
      return response.status == 200;
    } catch (e) {
      print('deleteUser error: $e');
      return false;
    }
  }

  // ─── PHÂN QUYỀN (ROLES & PERMISSIONS) ─────────────────
  // Hệ thống bổ sung, đứng CẠNH cột `profiles.role` (text) hiện tại —
  // không thay thế. `profiles.role` vẫn quyết định các luồng lớn
  // (admin/thu ngân/khách). Hệ thống này cho phép admin tự bật/tắt từng
  // quyền nhỏ theo VAI TRÒ (bảng `roles`) hoặc ghi đè riêng cho TỪNG
  // TÀI KHOẢN, không cần sửa code mỗi khi cần thay đổi quyền hạn.

  /// Danh sách tất cả vai trò hiện có (Admin, Thu ngân, Phục vụ, Trưởng ca...).
  static Future<List<Map<String, dynamic>>> getRoles() async {
    try {
      final rows = await _supabase.from('roles').select('id, name, description').order('id');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      print('getRoles error: $e');
      return [];
    }
  }

  /// Danh sách tất cả "quyền" cố định trong code, có nhóm theo category.
  static Future<List<Map<String, dynamic>>> getPermissions() async {
    try {
      final rows = await _supabase
          .from('permissions')
          .select('key, label, description, category, display_order')
          .order('display_order');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      print('getPermissions error: $e');
      return [];
    }
  }

  /// Các quyền đang được BẬT mặc định cho 1 vai trò.
  static Future<Set<String>> getRolePermissionKeys(int roleId) async {
    try {
      final rows = await _supabase
          .from('role_permissions')
          .select('permission_key, allowed')
          .eq('role_id', roleId);
      return List<Map<String, dynamic>>.from(rows)
          .where((r) => r['allowed'] == true)
          .map((r) => r['permission_key'].toString())
          .toSet();
    } catch (e) {
      print('getRolePermissionKeys error: $e');
      return {};
    }
  }

  /// Bật/tắt 1 quyền cho 1 vai trò (dùng ở màn "Phân quyền" của admin).
  static Future<bool> setRolePermission({
    required int roleId,
    required String permissionKey,
    required bool allowed,
  }) async {
    try {
      await _supabase.from('role_permissions').upsert({
        'role_id': roleId,
        'permission_key': permissionKey,
        'allowed': allowed,
      });
      return true;
    } catch (e) {
      print('setRolePermission error: $e');
      return false;
    }
  }

  /// Các quyền đang được GHI ĐÈ riêng cho 1 tài khoản cụ thể (bất kể vai
  /// trò). Map key -> true (luôn cho phép) / false (luôn từ chối).
  static Future<Map<String, bool>> getUserPermissionOverrides(String userId) async {
    try {
      final rows = await _supabase
          .from('user_permissions')
          .select('permission_key, allowed')
          .eq('user_id', userId);
      return {
        for (final r in List<Map<String, dynamic>>.from(rows))
          r['permission_key'].toString(): r['allowed'] == true,
      };
    } catch (e) {
      print('getUserPermissionOverrides error: $e');
      return {};
    }
  }

  /// Ghi đè 1 quyền riêng cho 1 tài khoản (ưu tiên cao hơn quyền theo vai trò).
  static Future<bool> setUserPermissionOverride({
    required String userId,
    required String permissionKey,
    required bool allowed,
  }) async {
    try {
      await _supabase.from('user_permissions').upsert({
        'user_id': userId,
        'permission_key': permissionKey,
        'allowed': allowed,
      });
      return true;
    } catch (e) {
      print('setUserPermissionOverride error: $e');
      return false;
    }
  }

  /// Xóa ghi đè riêng, quay về dùng quyền mặc định theo vai trò.
  static Future<bool> clearUserPermissionOverride({
    required String userId,
    required String permissionKey,
  }) async {
    try {
      await _supabase
          .from('user_permissions')
          .delete()
          .eq('user_id', userId)
          .eq('permission_key', permissionKey);
      return true;
    } catch (e) {
      print('clearUserPermissionOverride error: $e');
      return false;
    }
  }

  /// Tính quyền HIỆU LỰC cuối cùng của 1 tài khoản: bắt đầu từ quyền mặc
  /// định theo vai trò, sau đó áp ghi đè riêng (nếu có) — gọi lúc đăng
  /// nhập để gắn sẵn vào UserAccount, tránh phải truy vấn lại nhiều lần.
  static Future<Set<String>> getEffectivePermissions({
    int? roleId,
    required String userId,
  }) async {
    final effective = <String>{};
    if (roleId != null) {
      effective.addAll(await getRolePermissionKeys(roleId));
    }
    final overrides = await getUserPermissionOverrides(userId);
    overrides.forEach((key, allowed) {
      if (allowed) {
        effective.add(key);
      } else {
        effective.remove(key);
      }
    });
    return effective;
  }

  // ─── KHO HÀNG (INVENTORY) ──────────────────────────────
  // Quản lý tồn kho cho cả nguyên liệu và sản phẩm đang bán, độc lập với
  // bảng `products` (chỉ liên kết qua `linked_product_id` khi cần).

  static Future<List<InventoryItem>> getInventoryItems() async {
    try {
      final rows = await _supabase
          .from('inventory_items')
          .select()
          .order('name', ascending: true);
      return List<Map<String, dynamic>>.from(rows)
          .map((r) => InventoryItem.fromJson(r))
          .toList();
    } catch (e) {
      print('getInventoryItems error: $e');
      return [];
    }
  }

  static Future<InventoryItem?> createInventoryItem({
    required String name,
    required InventoryItemType type,
    required String unit,
    double initialStock = 0,
    double lowStockThreshold = 0,
    int? linkedProductId,
    String? note,
  }) async {
    try {
      final row = await _supabase
          .from('inventory_items')
          .insert({
        'name': name,
        'type': InventoryItem.typeToDatabase(type),
        'unit': unit,
        'current_stock': initialStock,
        'low_stock_threshold': lowStockThreshold,
        if (linkedProductId != null) 'linked_product_id': linkedProductId,
        if (note != null && note.isNotEmpty) 'note': note,
      })
          .select()
          .single();
      return InventoryItem.fromJson(row);
    } catch (e) {
      print('createInventoryItem error: $e');
      return null;
    }
  }

  static Future<bool> updateInventoryItem({
    required int id,
    required String name,
    required String unit,
    required double lowStockThreshold,
    int? linkedProductId,
    String? note,
  }) async {
    try {
      await _supabase.from('inventory_items').update({
        'name': name,
        'unit': unit,
        'low_stock_threshold': lowStockThreshold,
        'linked_product_id': linkedProductId,
        'note': note,
      }).eq('id', id);
      return true;
    } catch (e) {
      print('updateInventoryItem error: $e');
      return false;
    }
  }

  static Future<bool> deleteInventoryItem(int id) async {
    try {
      await _supabase.from('inventory_items').delete().eq('id', id);
      return true;
    } catch (e) {
      print('deleteInventoryItem error: $e');
      return false;
    }
  }

  /// Nhập / xuất / điều chỉnh (kiểm kê) tồn kho cho 1 mặt hàng. Gọi hàm
  /// Postgres `adjust_inventory_stock` để cập nhật tồn kho VÀ ghi lịch sử
  /// trong cùng 1 giao dịch, tránh lệch số nếu có lỗi giữa chừng.
  static Future<bool> adjustInventoryStock({
    required int itemId,
    required InventoryTransactionType type,
    required double quantity,
    String? note,
    String? userId,
    String? userName,
  }) async {
    try {
      await _supabase.rpc('adjust_inventory_stock', params: {
        'p_item_id': itemId,
        'p_type': InventoryTransaction.typeToDatabase(type),
        'p_quantity': quantity,
        if (note != null && note.isNotEmpty) 'p_note': note,
        if (userId != null) 'p_created_by': userId,
        if (userName != null) 'p_created_by_name': userName,
      });
      return true;
    } catch (e) {
      print('adjustInventoryStock error: $e');
      return false;
    }
  }

  /// Lịch sử nhập/xuất/điều chỉnh, mới nhất trước. Có thể lọc theo 1 mặt
  /// hàng cụ thể (dùng ở màn chi tiết) hoặc lấy tất cả (tab "Lịch sử").
  static Future<List<InventoryTransaction>> getInventoryTransactions({
    int? itemId,
    int limit = 100,
  }) async {
    try {
      var query = _supabase
          .from('inventory_transactions')
          .select('*, inventory_items(name, unit)');
      if (itemId != null) {
        query = query.eq('item_id', itemId);
      }
      final rows = await query.order('created_at', ascending: false).limit(limit);
      return List<Map<String, dynamic>>.from(rows)
          .map((r) => InventoryTransaction.fromJson(r))
          .toList();
    } catch (e) {
      print('getInventoryTransactions error: $e');
      return [];
    }
  }
}