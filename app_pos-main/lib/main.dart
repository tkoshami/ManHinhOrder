import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pos_fnb/screens/login_screen.dart';
import 'package:pos_fnb/screens/self_order_screen.dart';
import 'package:pos_fnb/widgets/internet_status_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://asssotnvhkilritnrtqn.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzc3NvdG52aGtpbHJpdG5ydHFuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM5MjE1OTYsImV4cCI6MjA5OTQ5NzU5Nn0.Q6G9r2llMUCej446MHC2tEMwWOWo1srvG8ZNvMKOiE8',
  );
  runApp(const MyApp());
}

String _initialRouteForCurrentUrl() {
  final path = Uri.base.path;
  if (path == '/self-order' ||
      path == '/self-order/' ||
      path == '/HuyCua' ||
      path == '/HuyCua/') {
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }
  return '/';
}

/// Đọc tên bàn từ URL mã QR (VD .../self-order?table=Bàn%201).
/// Uri.base phản ánh đúng URL trình duyệt lúc app khởi động.
String? _initialTableFromUrl() {
  final table = Uri.base.queryParameters['table'];
  return (table != null && table.trim().isNotEmpty) ? table.trim() : null;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarPOS',
      builder: (context, child) {
        return InternetStatusBanner(child: child ?? const SizedBox.shrink());
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          labelStyle: const TextStyle(color: Colors.black),
          hintStyle: const TextStyle(color: Colors.grey),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black54, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black54, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.orange, width: 2.2),
          ),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.black),
          bodyMedium: TextStyle(color: Colors.black),
        ),
      ),
      initialRoute: _initialRouteForCurrentUrl(),
      onGenerateRoute: (settings) {
        if (settings.name == '/self-order' || settings.name == '/HuyCua') {
          return MaterialPageRoute(
            builder: (_) => SelfOrderScreen(tableNumber: _initialTableFromUrl()),
          );
        }
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      },
      debugShowCheckedModeBanner: false,
    );
  }
}