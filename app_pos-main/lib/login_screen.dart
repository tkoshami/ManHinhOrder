import 'package:flutter/material.dart';
import 'main_navigation_screen.dart';
import 'models.dart';

// Mock users
final List<UserAccount> mockUsers = [
  UserAccount(name: 'Nguyễn Admin', email: 'admin', password: '1234', role: UserRole.admin),
  UserAccount(name: 'Trần Cashier', email: 'cashier', password: '1234', role: UserRole.cashier),
  UserAccount(name: 'Lê Staff', email: 'user', password: '1234', role: UserRole.user),
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final user = mockUsers.firstWhere(
        (u) => u.email == _emailController.text && u.password == _passwordController.text,
        orElse: () => UserAccount(name: '', email: '', password: '', role: UserRole.user),
      );

      if (user.name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sai tài khoản hoặc mật khẩu (admin/password)')),
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MainNavigationScreen(currentUser: user)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange[50],
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.restaurant_menu, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text('F&B POS SYSTEM', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Dùng: admin/cashier/user - pass: 1234', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Tài khoản', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mật khẩu', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    child: const Text('ĐĂNG NHẬP', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
