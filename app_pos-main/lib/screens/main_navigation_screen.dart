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
    if (widget.currentUser.role == UserRole.user) {
      return StaffOrderScreen(user: widget.currentUser);
    }

    final List<Widget> screens = [OrderScreen(user: widget.currentUser)];
    final List<BottomNavigationBarItem> navItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.add_shopping_cart), label: 'Tạo đơn'),
    ];

    screens.add(const HistoryScreen());
    navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Lịch sử'));

    if (widget.currentUser.role == UserRole.cashier) {
      screens.add(FeedbackScreen(currentUser: widget.currentUser));
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.feedback), label: 'Phản hồi'));
    }

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
