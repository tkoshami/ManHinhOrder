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

enum _StockFilter { all, material, product, lowStock }

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  List<InventoryItem> _items = [];
  List<InventoryTransaction> _transactions = [];
  String _search = '';
  _StockFilter _filter = _StockFilter.all;

  final _numFmt = NumberFormat.decimalPattern('vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
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

  List<InventoryItem> get _lowStockItems => _items.where((i) => i.isLowStock).toList();
  List<InventoryItem> get _materials => _items.where((i) => i.type == InventoryItemType.material).toList();
  List<InventoryItem> get _products => _items.where((i) => i.type == InventoryItemType.product).toList();

  List<InventoryItem> get _filteredItems {
    Iterable<InventoryItem> list = _items;
    switch (_filter) {
      case _StockFilter.material:
        list = list.where((i) => i.type == InventoryItemType.material);
        break;
      case _StockFilter.product:
        list = list.where((i) => i.type == InventoryItemType.product);
        break;
      case _StockFilter.lowStock:
        list = list.where((i) => i.isLowStock);
        break;
      case _StockFilter.all:
        break;
    }
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list.where((i) => i.name.toLowerCase().contains(q));
    }
    return list.toList()
      ..sort((a, b) {
        if (a.isLowStock != b.isLowStock) return a.isLowStock ? -1 : 1;
        return a.name.compareTo(b.name);
      });
  }

  String _formatQty(double value) {
    if (value == value.roundToDouble()) return _numFmt.format(value.round());
    return _numFmt.format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        title: const Text('Kho hàng', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 1,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepOrange,
          unselectedLabelColor: Colors.grey.shade500,
          indicatorColor: Colors.deepOrange,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'TỒN KHO'),
            Tab(text: 'LỊCH SỬ GIAO DỊCH'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
        onPressed: _openAddItemDialog,
        backgroundColor: Colors.deepOrange,
        icon: const Icon(Icons.add),
        label: const Text('Thêm mặt hàng'),
      )
          : null,
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildStatsRow(),
          _buildToolbar(),
          if (_items.isEmpty)
            _buildEmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'Chưa có mặt hàng nào trong kho',
              actionLabel: 'Thêm mặt hàng đầu tiên',
              onAction: _openAddItemDialog,
            )
          else if (_filteredItems.isEmpty)
            _buildEmptyState(icon: Icons.search_off, message: 'Không tìm thấy mặt hàng phù hợp')
          else
            _buildStockTable(),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Tổng mặt hàng',
              value: '${_items.length}',
              icon: Icons.inventory_2_rounded,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'Nguyên liệu',
              value: '${_materials.length}',
              icon: Icons.eco_rounded,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'Sản phẩm',
              value: '${_products.length}',
              icon: Icons.fastfood_rounded,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'Sắp hết hàng',
              value: '${_lowStockItems.length}',
              icon: Icons.warning_amber_rounded,
              color: Colors.red,
              highlighted: _lowStockItems.isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Tìm mặt hàng theo tên...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF4F5F7),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Expanded(child: _FilterChip(label: 'Tất cả', selected: _filter == _StockFilter.all, onTap: () => setState(() => _filter = _StockFilter.all))),
                const SizedBox(width: 8),
                Expanded(child: _FilterChip(label: 'Nguyên liệu', selected: _filter == _StockFilter.material, onTap: () => setState(() => _filter = _StockFilter.material))),
                const SizedBox(width: 8),
                Expanded(child: _FilterChip(label: 'Sản phẩm', selected: _filter == _StockFilter.product, onTap: () => setState(() => _filter = _StockFilter.product))),
                const SizedBox(width: 8),
                Expanded(
                  child: _FilterChip(
                    label: 'Sắp hết',
                    selected: _filter == _StockFilter.lowStock,
                    color: Colors.red,
                    onTap: () => setState(() => _filter = _StockFilter.lowStock),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockTable() {
    final items = _filteredItems;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFFAFAFA),
            child: Row(
              children: [
                const Expanded(flex: 5, child: Text('MẶT HÀNG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.3))),
                const Expanded(flex: 3, child: Text('TỒN KHO', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.3))),
                SizedBox(width: 8),
                const SizedBox(width: 76, child: Text('TRẠNG THÁI', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.3))),
              ],
            ),
          ),
          for (int i = 0; i < items.length; i++) _buildStockRow(items[i], i.isEven),
        ],
      ),
    );
  }

  Widget _buildStockRow(InventoryItem item, bool isEven) {
    final low = item.isLowStock;
    return InkWell(
      onTap: () => _openItemDetail(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isEven ? Colors.white : const Color(0xFFFBFBFB),
          border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: (low ? Colors.red : (item.type == InventoryItemType.material ? Colors.green : Colors.orange)).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      item.type == InventoryItemType.material ? Icons.eco_rounded : Icons.fastfood_rounded,
                      size: 17,
                      color: low ? Colors.red : (item.type == InventoryItemType.material ? Colors.green.shade700 : Colors.orange.shade700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        Text(
                          item.type == InventoryItemType.material ? 'Nguyên liệu' : 'Sản phẩm',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_formatQty(item.currentStock)} ${item.unit}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: low ? Colors.red.shade700 : Colors.black87),
                  ),
                  Text('Ngưỡng: ${_formatQty(item.lowStockThreshold)}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 76, child: Center(child: _StatusBadge(isLow: low))),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: Colors.grey.shade500)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── TAB: LỊCH SỬ ─────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_transactions.isEmpty) {
      return _buildEmptyState(icon: Icons.receipt_long_outlined, message: 'Chưa có giao dịch nhập/xuất nào');
    }

    final groups = <String, List<InventoryTransaction>>{};
    for (final tx in _transactions) {
      final label = _dayLabel(tx.createdAt);
      groups.putIfAbsent(label, () => []).add(tx);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(entry.key, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600, fontSize: 12, letterSpacing: 0.3)),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(children: entry.value.map((tx) => _buildTransactionRow(tx)).toList()),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'HÔM NAY';
    if (d == today.subtract(const Duration(days: 1))) return 'HÔM QUA';
    return DateFormat('dd/MM/yyyy').format(dt).toUpperCase();
  }

  Widget _buildTransactionRow(InventoryTransaction tx) {
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
    final sign = tx.type == InventoryTransactionType.adjustment ? '' : (tx.type == InventoryTransactionType.stockIn ? '+' : '-');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tx.itemName ?? 'Mặt hàng #${tx.itemId}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    ),
                    Text('$sign${_formatQty(tx.quantity)} ${tx.itemUnit ?? ''}', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$label • ${_dateFmt.format(tx.createdAt)}${tx.createdByName != null ? ' • ${tx.createdByName}' : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                if (tx.note != null && tx.note!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(tx.note!, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool highlighted;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: highlighted ? color.withOpacity(0.08) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: highlighted ? color.withOpacity(0.3) : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: highlighted ? color : Colors.black87)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({required this.label, required this.selected, required this.onTap, this.color = Colors.deepOrange});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(color: selected ? color : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? color : Colors.grey.shade600),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isLow;
  const _StatusBadge({required this.isLow});

  @override
  Widget build(BuildContext context) {
    final baseColor = isLow ? Colors.red : Colors.green;
    final textColor = isLow ? Colors.red.shade700 : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: baseColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(
        isLow ? 'Sắp hết' : 'Còn hàng',
        style: TextStyle(color: textColor, fontSize: 10.5, fontWeight: FontWeight.bold),
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
  late InventoryItem _item;
  bool _deleting = false;
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  final _numFmt = NumberFormat.decimalPattern('vi_VN');

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final history = await SupabaseService.getInventoryTransactions(itemId: _item.id, limit: 20);
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

  Future<void> _openEditDialog() async {
    final nameCtl = TextEditingController(text: _item.name);
    final unitCtl = TextEditingController(text: _item.unit);
    final thresholdCtl = TextEditingController(
      text: _item.lowStockThreshold == _item.lowStockThreshold.roundToDouble()
          ? _item.lowStockThreshold.round().toString()
          : _item.lowStockThreshold.toString(),
    );
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Sửa mặt hàng', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Tên mặt hàng'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unitCtl,
                decoration: const InputDecoration(labelText: 'Đơn vị tính (kg, lít, cái...)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: thresholdCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Ngưỡng cảnh báo'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                final name = nameCtl.text.trim();
                final unit = unitCtl.text.trim();
                if (name.isEmpty || unit.isEmpty) return;
                final threshold = double.tryParse(thresholdCtl.text.replaceAll(',', '.')) ?? _item.lowStockThreshold;
                setDialogState(() => saving = true);
                final ok = await SupabaseService.updateInventoryItem(
                  id: _item.id,
                  name: name,
                  unit: unit,
                  lowStockThreshold: threshold,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (ok) {
                  setState(() {
                    _item = _item.copyWith(name: name, unit: unit, lowStockThreshold: threshold);
                  });
                  widget.onChanged();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Đã cập nhật mặt hàng'),
                      backgroundColor: Colors.green,
                    ));
                  }
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Không thể cập nhật, vui lòng thử lại'), backgroundColor: Colors.red),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xóa mặt hàng?'),
        content: Text('"${_item.name}" sẽ bị xóa vĩnh viễn khỏi kho, không thể khôi phục.'),
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
    if (confirmed != true) return;

    setState(() => _deleting = true);
    final ok = await SupabaseService.deleteInventoryItem(_item.id);
    if (!mounted) return;
    if (ok) {
      widget.onChanged();
      Navigator.pop(context);
    } else {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xóa thất bại, vui lòng thử lại'), backgroundColor: Colors.red),
      );
    }
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
                      ? 'Tồn kho thực tế (${_item.unit})'
                      : 'Số lượng (${_item.unit})',
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
                  itemId: _item.id,
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
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
    final item = _item;
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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        item.type == InventoryItemType.material ? 'Nguyên liệu' : 'Sản phẩm',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(isLow: item.isLowStock),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  enabled: !_deleting,
                  onSelected: (v) {
                    if (v == 'edit') _openEditDialog();
                    if (v == 'delete') _confirmDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Sửa mặt hàng'))),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Xóa mặt hàng', style: TextStyle(color: Colors.red))),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: item.isLowStock ? Colors.red.shade50 : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: item.isLowStock ? Colors.red.shade100 : Colors.grey.shade200),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Ngưỡng cảnh báo', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      Text('${_formatQty(item.lowStockThreshold)} ${item.unit}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
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
            Text('LỊCH SỬ GẦN ĐÂY', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade500, fontSize: 11.5, letterSpacing: 0.3)),
            const SizedBox(height: 8),
            if (_loadingHistory)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Chưa có giao dịch nào', style: TextStyle(color: Colors.grey.shade500))),
              )
            else
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: _history.map((tx) {
                    final isIn = tx.type == InventoryTransactionType.stockIn;
                    final isOut = tx.type == InventoryTransactionType.stockOut;
                    final color = isIn ? Colors.green : (isOut ? Colors.red : Colors.blue);
                    final sign = isIn ? '+' : (isOut ? '-' : '');
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
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
                          Text('$sign${_formatQty(tx.quantity)} ${item.unit}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13.5)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}