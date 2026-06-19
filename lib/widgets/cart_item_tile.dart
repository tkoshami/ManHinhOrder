import 'package:flutter/material.dart';
import '../models.dart';
import '../constants.dart';

class CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onTap;

  const CartItemTile({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (item.discountPercent > 0) ...[
                    Text(
                      appCurrencyFormat.format(item.product.price),
                      style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '-${item.discountPercent.toStringAsFixed(0)}%  →  ${appCurrencyFormat.format(item.product.price * (1 - item.discountPercent / 100))}',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ] else
                    Text(
                      appCurrencyFormat.format(item.product.price),
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  if (item.note.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.sticky_note_2, size: 12, color: Colors.orange),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.note,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontStyle: FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onDecrement,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onIncrement,
                    ),
                  ],
                ),
                Text(
                  appCurrencyFormat.format(item.total),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
