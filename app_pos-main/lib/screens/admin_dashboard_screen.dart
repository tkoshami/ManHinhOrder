import 'package:flutter/material.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/screens/admin_products_screen.dart';
import 'package:pos_fnb/screens/admin_reports_screen.dart';
import 'package:pos_fnb/screens/admin_users_screen.dart';

/// Trang trung tâm quản trị (chỉ dành cho role = admin).
/// Gom 3 nhóm chức năng chính: tài khoản, món ăn, báo cáo.
class AdminDashboardScreen extends StatelessWidget {
  final UserAccount user;

  const AdminDashboardScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('Quản trị hệ thống', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Xin chào, ${user.name}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Chọn một mục để quản lý cửa hàng của bạn',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 20),
            _AdminMenuCard(
              icon: Icons.people_alt,
              color: Colors.purple,
              title: 'Quản lý tài khoản',
              subtitle: 'Thêm, sửa, xóa tài khoản nhân viên và thu ngân',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminUsersScreen()),
              ),
            ),
            const SizedBox(height: 14),
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
          ],
        ),
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