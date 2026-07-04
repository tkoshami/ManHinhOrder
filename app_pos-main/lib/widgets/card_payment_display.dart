import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CardPaymentDisplay extends StatefulWidget {
  final double amount;
  final Function(String brand, String lastFour, String holderName) onPaymentSuccess;

  const CardPaymentDisplay({
    super.key,
    required this.amount,
    required this.onPaymentSuccess,
  });

  @override
  State<CardPaymentDisplay> createState() => _CardPaymentDisplayState();
}

class _CardPaymentDisplayState extends State<CardPaymentDisplay> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _expiryDateController = TextEditingController();
  final _securityCodeController = TextEditingController();
  final _nameOnCardController = TextEditingController();
  final _zipCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cardNumberController.addListener(() => setState(() {}));
    _expiryDateController.addListener(() => setState(() {}));
    _nameOnCardController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryDateController.dispose();
    _securityCodeController.dispose();
    _nameOnCardController.dispose();
    _zipCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

    String cleanNumber = _cardNumberController.text.replaceAll(' ', '');
    String lastFour = cleanNumber.length >= 4 
        ? cleanNumber.substring(cleanNumber.length - 4) 
        : cleanNumber;
    String brand = _getBrandName(cleanNumber);
    String holderName = _nameOnCardController.text.toUpperCase();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'Thanh toán hóa đơn',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              _buildVisualCard(brand, cleanNumber, holderName),
              
              const SizedBox(height: 24),
              const Text(
                'Số tiền thanh toán',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              Text(
                currencyFormat.format(widget.amount),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 20),
              _buildTextField(
                label: 'Tên trên thẻ',
                controller: _nameOnCardController,
                hint: 'NGUYEN VAN A',
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                ],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Vui lòng nhập tên chủ thẻ';
                  if (value.length < 3) return 'Tên quá ngắn';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: 'Số thẻ',
                controller: _cardNumberController,
                hint: '0000 0000 0000 0000',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _CardNumberFormatter(),
                  LengthLimitingTextInputFormatter(19),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Vui lòng nhập số thẻ';
                  String clean = value.replaceAll(' ', '');
                  if (clean.length < 13) return 'Số thẻ không hợp lệ';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'Ngày hết hạn',
                      controller: _expiryDateController,
                      hint: 'MM / YY',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _ExpiryDateFormatter(),
                        LengthLimitingTextInputFormatter(7),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Bắt buộc';
                        String clean = value.replaceAll(' ', '');
                        if (clean.length < 5) return 'Sai định dạng';
                        
                        List<String> parts = clean.split('/');
                        int month = int.tryParse(parts[0]) ?? 0;
                        int year = int.tryParse('20${parts[1].trim()}') ?? 0;
                        
                        if (month < 1 || month > 12) return 'Tháng 01-12';
                        
                        DateTime now = DateTime.now();
                        DateTime cardDate = DateTime(year, month + 1, 0); // Last day of month
                        if (cardDate.isBefore(DateTime(now.year, now.month, 1))) return 'Thẻ đã hết hạn';
                        
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      label: 'Mã bảo mật',
                      controller: _securityCodeController,
                      hint: 'CVV',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Bắt buộc';
                        if (value.length < 3) return '3-4 số';
                        return null;
                      },
                      suffixIcon: const Tooltip(
                        message: 'Mã bảo mật (CVV/CVC) gồm 3 hoặc 4 chữ số thường nằm ở mặt sau thẻ.',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Icon(Icons.help_outline, size: 20, color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: 'Mã bưu chính (ZIP/Postal code)',
                controller: _zipCodeController,
                hint: '10000',
                keyboardType: TextInputType.number,
                inputFormatters: [
                   FilteringTextInputFormatter.digitsOnly,
                   LengthLimitingTextInputFormatter(5),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Vui lòng nhập ZIP code';
                  if (value.length < 5) return 'Phải có 5 chữ số';
                  return null;
                },
                suffixIcon: const Tooltip(
                  message: 'Mã bưu chính của khu vực (Ví dụ: 70000).',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Icon(Icons.help_outline, size: 20, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      widget.onPaymentSuccess(brand, lastFour, holderName);
                    }
                  },
                  icon: const Icon(Icons.lock, size: 18),
                  label: Text(
                    'THANH TOÁN ${currencyFormat.format(widget.amount)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4DB6AC),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisualCard(String brand, String cleanNumber, String name) {
    String cardNumber = _cardNumberController.text.isEmpty ? '**** **** **** ****' : _cardNumberController.text;
    String expiry = _expiryDateController.text.isEmpty ? 'MM/YY' : _expiryDateController.text;
    String displayName = name.isEmpty ? 'TEN CHU THE' : name;

    // Dynamic Colors based on Card Type
    List<Color> cardColors = [const Color(0xFF434343), const Color(0xFF000000)]; // Default Black
    
    if (brand == 'VISA') {
      cardColors = [const Color(0xFF2E3192), const Color(0xFF1BFFFF)];
    } else if (brand == 'MasterCard') {
      cardColors = [const Color(0xFFED213A), const Color(0xFF93291E)];
    } else if (brand == 'AMEX') {
      cardColors = [const Color(0xFF11998e), const Color(0xFF38ef7d)];
    } else if (brand == 'DISCOVER') {
      cardColors = [const Color(0xFFf8ff00), const Color(0xFFf8c102)];
    }

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: cardColors,
          ),
          boxShadow: [
            BoxShadow(
              color: cardColors.first.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Opacity(
                opacity: 0.1,
                child: Icon(Icons.credit_card, size: 150, color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'MarPOS Bank',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      _buildBrandLogo(brand, Colors.white),
                    ],
                  ),
                  Container(
                    width: 45,
                    height: 35,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.8),
                      borderRadius: BorderRadius.circular(6),
                      gradient: LinearGradient(
                        colors: [Colors.yellow.shade200, Colors.orange.shade300],
                      ),
                    ),
                  ),
                  Text(
                    cardNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2.5,
                      fontFamily: 'Courier',
                      shadows: [Shadow(blurRadius: 2, color: Colors.black26)],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CHỦ THẺ',
                            style: TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'HẾT HẠN',
                            style: TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                          Text(
                            expiry,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getBrandName(String number) {
    if (number.startsWith('4')) return 'VISA';
    if (number.startsWith('5')) return 'MasterCard';
    if (number.startsWith('3')) return 'AMEX';
    if (number.startsWith('6')) return 'DISCOVER';
    return 'CARD';
  }

  Widget _buildBrandLogo(String brand, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        brand,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            suffixIcon: suffixIcon,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.orange, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.orange, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.orange, width: 2.2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (newValue.selection.baseOffset == 0) return newValue;
    String digitsOnly = text.replaceAll(' ', '');
    var buffer = StringBuffer();
    for (int i = 0; i < digitsOnly.length; i++) {
      buffer.write(digitsOnly[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != digitsOnly.length) {
        buffer.write(' ');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (newValue.selection.baseOffset == 0) return newValue;
    
    String digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (digitsOnly.isNotEmpty) {
      int firstDigit = int.parse(digitsOnly[0]);
      if (firstDigit > 1) {
        digitsOnly = '0' + digitsOnly;
      }
    }
    
    if (digitsOnly.length >= 2) {
      int month = int.parse(digitsOnly.substring(0, 2));
      if (month > 12) {
        digitsOnly = '12' + digitsOnly.substring(2);
      } else if (month == 0 && digitsOnly.length == 2) {
         return oldValue;
      }
    }

    var buffer = StringBuffer();
    for (int i = 0; i < digitsOnly.length; i++) {
      buffer.write(digitsOnly[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 2 == 0 && nonZeroIndex != digitsOnly.length && i < 2) {
        buffer.write(' / ');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}
