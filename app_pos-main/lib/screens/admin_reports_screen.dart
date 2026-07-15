import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/services/supabase_service.dart';
import 'package:pos_fnb/widgets/product_image.dart';

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

  /// Ngày (định dạng dd/MM/yyyy) đang được thu gọn (ẩn danh sách ca).
  /// Mặc định chỉ ngày gần nhất được mở sẵn, các ngày cũ hơn thu gọn lại
  /// để danh sách gọn hơn khi có nhiều ca lịch sử.
  final Set<String> _collapsedDates = {};
  bool _initializedCollapse = false;

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
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  _ShiftMeta _buildMeta(Map<String, dynamic> shift) {
    final id = _field(shift, ['id']);
    final staffName = _field(shift, ['staff_name', 'full_name', 'cashier_name']) ?? 'Nhân viên';
    final status = (_field(shift, ['status']) ?? '').toString();
    final openedAt = _parseDate(_field(shift, ['start_at', 'opened_at', 'start_time', 'created_at']));
    final closedAt = _parseDate(_field(shift, ['end_at', 'closed_at', 'end_time']));
    final openingCash = (_field(shift, ['opening_cash', 'start_cash']) as num?)?.toDouble();
    final closingCash = (_field(shift, ['closing_cash', 'end_cash']) as num?)?.toDouble();

    final shiftOrders = _allOrders.where((o) => o.shiftId != null && o.shiftId.toString() == id.toString()).toList();
    final cashTotal = shiftOrders.where((o) => o.paymentMethod == 'cash').fold(0.0, (s, o) => s + o.totalAmount);
    final transferTotal = shiftOrders.where((o) => o.paymentMethod == 'qr_code').fold(0.0, (s, o) => s + o.totalAmount);

    return _ShiftMeta(
      id: id,
      staffName: staffName.toString(),
      isOpen: status == 'open',
      openedAt: openedAt,
      closedAt: closedAt,
      openingCash: openingCash,
      closingCash: closingCash,
      orderCount: shiftOrders.length,
      cashTotal: cashTotal,
      transferTotal: transferTotal,
    );
  }

  /// Gộp danh sách ca theo ngày (dựa trên thời điểm mở ca), giữ nguyên thứ tự
  /// ca mới nhất lên trước như dữ liệu gốc trả về.
  List<_ShiftDayGroup> _groupByDay(List<_ShiftMeta> metas) {
    final groups = <String, _ShiftDayGroup>{};
    final order = <String>[];
    for (final meta in metas) {
      final day = meta.openedAt ?? meta.closedAt;
      final key = day != null ? DateFormat('dd/MM/yyyy').format(day) : 'Không rõ ngày';
      if (!groups.containsKey(key)) {
        groups[key] = _ShiftDayGroup(dateLabel: key, date: day, shifts: []);
        order.add(key);
      }
      groups[key]!.shifts.add(meta);
    }
    return order.map((k) => groups[k]!).toList();
  }

  String _relativeDayLabel(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final d = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    return '';
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

    final metas = _shifts.map(_buildMeta).toList();
    final groups = _groupByDay(metas);

    // Mặc định luôn mở sẵn nhóm của HÔM NAY (nếu có), các ngày khác thu gọn.
    // Nếu hôm nay chưa có ca nào thì không tự mở ngày nào khác thay thế.
    // Chỉ tính một lần khi có dữ liệu, để không ghi đè lựa chọn người dùng
    // đã tự bấm sau đó.
    final todayLabel = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final hasToday = groups.any((g) => g.dateLabel == todayLabel);
    if (!_initializedCollapse) {
      _initializedCollapse = true;
      for (final g in groups) {
        if (g.dateLabel != todayLabel) _collapsedDates.add(g.dateLabel);
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: groups.length + (hasToday ? 0 : 1),
        itemBuilder: (context, i) {
          if (!hasToday && i == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_busy_rounded, color: Colors.grey.shade400, size: 18),
                  const SizedBox(width: 10),
                  Text('Hôm nay chưa có ca nào', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ],
              ),
            );
          }
          final group = groups[hasToday ? i : i - 1];
          final isCollapsed = _collapsedDates.contains(group.dateLabel);
          final relative = _relativeDayLabel(group.date);

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShiftDayHeader(
                  dateLabel: group.dateLabel,
                  relativeLabel: relative,
                  shiftCount: group.shifts.length,
                  totalRevenue: group.totalRevenue,
                  currencyFormat: currencyFormat,
                  collapsed: isCollapsed,
                  onTap: () {
                    setState(() {
                      if (isCollapsed) {
                        _collapsedDates.remove(group.dateLabel);
                      } else {
                        _collapsedDates.add(group.dateLabel);
                      }
                    });
                  },
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: isCollapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Column(
                    children: [
                      const SizedBox(height: 10),
                      ...group.shifts.map((meta) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ShiftCard(meta: meta, currencyFormat: currencyFormat),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Dữ liệu đã được tính toán sẵn cho một ca làm việc, dùng chung giữa bước
/// gộp nhóm theo ngày và bước hiển thị card chi tiết.
class _ShiftMeta {
  final dynamic id;
  final String staffName;
  final bool isOpen;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double? openingCash;
  final double? closingCash;
  final int orderCount;
  final double cashTotal;
  final double transferTotal;

  _ShiftMeta({
    required this.id,
    required this.staffName,
    required this.isOpen,
    required this.openedAt,
    required this.closedAt,
    required this.openingCash,
    required this.closingCash,
    required this.orderCount,
    required this.cashTotal,
    required this.transferTotal,
  });

  double get totalRevenue => cashTotal + transferTotal;
}

class _ShiftDayGroup {
  final String dateLabel;
  final DateTime? date;
  final List<_ShiftMeta> shifts;

  _ShiftDayGroup({required this.dateLabel, required this.date, required this.shifts});

  double get totalRevenue => shifts.fold(0.0, (s, m) => s + m.totalRevenue);
}

/// Header gộp theo ngày: hiển thị ngày, số ca, tổng doanh thu trong ngày,
/// và cho phép bấm để thu gọn / mở rộng danh sách ca của ngày đó.
class _ShiftDayHeader extends StatelessWidget {
  final String dateLabel;
  final String relativeLabel;
  final int shiftCount;
  final double totalRevenue;
  final NumberFormat currencyFormat;
  final bool collapsed;
  final VoidCallback onTap;

  const _ShiftDayHeader({
    required this.dateLabel,
    required this.relativeLabel,
    required this.shiftCount,
    required this.totalRevenue,
    required this.currencyFormat,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), shape: BoxShape.circle),
                child: const Icon(Icons.calendar_today_rounded, color: Colors.orange, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(dateLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                        if (relativeLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20)),
                            child: Text(relativeLabel,
                                style: TextStyle(color: Colors.orange.shade700, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        children: [
                          TextSpan(text: '$shiftCount ca  •  '),
                          TextSpan(
                            text: 'Doanh thu ${currencyFormat.format(totalRevenue)}',
                            style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                child: Icon(
                  collapsed ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                  color: Colors.grey.shade600,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card chi tiết một ca làm việc (tách ra từ danh sách để dùng lại bên trong
/// từng nhóm ngày).
class _ShiftCard extends StatelessWidget {
  final _ShiftMeta meta;
  final NumberFormat currencyFormat;

  const _ShiftCard({required this.meta, required this.currencyFormat});

  String get _initial {
    final trimmed = meta.staffName.trim();
    return trimmed.isNotEmpty ? trimmed.substring(0, 1).toUpperCase() : '?';
  }

  String? get _durationLabel {
    final start = meta.openedAt;
    if (start == null) return null;
    final end = meta.closedAt ?? (meta.isOpen ? DateTime.now() : null);
    if (end == null) return null;
    final d = end.difference(start);
    if (d.isNegative) return null;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '$h giờ $m phút' : '$m phút';
  }

  @override
  Widget build(BuildContext context) {
    final expectedCash =
    meta.openingCash != null ? meta.openingCash! + meta.cashTotal : null;
    final diff = (!meta.isOpen && expectedCash != null && meta.closingCash != null)
        ? meta.closingCash! - expectedCash
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: meta.isOpen
              ? Colors.green.shade200
              : (diff != null && diff != 0 ? Colors.red.shade100 : Colors.transparent),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: Colors.orange.shade50,
                child: Text(_initial, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(meta.staffName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('Ca #${meta.id}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
                        if (_durationLabel != null) ...[
                          Text('  •  ', style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5)),
                          Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 3),
                          Text(_durationLabel!, style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (meta.isOpen ? Colors.green : Colors.grey).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(meta.isOpen ? Icons.play_circle_fill_rounded : Icons.check_circle_rounded,
                        size: 12, color: meta.isOpen ? Colors.green.shade600 : Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(meta.isOpen ? 'Đang mở ca' : 'Đã kết ca',
                        style: TextStyle(
                            color: meta.isOpen ? Colors.green.shade700 : Colors.grey.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ShiftInfoRow(
                    icon: Icons.login_rounded,
                    iconColor: Colors.green.shade600,
                    label: 'Đầu ca',
                    time: meta.openedAt != null ? DateFormat('dd/MM HH:mm').format(meta.openedAt!) : '—',
                    cash: meta.openingCash != null ? currencyFormat.format(meta.openingCash) : null,
                  ),
                ),
                Container(width: 1, color: Colors.grey.shade100, margin: const EdgeInsets.symmetric(horizontal: 4)),
                Expanded(
                  child: _ShiftInfoRow(
                    icon: Icons.logout_rounded,
                    iconColor: meta.isOpen ? Colors.grey.shade400 : Colors.red.shade400,
                    label: 'Kết ca',
                    time: meta.closedAt != null
                        ? DateFormat('dd/MM HH:mm').format(meta.closedAt!)
                        : (meta.isOpen ? 'Chưa kết' : '—'),
                    cash: meta.closingCash != null ? currencyFormat.format(meta.closingCash) : null,
                  ),
                ),
              ],
            ),
          ),
          if (diff != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: (diff == 0 ? Colors.green : (diff > 0 ? Colors.blue : Colors.red)).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    diff == 0
                        ? Icons.check_circle_rounded
                        : (diff > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                    size: 15,
                    color: diff == 0 ? Colors.green.shade700 : (diff > 0 ? Colors.blue.shade700 : Colors.red.shade700),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    diff == 0 ? 'Khớp quỹ' : (diff > 0 ? 'Dư quỹ' : 'Thiếu quỹ'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: diff == 0 ? Colors.green.shade700 : (diff > 0 ? Colors.blue.shade700 : Colors.red.shade700),
                    ),
                  ),
                  if (diff != 0) ...[
                    const Spacer(),
                    Text(
                      currencyFormat.format(diff.abs()),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: diff > 0 ? Colors.blue.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ShiftRevenueChip(icon: Icons.payments_rounded, color: Colors.green, label: 'Tiền mặt', amount: currencyFormat.format(meta.cashTotal)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ShiftRevenueChip(icon: Icons.qr_code_rounded, color: Colors.blue, label: 'Chuyển khoản', amount: currencyFormat.format(meta.transferTotal)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Icon(Icons.receipt_long_rounded, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text('${meta.orderCount} đơn hàng', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const Spacer(),
                Text('Tổng: ${currencyFormat.format(meta.totalRevenue)}',
                    style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String time;
  final String? cash;

  const _ShiftInfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.time,
    this.cash,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 1),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 12, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 1),
              Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              if (cash != null) ...[
                const SizedBox(height: 1),
                Text('Quỹ: $cash', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: color)),
                Text(amount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: color)),
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
    String query = '';

    final picked = await showDialog<Product>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = query.trim().isEmpty
              ? _availableProducts
              : _availableProducts
              .where((p) => p.name.toLowerCase().contains(query.trim().toLowerCase()))
              .toList();
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380, maxHeight: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 8, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Chọn món để thêm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) => setSheetState(() => query = v),
                      decoration: InputDecoration(
                        hintText: 'Tìm món...',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: filtered.isEmpty
                        ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: Text('Không tìm thấy món nào', style: TextStyle(color: Colors.grey)),
                    )
                        : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: ProductImage(imageUrl: p.imageUrl, fit: BoxFit.cover),
                            ),
                          ),
                          title: Text(p.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          subtitle: Text(currencyFormat.format(p.price), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          onTap: () => Navigator.pop(ctx, p),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (picked == null) return;
    setState(() {
      final index = _items.indexWhere((item) => item.product.id == picked.id);
      if (index >= 0) {
        _items[index].quantity++;
      } else {
        _items.add(CartItem(product: picked, quantity: 1));
      }
    });
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

  Widget _buildHeader(SavedOrder o) {
    final isCash = o.paymentMethod == 'cash';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 8, 16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(isCash ? Icons.payments_rounded : Icons.qr_code_rounded,
                color: isCash ? Colors.green : Colors.blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text('Đơn #${o.id ?? '---'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    if (o.isEdited)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.amber.shade200, borderRadius: BorderRadius.circular(20)),
                        child: Text('Đã sửa',
                            style: TextStyle(color: Colors.amber.shade900, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('dd/MM/yyyy HH:mm').format(o.dateTime)} • ${o.tableOrCustomer} • ${isCash ? 'Tiền mặt' : 'Chuyển khoản'}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _saving ? null : _confirmDeleteOrder,
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
            tooltip: 'Xóa đơn hàng',
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityStepper(CartItem item) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: item.quantity > 1 ? () => setState(() => item.quantity -= 1) : null,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.remove, size: 16, color: item.quantity > 1 ? Colors.black87 : Colors.grey.shade300),
            ),
          ),
          SizedBox(
            width: 22,
            child: Text('${item.quantity}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => item.quantity += 1),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.add, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final item = _items[index];
    final lineTotal = item.product.price * item.quantity;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 42,
              height: 42,
              child: ProductImage(imageUrl: item.product.imageUrl, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text('${currencyFormat.format(item.product.price)} × ${item.quantity} = ${currencyFormat.format(lineTotal)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
                if (item.discountPercent > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Giảm ${item.discountPercent.toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                if (item.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Ghi chú: ${item.note}',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontStyle: FontStyle.italic)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _buildQuantityStepper(item),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 19, color: Colors.red.shade300),
            onPressed: () => setState(() => _items.removeAt(index)),
            tooltip: 'Xóa món',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: bold ? Colors.black87 : Colors.grey.shade700,
              )),
          Text(value,
              style: TextStyle(
                fontSize: bold ? 17 : 13.5,
                fontWeight: FontWeight.bold,
                color: bold ? Colors.deepOrange : Colors.black87,
              )),
        ],
      ),
    );
  }

  Widget _buildTotals(SavedOrder o) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          _totalRow('Tạm tính', currencyFormat.format(_subtotal)),
          if (o.discountAmount > 0) _totalRow('Giảm giá', '-${currencyFormat.format(o.discountAmount)}'),
          _totalRow('VAT (${o.vatRate.toStringAsFixed(0)}%)', currencyFormat.format(_vatAmount)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Colors.orange.shade100),
          ),
          _totalRow('TỔNG CỘNG', currencyFormat.format(_total), bold: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(o),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('DANH SÁCH MÓN',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 11.5, letterSpacing: 0.3)),
                        Text('${_items.length} món', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(_items.length, (i) => _buildItemRow(i)),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _loadingProducts ? null : _pickProductToAdd,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green.shade200, width: 1.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _loadingProducts
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.add_circle_outline, color: Colors.green, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _loadingProducts ? 'Đang tải món...' : 'Thêm món',
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTotals(o),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('HỦY', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _saving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                            : const Icon(Icons.check, color: Colors.white, size: 18),
                        label: const Text('LƯU THAY ĐỔI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}