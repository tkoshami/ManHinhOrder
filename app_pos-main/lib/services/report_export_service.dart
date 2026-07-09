import 'package:excel/excel.dart' as xls;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import 'Report_export_platform_stub.dart'
if (dart.library.io) 'Report_export_platform_io.dart'
if (dart.library.html) 'Report_export_platform_web.dart';

class ReportExportService {
  static final _numFormat = NumberFormat.decimalPattern('vi_VN');

  static String _fmtNum(num v) {
    final d = v.toDouble();
    return d == d.roundToDouble()
        ? _numFormat.format(d.round())
        : _numFormat.format(d);
  }

  // ─────────────────────────────────────
  // XUẤT EXCEL
  // ─────────────────────────────────────
  static Future<String?> exportExcel({
    required List<Map<String, dynamic>> rows,
    required DateTime from,
    required DateTime to,
  }) async {
    final book = xls.Excel.createExcel();
    final sheet = book['Tồn kho'];
    book.setDefaultSheet('Tồn kho');

    final headerStyle = xls.CellStyle(
      bold: true,
      horizontalAlign: xls.HorizontalAlign.Center,
      verticalAlign: xls.VerticalAlign.Center,
    );

    // Tiêu đề
    sheet.merge(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        xls.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 0));
    sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
      ..value = xls.TextCellValue('BẢNG TỔNG HỢP NHẬP XUẤT TỒN')
      ..cellStyle = headerStyle;

