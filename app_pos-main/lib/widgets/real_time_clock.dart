import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RealTimeClock extends StatelessWidget {
  final Color color;
  final double fontSize;

  const RealTimeClock({
    super.key,
    this.color = Colors.white,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        final timeStr = DateFormat('HH:mm:ss').format(snapshot.data ?? DateTime.now());
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time, size: fontSize + 4, color: color),
            const SizedBox(width: 6),
            Text(
              timeStr,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
                fontFamily: 'monospace', // Monospace helps to keep width stable
              ),
            ),
          ],
        );
      },
    );
  }
}
