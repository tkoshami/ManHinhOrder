import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pos_fnb/services/supabase_service.dart';

/// Màn hình quản lý mã QR gọi món theo từng bàn. Admin (hoặc người có
/// quyền `qr.generate`) có thể tự thêm/sửa/xóa tên bàn tùy ý; mỗi bàn có
/// 1 mã QR riêng, khi khách quét sẽ tự động điền sẵn tên bàn đó vào đơn.
class QrGeneratorScreen extends StatefulWidget {
  const QrGeneratorScreen({super.key});

  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  // Đường dẫn deploy thực tế của trang tự gọi món.
  static const String _baseUrl = 'https://web-mar-pos.vercel.app/zonzon';

  bool _loading = true;
  List<Map<String, dynamic>> _tables = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tables = await SupabaseService.getQrTables();
    if (!mounted) return;
    setState(() {
      _tables = tables;
      _loading = false;
    });
  }

  String _linkFor(String tableName) =>
      '$_baseUrl?table=${Uri.encodeQueryComponent(tableName)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('TẠO MÃ QR THEO BÀN', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTableDialog,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.add),
        label: const Text('Thêm bàn'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tables.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: _load,
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.85,
          ),
          itemCount: _tables.length,
          itemBuilder: (context, i) => _buildTableCard(_tables[i]),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_2_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Chưa có bàn nào', style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
          const SizedBox(height: 8),
          Text('Bấm "Thêm bàn" để tạo mã QR đầu tiên', style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _buildTableCard(Map<String, dynamic> table) {
    final id = int.tryParse(table['id'].toString()) ?? 0;
    final name = (table['name'] ?? '').toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openQrPreview(id: id, name: name),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade500),
                    onSelected: (v) {
                      if (v == 'rename') _openRenameDialog(id: id, currentName: name);
                      if (v == 'delete') _confirmDelete(id: id, name: name);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Sửa tên'), dense: true)),
                      PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Xóa bàn', style: TextStyle(color: Colors.red)), dense: true)),
                    ],
                  ),
                ),
                Expanded(
                  child: QrImageView(
                    data: _linkFor(name),
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.all(4),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openQrPreview({required int id, required String name}) {
    final link = _linkFor(name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: link, version: QrVersions.auto, size: 260, backgroundColor: Colors.white),
            const SizedBox(height: 16),
            Text(
              'Dán mã này tại bàn "$name"',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã sao chép liên kết')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Sao chép link'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              // In mã QR (giả lập — chưa nối máy in thật).
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đang gửi lệnh in mã QR "$name"...')),
              );
            },
            icon: const Icon(Icons.print, size: 18),
            label: const Text('In mã QR'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddTableDialog() async {
    final nameCtl = TextEditingController();
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Thêm bàn mới', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: nameCtl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tên bàn (VD: Bàn 5, Sân vườn 2...)'),
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
                final ok = await SupabaseService.createQrTable(name);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (ok) {
                  _load();
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Không thêm được (tên có thể đã tồn tại)'), backgroundColor: Colors.red),
                  );
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

  Future<void> _openRenameDialog({required int id, required String currentName}) async {
    final nameCtl = TextEditingController(text: currentName);
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Sửa tên bàn', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: nameCtl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tên bàn'),
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
                final ok = await SupabaseService.updateQrTable(id: id, name: name);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (ok) {
                  _load();
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Không lưu được, vui lòng thử lại'), backgroundColor: Colors.red),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete({required int id, required String name}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xóa bàn?'),
        content: Text('Mã QR của "$name" sẽ ngừng hoạt động. Nếu còn dán ở bàn, khách quét sẽ không vào được trang gọi món.'),
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
    final ok = await SupabaseService.deleteQrTable(id);
    if (!mounted) return;
    if (ok) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xóa thất bại, vui lòng thử lại'), backgroundColor: Colors.red),
      );
    }
  }
}