    sheet.merge(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
        xls.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 1));
    sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
        xls.TextCellValue(
            'Từ ngày ${DateFormat('dd/MM/yyyy').format(from)} đến ${DateFormat('dd/MM/yyyy').format(to)}');

    // Header nhóm cột (dòng 3)
    const groupLabels = ['Tồn đầu', 'Nhập', 'Xuất', 'Tồn'];
    int col = 3;
    for (final label in groupLabels) {
      sheet.merge(
        xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 3),
        xls.CellIndex.indexByColumnRow(columnIndex: col + 1, rowIndex: 3),
      );
      sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 3))
        ..value = xls.TextCellValue(label)
        ..cellStyle = headerStyle;
      col += 2;
    }

    // Header chi tiết (dòng 4)
    final subHeaders = [
      'STT', 'Tên hàng hóa', 'ĐVT',
      'Số lượng', 'Số tiền', // Tồn đầu
      'Số lượng', 'Số tiền', // Nhập
      'Số lượng', 'Số tiền', // Xuất
      'Số lượng', 'Số tiền', // Tồn
      'Đơn giá',
    ];
    for (int i = 0; i < subHeaders.length; i++) {
      sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 4))
        ..value = xls.TextCellValue(subHeaders[i])
        ..cellStyle = headerStyle;
    }

    // Dòng "Cộng"
    num sumOpenQty = 0, sumOpenVal = 0, sumInQty = 0, sumInVal = 0;
    num sumOutQty = 0, sumOutVal = 0, sumCloseQty = 0, sumCloseVal = 0;
    for (final r in rows) {
      sumOpenQty += (r['opening_qty'] as num? ?? 0);
      sumOpenVal += (r['opening_value'] as num? ?? 0);
      sumInQty += (r['in_qty'] as num? ?? 0);
      sumInVal += (r['in_value'] as num? ?? 0);
      sumOutQty += (r['out_qty'] as num? ?? 0);
      sumOutVal += (r['out_value'] as num? ?? 0);
      sumCloseQty += (r['closing_qty'] as num? ?? 0);
      sumCloseVal += (r['closing_value'] as num? ?? 0);
    }

    int rowIdx = 5;
    void setCell(int c, int r, dynamic val, {bool bold = false}) {
      final cell = sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
      cell.value = val is String ? xls.TextCellValue(val) : xls.TextCellValue(val.toString());
      if (bold) cell.cellStyle = xls.CellStyle(bold: true);
    }

    setCell(1, rowIdx, 'Cộng', bold: true);
    setCell(3, rowIdx, _fmtNum(sumOpenQty), bold: true);
    setCell(4, rowIdx, _fmtNum(sumOpenVal), bold: true);
    setCell(5, rowIdx, _fmtNum(sumInQty), bold: true);
    setCell(6, rowIdx, _fmtNum(sumInVal), bold: true);
    setCell(7, rowIdx, _fmtNum(sumOutQty), bold: true);
    setCell(8, rowIdx, _fmtNum(sumOutVal), bold: true);
    setCell(9, rowIdx, _fmtNum(sumCloseQty), bold: true);
    setCell(10, rowIdx, _fmtNum(sumCloseVal), bold: true);
    rowIdx++;

    // Chi tiết từng mặt hàng
    int stt = 1;
    for (final r in rows) {
      setCell(0, rowIdx, stt.toString());
      setCell(1, rowIdx, r['name']?.toString() ?? '');
      setCell(2, rowIdx, r['unit']?.toString() ?? '');
      setCell(3, rowIdx, _fmtNum(r['opening_qty'] as num? ?? 0));
      setCell(4, rowIdx, _fmtNum(r['opening_value'] as num? ?? 0));
      setCell(5, rowIdx, _fmtNum(r['in_qty'] as num? ?? 0));
      setCell(6, rowIdx, _fmtNum(r['in_value'] as num? ?? 0));
      setCell(7, rowIdx, _fmtNum(r['out_qty'] as num? ?? 0));
      setCell(8, rowIdx, _fmtNum(r['out_value'] as num? ?? 0));
      setCell(9, rowIdx, _fmtNum(r['closing_qty'] as num? ?? 0));
      setCell(10, rowIdx, _fmtNum(r['closing_value'] as num? ?? 0));
      setCell(11, rowIdx, _fmtNum(r['unit_price'] as num? ?? 0));
      rowIdx++;
      stt++;
    }

    final bytes = book.encode();
    if (bytes == null) return null;

    final fileName =
        'ton_kho_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.xlsx';
    return saveExportedFile(bytes, fileName);
  }

  // ─────────────────────────────────────
  // XUẤT PDF
  // ─────────────────────────────────────
  static Future<String?> exportPdf({
    required List<Map<String, dynamic>> rows,
    required DateTime from,
    required DateTime to,
  }) async {
    final doc = pw.Document();

    final headers = [
      'STT', 'Tên hàng hóa', 'ĐVT',
      'SL đầu', 'Tiền đầu', 'SL nhập', 'Tiền nhập',
      'SL xuất', 'Tiền xuất', 'SL tồn', 'Tiền tồn', 'Đơn giá',
    ];

    final data = rows.asMap().entries.map((e) {
      final i = e.key + 1;
      final r = e.value;
      return [
        '$i',
        r['name']?.toString() ?? '',
        r['unit']?.toString() ?? '',
        _fmtNum(r['opening_qty'] as num? ?? 0),
        _fmtNum(r['opening_value'] as num? ?? 0),
        _fmtNum(r['in_qty'] as num? ?? 0),
        _fmtNum(r['in_value'] as num? ?? 0),
        _fmtNum(r['out_qty'] as num? ?? 0),
        _fmtNum(r['out_value'] as num? ?? 0),
        _fmtNum(r['closing_qty'] as num? ?? 0),
        _fmtNum(r['closing_value'] as num? ?? 0),
        _fmtNum(r['unit_price'] as num? ?? 0),
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Center(
            child: pw.Text('BẢNG TỔNG HỢP NHẬP XUẤT TỒN',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Center(
            child: pw.Text(
                'Từ ngày ${DateFormat('dd/MM/yyyy').format(from)} đến ${DateFormat('dd/MM/yyyy').format(to)}'),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
            },
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final fileName =
        'ton_kho_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.pdf';
    return saveExportedFile(bytes, fileName);
  }
}