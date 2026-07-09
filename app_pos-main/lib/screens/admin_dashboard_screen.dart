import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/screens/admin_products_screen.dart';
import 'package:pos_fnb/screens/admin_reports_screen.dart';
import 'package:pos_fnb/screens/admin_users_screen.dart';
import 'package:pos_fnb/screens/permission_management_screen.dart';
import 'package:pos_fnb/services/supabase_service.dart';

/// Trang trung tâm quản trị (chỉ dành cho role = admin).
/// Gom 3 nhóm chức năng chính: tài khoản, món ăn, báo cáo — và hiển thị
/// danh sách các ca làm việc đang hoạt động (ai đang trực) để admin theo
/// dõi nhanh, kèm khả năng đóng ca hộ nếu nhân viên quên kết ca.
class AdminDashboardScreen extends StatefulWidget {
  final UserAccount user;

  const AdminDashboardScreen({super.key, required this.user});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

  bool _loadingShifts = true;
  List<Map<String, dynamic>> _activeShifts = [];

  @override
  void initState() {
    super.initState();
    _loadActiveShifts();
  }

  Future<void> _loadActiveShifts() async {
    setState(() => _loadingShifts = true);
    try {
      final shifts = await SupabaseService.getAllOpenShifts();
      final withSummary = await Future.wait(shifts.map((shift) async {
        final id = int.tryParse(shift['id'].toString());
        final summary = id != null
            ? await SupabaseService.getShiftOrdersSummary(id)
            : {'cash': 0.0, 'transfer': 0.0, 'other': 0.0, 'count': 0};
        return {...shift, 'summary': summary};
      }));
      if (!mounted) return;
      setState(() {
        _activeShifts = withSummary;
        _loadingShifts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingShifts = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không tải được danh sách ca đang hoạt động'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _forceCloseShift(Map<String, dynamic> shift) async {
    final shiftId = int.tryParse(shift['id'].toString());
    if (shiftId == null) return;

    final staffName = (shift['staff_name'] as String?)?.trim().isNotEmpty == true
        ? shift['staff_name'] as String
        : 'nhân viên này';
    final summary = shift['summary'] as Map<String, dynamic>? ?? {};
    final startCash = (shift['start_cash'] as num?)?.toDouble() ?? 0;
    final cashRevenue = (summary['cash'] as num?)?.toDouble() ?? 0;
    final expectedCash = startCash + cashRevenue;
    final notesCtl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade400, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Đóng ca hộ $staffName?', style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ca sẽ được đóng theo quỹ tiền mặt dự kiến của hệ thống, vì không có ai đếm quỹ thực tế tại quầy.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              _InfoRow(label: 'Quỹ đầu ca', value: currencyFormat.format(startCash)),
              _InfoRow(label: 'Doanh thu tiền mặt', value: currencyFormat.format(cashRevenue)),
              const Divider(height: 20),
              _InfoRow(
                label: 'Tiền mặt dự kiến khi đóng',
                value: currencyFormat.format(expectedCash),
                bold: true,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: notesCtl,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Lý do đóng ca hộ (không bắt buộc)',
                  hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('HỦY', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('ĐÓNG CA HỘ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await SupabaseService.forceCloseShift(shiftId: shiftId, notes: notesCtl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Đã đóng ca hộ $staffName' : 'Đóng ca thất bại, vui lòng thử lại'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) _loadActiveShifts();
  }

  bool _canAny(List<String> keys) {
    if (widget.user.role == UserRole.admin) return true;
    return keys.any((k) => widget.user.can(k));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('Quản trị hệ thống', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadActiveShifts,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Xin chào, ${widget.user.name}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Chọn một mục để quản lý cửa hàng của bạn',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 20),
              _buildActiveShiftsSection(),
              const SizedBox(height: 20),
              if (_canAny(['users.manage'])) ...[
                _AdminMenuCard(
                  icon: Icons.people_alt,
                  color: Colors.purple,
                  title: 'Quản lý tài khoản',
                  subtitle: 'Thêm, sửa, xóa tài khoản nhân viên và thu ngân',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AdminUsersScreen(currentUser: widget.user)),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_canAny(['products.manage'])) ...[
                _AdminMenuCard(
                  icon: Icons.restaurant_menu,
                  color: Colors.green,
                  title: 'Quản lý món ăn',
                  subtitle: 'Thêm, sửa, xóa món và cập nhật giá, hình ảnh',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AdminProductsScreen()),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_canAny(['reports.view'])) ...[
                _AdminMenuCard(
                  icon: Icons.bar_chart,
                  color: Colors.orange,
                  title: 'Báo cáo',
                  subtitle: 'Doanh thu tiền mặt / chuyển khoản và báo cáo ca làm việc',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AdminReportsScreen()),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_canAny(['permissions.manage']))
                _AdminMenuCard(
                  icon: Icons.admin_panel_settings,
                  color: Colors.indigo,
                  title: 'Phân quyền',
                  subtitle: 'Bật/tắt chức năng theo vai trò hoặc riêng từng tài khoản',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PermissionManagementScreen()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveShiftsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('CA ĐANG HOẠT ĐỘNG',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12, letterSpacing: 0.3)),
            const Spacer(),
            if (!_loadingShifts && _activeShifts.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
                child: Text('${_activeShifts.length} ca',
                    style: TextStyle(color: Colors.green.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loadingShifts)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_activeShifts.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Row(
              children: [
                Icon(Icons.nightlight_round, color: Colors.grey.shade400, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Hiện không có ca nào đang hoạt động',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              ],
            ),
          )
        else
          ..._activeShifts.map((shift) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ActiveShiftCard(
              shift: shift,
              currencyFormat: currencyFormat,
              canForceClose: _canAny(['shifts.force_close']),
              onForceClose: () => _forceCloseShift(shift),
            ),
          )),
      ],
    );
  }
}

class _ActiveShiftCard extends StatelessWidget {
  final Map<String, dynamic> shift;
  final NumberFormat currencyFormat;
  final VoidCallback onForceClose;
  final bool canForceClose;

  const _ActiveShiftCard({
    required this.shift,
    required this.currencyFormat,
    required this.onForceClose,
    this.canForceClose = true,
  });

  @override
  Widget build(BuildContext context) {
    final staffName = (shift['staff_name'] as String?)?.trim().isNotEmpty == true
        ? shift['staff_name'] as String
        : 'Nhân viên #${shift['staff_id']}';
    final startAt = DateTime.tryParse(shift['start_at']?.toString() ?? '')?.toLocal();
    final startCash = (shift['start_cash'] as num?)?.toDouble() ?? 0;
    final summary = shift['summary'] as Map<String, dynamic>? ?? {};
    final cash = (summary['cash'] as num?)?.toDouble() ?? 0;
    final count = summary['count'] ?? 0;

    final duration = startAt != null ? DateTime.now().difference(startAt) : null;
    final isLongShift = duration != null && duration.inHours >= 12;
    final durationText = duration != null
        ? (duration.inHours > 0 ? '${duration.inHours} giờ ${duration.inMinutes % 60} phút' : '${duration.inMinutes} phút')
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isLongShift ? Border.all(color: Colors.orange.shade200, width: 1.2) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Icons.person, color: Colors.green.shade700, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(staffName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (startAt != null)
                      Text('Mở ca lúc ${DateFormat('HH:mm dd/MM').format(startAt)}',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
                  ],
                ),
              ),
              if (durationText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLongShift ? Colors.orange.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 13, color: isLongShift ? Colors.orange.shade700 : Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(durationText,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isLongShift ? Colors.orange.shade700 : Colors.grey.shade600)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(label: 'Quỹ đầu ca', value: currencyFormat.format(startCash)),
              ),
              Expanded(
                child: _MiniStat(label: 'Tiền mặt trong ca', value: currencyFormat.format(cash)),
              ),
              Expanded(
                child: _MiniStat(label: 'Đơn hàng', value: '$count'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (canForceClose)
            SizedBox(
              width: double.infinity,
              height: 38,
              child: OutlinedButton.icon(
                onPressed: onForceClose,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                  side: BorderSide(color: Colors.red.shade200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Đóng ca hộ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _InfoRow({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AdminMenuCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminMenuCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}