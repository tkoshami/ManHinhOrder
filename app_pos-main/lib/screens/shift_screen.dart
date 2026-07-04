import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/services/supabase_service.dart';

/// Màn hình Mở ca / Kết ca cho thu ngân (và admin).
/// - Nếu chưa có ca đang mở: hiển thị form nhập quỹ tiền mặt đầu ca.
/// - Nếu đang có ca mở: hiển thị tổng doanh thu tạm tính trong ca và
///   form đếm quỹ tiền mặt thực tế để kết ca, tự tính chênh lệch.
class ShiftScreen extends StatefulWidget {
  final UserAccount user;

  const ShiftScreen({super.key, required this.user});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  static const _primary = Color(0xFFE8590C);
  static const _primaryDark = Color(0xFFD9480F);
  static const _bg = Color(0xFFF5F6F8);

  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
  final _startCashCtl = TextEditingController();
  final _endCashCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  final _thousandsFormatter = _ThousandsSeparatorInputFormatter();

  bool _loading = true;
  bool _submitting = false;
  String? _startCashError;
  String? _endCashError;
  Map<String, dynamic>? _openShift;
  Map<String, dynamic> _summary = {'cash': 0.0, 'transfer': 0.0, 'other': 0.0, 'count': 0};

  @override
  void dispose() {
    _startCashCtl.dispose();
    _endCashCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final shift = await SupabaseService.getOpenShiftForStaff(widget.user.id);
      Map<String, dynamic> summary = {'cash': 0.0, 'transfer': 0.0, 'other': 0.0, 'count': 0};
      if (shift != null) {
        summary = await SupabaseService.getShiftOrdersSummary(int.parse(shift['id'].toString()));
      }
      if (!mounted) return;
      setState(() {
        _openShift = shift;
        _summary = summary;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Không thể tải dữ liệu ca làm việc, vui lòng thử lại', isError: true);
    }
  }

  double _parseAmount(String text) {
    return double.tryParse(text.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0;
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ));
  }

