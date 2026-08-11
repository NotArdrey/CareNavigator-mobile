import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    final arm = size * 0.38;
    return Semantics(
      label: 'CareNavigator PH',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: arm,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(size * 0.14),
              ),
            ),
            Container(
              width: size,
              height: arm,
              decoration: BoxDecoration(
                color: const Color(0xFF16B8AD),
                borderRadius: BorderRadius.circular(size * 0.14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The larger, friendlier mark used on authentication screens.
class CareHeartMark extends StatelessWidget {
  const CareHeartMark({super.key, this.size = 78});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'CareNavigator PH',
    image: true,
    child: CustomPaint(
      size: Size.square(size),
      painter: const _CareHeartPainter(),
    ),
  );
}

class _CareHeartPainter extends CustomPainter {
  const _CareHeartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final teal = Paint()
      ..color = AppColors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final heart = Path()
      ..moveTo(size.width * .50, size.height * .85)
      ..cubicTo(
        size.width * .18,
        size.height * .66,
        size.width * .08,
        size.height * .38,
        size.width * .20,
        size.height * .20,
      )
      ..cubicTo(
        size.width * .31,
        size.height * .04,
        size.width * .47,
        size.height * .12,
        size.width * .50,
        size.height * .25,
      )
      ..cubicTo(
        size.width * .56,
        size.height * .10,
        size.width * .76,
        size.height * .06,
        size.width * .84,
        size.height * .24,
      )
      ..cubicTo(
        size.width * .94,
        size.height * .47,
        size.width * .76,
        size.height * .70,
        size.width * .50,
        size.height * .85,
      );
    canvas.drawPath(heart, teal);

    final cross = Paint()..color = AppColors.brand;
    final radius = Radius.circular(size.width * .025);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * .48, size.height * .47),
          width: size.width * .13,
          height: size.height * .34,
        ),
        radius,
      ),
      cross,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * .48, size.height * .47),
          width: size.width * .34,
          height: size.height * .13,
        ),
        radius,
      ),
      cross,
    );
    canvas.drawCircle(
      Offset(size.width * .74, size.height * .55),
      size.width * .065,
      Paint()..color = const Color(0xFF16B8AD),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.compact = false, this.onDark = false});

  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white : AppColors.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: compact ? 26 : 34),
        SizedBox(width: compact ? 8 : 10),
        Flexible(
          child: Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: color,
                fontSize: compact ? 15 : 18,
              ),
              children: [
                const TextSpan(text: 'CareNavigator '),
                TextSpan(
                  text: 'PH',
                  style: TextStyle(
                    color: onDark ? const Color(0xFF8FE7DE) : AppColors.brand,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
          ),
        ),
      ],
    );
  }
}
