import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/data/order_data.dart';
import 'package:pos_fnb/models/app_models.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _TimeSlot {
  final String label;
  final int startHour; // inclusive
  final int endHour;   // exclusive
  final Color color;
  const _TimeSlot(this.label, this.startHour, this.endHour, this.color);
}

class _StatsScreenState extends State<StatsScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  DateTime _selectedDate = DateTime.now();
  int? _expandedSlotIndex;

  static const List<_TimeSlot> _timeSlots = [
    _TimeSlot('Sáng', 6, 11, Colors.amber),
    _TimeSlot('Trưa', 11, 14, Colors.orange),
    _TimeSlot('Chiều', 14, 18, Colors.deepOrange),
    _TimeSlot('Tối', 18, 24, Colors.indigo),
  ];

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  List<SavedOrder> get _ordersForSelectedDate {
    return globalCompletedOrders.where((o) =>
    o.dateTime.year == _selectedDate.year &&
        o.dateTime.month == _selectedDate.month &&
        o.dateTime.day == _selectedDate.day).toList();
  }

  int get _orderCount => _ordersForSelectedDate.length;

  double get _totalRevenue =>
      _ordersForSelectedDate.fold(0.0, (sum, o) => sum + o.total);

  List<double> get _revenueBySlot {
    final result = List<double>.filled(_timeSlots.length, 0.0);
    for (final order in _ordersForSelectedDate) {
      final hour = order.dateTime.hour;
      for (int i = 0; i < _timeSlots.length; i++) {
        final slot = _timeSlots[i];
        if (hour >= slot.startHour && hour < slot.endHour) {
          result[i] += order.total;
          break;
        }
      }
    }
    return result;
  }

  Map<int, double> _revenueByHourInSlot(_TimeSlot slot) {
    final Map<int, double> result = {};
    for (int h = slot.startHour; h < slot.endHour; h++) {
      result[h] = 0.0;
    }
    for (final order in _ordersForSelectedDate) {
      final hour = order.dateTime.hour;
      if (hour >= slot.startHour && hour < slot.endHour) {
        result[hour] = (result[hour] ?? 0.0) + order.total;
      }
    }
    return result;
  }

  List<Map<String, dynamic>> get _allProductsForSelectedDate {
    final Map<String, Map<String, dynamic>> tally = {};
    for (final order in _ordersForSelectedDate) {
      for (final item in order.items) {
        final name = item.product.name;
        tally.putIfAbsent(name, () => {
          'name': name,
          'sales': 0,
          'revenue': 0.0,
          'image': item.product.imageUrl,
        });
        tally[name]!['sales'] = (tally[name]!['sales'] as int) + item.quantity;
        tally[name]!['revenue'] = (tally[name]!['revenue'] as double) + item.total;
      }
    }
    final list = tally.values.toList()
      ..sort((a, b) => (b['sales'] as int).compareTo(a['sales'] as int));
    return list;
  }

  List<Map<String, dynamic>> get _topProductsForSelectedDate =>
      _allProductsForSelectedDate.take(3).toList();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _expandedSlotIndex = null;
      });
    }
  }

  void _showAllProductsDialog() {
    final products = _allProductsForSelectedDate;
    final dateLabel = _isToday ? 'hôm nay' : DateFormat('dd/MM/yyyy').format(_selectedDate);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.restaurant_menu, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text('Các món đã bán $dateLabel',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ]),
        content: SizedBox(
          width: 380,
          child: products.isEmpty
              ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Chưa có món nào được bán $dateLabel',
                style: const TextStyle(color: Colors.grey)),
          )
              : SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${products.length} món', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  Text('Tổng: ${currencyFormat.format(_totalRevenue)}',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                ]),
                const Divider(),
                ...products.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(p['image'], width: 44, height: 44, fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => const Icon(Icons.image)),
                  ),
                  title: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('Đã bán: ${p['sales']}', style: const TextStyle(fontSize: 12)),
                  trailing: Text(currencyFormat.format(p['revenue']),
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                )),
              ],
            ),
          ),
        ),
        actions: [
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

  @override
  Widget build(BuildContext context) {
    final dateLabel = _isToday
        ? 'Hôm nay, ${DateFormat('dd/MM/yyyy').format(_selectedDate)}'
        : DateFormat('dd/MM/yyyy').format(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Thống kê doanh thu', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateSelector(dateLabel),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _buildSummaryCard('Số đơn', '$_orderCount', Icons.shopping_bag, Colors.blue)),
                const SizedBox(width: 24),
                Expanded(child: _buildSummaryCard('Doanh thu', currencyFormat.format(_totalRevenue), Icons.monetization_on, Colors.green,
                    onTap: _showAllProductsDialog)),
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DOANH THU THEO KHUNG GIỜ',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 4),
                  const Text('Bấm vào cột để xem chi tiết từng giờ',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 32),
                  _buildSlotBarChart(),
                  if (_expandedSlotIndex != null) ...[
                    const Divider(height: 32),
                    _buildHourBreakdown(_timeSlots[_expandedSlotIndex!]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildTopProductsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector(String dateLabel) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 18, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(dateLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
        if (!_isToday) ...[
          const SizedBox(width: 10),
          InkWell(
            onTap: () => setState(() {
              _selectedDate = DateTime.now();
              _expandedSlotIndex = null;
            }),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.today, color: Colors.orange),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    final card = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.info_outline, size: 13, color: Colors.grey[400]),
                  ],
                ]),
                Text(value,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          )
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: card,
    );
  }

  Widget _buildSlotBarChart() {
    final revenues = _revenueBySlot;
    final maxValue = revenues.fold(0.0, (m, v) => v > m ? v : m);
    const double maxBarHeight = 160;

    return SizedBox(
      height: 220,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_timeSlots.length, (index) {
          final slot = _timeSlots[index];
          final value = revenues[index];
          final isExpanded = _expandedSlotIndex == index;

          double barHeight = maxValue > 0 ? (value / maxValue) * maxBarHeight : 0;
          if (value > 0 && barHeight < 16) barHeight = 16; 

          return GestureDetector(
            onTap: () => setState(() {
              _expandedSlotIndex = isExpanded ? null : index;
            }),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  value > 0 ? currencyFormat.format(value) : '—',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 56,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: slot.color,
                    borderRadius: BorderRadius.circular(8),
                    border: isExpanded ? Border.all(color: Colors.black54, width: 2) : null,
                    boxShadow: [BoxShadow(color: slot.color.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                ),
                const SizedBox(height: 12),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(slot.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 14, color: Colors.grey),
                ]),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHourBreakdown(_TimeSlot slot) {
    final byHour = _revenueByHourInSlot(slot);
    final maxValue = byHour.values.fold(0.0, (m, v) => v > m ? v : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: slot.color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('Chi tiết khung "${slot.label}" theo từng giờ',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        const SizedBox(height: 16),
        ...byHour.entries.map((entry) {
          final hour = entry.key;
          final value = entry.value;
          final ratio = maxValue > 0 ? value / maxValue : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 48, child: Text('${hour.toString().padLeft(2, '0')}:00', style: const TextStyle(fontSize: 12, color: Colors.grey))),
              Expanded(
                child: Stack(children: [
                  Container(
                    height: 18,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)),
                  ),
                  FractionallySizedBox(
                    widthFactor: ratio.clamp(0.0, 1.0),
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(color: slot.color, borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: Text(
                  value > 0 ? currencyFormat.format(value) : '—',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          );
        }),
      ],
    );
  }

  Widget _buildTopProductsList() {
    final topProducts = _topProductsForSelectedDate;
    final titleSuffix = _isToday ? 'hôm nay' : 'ngày ${DateFormat('dd/MM/yyyy').format(_selectedDate)}';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top 3 món bán chạy $titleSuffix', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          if (topProducts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Chưa có đơn nào $titleSuffix', style: const TextStyle(color: Colors.grey)),
            )
          else
            ...topProducts.map((p) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(p['image'], width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.image)),
              ),
              title: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Đã bán: ${p['sales']}'),
              trailing: Text(currencyFormat.format(p['revenue']), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            )),
        ],
      ),
    );
  }
}
