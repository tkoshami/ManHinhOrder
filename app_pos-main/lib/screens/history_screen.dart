import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/data/order_data.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/services/supabase_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  bool _isLoadingHistory = false;
  DateTime? _startDate;
  DateTime? _endDate;
  final Set<String> _selectedMethods = {'cash', 'qr_code', 'card'};

  List<SavedOrder> get _filteredOrders {
    var orders = globalCompletedOrders;
    // Filter by Date
    if (_startDate != null) {
      final start =
          DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      orders = orders
          .where((o) =>
              o.dateTime.isAfter(start.subtract(const Duration(seconds: 1))))
          .toList();
    }
    if (_endDate != null) {
      final end = DateTime(
          _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      orders = orders
          .where((o) => o.dateTime.isBefore(end.add(const Duration(seconds: 1))))
          .toList();
    }
    // Filter by Method
    orders = orders.where((o) {
      return _selectedMethods.contains(o.paymentMethod);
    }).toList();

    return orders;
  }

  List<SavedOrder> get _allOrders => _filteredOrders;

  Future<void> _pickDate(bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.orangeAccent,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _startDate!.isAfter(_endDate!)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          if (_startDate != null && _endDate!.isBefore(_startDate!)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  void _clearFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedMethods.clear();
      _selectedMethods.addAll(['cash', 'qr_code', 'card']);
    });
  }

  void _toggleMethod(String method) {
    setState(() {
      if (_selectedMethods.contains(method)) {
        _selectedMethods.remove(method);
      } else {
        _selectedMethods.add(method);
      }
    });
  }

  Widget _buildFilterBar() {
    final df = DateFormat('dd/MM/yyyy');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Từ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(true),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 14, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _startDate == null ? 'Bắt đầu' : df.format(_startDate!),
                            style: TextStyle(
                              fontSize: 12,
                              color: _startDate == null
                                  ? Colors.grey
                                  : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'đến',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(false),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 14, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _endDate == null ? 'Kết thúc' : df.format(_endDate!),
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  _endDate == null ? Colors.grey : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_startDate != null || _endDate != null || _selectedMethods.length < 3)
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.red, size: 20),
                  onPressed: _clearFilter,
                  tooltip: 'Đặt lại bộ lọc',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Thanh toán:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _methodChip('Tiền mặt', 'cash', Colors.green)),
                    const SizedBox(width: 6),
                    Expanded(child: _methodChip('C.Khoản', 'qr_code', Colors.blue)),
                    const SizedBox(width: 6),
                    Expanded(child: _methodChip('Thẻ', 'card', Colors.orange)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _methodChip(String label, String method, Color color) {
    final isSelected = _selectedMethods.contains(method);
    return InkWell(
      onTap: () => _toggleMethod(method),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected)
              Icon(Icons.check, size: 12, color: color)
            else
              const SizedBox(width: 12),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? color : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadOrderHistory();
  }

  Future<void> _loadOrderHistory() async {
    setState(() {
      _isLoadingHistory = true;
    });

    final orders = await SupabaseService.getOrderHistory();
    if (!mounted) return;

    setState(() {
      globalCompletedOrders
        ..clear()
        ..addAll(orders);
      _isLoadingHistory = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Lịch sử thanh toán',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.orangeAccent,
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _isLoadingHistory ? null : _loadOrderHistory,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _isLoadingHistory && globalCompletedOrders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _OrderHistoryTab(
                    orders: _allOrders,
                    currencyFormat: currencyFormat,
                    onRefresh: () => setState(() {}),
                  ),
          ),
        ],
      ),
    );
  }
}

