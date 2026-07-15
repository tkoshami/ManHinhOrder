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
