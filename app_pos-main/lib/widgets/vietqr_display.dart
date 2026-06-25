import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pos_fnb/services/vietqr_service.dart';
import 'package:pos_fnb/services/storage_service.dart';
import 'package:pos_fnb/services/supabase_service.dart';
import 'package:pos_fnb/screens/settings_screen.dart';
import 'package:pos_fnb/data/constants.dart';

class VietQRDisplay extends StatefulWidget {
  final int amount;
  final String description;

  const VietQRDisplay({
    super.key,
    required this.amount,
    required this.description,
  });

  @override
  State<VietQRDisplay> createState() => _VietQRDisplayState();
}

class _VietQRDisplayState extends State<VietQRDisplay> {
  String? _qrBase64;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchQRCode();
  }

  Future<void> _fetchQRCode() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Ưu tiên lấy cấu hình từ Supabase để đồng bộ nhiều máy
      final shopSettings = await SupabaseService.getShopPaymentSettings();
      
      String bankBin;
      String accountNo;
      String accountName;

      if (shopSettings != null) {
        bankBin = shopSettings['bank_bin'];
        accountNo = shopSettings['account_no'];
        accountName = shopSettings['account_name'];
      } else {
        // Nếu không có trên Supabase, dùng thông tin ở máy hoặc mặc định
        final info = await StorageService.getPaymentInfo();
        bankBin = info['bankBin'] ?? vietQrBankId;
        accountNo = info['accountNo'] ?? vietQrAccountNo;
        accountName = info['accountName'] ?? vietQrAccountName;
      }

      // 2. Gọi API tạo mã QR
      final qrData = await VietQRService.generateQRCode(
        bankBin: bankBin,
        accountNo: accountNo,
        accountName: accountName,
        amount: widget.amount,
        description: widget.description,
      );

      if (mounted) {
        setState(() {
          _qrBase64 = qrData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception:', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(12),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            ),
            child: _buildContent(),
          ),
          if (!_isLoading && _errorMessage == null) ...[
            const SizedBox(height: 12),
            Text(
              'Số tiền: ${appCurrencyFormat.format(widget.amount)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Vui lòng quét mã để thanh toán',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.orange),
            SizedBox(height: 16),
            Text('Đang tạo mã QR...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, color: Colors.orange, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 12),
              if (_errorMessage!.contains('Chưa cấu hình'))
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    ).then((_) => _fetchQRCode()); // Sau khi quay lại thì tự động load lại QR
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('ĐI TỚI CÀI ĐẶT'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                )
              else
                TextButton.icon(
                  onPressed: _fetchQRCode,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
            ],
          ),
        ),
      );
    }

    if (_qrBase64 != null) {
      final base64String = _qrBase64!.split(',').last;
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          base64Decode(base64String),
          fit: BoxFit.contain,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
