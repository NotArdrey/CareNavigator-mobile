import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

class HospitalImage extends StatelessWidget {
  const HospitalImage({
    super.key,
    this.imageUrl,
    this.height = 160,
    this.width = double.infinity,
    this.borderRadius = AppRadius.panel,
    this.semanticLabel = 'Hospital exterior',
  });

  final String? imageUrl;
  final double height;
  final double width;
  final double borderRadius;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final publishedUrl = imageUrl?.trim();
    final fallback = Container(
      width: width,
      height: height,
      color: AppColors.surfaceMuted,
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_hospital_outlined,
        size: 36,
        color: AppColors.textMuted,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: !_isUsableNetworkUrl(publishedUrl)
          ? fallback
          : Image.network(
              publishedUrl!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              semanticLabel: semanticLabel,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

bool _isUsableNetworkUrl(String? value) {
  if (value == null || value.isEmpty) return false;
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.hasAuthority &&
      (uri.scheme == 'https' || uri.scheme == 'http');
}