  Future<void> _openNewShift() async {
    final startCash = _parseAmount(_startCashCtl.text);
    setState(() {
      _startCashError = _startCashCtl.text.trim().isEmpty ? 'Vui lòng nhập số tiền quỹ đầu ca' : null;
    });
    if (_startCashError != null) return;

    final confirmed = await _showConfirmDialog(
      icon: Icons.login_rounded,
      iconColor: _primary,
      title: 'Xác nhận mở ca',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SummaryLine(label: 'Nhân viên', value: widget.user.name),
          _SummaryLine(label: 'Thời điểm mở ca', value: DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now())),
          const Divider(height: 20),
          _SummaryLine(label: 'Quỹ tiền mặt đầu ca', value: currencyFormat.format(startCash), bold: true),
        ],
      ),
      confirmLabel: 'MỞ CA',
      confirmColor: _primary,
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      final shift = await SupabaseService.openShift(staffId: widget.user.id, startCash: startCash);
      if (!mounted) return;
      if (shift != null) {
        _startCashCtl.clear();
        _showSnack('Đã mở ca làm việc thành công');
        await _load();
      } else {
        _showSnack('Mở ca thất bại, vui lòng thử lại', isError: true);
      }
    } catch (_) {
      if (mounted) _showSnack('Đã xảy ra lỗi, vui lòng thử lại', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmCloseShift() async {
    setState(() {
      _endCashError = _endCashCtl.text.trim().isEmpty ? 'Vui lòng nhập số tiền mặt đếm được cuối ca' : null;
    });
    if (_endCashError != null) return;

    final endCash = _parseAmount(_endCashCtl.text);
    final startCash = (_openShift?['start_cash'] as num?)?.toDouble() ?? 0;
    final cashRevenue = (_summary['cash'] as num?)?.toDouble() ?? 0;
    final expectedCash = startCash + cashRevenue;
    final diff = endCash - expectedCash;
    final diffColor = diff == 0 ? Colors.green.shade600 : (diff > 0 ? Colors.blue.shade600 : Colors.red.shade600);
    final diffLabel = diff == 0 ? 'Khớp quỹ' : (diff > 0 ? 'Dư quỹ' : 'Thiếu quỹ');

    final confirmed = await _showConfirmDialog(
      icon: Icons.logout_rounded,
      iconColor: Colors.red.shade400,
      title: 'Xác nhận kết ca',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryLine(label: 'Quỹ đầu ca', value: currencyFormat.format(startCash)),
          _SummaryLine(label: 'Doanh thu tiền mặt', value: currencyFormat.format(cashRevenue)),
          _SummaryLine(label: 'Tiền mặt dự kiến', value: currencyFormat.format(expectedCash)),
          _SummaryLine(label: 'Tiền mặt đếm được', value: currencyFormat.format(endCash)),
          const Divider(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(color: diffColor.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
            child: _SummaryLine(label: diffLabel, value: currencyFormat.format(diff.abs()), color: diffColor, bold: true),
          ),
          if (diff != 0) ...[
            const SizedBox(height: 8),
            Text(
              diff > 0
                  ? 'Quỹ tiền mặt đang dư so với dự kiến. Vui lòng kiểm tra lại trước khi xác nhận.'
                  : 'Quỹ tiền mặt đang thiếu so với dự kiến. Vui lòng kiểm tra lại trước khi xác nhận.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
      confirmLabel: 'XÁC NHẬN KẾT CA',
      confirmColor: Colors.red.shade400,
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      final ok = await SupabaseService.closeShift(
        shiftId: int.parse(_openShift!['id'].toString()),
        endCash: endCash,
        expectedCash: expectedCash,
        notes: _notesCtl.text,
      );
      if (!mounted) return;
      if (ok) {
        _endCashCtl.clear();
        _notesCtl.clear();
        _showSnack('Đã kết ca thành công');
        await _load();
      } else {
        _showSnack('Kết ca thất bại, vui lòng thử lại', isError: true);
      }
    } catch (_) {
      if (mounted) _showSnack('Đã xảy ra lỗi, vui lòng thử lại', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool?> _showConfirmDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget content,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17))),
          ],
        ),
        content: SingleChildScrollView(child: content),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('HỦY', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(confirmLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(_openShift == null ? 'Mở ca làm việc' : 'Kết ca làm việc',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: _bg,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _load,
          color: _primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _openShift == null
                  ? _buildOpenShiftForm(key: const ValueKey('open'))
                  : _buildCloseShiftForm(key: const ValueKey('close')),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOpenShiftForm({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoBanner(
          icon: Icons.point_of_sale_rounded,
          iconColor: _primary,
          iconBg: _primary.withOpacity(0.12),
          title: 'Chưa có ca làm việc',
          subtitle: 'Nhập quỹ tiền mặt đầu ca để bắt đầu bán hàng',
        ),
        const SizedBox(height: 20),
        _AmountField(
          label: 'QUỸ TIỀN MẶT ĐẦU CA',
          controller: _startCashCtl,
          formatter: _thousandsFormatter,
          accentColor: _primary,
          errorText: _startCashError,
          onChanged: (_) {
            if (_startCashError != null) setState(() => _startCashError = null);
          },
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _openNewShift,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              disabledBackgroundColor: _primary.withOpacity(0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _submitting
                ? const SizedBox(
                height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.play_arrow_rounded, color: Colors.white),
            label: const Text('MỞ CA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildCloseShiftForm({Key? key}) {
    final startCash = (_openShift?['start_cash'] as num?)?.toDouble() ?? 0;
    final startAt = DateTime.tryParse(_openShift?['start_at']?.toString() ?? '');
    final cash = (_summary['cash'] as num?)?.toDouble() ?? 0;
    final transfer = (_summary['transfer'] as num?)?.toDouble() ?? 0;
    final other = (_summary['other'] as num?)?.toDouble() ?? 0;
    final count = _summary['count'] ?? 0;
    final expectedCash = startCash + cash;
    final totalRevenue = cash + transfer + other;

    final duration = startAt != null ? DateTime.now().difference(startAt) : null;
    final durationText = duration != null
        ? (duration.inHours > 0 ? '${duration.inHours} giờ ${duration.inMinutes % 60} phút' : '${duration.inMinutes} phút')
        : null;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primary, _primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: _primary.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                        SizedBox(width: 6),
                        Text('CA ĐANG MỞ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (durationText != null)
                    Text(durationText, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                startAt != null ? 'Bắt đầu lúc ${DateFormat('HH:mm dd/MM/yyyy').format(startAt)}' : 'Đang mở ca',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 4),
              Text('Quỹ đầu ca: ${currencyFormat.format(startCash)}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(icon: Icons.payments_rounded, color: Colors.green.shade600, label: 'Tiền mặt', value: currencyFormat.format(cash)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(icon: Icons.qr_code_rounded, color: Colors.blue.shade600, label: 'Chuyển khoản', value: currencyFormat.format(transfer)),
            ),
          ],
        ),
        if (other > 0) ...[
          const SizedBox(height: 10),
          _StatCard(icon: Icons.more_horiz_rounded, color: Colors.purple.shade400, label: 'Khác', value: currencyFormat.format(other), fullWidth: true),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$count đơn hàng trong ca', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  Text(currencyFormat.format(totalRevenue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tiền mặt dự kiến cuối ca', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  Text(currencyFormat.format(expectedCash), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryDark)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _AmountField(
          label: 'ĐẾM QUỸ TIỀN MẶT CUỐI CA',
          controller: _endCashCtl,
          formatter: _thousandsFormatter,
          accentColor: _primary,
          errorText: _endCashError,
          onChanged: (_) {
            if (_endCashError != null) _endCashError = null;
            setState(() {});
          },
        ),
        if (_endCashCtl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Builder(builder: (context) {
            final endCash = _parseAmount(_endCashCtl.text);
            final diff = endCash - expectedCash;
            final color = diff == 0 ? Colors.green.shade600 : (diff > 0 ? Colors.blue.shade600 : Colors.red.shade600);
            final icon = diff == 0 ? Icons.check_circle_rounded : (diff > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded);
            final label = diff == 0 ? 'Khớp quỹ' : (diff > 0 ? 'Dư quỹ' : 'Thiếu quỹ');
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 8),
                      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text(currencyFormat.format(diff.abs()), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 20),
        const Text('GHI CHÚ (không bắt buộc)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12, letterSpacing: 0.3)),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'VD: Lý do chênh lệch quỹ, bàn giao ca...',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _confirmCloseShift,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              disabledBackgroundColor: Colors.red.shade200,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _submitting
                ? const SizedBox(
                height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.stop_circle_outlined, color: Colors.white),
            label: const Text('KẾT CA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ],
    );
  }
}

/// Banner thông tin hiển thị ở đầu màn hình (dùng cho trạng thái chưa mở ca).
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;

  const _InfoBanner({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ô nhập số tiền có định dạng nghìn tự động, kèm nhãn và thông báo lỗi.
class _AmountField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputFormatter formatter;
  final Color accentColor;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const _AmountField({
    required this.label,
    required this.controller,
    required this.formatter,
    required this.accentColor,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12, letterSpacing: 0.3)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, formatter],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: '0',
            suffixText: '₫',
            errorText: errorText,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: hasError ? Colors.red.shade300 : Colors.grey.shade300, width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: hasError ? Colors.red.shade400 : accentColor, width: 2.2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade300, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Formatter tự động chèn dấu chấm phân cách hàng nghìn khi người dùng nhập số.
class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat.decimalPattern('vi_VN');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final digitsOnly = newValue.text.replaceAll('.', '');
    final number = int.tryParse(digitsOnly);
    if (number == null) return oldValue;
    final formatted = _formatter.format(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool fullWidth;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      width: fullWidth ? double.infinity : null,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: fullWidth
          ? Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;

  const _SummaryLine({required this.label, required this.value, this.color, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: TextStyle(color: color ?? Colors.grey.shade700, fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(color: color ?? Colors.black87, fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }
}