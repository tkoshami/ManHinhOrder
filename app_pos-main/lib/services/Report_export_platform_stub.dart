/// Stub mặc định — chỉ tồn tại để thỏa mãn cú pháp conditional import.
/// Trên thực tế luôn có `dart.library.io` (mobile/desktop) hoặc
/// `dart.library.html` (web) nên nhánh này không bao giờ thực sự chạy.
Future<String?> saveExportedFile(List<int> bytes, String fileName) async {
  throw UnsupportedError('Nền tảng hiện tại không hỗ trợ xuất file.');
}