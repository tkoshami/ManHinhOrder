import 'dart:html' as html;
import 'dart:typed_data';

/// Trên Web không có khái niệm "thư mục" hay "chia sẻ file" như
/// mobile/desktop — cách chuẩn là tạo Blob rồi kích hoạt tải xuống qua
/// trình duyệt (giống bấm nút Download trên một trang web bất kỳ).
Future<String?> saveExportedFile(List<int> bytes, String fileName) async {
  final blob = html.Blob([Uint8List.fromList(bytes)]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);

  // Web không có "đường dẫn file" thật (trình duyệt tự quản lý thư mục
  // Downloads) — trả về tên file để hiển thị thông báo cho người dùng.
  return fileName;
}