import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class ProductImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl.trim();

    if (trimmedUrl.isEmpty) {
      return _buildFallback(context, ArgumentError('Empty image URL'), null);
    }

    // Ảnh có sẵn trong assets của app
    if (trimmedUrl.startsWith('assets/')) {
      return Image.asset(
        trimmedUrl,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: _buildFallback,
      );
    }

    // Ảnh network (http/https)
    final uri = Uri.tryParse(trimmedUrl);
    final isNetwork = uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.hasAuthority;

    if (isNetwork) {
      return Image.network(
        trimmedUrl,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        errorBuilder: _buildFallback,
      );
    }

    // Ảnh chọn từ thư viện / chụp bằng camera (đường dẫn file local)
    // Không áp dụng trên Flutter Web
    if (!kIsWeb) {
      final file = File(trimmedUrl);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          width: width,
          height: height,
          cacheWidth: cacheWidth,
          errorBuilder: _buildFallback,
        );
      }
    }

    return _buildFallback(context, ArgumentError('Invalid image URL'), null);
  }

  Widget _buildFallback(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
      ) {
    return Container(
      color: Colors.grey[100],
      child: const Center(
        child: Icon(Icons.image, color: Colors.grey, size: 32),
      ),
    );
  }
}