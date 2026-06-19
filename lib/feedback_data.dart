class FeedbackModel {
  final String id;
  final String customerName;
  final String phoneNumber;
  final String content;
  final DateTime dateTime;

  FeedbackModel({
    required this.id,
    required this.customerName,
    required this.phoneNumber,
    required this.content,
    required this.dateTime,
  });
}

// Danh sách feedback giả lập dùng chung cho toàn bộ app
List<FeedbackModel> globalFeedbacks = [
  FeedbackModel(
    id: '1',
    customerName: 'Nguyễn Văn A',
    phoneNumber: '0901234567',
    content: 'Cà phê sữa rất ngon, phục vụ nhanh!',
    dateTime: DateTime.now().subtract(const Duration(hours: 2)),
  ),
  FeedbackModel(
    id: '2',
    customerName: 'Trần Thị B',
    phoneNumber: '0988777666',
    content: 'Bánh mì hơi nguội một chút, mong quán cải thiện.',
    dateTime: DateTime.now().subtract(const Duration(days: 1)),
  ),
];
