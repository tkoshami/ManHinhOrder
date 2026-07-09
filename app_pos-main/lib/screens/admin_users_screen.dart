import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/services/supabase_service.dart';

/// Màn hình quản lý tài khoản con (admin): thêm, sửa, đổi mật khẩu, xóa.
class AdminUsersScreen extends StatefulWidget {
  final UserAccount currentUser;
  const AdminUsersScreen({super.key, required this.currentUser});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String _search = '';

  static const _allRoles = ['admin', 'shift_leader', 'cashier', 'user'];

  /// Chỉ Admin, hoặc người được cấp riêng quyền `users.assign_admin`, mới
  /// được phép gán/duy trì vai trò Admin cho tài khoản khác — tránh trường
  /// hợp một tài khoản chỉ được cấp `users.manage` (ví dụ Trưởng ca) tự
  /// tạo/leo thang thành Admin.
  bool get _canAssignAdmin =>
      widget.currentUser.role == UserRole.admin || widget.currentUser.can('users.assign_admin');

  List<String> get _roles => _canAssignAdmin ? _allRoles : _allRoles.where((r) => r != 'admin').toList();

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    final users = await SupabaseService.getAllUsers();
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  String _roleName(String? role) {
    switch (role) {
      case 'admin':
        return 'Quản trị viên';
      case 'shift_leader':
        return 'Trưởng ca';
      case 'cashier':
        return 'Thu ngân';
      case 'user':
      default:
        return 'Nhân viên';
    }
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'admin':
        return Colors.purple;
      case 'shift_leader':
        return Colors.indigo;
      case 'cashier':
        return Colors.orange;
      case 'user':
      default:
        return Colors.green;
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_search.trim().isEmpty) return _users;
    final q = _search.trim().toLowerCase();
    return _users.where((u) {
      final name = (u['full_name'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  /// Tài khoản Admin chỉ được sửa/xóa/đổi role bởi Admin khác (hoặc người
  /// có quyền `users.assign_admin`) — chặn việc một tài khoản chỉ có
  /// `users.manage` tự ý sửa/hạ quyền/xóa tài khoản Admin thật.
  bool _isProtectedAdmin(Map<String, dynamic> user) =>
      (user['role']?.toString() == 'admin') && !_canAssignAdmin;

  Future<void> _openCreateDialog() async {
    final emailCtl = TextEditingController();
    final passCtl = TextEditingController();
    final nameCtl = TextEditingController();
    String role = 'cashier';
    bool isSaving = false;
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Thêm tài khoản', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: 'Họ tên', prefixIcon: Icon(Icons.badge_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Quyền hạn', prefixIcon: Icon(Icons.security_outlined)),
                  items: _roles
                      .map((r) => DropdownMenuItem(value: r, child: Text(_roleName(r))))
                      .toList(),
                  onChanged: (v) => setDialogState(() => role = v ?? role),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                if (nameCtl.text.trim().isEmpty ||
                    emailCtl.text.trim().isEmpty ||
                    passCtl.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Vui lòng nhập đủ thông tin, mật khẩu tối thiểu 6 ký tự'),
                  ));
                  return;
                }
                setDialogState(() => isSaving = true);
                final ok = await SupabaseService.createUser(
                  email: emailCtl.text.trim(),
                  password: passCtl.text,
                  fullName: nameCtl.text.trim(),
                  role: role,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? 'Đã tạo tài khoản' : 'Tạo tài khoản thất bại'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ));
                  if (ok) _loadUsers();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: isSaving
                  ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('TẠO', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditDialog(Map<String, dynamic> user) async {
    if (_isProtectedAdmin(user)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bạn không có quyền chỉnh sửa tài khoản Admin'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final nameCtl = TextEditingController(text: user['full_name'] ?? '');
    String role = (user['role'] ?? 'user').toString();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Sửa tài khoản', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Họ tên', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _roles.contains(role) ? role : 'user',
                decoration: const InputDecoration(labelText: 'Quyền hạn', prefixIcon: Icon(Icons.security_outlined)),
                items: _roles
                    .map((r) => DropdownMenuItem(value: r, child: Text(_roleName(r))))
                    .toList(),
                onChanged: (v) => setDialogState(() => role = v ?? role),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openChangePasswordDialog(user);
                  },
                  icon: const Icon(Icons.lock_reset, size: 18),
                  label: const Text('Đổi mật khẩu'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: const Text('HỦY')),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                if (nameCtl.text.trim().isEmpty) return;
                setDialogState(() => isSaving = true);
                final ok = await SupabaseService.updateUserProfile(
                  userId: user['id'],
                  fullName: nameCtl.text.trim(),
                  role: role,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? 'Đã cập nhật' : 'Cập nhật thất bại'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ));
                  if (ok) _loadUsers();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: isSaving
                  ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('LƯU', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChangePasswordDialog(Map<String, dynamic> user) async {
    if (_isProtectedAdmin(user)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bạn không có quyền đổi mật khẩu tài khoản Admin'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final passCtl = TextEditingController();
    bool isSaving = false;
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Đổi mật khẩu — ${user['full_name'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: passCtl,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'Mật khẩu mới',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setDialogState(() => obscure = !obscure),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: const Text('HỦY')),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                if (passCtl.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Mật khẩu tối thiểu 6 ký tự')));
                  return;
                }
                setDialogState(() => isSaving = true);
                final ok = await SupabaseService.changeUserPassword(
                  userId: user['id'],
                  newPassword: passCtl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? 'Đã đổi mật khẩu' : 'Đổi mật khẩu thất bại'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: isSaving
                  ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('LƯU', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    if (_isProtectedAdmin(user)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bạn không có quyền xóa tài khoản Admin'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xóa tài khoản?'),
        content: Text('Bạn có chắc muốn xóa "${user['full_name'] ?? user['email']}"? '
            'Hành động này không thể hoàn tác.'),
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
    final ok = await SupabaseService.deleteUser(userId: user['id']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Đã xóa tài khoản' : 'Xóa thất bại'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) _loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('Quản lý tài khoản', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.person_add),
        label: const Text('Thêm tài khoản'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc email...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                ? const Center(child: Text('Không có tài khoản nào'))
                : RefreshIndicator(
              onRefresh: _loadUsers,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _filteredUsers.length,
                itemBuilder: (context, i) {
                  final u = _filteredUsers[i];
                  final role = (u['role'] ?? 'user').toString();
                  DateTime? createdAt;
                  try {
                    createdAt = DateTime.tryParse(u['created_at']?.toString() ?? '');
                  } catch (_) {}
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: _roleColor(role).withOpacity(0.12),
                          child: Text(
                            (u['full_name'] ?? '?').toString().substring(0, 1).toUpperCase(),
                            style: TextStyle(color: _roleColor(role), fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(u['full_name'] ?? '(Chưa đặt tên)',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(u['email'] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _roleColor(role).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(_roleName(role),
                                        style: TextStyle(color: _roleColor(role), fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  if (createdAt != null) ...[
                                    const SizedBox(width: 8),
                                    Text('Từ ${DateFormat('dd/MM/yyyy').format(createdAt)}',
                                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        _isProtectedAdmin(u)
                            ? Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 20)
                            : PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _openEditDialog(u);
                            if (v == 'password') _openChangePasswordDialog(u);
                            if (v == 'delete') _deleteUser(u);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Sửa'))),
                            PopupMenuItem(value: 'password', child: ListTile(leading: Icon(Icons.lock_reset), title: Text('Đổi mật khẩu'))),
                            PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Xóa', style: TextStyle(color: Colors.red)))),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}