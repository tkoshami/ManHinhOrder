import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

class PrintService {
  static final currencyFormat = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'd',
  );

  static Future<void> printBill(SavedOrder order) async {
    await SunmiPrinter.printText(
      'MAR POS - F&B',
      style: SunmiTextStyle(
        align: SunmiPrintAlign.CENTER,
        bold: true,
        fontSize: 36,
      ),
    );
    await SunmiPrinter.printText(
      'Dia chi: 123 Duong ABC, Quan 1, TP.HCM',
      style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 24),
    );
    await SunmiPrinter.printText(
      'Hotline: 0123 456 789',
      style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 24),
    );

    await SunmiPrinter.lineWrap(1);
    await SunmiPrinter.printText(
      'HOA DON THANH TOAN',
      style: SunmiTextStyle(
        align: SunmiPrintAlign.CENTER,
        bold: true,
        fontSize: 30,
      ),
    );
    await SunmiPrinter.lineWrap(1);

    await SunmiPrinter.printText('Ma don: ${order.id ?? ''}');
    await SunmiPrinter.printText(
      'Ngay: ${DateFormat('dd/MM/yyyy HH:mm').format(order.dateTime)}',
    );
    await SunmiPrinter.printText('Loai: ${order.tableOrCustomer}');
    await SunmiPrinter.printText(
      'PTTT: ${_getPaymentMethodName(order.paymentMethod)}',
    );

    await SunmiPrinter.line();
    await SunmiPrinter.printRow(
      cols: [
        _column('Ten mon', 15, SunmiPrintAlign.LEFT),
        _column('SL', 5, SunmiPrintAlign.CENTER),
        _column('T.Tien', 10, SunmiPrintAlign.RIGHT),
      ],
    );
    await SunmiPrinter.line();

    for (final item in order.items) {
      await SunmiPrinter.printRow(
        cols: [
          _column(item.product.name, 15, SunmiPrintAlign.LEFT),
          _column('x${item.quantity}', 5, SunmiPrintAlign.CENTER),
          _column(currencyFormat.format(item.total), 10, SunmiPrintAlign.RIGHT),
        ],
      );

      if (item.note.isNotEmpty) {
        await SunmiPrinter.printText(
          ' - Ghi chu: ${item.note}',
          style: SunmiTextStyle(fontSize: 20),
        );
      }
      if (item.discountPercent > 0) {
        await SunmiPrinter.printText(
          ' - Giam gia: ${item.discountPercent.toStringAsFixed(0)}%',
          style: SunmiTextStyle(fontSize: 20),
        );
      }
    }

    await SunmiPrinter.line();
    await SunmiPrinter.printRow(
      cols: [
        _column('Tam tinh:', 15, SunmiPrintAlign.LEFT),
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
        _column('TONG CONG:', 15, SunmiPrintAlign.LEFT, bold: true),
        _column(
          currencyFormat.format(order.totalAmount),
          15,
          SunmiPrintAlign.RIGHT,
          bold: true,
        ),
      ],
    );

    await SunmiPrinter.lineWrap(2);
    await SunmiPrinter.printText(
      'Cam on Quy khach. Hen gap lai!',
      style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, italic: true),
    );

    if (order.id != null) {
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printQRCode(
        order.id!,
        style: SunmiQrcodeStyle(align: SunmiPrintAlign.CENTER),
      );
    }

    await SunmiPrinter.lineWrap(4);
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

  static String _getPaymentMethodName(String method) {
    switch (method) {
      case 'cash':
        return 'Tien mat';
      case 'qr_code':
        return 'Chuyen khoan';
      case 'card':
        return 'Quet the';
      default:
        return method;
    }
  }
}
