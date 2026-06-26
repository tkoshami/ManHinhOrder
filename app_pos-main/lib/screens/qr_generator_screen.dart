import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrGeneratorScreen extends StatelessWidget {
  const QrGeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Đường dẫn deploy thực tế
    const String baseUrl = "https://web-mar-pos.vercel.app/zonzon";

    return Scaffold(
      appBar: AppBar(
        title: const Text('TẠO MÃ QR GỌI MÓN'),
        backgroundColor: Colors.orange,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'QUÉT MÃ ĐỂ GỌI MÓN',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            QrImageView(
              data: baseUrl,
              version: QrVersions.auto,
              size: 300.0,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 24),
            const Text(
              'Dán mã này tại quầy hoặc trên bàn',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                // Logic in mã QR (giả lập)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đang gửi lệnh in mã QR...')),
                );
              },
              icon: const Icon(Icons.print),
              label: const Text('IN MÃ QR'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
