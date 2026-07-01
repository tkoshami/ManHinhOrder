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
    final uri = Uri.tryParse(trimmedUrl);

    if (trimmedUrl.isEmpty ||
        uri == null ||
        (uri.hasScheme && !uri.hasAuthority) ||
        (!trimmedUrl.startsWith('assets/') &&
            uri.hasScheme &&
            uri.scheme != 'http' &&
            uri.scheme != 'https') ||
        (!trimmedUrl.startsWith('assets/') && !uri.hasScheme)) {
      return _buildFallback(context, ArgumentError('Invalid image URL'), null);
    }

    if (trimmedUrl.startsWith('assets/')) {
      return Image.asset(
        trimmedUrl,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: _buildFallback,
      );
    }

    return Image.network(
      trimmedUrl,
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      errorBuilder: _buildFallback,
    );
  }

  Widget _buildFallback(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return const Center(child: Icon(Icons.image));
  }
}
