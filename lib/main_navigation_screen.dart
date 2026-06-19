import 'package:flutter/material.dart';
import 'order_screen.dart';
import 'staff_order_screen.dart';
import 'history_screen.dart';
import 'stats_screen.dart';
import 'feedback_screen.dart';
import 'models.dart';

class MainNavigationScreen extends StatefulWidget {
  final UserAccount currentUser;
  const MainNavigationScreen({super.key, required this.currentUser});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Nếu là Staff (role user), chuyển hướng sang trang StaffOrderScreen riêng biệt
    if (widget.currentUser.role == UserRole.user) {
      return StaffOrderScreen(user: widget.currentUser);
    }

    // Với Admin và Cashier, chuẩn bị danh sách màn hình và icon
    final List<Widget> screens = [OrderScreen(user: widget.currentUser)];
    final List<BottomNavigationBarItem> navItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.add_shopping_cart), label: 'Tạo đơn'),
    ];

    // Thêm tab Lịch sử cho Cashier và Admin
    screens.add(const HistoryScreen());
    navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Lịch sử'));

    // Thêm tab Phản hồi cho Cashier (để xem danh sách)
    if (widget.currentUser.role == UserRole.cashier) {
      screens.add(FeedbackScreen(currentUser: widget.currentUser));
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.feedback), label: 'Phản hồi'));
    }

    // Thêm các tab đặc quyền cho Admin
    if (widget.currentUser.role == UserRole.admin) {
      screens.add(const StatsScreen());
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Thống kê'));

      screens.add(FeedbackScreen(currentUser: widget.currentUser));
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.feedback), label: 'Phản hồi'));
    }

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: navItems,
      ),
    );
  }
}