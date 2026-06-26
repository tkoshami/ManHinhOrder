import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pos_fnb/config/app_secrets.dart';

class VietQRService {
  static const String _baseUrl = 'https://api.vietqr.io/v2/generate';
  static const String _banksUrl = 'https://api.vietqr.io/v2/banks';
  
  static const String _clientId = AppSecrets.vietQrClientId;
  static const String _apiKey = AppSecrets.vietQrApiKey;

  /// Lấy danh sách ngân hàng từ VietQR
  static Future<List<Map<String, dynamic>>> getBanksList() async {
    try {
      final response = await http.get(Uri.parse(_banksUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == '00') {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      throw Exception('Không thể lấy danh sách ngân hàng');
    } catch (e) {
      throw Exception('Lỗi kết nối: $e');
    }
  }

  /// Sinh mã QR từ VietQR.io
  static Future<String> generateQRCode({
    required String bankBin,
    required String accountNo,
    required String accountName,
    required int amount,
    required String description,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-client-id': _clientId,
          'x-api-key': _apiKey,
        },
        body: jsonEncode({
          'accountNo': accountNo,
          'accountName': accountName,
          'acqId': bankBin,
          'amount': amount,
          'addInfo': description,
          'format': 'base64',
          'template': 'compact', 
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['code'] == '00') {
          return data['data']['qrDataURL'];
        } else {
          throw Exception(data['desc'] ?? 'Lỗi từ hệ thống VietQR');
        }
      } else {
        throw Exception('Lỗi kết nối API: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Không thể tạo mã QR: $e');
    }
  }
}