void showOrderDetail(
  BuildContext context,
  SavedOrder order,
  NumberFormat fmt,
) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.receipt, color: Colors.orange),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              order.id?.toString() ?? 'No ID',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow('Hình thức', order.tableOrCustomer),
              _infoRow(
                'Thời gian',
                DateFormat('dd/MM/yyyy HH:mm').format(order.dateTime),
              ),
              _infoRow(
                'Trạng thái',
                order.status == OrderStatus.completed
                    ? 'Đã thanh toán'
                    : (order.status == OrderStatus.cancelled
                          ? 'Đã hủy'
                          : 'Đang chờ'),
              ),
              _infoRow(
                'Thanh toán',
                order.status == OrderStatus.cancelled
                    ? 'Chưa thanh toán'
                    : (order.paymentMethod == 'cash'
                          ? 'Tiền mặt'
                          : (order.paymentMethod == 'qr_code'
                                ? 'Chuyển khoản'
                                : 'Thẻ')),
              ),
              const Divider(),
              ...order.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.product.name} x${item.quantity}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (item.discountPercent > 0)
                              Text(
                                '-${item.discountPercent.toStringAsFixed(0)}% giảm giá',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                ),
                              ),
                            if (item.note.isNotEmpty)
                              Text(
                                '📝 ${item.note}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        fmt.format(item.total),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              _infoRow('Tạm tính', fmt.format(order.subtotal)),
              if (order.vatPercent > 0)
                _infoRow(
                  'VAT (${order.vatPercent.toStringAsFixed(0)}%)',
                  fmt.format(order.vatAmount),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TỔNG CỘNG:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    fmt.format(order.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
              ..._paymentDetailRows(order, fmt),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              'Đóng',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

List<Widget> _paymentDetailRows(SavedOrder order, NumberFormat fmt) {
  if (order.status != OrderStatus.completed) return const [];

  if (order.paymentMethod == 'cash') {
    final receivedAmount = order.cashReceivedAmount ?? order.totalAmount;
    final changeAmount =
        order.cashChangeAmount ?? (receivedAmount - order.totalAmount);
    final returnAmount = order.cashReturnAmount ?? changeAmount;

    return [
      const Divider(height: 18),
      _infoRow('Khách đưa', fmt.format(receivedAmount)),
      _infoRow('Tiền thừa', fmt.format(changeAmount)),
      _infoRow('Thu ngân', _nonEmptyOrDash(order.cashierName)),
    ];
  }

  if (order.paymentMethod == 'qr_code') {
    final paidAt = order.paidAt ?? order.dateTime;

    return [
      const Divider(height: 18),
      _infoRow('Phương thức', _nonEmptyOrDash(order.transferMethod ?? 'VietQR')),
      _infoRow('Số tiền thanh toán', fmt.format(order.paidAmount ?? order.totalAmount)),
      _infoRow('Mã giao dịch', _nonEmptyOrDash(order.transactionCode)),
      _infoRow(
        'Thời gian thanh toán',
        DateFormat('dd/MM/yyyy HH:mm').format(paidAt),
      ),
      _infoRow('Thu ngân', _nonEmptyOrDash(order.cashierName)),
    ];
  }

  return const [];
}

String _nonEmptyOrDash(String? value) {
  if (value == null || value.trim().isEmpty) return '-';
  return value;
}

Widget _infoRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: Colors.grey)),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  ),
);

class _OrderHistoryTab extends StatefulWidget {
  final List<SavedOrder> orders;
  final NumberFormat currencyFormat;
  final VoidCallback onRefresh;

  const _OrderHistoryTab({
    required this.orders,
    required this.currencyFormat,
    required this.onRefresh,
  });

  @override
  State<_OrderHistoryTab> createState() => _OrderHistoryTabState();
}

class _OrderHistoryTabState extends State<_OrderHistoryTab> {
  OrderStatus _selectedStatus = OrderStatus.completed;

