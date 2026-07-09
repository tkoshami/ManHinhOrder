import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Xác định thư mục lưu file — KHÔNG dùng path_provider trên Windows
/// vì hay bị MissingPluginException nếu native plugin chưa đăng ký.
Future<Directory> _getExportDirectory() async {
  // Windows: dùng biến môi trường thuần Dart, không cần plugin
  if (Platform.isWindows) {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) {
      final downloads = Directory('$userProfile\\Downloads');
      if (await downloads.exists()) return downloads;
    }
    return Directory.systemTemp;
  }

  // Android / iOS / macOS / Linux: thử path_provider, có fallback an toàn
  try {
    final dir = await getApplicationDocumentsDirectory();
    return dir;
  } catch (e) {
    debugPrint('path_provider lỗi, dùng thư mục tạm: $e');
    return Directory.systemTemp;
  }
}

/// Lưu file xuống đĩa (mobile/desktop) rồi mở hộp thoại chia sẻ nếu nền
/// tảng hỗ trợ. Trả về đường dẫn file thật trên máy.
Future<String?> saveExportedFile(List<int> bytes, String fileName) async {
  final dir = await _getExportDirectory();
  final separator = Platform.isWindows ? '\\' : '/';
  final file = File('${dir.path}$separator$fileName');
  await file.writeAsBytes(bytes);

  try {
    await Share.shareXFiles([XFile(file.path)], text: 'Báo cáo tồn kho');
  } catch (e) {
    // Trên desktop (Windows) share_plus thường không hỗ trợ — bỏ qua,
    // file vẫn đã được lưu thành công, chỉ là không mở được hộp thoại chia sẻ.
    debugPrint('Share không khả dụng trên nền tảng này: $e');
  }

  return file.path;
}