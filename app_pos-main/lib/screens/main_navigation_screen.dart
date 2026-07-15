import 'package:flutter/material.dart';
import 'package:pos_fnb/screens/order_screen.dart';
import 'package:pos_fnb/models/app_models.dart';

class MainNavigationScreen extends StatefulWidget {
  final UserAccount currentUser;
  const MainNavigationScreen({super.key, required this.currentUser});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  @override
  Widget build(BuildContext context) {
    // Chỉ còn màn Order — mọi tính năng khác (Lịch sử, Thống kê,
    // Kho hàng, Quản lý tài khoản...) đã được ẩn hoàn toàn.
    return OrderScreen(user: widget.currentUser);
  }
}