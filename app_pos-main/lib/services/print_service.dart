import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:pos_fnb/services/supabase_service.dart';
import 'package:pos_fnb/services/vietqr_service.dart';
import 'package:pos_fnb/services/storage_service.dart';
import 'package:pos_fnb/data/constants.dart';

class PrintService {
  static final currencyFormat = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'd',
  );

  static Future<void> printBill(SavedOrder order) async {
    await SunmiPrinter.printText(
      'BÁNH MÌ ZONZON',
      style: SunmiTextStyle(
        align: SunmiPrintAlign.CENTER,
        bold: true,
        fontSize: 36,
      ),
    );
    await SunmiPrinter.printText(
      'Địa chỉ: 123 Đường ABC, Quận 1, TP.HCM',
      style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 24),
    );
    await SunmiPrinter.printText(
      'Hotline: 0123 456 789',
      style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 24),
    );

    await _printBlankLine();
    await SunmiPrinter.printText(
      'HÓA ĐƠN THANH TOÁN',
      style: SunmiTextStyle(
        align: SunmiPrintAlign.CENTER,
        bold: true,
        fontSize: 30,
      ),
    );
    await SunmiPrinter.lineWrap(1);

    await SunmiPrinter.printText('Mã đơn: ${order.id ?? ''}');
    await SunmiPrinter.printText(
      'Ngày: ${DateFormat('dd/MM/yyyy HH:mm').format(order.dateTime)}',
    );
    await SunmiPrinter.printText('Hình thức: ${order.tableOrCustomer}');
    await SunmiPrinter.printText(
      'PTTT: ${_getPaymentMethodName(order.paymentMethod)}',
    );

    await _printItemsTable(order.items);

    await SunmiPrinter.printRow(
      cols: [
        _column('Tạm tính:', 15, SunmiPrintAlign.LEFT),
        _column(currencyFormat.format(order.subtotal), 15, SunmiPrintAlign.RIGHT),
      ],
    );

    if (order.vatRate > 0) {
      await SunmiPrinter.printRow(
        cols: [
          _column(
            'VAT (${order.vatRate.toStringAsFixed(0)}%):',
            15,
            SunmiPrintAlign.LEFT,
          ),
          _column(currencyFormat.format(order.vatAmount), 15, SunmiPrintAlign.RIGHT),
        ],
      );
    }

    await SunmiPrinter.printRow(
      cols: [
        _column('TỔNG CỘNG:', 15, SunmiPrintAlign.LEFT, bold: true),
        _column(
          currencyFormat.format(order.totalAmount),
          15,
          SunmiPrintAlign.RIGHT,
          bold: true,
        ),
      ],
    );

    await _printBlankLine();
    await SunmiPrinter.printText(
      'Cảm ơn Quý khách. Hẹn gặp lại!',
      style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, italic: true),
    );

    if (order.paymentMethod == 'qr_code') {
      await _printBlankLine();
      await _printVietQR(order);
    } else if (order.id != null) {
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printQRCode(
        order.id!,
        style: SunmiQrcodeStyle(align: SunmiPrintAlign.CENTER),
      );
    }

    await SunmiPrinter.lineWrap(4);
  }

  static Future<void> _printVietQR(SavedOrder order) async {
    try {
      // 1. Lấy thông tin cấu hình ngân hàng (Ưu tiên Supabase -> Local Storage -> Constants)
      final shopSettings = await SupabaseService.getShopPaymentSettings();
      
      String? bankBin;
      String? accountNo;
      String? accountName;
      String? bankShortName;

      if (shopSettings != null && shopSettings['account_no'] != null) {
        bankBin = shopSettings['bank_bin']?.toString();
        accountNo = shopSettings['account_no']?.toString();
        accountName = shopSettings['account_name']?.toString();
        bankShortName = shopSettings['bank_short_name']?.toString() ?? 'Ngân hàng';
      } else {
        final info = await StorageService.getPaymentInfo();
        bankBin = info['bankBin'] ?? vietQrBankId;
        accountNo = info['accountNo'] ?? vietQrAccountNo;
        accountName = info['accountName'] ?? vietQrAccountName;
        bankShortName = info['bankShortName'] ?? vietQrBankShortName;
      }

      if (bankBin == null || accountNo == null || accountName == null) return;

      // 2. Gọi API để lấy chuỗi raw VietQR code
      final qrResponse = await VietQRService.generateQRCode(
        bankBin: bankBin,
        accountNo: accountNo,
        accountName: accountName,
        amount: order.totalAmount.toInt(),
        description: order.id ?? '',
      );
      
      final qrCode = qrResponse['qrCode'];
      if (qrCode == null || qrCode.isEmpty) return;

      // 3. In thông tin thụ hưởng
      await SunmiPrinter.line();
      await SunmiPrinter.printText(
        'THÔNG TIN CHUYỂN KHOẢN',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, bold: true, fontSize: 24),
      );
      await SunmiPrinter.printText(
        'Chủ TK: ${accountName.toUpperCase()}',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 24),
      );
      await SunmiPrinter.printText(
        'STK: $accountNo',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, bold: true, fontSize: 24),
      );
      await SunmiPrinter.printText(
        'Ngân hàng: $bankShortName',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 24),
      );
      await SunmiPrinter.printText(
        'Nội dung: ${order.id ?? ''}',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 22),
      );

      // 4. In mã QR thanh toán
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printQRCode(
        qrCode,
        style: SunmiQrcodeStyle(align: SunmiPrintAlign.CENTER, qrcodeSize: 5),
      );
      await SunmiPrinter.printText(
        'Vui lòng quét mã để thanh toán',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 20),
      );
      await SunmiPrinter.line();
    } catch (e) {
      print('Lỗi in QR thanh toán: $e');
    }
  }

  static SunmiColumn _column(
    String text,
    int width,
    SunmiPrintAlign align, {
    bool bold = false,
  }) {
    return SunmiColumn(
      text: text,
      width: width,
      style: SunmiTextStyle(align: align, bold: bold),
    );
  }

  static Future<void> _printBlankLine() async {
    await SunmiPrinter.printText(' ');
  }

  static Future<void> _printItemsTable(List<CartItem> items) async {
    const separator = '--------------------------------';
    await SunmiPrinter.printText(separator);
    await SunmiPrinter.printText(
      '${_fitRight('SL', 4)} ${_fitLeft('Tên món', 14)} ${_fitRight('Thành tiền', 12)}',
      style: SunmiTextStyle(bold: true),
    );
    await SunmiPrinter.printText(separator);

    for (final item in items) {
      final nameLines = _wrapText(item.product.name, 14);
      final totalText = currencyFormat.format(item.total);

      await SunmiPrinter.printText(
        '${_fitRight('${item.quantity}', 4)} '
        '${_fitLeft(nameLines.first, 14)} '
        '${_fitRight(totalText, 12)}',
      );

      for (final line in nameLines.skip(1)) {
        await SunmiPrinter.printText('     ${_fitLeft(line, 14)}');
      }

      if (item.note.isNotEmpty) {
        await SunmiPrinter.printText(
          '     Ghi chú: ${item.note}',
          style: SunmiTextStyle(fontSize: 20),
        );
      }
      if (item.discountPercent > 0) {
        await SunmiPrinter.printText(
          '     Giảm giá: ${item.discountPercent.toStringAsFixed(0)}%',
          style: SunmiTextStyle(fontSize: 20),
        );
      }
    }

    await SunmiPrinter.printText(separator);
  }

  static List<String> _wrapText(String text, int width) {
    final words = text.trim().split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';

    for (final word in words) {
      if (word.length > width) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        for (var i = 0; i < word.length; i += width) {
          final end = i + width < word.length ? i + width : word.length;
          lines.add(word.substring(i, end));
        }
        continue;
      }

      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= width) {
        current = candidate;
      } else {
        lines.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) lines.add(current);
    return lines.isEmpty ? [''] : lines;
  }

  static String _fitLeft(String text, int width) {
    final value = text.length > width ? text.substring(0, width) : text;
    return value.padRight(width);
  }

  static String _fitRight(String text, int width) {
    final value = text.length > width ? text.substring(text.length - width) : text;
    return value.padLeft(width);
  }

  static String _getPaymentMethodName(String method) {
    switch (method) {
      case 'cash':
        return 'Tiền mặt';
      case 'qr_code':
        return 'Chuyển khoản';
      case 'card':
        return 'Quẹt thẻ';
      default:
        return method;
    }
  }
}
