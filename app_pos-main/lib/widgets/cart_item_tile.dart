import 'package:flutter/material.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/data/constants.dart';

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
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(appCurrencyFormat.format(item.product.price), style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
            onPressed: onDecrement,
          ),
          Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 20),
            onPressed: onIncrement,
          ),
          const SizedBox(width: 8),
          Text(
            appCurrencyFormat.format(item.total),
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
