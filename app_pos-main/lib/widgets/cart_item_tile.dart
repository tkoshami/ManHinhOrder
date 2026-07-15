import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_fnb/data/constants.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/widgets/product_image.dart';

class CartItemTile extends StatefulWidget {
  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onTap;
  final Function(int)? onQuantityChanged;

  const CartItemTile({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onTap,
    this.onQuantityChanged,
  });

  @override
  State<CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends State<CartItemTile> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.item.quantity}');
  }

  @override
  void didUpdateWidget(covariant CartItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.quantity != oldWidget.item.quantity) {
      if (_controller.text != '${widget.item.quantity}') {
        _controller.text = '${widget.item.quantity}';
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: widget.onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ProductImage(
          imageUrl: widget.item.product.imageUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      ),
      title: Text(
        widget.item.product.name,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(
        appCurrencyFormat.format(widget.item.product.price),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(
              Icons.remove_circle_outline,
              color: Colors.red,
              size: 20,
            ),
            onPressed: widget.onDecrement,
          ),
          SizedBox(
            width: 45,
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                signed: false,
                decimal: false,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Colors.black54, width: 1.2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Colors.black54, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Colors.green, width: 2.0),
                ),
              ),
              onChanged: (v) {
                  if (v.isEmpty || v == '0') {
                    widget.onQuantityChanged?.call(0);
                  } else {
                    final val = int.tryParse(v) ?? 0;
                    if (val > 100) {
                      _controller.text = '100';
                      _controller.selection = TextSelection.fromPosition(
                        const TextPosition(offset: 3),
                      );
                      widget.onQuantityChanged?.call(100);
                    } else {
                      widget.onQuantityChanged?.call(val);
                    }
                  }
                },
              ),
            ),
          IconButton(
            icon: const Icon(
              Icons.add_circle_outline,
              color: Colors.green,
              size: 20,
            ),
            onPressed: widget.onIncrement,
          ),
          const SizedBox(width: 8),
          Text(
            appCurrencyFormat.format(widget.item.total),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
