import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'feedback_data.dart';
import 'models.dart';

class FeedbackScreen extends StatefulWidget {
  final UserAccount? currentUser; // null nếu là khách hàng (user role)
  const FeedbackScreen({super.key, this.currentUser});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _contentController = TextEditingController();

  bool get _isAdminOrCashier =>
      widget.currentUser?.role == UserRole.admin ||
      widget.currentUser?.role == UserRole.cashier;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _submitFeedback() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        globalFeedbacks.insert(
          0,
          FeedbackModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            customerName: _nameController.text.trim(),
            phoneNumber: _phoneController.text.trim(),
            content: _contentController.text.trim(),
            dateTime: DateTime.now(),
          ),
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cảm ơn bạn đã gửi phản hồi!'),
          backgroundColor: Colors.green,
        ),
      );

      _nameController.clear();
      _phoneController.clear();
      _contentController.clear();
      
      // Nếu là khách hàng (mở từ StaffOrderScreen), có thể tự động đóng sau khi gửi
      if (widget.currentUser?.role == UserRole.user) {
        Future.delayed(const Duration(seconds: 1), () => Navigator.pop(context));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nếu là Admin hoặc Thu ngân -> Hiển thị danh sách phản hồi
    if (_isAdminOrCashier) {
      return _buildFeedbackList();
    }

    // Nếu là Khách hàng -> Hiển thị form nhập
    return _buildFeedbackForm();
  }

  Widget _buildFeedbackList() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách phản hồi'),
        backgroundColor: Colors.orangeAccent,
      ),
      body: globalFeedbacks.isEmpty
          ? const Center(child: Text('Chưa có phản hồi nào.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: globalFeedbacks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final fb = globalFeedbacks[index];
                final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(fb.dateTime);
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(fb.customerName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('SĐT: ${fb.phoneNumber}', style: const TextStyle(color: Colors.blue, fontSize: 13)),
                        const Divider(),
                        Text(fb.content, style: const TextStyle(fontSize: 14, height: 1.4)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildFeedbackForm() {
    return Scaffold(
      appBar: AppBar(title: const Text('Gửi phản hồi cho quán')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chúng tôi luôn lắng nghe ý kiến của bạn',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên của bạn',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Vui lòng nhập tên' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Vui lòng nhập SĐT' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Nội dung phản hồi',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Vui lòng nhập nội dung' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _submitFeedback,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('GỬI PHẢN HỒI',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