  @override
  Widget build(BuildContext context) {
    final filteredOrders = widget.orders
        .where((o) => o.status == _selectedStatus)
        .toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statusChip('Đã thanh toán', OrderStatus.completed, Colors.green),
              const SizedBox(width: 12),
              _statusChip('Đã hủy', OrderStatus.cancelled, Colors.red),
            ],
          ),
        ),
        if (filteredOrders.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selectedStatus == OrderStatus.completed
                        ? Icons.receipt_long_outlined
                        : Icons.cancel_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Không có đơn lưu trong lịch sử',
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color:
                (_selectedStatus == OrderStatus.completed
                        ? Colors.green
                        : Colors.red)
                    .withOpacity(0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.bar_chart,
                      color: _selectedStatus == OrderStatus.completed
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${filteredOrders.length} đơn',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Text(
                  widget.currencyFormat.format(
                    filteredOrders.fold(0.0, (sum, o) => sum + o.total),
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _selectedStatus == OrderStatus.completed
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: filteredOrders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final order = filteredOrders[index];
                return _OrderTile(
                  order: order,
                  currencyFormat: widget.currencyFormat,
                  accentColor: _selectedStatus == OrderStatus.completed
                      ? Colors.green
                      : Colors.red,
                  onTap: () => showOrderDetail(
                    context,
                    order,
                    widget.currencyFormat,
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _statusChip(String label, OrderStatus status, Color color) {
    final isSelected = _selectedStatus == status;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _selectedStatus = status);
      },
      selectedColor: color.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

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
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: Colors.orange,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.orange,
              tabs: [
                Tab(
                  icon: Icon(Icons.money, color: Colors.green),
                  text: 'Tiền mặt',
                ),
                Tab(
                  icon: Icon(Icons.account_balance, color: Colors.blue),
                  text: 'Chuyển khoản',
                ),
                Tab(
                  icon: Icon(Icons.credit_card, color: Colors.orange),
                  text: 'Thẻ',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _MethodList(
                  orders: byMethod('cash'),
                  currencyFormat: currencyFormat,
                  sumTotal: sumTotal,
                  color: Colors.green,
                  icon: Icons.money,
                  onRefresh: onRefresh,
                ),
                _MethodList(
                  orders: byMethod('qr_code'),
                  currencyFormat: currencyFormat,
                  sumTotal: sumTotal,
                  color: Colors.blue,
                  icon: Icons.account_balance,
                  onRefresh: onRefresh,
                ),
                _MethodList(
                  orders: byMethod('card'), // Giữ lại cho tương lai
                  currencyFormat: currencyFormat,
                  sumTotal: sumTotal,
                  color: Colors.orange,
                  icon: Icons.credit_card,
                  onRefresh: onRefresh,
                ),
              ],
            ),
          ),
        ],
      ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('Chưa có đơn nào', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: color.withValues(alpha: 0.08),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${orders.length} đơn',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Text(
                currencyFormat.format(sumTotal(orders)),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: orders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _OrderTile(
              order: orders[index],
              currencyFormat: currencyFormat,
              accentColor: color,
              onTap: () => showOrderDetail(
                context,
                orders[index],
                currencyFormat,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
    final isCompact = MediaQuery.sizeOf(context).width < 380;
    final isCancelledDraft =
        order.status == OrderStatus.cancelled &&
        order.source == OrderSource.posStaff;
    final String methodName;
    final IconData methodIcon;
    final Color methodColor;

    if (order.status == OrderStatus.cancelled) {
      methodName = 'Chưa thanh toán';
      methodIcon = Icons.money_off;
      methodColor = Colors.grey;
    } else {
      if (order.paymentMethod == 'cash') {
        methodName = 'Tiền mặt';
        methodIcon = Icons.money;
        methodColor = Colors.green;
      } else if (order.paymentMethod == 'qr_code') {
        methodName = 'Chuyển khoản';
        methodIcon = Icons.qr_code;
        methodColor = Colors.blue;
      } else {
        methodName = 'Thẻ';
        methodIcon = Icons.credit_card;
        methodColor = Colors.orange;
      }
    }

    return ListTile(
      onTap: onTap,
      dense: isCompact,
      horizontalTitleGap: isCompact ? 8 : 16,
      minLeadingWidth: isCompact ? 34 : null,
      contentPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 16,
        vertical: isCompact ? 2 : 0,
      ),
      leading: CircleAvatar(
        radius: isCompact ? 17 : 20,
        backgroundColor: accentColor.withValues(alpha: 0.12),
        child: Icon(
          Icons.receipt_long,
          color: accentColor,
          size: isCompact ? 18 : 20,
        ),
      ),
      title: Row(
        children: [
          Text(
            order.id?.toString() ?? 'No ID',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                order.tableOrCustomer,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (isCancelledDraft) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                'Tạm tính',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.access_time, size: 12, color: Colors.grey[400]),
          const SizedBox(width: 4),
          Text(
            DateFormat('dd/MM/yyyy HH:mm').format(order.dateTime),
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(width: 8),
          Icon(methodIcon, size: 12, color: methodColor),
          const SizedBox(width: 2),
          Text(methodName, style: TextStyle(fontSize: 12, color: methodColor)),
        ],
      ),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isCompact ? 86 : 112),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              currencyFormat.format(order.total),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
                fontSize: isCompact ? 12 : 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${order.items.length} loại - ${order.totalQuantity} món',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}
