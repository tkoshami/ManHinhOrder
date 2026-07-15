import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/services/supabase_service.dart';

class SelfOrderConfirmScreen extends StatefulWidget {
  final List<CartItem> cartItems;
  final double subtotal;
  final double total;

  /// Tên bàn lấy từ mã QR (nếu có). null nếu khách vào bằng link chung
  /// không gắn bàn cụ thể.
  final String? tableName;

  const SelfOrderConfirmScreen({
    super.key,
    required this.cartItems,
    required this.subtotal,
    required this.total,
    this.tableName,
  });

  @override
  State<SelfOrderConfirmScreen> createState() => _SelfOrderConfirmScreenState();
}

class _SelfOrderConfirmScreenState extends State<SelfOrderConfirmScreen> {
  bool _isSaving = false;
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  String get _tableOrCustomerLabel =>
      (widget.tableName != null && widget.tableName!.trim().isNotEmpty)
          ? widget.tableName!.trim()
          : 'Khách QR (Mang đi)';

  Future<void> _handlePlaceOrder() async {
    setState(() => _isSaving = true);
    try {
      final order = SavedOrder(
        items: List.from(widget.cartItems),
        dateTime: DateTime.now(),
        subtotal: widget.subtotal,
        discountAmount: 0,
        vatRate: 8,
        vatAmount: widget.subtotal * 0.08,
        totalAmount: widget.total,
        paymentMethod: 'qr_code',
        tableOrCustomer: _tableOrCustomerLabel,
        source: OrderSource.qrCode,
        status: OrderStatus.pending,
      );

      final savedOrder = await SupabaseService.saveSelfOrder(order);
      if (savedOrder != null && mounted) {
        Navigator.pop(context, savedOrder);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Có lỗi xảy ra khi đặt món. Vui lòng thử lại.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'XÁC NHẬN ĐƠN HÀNG',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.green,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Text(
                          'PHIẾU TẠM TÍNH',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      if (widget.tableName != null && widget.tableName!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.table_restaurant, size: 14, color: Colors.green),
                                const SizedBox(width: 6),
                                Text(
                                  _tableOrCustomerLabel,
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const Divider(height: 32, thickness: 1),
                      ...widget.cartItems.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.quantity}x ${item.product.name}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Text(
                                  currencyFormat.format(item.total),
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            if (item.note.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Ghi chú: ${item.note}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )),
                      const Divider(height: 32, thickness: 1),
                      _buildSummaryRow('Tạm tính:', widget.subtotal),
                      _buildSummaryRow('VAT (8%):', widget.subtotal * 0.08),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TỔNG CỘNG:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            currencyFormat.format(widget.total),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Quý khách vui lòng kiểm tra lại thông tin món ăn trước khi đặt.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handlePlaceOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                    'ĐẶT MÓN',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          Text(
            currencyFormat.format(amount),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}