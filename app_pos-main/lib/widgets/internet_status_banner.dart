import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pos_fnb/services/connectivity_probe.dart';

class InternetStatusBanner extends StatefulWidget {
  final Widget child;

  const InternetStatusBanner({super.key, required this.child});

  @override
  State<InternetStatusBanner> createState() => _InternetStatusBannerState();
}

class _InternetStatusBannerState extends State<InternetStatusBanner> {
  Timer? _timer;
  bool _isOffline = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkConnection(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    if (_isChecking) return;
    _isChecking = true;

    final hasConnection = await hasInternetConnection();
    if (mounted && _isOffline == hasConnection) {
      setState(() => _isOffline = !hasConnection);
    }

    _isChecking = false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: AnimatedSlide(
              offset: _isOffline ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _isOffline ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Material(
                  color: Colors.red.shade700,
                  elevation: 8,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off, color: Colors.white, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Không có kết nối Internet. Vui lòng kiểm tra mạng trước khi tiếp tục thao tác.',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
