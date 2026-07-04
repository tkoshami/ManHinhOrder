import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/services/supabase_service.dart';

/// Màn hình báo cáo cho admin: doanh thu tiền mặt / chuyển khoản,
/// và báo cáo đầu ca / kết ca.
class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7F9),
        appBar: AppBar(
          title: const Text('Báo cáo', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.orangeAccent,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Doanh thu', icon: Icon(Icons.bar_chart)),
              Tab(text: 'Ca làm việc', icon: Icon(Icons.access_time)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _RevenueReportTab(),
            _ShiftReportTab(),
          ],
        ),
      ),
    );
  }
}

enum _RangePreset { today, week, month, custom }

class _RevenueReportTab extends StatefulWidget {
  const _RevenueReportTab();

  @override
  State<_RevenueReportTab> createState() => _RevenueReportTabState();
}

class _RevenueReportTabState extends State<_RevenueReportTab> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
  bool _loading = true;
  List<SavedOrder> _allOrders = [];
  _RangePreset _preset = _RangePreset.today;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final orders = await SupabaseService.getOrderHistory(limit: 1000);
    if (!mounted) return;
    setState(() {
      _allOrders = orders;
      _loading = false;
    });
  }

  DateTimeRange get _activeRange {
    final now = DateTime.now();
    switch (_preset) {
      case _RangePreset.today:
        final start = DateTime(now.year, now.month, now.day);
        return DateTimeRange(start: start, end: start.add(const Duration(days: 1)));
      case _RangePreset.week:
        final start = now.subtract(Duration(days: now.weekday - 1));
        final startDay = DateTime(start.year, start.month, start.day);
        return DateTimeRange(start: startDay, end: startDay.add(const Duration(days: 7)));
      case _RangePreset.month:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return DateTimeRange(start: start, end: end);
      case _RangePreset.custom:
        return _customRange ??
            DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now.add(const Duration(days: 1)));
    }
  }

  List<SavedOrder> get _ordersInRange {
    final range = _activeRange;
    return _allOrders.where((o) {
      final dt = o.dateTime;
      return !dt.isBefore(range.start) && dt.isBefore(range.end);
    }).toList();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (picked != null) {
      setState(() {
        _preset = _RangePreset.custom;
        _customRange = DateTimeRange(
          start: DateTime(picked.start.year, picked.start.month, picked.start.day),
          end: DateTime(picked.end.year, picked.end.month, picked.end.day).add(const Duration(days: 1)),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final orders = _ordersInRange;
    final cashOrders = orders.where((o) => o.paymentMethod == 'cash').toList();
    final transferOrders = orders.where((o) => o.paymentMethod == 'qr_code').toList();
    final otherOrders = orders
        .where((o) => o.paymentMethod != 'cash' && o.paymentMethod != 'qr_code')
        .toList();

    double sum(List<SavedOrder> list) => list.fold(0.0, (s, o) => s + o.totalAmount);
    final cashTotal = sum(cashOrders);
    final transferTotal = sum(transferOrders);
    final otherTotal = sum(otherOrders);
    final grandTotal = cashTotal + transferTotal + otherTotal;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              _PresetChip(label: 'Hôm nay', selected: _preset == _RangePreset.today,
                  onTap: () => setState(() => _preset = _RangePreset.today)),
              _PresetChip(label: 'Tuần này', selected: _preset == _RangePreset.week,
                  onTap: () => setState(() => _preset = _RangePreset.week)),
              _PresetChip(label: 'Tháng này', selected: _preset == _RangePreset.month,
                  onTap: () => setState(() => _preset = _RangePreset.month)),
              _PresetChip(label: 'Tùy chọn', selected: _preset == _RangePreset.custom,
                  onTap: _pickCustomRange),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TỔNG DOANH THU', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                Text(currencyFormat.format(grandTotal),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
                const SizedBox(height: 4),
                Text('${orders.length} đơn hàng', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PaymentSummaryCard(
                  icon: Icons.payments,
                  color: Colors.green,
                  label: 'Tiền mặt',
                  amount: currencyFormat.format(cashTotal),
                  count: cashOrders.length,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PaymentSummaryCard(
                  icon: Icons.qr_code,
                  color: Colors.blue,
                  label: 'Chuyển khoản',
                  amount: currencyFormat.format(transferTotal),
                  count: transferOrders.length,
                ),
              ),
            ],
          ),
          if (otherOrders.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PaymentSummaryCard(
              icon: Icons.more_horiz,
              color: Colors.grey,
              label: 'Khác',
              amount: currencyFormat.format(otherTotal),
              count: otherOrders.length,
            ),
          ],
          const SizedBox(height: 20),
          const Text('CHI TIẾT ĐƠN HÀNG', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Không có đơn hàng nào trong khoảng này')),
            )
          else
            ...(orders..sort((a, b) => b.dateTime.compareTo(a.dateTime))).map((o) => Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => _OrderDetailDialog(order: o, onChanged: _load),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(o.paymentMethod == 'cash' ? Icons.payments : Icons.qr_code,
                          color: o.paymentMethod == 'cash' ? Colors.green : Colors.blue, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('#${o.id ?? '---'} • ${o.tableOrCustomer}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                if (o.isEdited) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('Đã sửa',
                                        style: TextStyle(color: Colors.amber.shade900, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),
                            Text(DateFormat('dd/MM/yyyy HH:mm').format(o.dateTime),
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                          ],
                        ),
                      ),
                      Text(currencyFormat.format(o.totalAmount),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            )),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Colors.orange,
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
      backgroundColor: Colors.white,
    );
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String amount;
  final int count;

  const _PaymentSummaryCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.amount,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text('$count đơn', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ShiftReportTab extends StatefulWidget {
  const _ShiftReportTab();

  @override
  State<_ShiftReportTab> createState() => _ShiftReportTabState();
}

class _ShiftReportTabState extends State<_ShiftReportTab> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
  bool _loading = true;
  List<Map<String, dynamic>> _shifts = [];
  List<SavedOrder> _allOrders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SupabaseService.getShiftsHistory(),
      SupabaseService.getOrderHistory(limit: 1000),
    ]);
    if (!mounted) return;
    setState(() {
      _shifts = results[0] as List<Map<String, dynamic>>;
      _allOrders = results[1] as List<SavedOrder>;
      _loading = false;
    });
  }

  /// Đọc linh hoạt nhiều khả năng đặt tên cột khác nhau trong bảng `shifts`.
  dynamic _field(Map<String, dynamic> shift, List<String> keys) {
    for (final k in keys) {
      if (shift.containsKey(k) && shift[k] != null) return shift[k];
    }
    return null;
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_shifts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Chưa có dữ liệu ca làm việc.\nBáo cáo sẽ hiện khi nhân viên bắt đầu mở ca trong bảng "shifts".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _shifts.length,
        itemBuilder: (context, i) {
          final shift = _shifts[i];
          final id = _field(shift, ['id']);
          final staffName = _field(shift, ['staff_name', 'full_name', 'cashier_name']) ?? 'Nhân viên';
          final status = (_field(shift, ['status']) ?? '').toString();
          final openedAt = _parseDate(_field(shift, ['opened_at', 'start_time', 'created_at']));
          final closedAt = _parseDate(_field(shift, ['closed_at', 'end_time']));
          final openingCash = (_field(shift, ['opening_cash', 'start_cash']) as num?)?.toDouble();
          final closingCash = (_field(shift, ['closing_cash', 'end_cash']) as num?)?.toDouble();

          final shiftOrders = _allOrders.where((o) => o.shiftId != null && o.shiftId.toString() == id.toString()).toList();
          final cashTotal = shiftOrders.where((o) => o.paymentMethod == 'cash').fold(0.0, (s, o) => s + o.totalAmount);
          final transferTotal = shiftOrders.where((o) => o.paymentMethod == 'qr_code').fold(0.0, (s, o) => s + o.totalAmount);
          final isOpen = status == 'open';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Ca #$id — $staffName',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isOpen ? Colors.green : Colors.grey).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(isOpen ? 'Đang mở ca' : 'Đã kết ca',
                          style: TextStyle(color: isOpen ? Colors.green : Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ShiftInfoRow(
                        icon: Icons.login,
                        label: 'Đầu ca',
                        time: openedAt != null ? DateFormat('dd/MM HH:mm').format(openedAt) : '—',
                        cash: openingCash != null ? currencyFormat.format(openingCash) : null,
                      ),
                    ),
                    Expanded(
                      child: _ShiftInfoRow(
                        icon: Icons.logout,
                        label: 'Kết ca',
                        time: closedAt != null ? DateFormat('dd/MM HH:mm').format(closedAt) : (isOpen ? 'Chưa kết' : '—'),
                        cash: closingCash != null ? currencyFormat.format(closingCash) : null,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _ShiftRevenueChip(icon: Icons.payments, color: Colors.green, label: 'Tiền mặt', amount: currencyFormat.format(cashTotal)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ShiftRevenueChip(icon: Icons.qr_code, color: Colors.blue, label: 'Chuyển khoản', amount: currencyFormat.format(transferTotal)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${shiftOrders.length} đơn hàng trong ca • Tổng: ${currencyFormat.format(cashTotal + transferTotal)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShiftInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String time;
  final String? cash;

  const _ShiftInfoRow({required this.icon, required this.label, required this.time, this.cash});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (cash != null) Text('Quỹ: $cash', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      ],
    );
  }
}

class _ShiftRevenueChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String amount;

  const _ShiftRevenueChip({required this.icon, required this.color, required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: color)),
                Text(amount, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog xem chi tiết 1 đơn hàng (chỉ admin thấy, mở từ màn Báo cáo):
/// cho phép sửa số lượng/ghi chú từng món, thêm món, xóa món, hoặc xóa
/// hẳn cả đơn. Khi lưu, đơn sẽ được đánh dấu `is_edited = true`.
class _OrderDetailDialog extends StatefulWidget {
  final SavedOrder order;
  final VoidCallback onChanged;

  const _OrderDetailDialog({required this.order, required this.onChanged});

  @override
  State<_OrderDetailDialog> createState() => _OrderDetailDialogState();
}

class _OrderDetailDialogState extends State<_OrderDetailDialog> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
  late List<CartItem> _items;
  List<Product> _availableProducts = [];
  bool _loadingProducts = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = widget.order.items
        .map((i) => CartItem(product: i.product, quantity: i.quantity, discountPercent: i.discountPercent, note: i.note))
        .toList();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final products = await SupabaseService.getProducts();
    if (!mounted) return;
    setState(() {
      _availableProducts = products;
      _loadingProducts = false;
    });
  }

  double get _subtotal => _items.fold(0.0, (s, i) => s + (i.product.price * i.quantity));
  double get _vatAmount => (_subtotal - widget.order.discountAmount) * widget.order.vatRate / 100;
  double get _total => _subtotal - widget.order.discountAmount + _vatAmount;

  Future<void> _pickProductToAdd() async {
    if (_loadingProducts) return;
    final picked = await showDialog<Product>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Chọn món để thêm', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 350,
          height: 400,
          child: _availableProducts.isEmpty
              ? const Center(child: Text('Không có món nào'))
              : ListView.builder(
            itemCount: _availableProducts.length,
            itemBuilder: (_, i) {
              final p = _availableProducts[i];
              return ListTile(
                title: Text(p.name),
                subtitle: Text(currencyFormat.format(p.price)),
                onTap: () => Navigator.pop(ctx, p),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY'))],
      ),
    );
    if (picked != null) {
      setState(() => _items.add(CartItem(product: picked, quantity: 1)));
    }
  }

  Future<void> _confirmDeleteOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xóa đơn hàng?'),
        content: Text('Đơn #${widget.order.id} sẽ bị xóa vĩnh viễn, không thể khôi phục.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('XÓA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || widget.order.id == null) return;
    setState(() => _saving = true);
    final ok = await SupabaseService.deleteOrder(widget.order.id!);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      widget.onChanged();
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xóa đơn thất bại'), backgroundColor: Colors.red));
    }
  }

  Future<void> _save() async {
    if (widget.order.id == null) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đơn phải có ít nhất 1 món'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    final ok = await SupabaseService.updateOrderItems(
      orderId: widget.order.id!,
      items: _items,
      vatRate: widget.order.vatRate,
      discountAmount: widget.order.discountAmount,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      widget.onChanged();
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lưu đơn thất bại'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Expanded(child: Text('Đơn #${o.id ?? '---'}', style: const TextStyle(fontWeight: FontWeight.bold))),
          if (o.isEdited)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
              child: Text('Đã sửa', style: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(DateFormat('dd/MM/yyyy HH:mm').format(o.dateTime), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              Text('${o.tableOrCustomer} • ${o.paymentMethod == 'cash' ? 'Tiền mặt' : 'Chuyển khoản'}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const Divider(height: 24),
              ..._items.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(currencyFormat.format(item.product.price), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: item.quantity > 1
                            ? () => setState(() => item.quantity -= 1)
                            : null,
                      ),
                      Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: () => setState(() => item.quantity += 1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        onPressed: () => setState(() => _items.removeAt(idx)),
                      ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: _pickProductToAdd,
                icon: const Icon(Icons.add, color: Colors.green),
                label: const Text('Thêm món', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Tạm tính'), Text(currencyFormat.format(_subtotal)),
              ]),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('VAT (${o.vatRate.toStringAsFixed(0)}%)'), Text(currencyFormat.format(_vatAmount)),
              ]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('TỔNG CỘNG', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(currencyFormat.format(_total), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16)),
              ]),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _saving ? null : _confirmDeleteOrder,
          child: const Text('XÓA ĐƠN', style: TextStyle(color: Colors.red)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('HỦY')),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('LƯU', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ],
    );
  }
}