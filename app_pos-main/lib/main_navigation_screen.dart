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
    final List<Widget> screens = [];
    final List<BottomNavigationBarItem> navItems = [];

    // Phân quyền cho Staff (Role: user)
    if (widget.currentUser.role == UserRole.user) {
      screens.add(StaffOrderScreen(user: widget.currentUser));
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.add_shopping_cart), label: 'Tạo đơn'));

      screens.add(const FeedbackScreen());
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.feedback), label: 'Phản hồi'));
    } 
    // Phân quyền cho Admin và Cashier
    else {
      screens.add(OrderScreen(user: widget.currentUser));
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.add_shopping_cart), label: 'Tạo đơn'));

      screens.add(const HistoryScreen());
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Lịch sử'));

      if (widget.currentUser.role == UserRole.admin) {
        screens.add(const StatsScreen());
        navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Thống kê'));
      }
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
