import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/services/supabase_service.dart';

/// Màn hình "Kho hàng": theo dõi tồn kho nguyên liệu + sản phẩm, nhập/xuất
/// kho, xem lịch sử giao dịch và cảnh báo khi sắp hết hàng.
/// Chỉ dành cho Admin + Trưởng ca (được kiểm soát ở nơi gọi màn hình này).
class InventoryScreen extends StatefulWidget {
  final UserAccount currentUser;
  const InventoryScreen({super.key, required this.currentUser});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  List<InventoryItem> _items = [];
  List<InventoryTransaction> _transactions = [];

  final _currencyFmt = NumberFormat.decimalPattern('vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SupabaseService.getInventoryItems(),
      SupabaseService.getInventoryTransactions(),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<InventoryItem>;
      _transactions = results[1] as List<InventoryTransaction>;
      _loading = false;
    });
  }

  List<InventoryItem> get _lowStockItems =>
      _items.where((i) => i.isLowStock).toList();

  String _typeLabel(InventoryItemType type) =>
      type == InventoryItemType.material ? 'Nguyên liệu' : 'Sản phẩm';

  String _formatQty(double value) {
    if (value == value.roundToDouble()) return _currencyFmt.format(value.round());
    return _currencyFmt.format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('Kho hàng', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Thêm mặt hàng',
            onPressed: _openAddItemDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: [
            Tab(
              icon: const Icon(Icons.inventory_2_rounded),
              text: _lowStockItems.isEmpty ? 'Tồn kho' : 'Tồn kho (${_lowStockItems.length} sắp hết)',
            ),
            const Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Lịch sử'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildStockTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  // ─── TAB: TỒN KHO ─────────────────────────────────────
  Widget _buildStockTab() {
    if (_items.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'Chưa có mặt hàng nào trong kho',
        actionLabel: 'Thêm mặt hàng đầu tiên',
        onAction: _openAddItemDialog,
      );
    }

    final materials = _items.where((i) => i.type == InventoryItemType.material).toList();
    final products = _items.where((i) => i.type == InventoryItemType.product).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (materials.isNotEmpty) ...[
            _sectionTitle('NGUYÊN LIỆU'),
            ...materials.map(_buildItemCard),
            const SizedBox(height: 16),
          ],
          if (products.isNotEmpty) ...[
            _sectionTitle('SẢN PHẨM'),
            ...products.map(_buildItemCard),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade600,
        fontSize: 11.5,
        letterSpacing: 0.3,
      ),
    ),
  );

  Widget _buildItemCard(InventoryItem item) {
    final low = item.isLowStock;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: low ? Border.all(color: Colors.red.shade200, width: 1.2) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        onTap: () => _openItemDetail(item),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (low ? Colors.red : Colors.orange).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            item.type == InventoryItemType.material ? Icons.eco_rounded : Icons.fastfood_rounded,
            color: low ? Colors.red : Colors.orange,
          ),
        ),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        subtitle: Text(
          'Ngưỡng cảnh báo: ${_formatQty(item.lowStockThreshold)} ${item.unit}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${_formatQty(item.currentStock)} ${item.unit}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: low ? Colors.red.shade700 : Colors.black87,
              ),
            ),
            if (low)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('Sắp hết hàng', style: TextStyle(fontSize: 10.5, color: Colors.red, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  // ─── TAB: LỊCH SỬ ─────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_transactions.isEmpty) {
      return _buildEmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'Chưa có giao dịch nhập/xuất nào',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _transactions.length,
        itemBuilder: (context, i) => _buildTransactionTile(_transactions[i]),
      ),
    );
  }

  Widget _buildTransactionTile(InventoryTransaction tx) {
    late final IconData icon;
    late final Color color;
    late final String label;
    switch (tx.type) {
      case InventoryTransactionType.stockIn:
        icon = Icons.arrow_downward_rounded;
        color = Colors.green;
        label = 'Nhập kho';
        break;
      case InventoryTransactionType.stockOut:
        icon = Icons.arrow_upward_rounded;
        color = Colors.red;
        label = 'Xuất kho';
        break;
      case InventoryTransactionType.adjustment:
        icon = Icons.tune_rounded;
        color = Colors.blue;
        label = 'Kiểm kê';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tx.itemName ?? 'Mặt hàng #${tx.itemId}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    Text(
                      '${tx.type == InventoryTransactionType.adjustment ? '' : (tx.type == InventoryTransactionType.stockIn ? '+' : '-')}${_formatQty(tx.quantity)} ${tx.itemUnit ?? ''}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13.5),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$label • ${_dateFmt.format(tx.createdAt)}${tx.createdByName != null ? ' • ${tx.createdByName}' : ''}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                ),
                if (tx.note != null && tx.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(tx.note!, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: Colors.grey.shade500)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  // ─── CHI TIẾT 1 MẶT HÀNG + NHẬP/XUẤT/KIỂM KÊ ──────────
  void _openItemDetail(InventoryItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ItemDetailSheet(
        item: item,
        currentUser: widget.currentUser,
        onChanged: _load,
      ),
    );
  }

  // ─── THÊM MẶT HÀNG MỚI ─────────────────────────────────
  Future<void> _openAddItemDialog() async {
    final nameCtl = TextEditingController();
    final unitCtl = TextEditingController(text: 'kg');
    final stockCtl = TextEditingController(text: '0');
    final thresholdCtl = TextEditingController(text: '0');
    final noteCtl = TextEditingController();
    InventoryItemType type = InventoryItemType.material;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Thêm mặt hàng', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: 'Tên mặt hàng'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<InventoryItemType>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Loại'),
                  items: const [
                    DropdownMenuItem(value: InventoryItemType.material, child: Text('Nguyên liệu')),
                    DropdownMenuItem(value: InventoryItemType.product, child: Text('Sản phẩm')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v ?? InventoryItemType.material),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitCtl,
                  decoration: const InputDecoration(labelText: 'Đơn vị tính (kg, lít, cái...)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: stockCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Tồn kho ban đầu'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: thresholdCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Ngưỡng cảnh báo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtl,
                  decoration: const InputDecoration(labelText: 'Ghi chú (không bắt buộc)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                final name = nameCtl.text.trim();
                if (name.isEmpty) return;
                setDialogState(() => saving = true);
                final created = await SupabaseService.createInventoryItem(
                  name: name,
                  type: type,
                  unit: unitCtl.text.trim().isEmpty ? 'cái' : unitCtl.text.trim(),
                  initialStock: double.tryParse(stockCtl.text.replaceAll(',', '.')) ?? 0,
                  lowStockThreshold: double.tryParse(thresholdCtl.text.replaceAll(',', '.')) ?? 0,
                  note: noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (created == null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Không thể thêm mặt hàng, vui lòng thử lại'), backgroundColor: Colors.red),
                  );
                } else {
                  _load();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Thêm'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet chi tiết 1 mặt hàng: thông tin, nút Nhập/Xuất/Kiểm kê và
/// lịch sử gần đây của riêng mặt hàng này.
class _ItemDetailSheet extends StatefulWidget {
  final InventoryItem item;
  final UserAccount currentUser;
  final VoidCallback onChanged;

  const _ItemDetailSheet({
    required this.item,
    required this.currentUser,
    required this.onChanged,
  });

  @override
  State<_ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<_ItemDetailSheet> {
  bool _loadingHistory = true;
  List<InventoryTransaction> _history = [];
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  final _numFmt = NumberFormat.decimalPattern('vi_VN');

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final history = await SupabaseService.getInventoryTransactions(itemId: widget.item.id, limit: 20);
    if (!mounted) return;
    setState(() {
      _history = history;
      _loadingHistory = false;
    });
  }

  String _formatQty(double value) {
    if (value == value.roundToDouble()) return _numFmt.format(value.round());
    return _numFmt.format(value);
  }

  Future<void> _openAdjustDialog(InventoryTransactionType type) async {
    final qtyCtl = TextEditingController();
    final noteCtl = TextEditingController();
    bool saving = false;
    final title = type == InventoryTransactionType.stockIn
        ? 'Nhập kho'
        : type == InventoryTransactionType.stockOut
        ? 'Xuất kho'
        : 'Kiểm kê (đặt lại tồn kho)';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: type == InventoryTransactionType.adjustment
                      ? 'Tồn kho thực tế (${widget.item.unit})'
                      : 'Số lượng (${widget.item.unit})',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtl,
                decoration: const InputDecoration(labelText: 'Ghi chú (không bắt buộc)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                final qty = double.tryParse(qtyCtl.text.replaceAll(',', '.'));
                if (qty == null || qty < 0) return;
                setDialogState(() => saving = true);
                final ok = await SupabaseService.adjustInventoryStock(
                  itemId: widget.item.id,
                  type: type,
                  quantity: qty,
                  note: noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
                  userId: widget.currentUser.id,
                  userName: widget.currentUser.name,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Không thực hiện được, vui lòng thử lại'), backgroundColor: Colors.red),
                  );
                } else {
                  widget.onChanged();
                  if (mounted) Navigator.pop(context); // đóng luôn bottom sheet chi tiết
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(item.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              item.type == InventoryItemType.material ? 'Nguyên liệu' : 'Sản phẩm',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: item.isLowStock ? Colors.red.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tồn kho hiện tại', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatQty(item.currentStock)} ${item.unit}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: item.isLowStock ? Colors.red.shade700 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  if (item.isLowStock)
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openAdjustDialog(InventoryTransactionType.stockIn),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nhập'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openAdjustDialog(InventoryTransactionType.stockOut),
                    icon: const Icon(Icons.remove, size: 18),
                    label: const Text('Xuất'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openAdjustDialog(InventoryTransactionType.adjustment),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Kiểm kê'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Lịch sử gần đây', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 13)),
            const SizedBox(height: 8),
            if (_loadingHistory)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Chưa có giao dịch nào', style: TextStyle(color: Colors.grey.shade500))),
              )
            else
              ..._history.map((tx) {
                final isIn = tx.type == InventoryTransactionType.stockIn;
                final isOut = tx.type == InventoryTransactionType.stockOut;
                final color = isIn ? Colors.green : (isOut ? Colors.red : Colors.blue);
                final sign = isIn ? '+' : (isOut ? '-' : '');
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_dateFmt.format(tx.createdAt), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            if (tx.createdByName != null)
                              Text(tx.createdByName!, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            if (tx.note != null && tx.note!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(tx.note!, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '$sign${_formatQty(tx.quantity)} ${item.unit}',
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}