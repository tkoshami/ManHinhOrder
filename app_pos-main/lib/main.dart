import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pos_fnb/screens/login_screen.dart';
import 'package:pos_fnb/screens/self_order_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://ictrofvccqswlgeeoqnw.supabase.co',
    publishableKey: 'sb_publishable_haRSLT58916WxVI8DF3WXA_iwtMkezF',
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      initialRoute: _initialRouteForCurrentUrl(),
      onGenerateRoute: (settings) {
        // Hỗ trợ cả đường dẫn /self-order và /zonzon theo yêu cầu
        if (settings.name == '/self-order' || settings.name == '/zonzon') {
          return MaterialPageRoute(builder: (_) => const SelfOrderScreen());
        }
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
