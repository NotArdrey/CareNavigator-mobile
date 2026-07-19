import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:flutter/material.dart';

class HospitalImage extends StatelessWidget {
  const HospitalImage({
    required this.hospital,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
    super.key,
  });

  final Hospital hospital;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      hospital.fallbackImageAsset,
      width: width,
      height: height,
      fit: BoxFit.cover,
      semanticLabel: '${hospital.capabilityLabel} hospital exterior',
    );
    final imageUrl = hospital.imageUrl?.trim() ?? '';

    return ClipRRect(
      borderRadius: borderRadius,
      child: imageUrl.isEmpty
          ? fallback
          : Image.network(
              imageUrl,
              width: width,
              height: height,
              fit: BoxFit.cover,
              semanticLabel: '${hospital.name} exterior',
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) return child;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    fallback,
                    ColoredBox(color: Colors.white.withValues(alpha: 0.20)),
                    const Center(child: CircularProgressIndicator()),
                  ],
                );
              },
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
