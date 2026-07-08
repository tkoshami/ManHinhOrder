import 'package:flutter/material.dart';
import 'package:pos_fnb/services/supabase_service.dart';

/// Màn hình cho admin bật/tắt từng "quyền" (permission) theo vai trò hoặc
/// ghi đè riêng cho từng tài khoản — thay vì phải sửa code mỗi khi cần
/// thay đổi ai được làm gì.
class PermissionManagementScreen extends StatefulWidget {
  const PermissionManagementScreen({super.key});

  @override
  State<PermissionManagementScreen> createState() => _PermissionManagementScreenState();
}

class _PermissionManagementScreenState extends State<PermissionManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  List<Map<String, dynamic>> _permissions = [];
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
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
      SupabaseService.getPermissions(),
      SupabaseService.getAllUsers(),
    ]);
    if (!mounted) return;
    setState(() {
      _permissions = results[0] as List<Map<String, dynamic>>;
      _users = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('Phân quyền', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.person_rounded), text: 'Theo tài khoản'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _UserOverrideTab(users: _users, permissions: _permissions),
        ],
      ),
    );
  }
}

/// Tab "Theo tài khoản": chọn 1 tài khoản cụ thể, xem quyền hiệu lực hiện
/// tại (theo vai trò hoặc đã bị ghi đè), và có thể ghi đè riêng 3 trạng
/// thái: Theo vai trò mặc định / Luôn cho phép / Luôn từ chối.
class _UserOverrideTab extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> permissions;

  const _UserOverrideTab({required this.users, required this.permissions});

  @override
  State<_UserOverrideTab> createState() => _UserOverrideTabState();
}

class _UserOverrideTabState extends State<_UserOverrideTab> {
  Map<String, dynamic>? _selectedUser;
  bool _loadingData = false;
  Set<String> _roleDefaultKeys = {};
  Map<String, bool> _overrides = {};

  Future<void> _loadForUser() async {
    if (_selectedUser == null) return;
    setState(() => _loadingData = true);
    final userId = _selectedUser!['id'].toString();
    final roleId = _selectedUser!['role_id'] == null ? null : int.tryParse(_selectedUser!['role_id'].toString());
    final results = await Future.wait([
      roleId != null ? SupabaseService.getRolePermissionKeys(roleId) : Future.value(<String>{}),
      SupabaseService.getUserPermissionOverrides(userId),
    ]);
    if (!mounted) return;
    setState(() {
      _roleDefaultKeys = results[0] as Set<String>;
      _overrides = results[1] as Map<String, bool>;
      _loadingData = false;
    });
  }

  Future<void> _setOverride(String key, bool? value) async {
    final userId = _selectedUser?['id']?.toString();
    if (userId == null) return;
    setState(() {
      if (value == null) {
        _overrides.remove(key);
      } else {
        _overrides[key] = value;
      }
    });
    final ok = value == null
        ? await SupabaseService.clearUserPermissionOverride(userId: userId, permissionKey: key)
        : await SupabaseService.setUserPermissionOverride(userId: userId, permissionKey: key, allowed: value);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không lưu được, vui lòng thử lại'), backgroundColor: Colors.red),
      );
      _loadForUser();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.users.isEmpty) {
      return const Center(child: Text('Chưa có tài khoản nào'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<Map<String, dynamic>>(
            value: _selectedUser,
            decoration: InputDecoration(
              labelText: 'Chọn tài khoản',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.person_search_rounded),
            ),
            items: widget.users.map((u) {
              final roleName = u['roles'] is Map ? u['roles']['name']?.toString() : null;
              final label = '${u['full_name'] ?? u['email'] ?? 'Không tên'}${roleName != null ? ' — $roleName' : ''}';
              return DropdownMenuItem(value: u, child: Text(label, overflow: TextOverflow.ellipsis));
            }).toList(),
            onChanged: (u) {
              setState(() => _selectedUser = u);
              _loadForUser();
            },
          ),
        ),
        if (_selectedUser == null)
          const Expanded(child: Center(child: Text('Chọn một tài khoản để xem/chỉnh quyền', style: TextStyle(color: Colors.grey))))
        else if (_loadingData)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.permissions.length,
              itemBuilder: (context, i) {
                final p = widget.permissions[i];
                final key = p['key'].toString();
                final byRole = _roleDefaultKeys.contains(key);
                final override = _overrides[key]; // null = không ghi đè

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(p['label']?.toString() ?? key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (override == true || (override == null && byRole) ? Colors.green : Colors.grey).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              override == null ? (byRole ? 'Đang bật (vai trò)' : 'Đang tắt (vai trò)') : (override ? 'Luôn bật' : 'Luôn tắt'),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: (override == true || (override == null && byRole)) ? Colors.green.shade700 : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (p['description'] != null) ...[
                        const SizedBox(height: 2),
                        Text(p['description'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ],
                      const SizedBox(height: 10),
                      SegmentedButton<bool?>(
                        segments: const [
                          ButtonSegment(value: null, label: Text('Theo vai trò'), icon: Icon(Icons.groups_rounded, size: 15)),
                          ButtonSegment(value: true, label: Text('Luôn bật'), icon: Icon(Icons.check_circle_rounded, size: 15)),
                          ButtonSegment(value: false, label: Text('Luôn tắt'), icon: Icon(Icons.cancel_rounded, size: 15)),
                        ],
                        selected: {override},
                        onSelectionChanged: (s) => _setOverride(key, s.first),
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11.5)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}