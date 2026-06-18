import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'order_screen.dart'; // globalCompletedOrders
import 'models.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  // Lấy đơn đã thanh toán theo phương thức
  List<SavedOrder> get _allOrders => globalCompletedOrders;
  List<SavedOrder> _byMethod(String method) =>
      globalCompletedOrders.where((o) => o.requestedMethod == method).toList();

  double _sumTotal(List<SavedOrder> orders) =>
      orders.fold(0, (sum, o) => sum + o.total);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lịch sử thanh toán', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.orangeAccent,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.receipt_long), text: 'Đơn hàng'),
              Tab(icon: Icon(Icons.payments), text: 'Loại thanh toán'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ── Tab 1: Tất cả đơn đã thanh toán ──
            _OrderHistoryTab(
              orders: _allOrders,
              currencyFormat: currencyFormat,
              onRefresh: () => setState(() {}),
            ),

            // ── Tab 2: Phân loại theo PTTT ──
            _PaymentMethodTab(
              currencyFormat: currencyFormat,
              byMethod: _byMethod,
              sumTotal: _sumTotal,
              onRefresh: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// Hàm dùng chung: hiện chi tiết đơn hàng
// ══════════════════════════════════════════
void showOrderDetail(BuildContext context, SavedOrder order, NumberFormat fmt, {VoidCallback? onDeleted}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.receipt, color: Colors.orange),
        const SizedBox(width: 8),
        Flexible(child: Text(order.id,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _infoRow('Hình thức', order.tableOrCustomer),
            _infoRow('Thời gian', DateFormat('dd/MM/yyyy HH:mm').format(order.dateTime)),
            _infoRow('Thanh toán', order.requestedMethod ?? '—'),
            const Divider(),
            ...order.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item.product.name} x${item.quantity}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    if (item.discountPercent > 0)
                      Text('-${item.discountPercent.toStringAsFixed(0)}% giảm giá',
                          style: const TextStyle(fontSize: 11, color: Colors.red)),
                    if (item.note.isNotEmpty)
                      Text('📝 ${item.note}',
                          style: const TextStyle(fontSize: 11, color: Colors.orange,
                              fontStyle: FontStyle.italic)),
                  ],
                )),
                Text(fmt.format(item.total),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            )),
            const Divider(),
            _infoRow('Tạm tính', fmt.format(order.subtotal)),
            if (order.vatPercent > 0)
              _infoRow('VAT (${order.vatPercent.toStringAsFixed(0)}%)',
                  fmt.format(order.vatAmount)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('TỔNG CỘNG:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(fmt.format(order.total),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 17)),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('In thành công'), backgroundColor: Colors.green),
            );
          },
          icon: const Icon(Icons.print, color: Colors.blue, size: 18),
          label: const Text('In hóa đơn', style: TextStyle(color: Colors.blue)),
        ),
        TextButton.icon(
          onPressed: () => _confirmDeleteOrder(ctx, order, onDeleted),
          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
          label: const Text('Xóa đơn', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: const Text('Đóng', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

// ══════════════════════════════════════════
// Popup xác nhận xóa đơn hàng
// ══════════════════════════════════════════
void _confirmDeleteOrder(BuildContext detailCtx, SavedOrder order, VoidCallback? onDeleted) {
  showDialog(
    context: detailCtx,
    builder: (confirmCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Xác nhận xóa'),
      content: Text('Bạn có chắc chắn muốn xóa đơn hàng "${order.id}" không? Hành động này không thể hoàn tác.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text('Hủy')),
        ElevatedButton(
          onPressed: () {
            globalCompletedOrders.remove(order);
            Navigator.pop(confirmCtx); // đóng popup xác nhận
            Navigator.pop(detailCtx); // đóng dialog chi tiết đơn
            onDeleted?.call(); // báo cho màn hình cha refresh lại danh sách
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('XÓA ĐƠN', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

Widget _infoRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: const TextStyle(color: Colors.grey)),
    Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
  ]),
);

// ══════════════════════════════════════════
// Tab 1 — Tất cả đơn hàng
// ══════════════════════════════════════════
class _OrderHistoryTab extends StatelessWidget {
  final List<SavedOrder> orders;
  final NumberFormat currencyFormat;
  final VoidCallback onRefresh;

  const _OrderHistoryTab({
    required this.orders,
    required this.currencyFormat,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('Chưa có đơn hàng nào', style: TextStyle(color: Colors.grey, fontSize: 16)),
          SizedBox(height: 4),
          Text('Các đơn sau khi thanh toán sẽ hiện ở đây',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ]),
      );
    }

    final total = orders.fold(0.0, (sum, o) => sum + o.total);

    return Column(children: [
      // Tổng doanh thu
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.orange[50],
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.bar_chart, color: Colors.orange),
            const SizedBox(width: 8),
            Text('${orders.length} đơn', style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          Text(currencyFormat.format(total),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
        ]),
      ),

      // Danh sách đơn
      Expanded(
        child: ListView.separated(
          itemCount: orders.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final order = orders[index];
            return _OrderTile(
              order: order,
              currencyFormat: currencyFormat,
              onTap: () => showOrderDetail(context, order, currencyFormat, onDeleted: onRefresh),
            );
          },
        ),
      ),
    ]);
  }

}

// ══════════════════════════════════════════
// Tab 2 — Phân loại theo phương thức TT
// ══════════════════════════════════════════
class _PaymentMethodTab extends StatelessWidget {
  final NumberFormat currencyFormat;
  final List<SavedOrder> Function(String) byMethod;
  final double Function(List<SavedOrder>) sumTotal;
  final VoidCallback onRefresh;

  const _PaymentMethodTab({
    required this.currencyFormat,
    required this.byMethod,
    required this.sumTotal,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        // Sub-tabs 3 loại PTTT
        Container(
          color: Colors.white,
          child: const TabBar(
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.orange,
            tabs: [
              Tab(icon: Icon(Icons.money, color: Colors.green), text: 'Tiền mặt'),
              Tab(icon: Icon(Icons.account_balance, color: Colors.blue), text: 'Chuyển khoản'),
              Tab(icon: Icon(Icons.credit_card, color: Colors.orange), text: 'Thẻ'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(children: [
            _MethodList(
              orders: byMethod('Tiền mặt'),
              currencyFormat: currencyFormat,
              sumTotal: sumTotal,
              color: Colors.green,
              icon: Icons.money,
              onRefresh: onRefresh,
            ),
            _MethodList(
              orders: byMethod('Chuyển khoản'),
              currencyFormat: currencyFormat,
              sumTotal: sumTotal,
              color: Colors.blue,
              icon: Icons.account_balance,
              onRefresh: onRefresh,
            ),
            _MethodList(
              orders: byMethod('Thẻ'),
              currencyFormat: currencyFormat,
              sumTotal: sumTotal,
              color: Colors.orange,
              icon: Icons.credit_card,
              onRefresh: onRefresh,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _MethodList extends StatelessWidget {
  final List<SavedOrder> orders;
  final NumberFormat currencyFormat;
  final double Function(List<SavedOrder>) sumTotal;
  final Color color;
  final IconData icon;
  final VoidCallback onRefresh;

  const _MethodList({
    required this.orders,
    required this.currencyFormat,
    required this.sumTotal,
    required this.color,
    required this.icon,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Text('Chưa có đơn nào', style: TextStyle(color: Colors.grey)),
        ]),
      );
    }

    return Column(children: [
      // Tổng theo loại
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: color.withOpacity(0.08),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text('${orders.length} đơn', style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          Text(currencyFormat.format(sumTotal(orders)),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        ]),
      ),

      Expanded(
        child: ListView.separated(
          itemCount: orders.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) => _OrderTile(
            order: orders[index],
            currencyFormat: currencyFormat,
            accentColor: color,
            onTap: () => showOrderDetail(context, orders[index], currencyFormat, onDeleted: onRefresh),
          ),
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════
// Widget dùng chung: 1 dòng đơn hàng
// ══════════════════════════════════════════
class _OrderTile extends StatelessWidget {
  final SavedOrder order;
  final NumberFormat currencyFormat;
  final Color accentColor;
  final VoidCallback? onTap;

  const _OrderTile({
    required this.order,
    required this.currencyFormat,
    this.accentColor = Colors.orange,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final methodIcon = {
      'Tiền mặt': Icons.money,
      'Chuyển khoản': Icons.account_balance,
      'Thẻ': Icons.credit_card,
    }[order.requestedMethod] ?? Icons.payment;

    final methodColor = {
      'Tiền mặt': Colors.green,
      'Chuyển khoản': Colors.blue,
      'Thẻ': Colors.orange,
    }[order.requestedMethod] ?? Colors.grey;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: accentColor.withOpacity(0.12),
        child: Icon(Icons.receipt_long, color: accentColor, size: 20),
      ),
      title: Row(children: [
        Text(order.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(order.tableOrCustomer,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ),
      ]),
      subtitle: Row(children: [
        Icon(Icons.access_time, size: 12, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(DateFormat('dd/MM/yyyy HH:mm').format(order.dateTime),
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(width: 8),
        Icon(methodIcon, size: 12, color: methodColor),
        const SizedBox(width: 2),
        Text(order.requestedMethod ?? '—',
            style: TextStyle(fontSize: 12, color: methodColor)),
      ]),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(currencyFormat.format(order.total),
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        Text('${order.items.length} món',
            style: TextStyle(fontSize: 11, color: Colors.grey[400])),
      ]),
    );
  }
}