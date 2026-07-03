import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/widgets/vietqr_display.dart';

class SelfOrderPaymentScreen extends StatefulWidget {
  final SavedOrder order;
  const SelfOrderPaymentScreen({super.key, required this.order});

  @override
  State<SelfOrderPaymentScreen> createState() => _SelfOrderPaymentScreenState();
}

class _SelfOrderPaymentScreenState extends State<SelfOrderPaymentScreen> {
  bool _isOffline = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    // Kiểm tra định kỳ mỗi 5 giây
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkConnection());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    bool offline = false;
    if (kIsWeb) {
      // Trên Web dùng phương pháp khác hoặc mặc định là online nếu không có package
      // (Để đơn giản và không lỗi build, ta giả định online trên web nếu không cài thêm package)
      return;
    }
    
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      offline = result.isEmpty || result[0].rawAddress.isEmpty;
    } catch (_) {
      offline = true;
    }

    if (mounted && _isOffline != offline) {
      setState(() {
        _isOffline = offline;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

    return Scaffold(
      appBar: AppBar(
        title: const Text('THANH TOÁN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.green,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              color: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Không có kết nối Internet. Vui lòng kiểm tra lại để tải mã QR.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
                  const SizedBox(height: 16),
                  const Text(
                    'Đơn hàng đã được ghi nhận!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mã đơn: ${widget.order.displayOrderCode}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tổng thanh toán:'),
                            Text(
                              currencyFormat.format(widget.order.totalAmount),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Vui lòng quét mã QR bên dưới để thanh toán',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  VietQRDisplay(
                    amount: widget.order.totalAmount.toInt(),
                    description: widget.order.displayOrderCode,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Sau khi chuyển khoản thành công, quý khách vui lòng đợi tại quầy để nhận món.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.green),
                        foregroundColor: Colors.green,
                      ),
                      child: const Text('QUAY LẠI MENU', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
