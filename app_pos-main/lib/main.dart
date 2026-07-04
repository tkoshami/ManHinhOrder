import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pos_fnb/screens/login_screen.dart';
import 'package:pos_fnb/screens/self_order_screen.dart';
import 'package:pos_fnb/widgets/internet_status_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://ictrofvccqswlgeeoqnw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImljdHJvZnZjY3Fzd2xnZWVvcW53Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE1MTQ2NzMsImV4cCI6MjA5NzA5MDY3M30.mjTsnWNKkZSfdeb1yI1gxQSleef35Ge2_hsqBY5iMys',
  );
  runApp(const MyApp());
}

String _initialRouteForCurrentUrl() {
  final path = Uri.base.path;
  if (path == '/self-order' ||
      path == '/self-order/' ||
      path == '/zonzon' ||
      path == '/zonzon/') {
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }
  return '/';
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
        if (settings.name == '/self-order' || settings.name == '/zonzon') {
          return MaterialPageRoute(builder: (_) => const SelfOrderScreen());
        }
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      },
      debugShowCheckedModeBanner: false,
    );
  }
}