import 'package:pos_fnb/models/feedback_model.dart';

List<FeedbackModel> globalFeedbacks = [
  FeedbackModel(
    id: '1',
    customerName: 'Nguyễn Văn A',
    phoneNumber: '0901234567',
    content: 'Nhật Lê đẹp trai quá, cho xin info!',
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
