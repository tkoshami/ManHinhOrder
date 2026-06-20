import 'package:flutter/material.dart';
import 'package:pos_fnb/screens/order_screen.dart';
import 'package:pos_fnb/screens/staff_order_screen.dart';
import 'package:pos_fnb/screens/history_screen.dart';
import 'package:pos_fnb/screens/stats_screen.dart';
import 'package:pos_fnb/screens/feedback_screen.dart';
import 'package:pos_fnb/models/app_models.dart';

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
    final bool isAdmin = widget.currentUser.role == UserRole.admin;
    final bool isCashier = widget.currentUser.role == UserRole.cashier;
    final bool isUser = widget.currentUser.role == UserRole.user;

    final List<Widget> screens = [OrderScreen(user: widget.currentUser)];
    final List<BottomNavigationBarItem> navItems = [
      BottomNavigationBarItem(
        icon: const Icon(Icons.restaurant_menu), 
        label: isUser ? 'Gọi món' : 'Tạo đơn',
      ),
    ];

    // Khách hàng (User) không thấy các tab quản lý
    if (!isUser) {
      screens.add(const HistoryScreen());
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Lịch sử'));

      if (isAdmin) {
        screens.add(const StatsScreen());
        navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Thống kê'));
      }

      screens.add(FeedbackScreen(currentUser: widget.currentUser));
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.feedback), label: 'Phản hồi'));
    }

    // Nếu chỉ có 1 item (User), không cần hiện BottomNavigationBar
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: isUser ? null : BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: isAdmin ? Colors.orangeAccent : Colors.orange,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: navItems,
      ),
    );
  }
}
