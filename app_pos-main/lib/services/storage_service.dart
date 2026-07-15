import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyBankBin = 'vietqr_bank_bin';
  static const String _keyAccountNo = 'vietqr_account_no';
  static const String _keyAccountName = 'vietqr_account_name';
  static const String _keyBankShortName = 'vietqr_bank_short_name';

  static Future<void> savePaymentInfo({
    required String bankBin,
    required String accountNo,
    required String accountName,
    required String bankShortName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBankBin, bankBin);
    await prefs.setString(_keyAccountNo, accountNo);
    await prefs.setString(_keyAccountName, accountName);
    await prefs.setString(_keyBankShortName, bankShortName);
  }

  static Future<Map<String, String?>> getPaymentInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'bankBin': prefs.getString(_keyBankBin),
      'accountNo': prefs.getString(_keyAccountNo),
      'accountName': prefs.getString(_keyAccountName),
      'bankShortName': prefs.getString(_keyBankShortName),
    };
  }
}
