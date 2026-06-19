import 'package:flutter/material.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // 1. Quản lý bộ nhớ bằng cách khai báo Controller và dispose chúng
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  void dispose() {
    // Luôn dispose controller khi không sử dụng để tránh memory leak
    _nameController.dispose();
    _phoneController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _submitFeedback() {
    // 2. Kiểm tra tính hợp lệ của Form trước khi xử lý
    if (_formKey.currentState!.validate()) {
      // Giả lập gửi dữ liệu
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã gửi phản hồi thành công!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Clear form sau khi gửi thành công
      _nameController.clear();
      _phoneController.clear();
      _contentController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phản hồi từ khách hàng'),
        elevation: 0,
      ),
      // 3. Sử dụng SingleChildScrollView để tránh lỗi tràn màn hình khi hiện bàn phím
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chúng tôi rất trân trọng ý kiến đóng góp của bạn!',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              
              // 4. Sử dụng TextFormField thay cho TextField để tận dụng validator
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên khách hàng',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập tên';
                  }
                  return null;
                },
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
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập số điện thoại';
                  }
                  // Regex kiểm tra số điện thoại cơ bản
                  if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
                    return 'Số điện thoại không hợp lệ';
                  }
                  return null;
                },
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
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập nội dung phản hồi';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitFeedback,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'GỬI PHẢN HỒI',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
