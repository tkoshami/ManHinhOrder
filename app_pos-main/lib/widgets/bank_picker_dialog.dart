import 'package:flutter/material.dart';
import 'package:pos_fnb/services/vietqr_service.dart';

class BankPickerDialog extends StatefulWidget {
  const BankPickerDialog({super.key});

  @override
  State<BankPickerDialog> createState() => _BankPickerDialogState();
}

class _BankPickerDialogState extends State<BankPickerDialog> {
  List<Map<String, dynamic>> _allBanks = [];
  List<Map<String, dynamic>> _filteredBanks = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final banks = await VietQRService.getBanksList();
      if (mounted) {
        setState(() {
          _allBanks = banks;
          _filteredBanks = banks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _filterBanks(String query) {
    setState(() {
      _filteredBanks = _allBanks
          .where((bank) =>
              (bank['name'] as String).toLowerCase().contains(query.toLowerCase()) ||
              (bank['shortName'] as String).toLowerCase().contains(query.toLowerCase()) ||
              (bank['bin'] as String).contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chọn Ngân hàng'),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc mã BIN...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _filterBanks,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ĐÓNG'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            ElevatedButton(onPressed: _loadBanks, child: const Text('Thử lại')),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _filteredBanks.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final bank = _filteredBanks[index];
        return ListTile(
          leading: Container(
            width: 60,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Image.network(
              bank['logo'],
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_balance),
            ),
          ),
          title: Text(
            bank['shortName'],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            bank['name'],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(
            bank['bin'],
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
          onTap: () => Navigator.pop(context, bank),
        );
      },
    );
  }
}
