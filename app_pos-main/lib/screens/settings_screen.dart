import 'package:flutter/material.dart';
import 'package:pos_fnb/services/storage_service.dart';
import 'package:pos_fnb/widgets/bank_picker_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _accountNoController = TextEditingController();
  final _accountNameController = TextEditingController();
  String? _selectedBankBin;
  String? _selectedBankName;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final info = await StorageService.getPaymentInfo();
    setState(() {
      _selectedBankBin = info['bankBin'];
      _selectedBankName = info['bankShortName'];
      _accountNoController.text = info['accountNo'] ?? '';
      _accountNameController.text = info['accountName'] ?? '';
    });
  }

  Future<void> _pickBank() async {
    final bank = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const BankPickerDialog(),
    );

    if (bank != null) {
      setState(() {
        _selectedBankBin = bank['bin'];
        _selectedBankName = bank['shortName'];
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_selectedBankBin == null || _accountNoController.text.isEmpty || _accountNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đầy đủ thông tin')),
      );
      return;
    }

    await StorageService.savePaymentInfo(
      bankBin: _selectedBankBin!,
      accountNo: _accountNoController.text,
      accountName: _accountNameController.text.toUpperCase(),
      bankShortName: _selectedBankName!,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu cấu hình thanh toán')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình POS')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CẤU HÌNH NHẬN TIỀN VIETQR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ngân hàng'),
              subtitle: Text(_selectedBankName ?? 'Chưa chọn ngân hàng'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickBank,
            ),
            const Divider(),
            TextField(
              controller: _accountNoController,
              decoration: InputDecoration(
                labelText: 'Số tài khoản',
                filled: true,
                fillColor: Colors.white,
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
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _accountNameController,
              decoration: InputDecoration(
                labelText: 'Tên chủ tài khoản (Không dấu)',
                filled: true,
                fillColor: Colors.white,
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
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('LƯU CẤU HÌNH', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
