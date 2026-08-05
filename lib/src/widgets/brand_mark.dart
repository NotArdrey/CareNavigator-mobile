import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false, this.inverse = false});

  final bool compact;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'CareNavigator PH',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 44 : 46,
            height: compact ? 44 : 46,
            decoration: BoxDecoration(
              color: AppColors.forest,
              borderRadius: BorderRadius.circular(AppRadius.extraLarge),
            ),
            child: const Icon(
              AppIcons.navigation,
              color: Colors.white,
              size: 27,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Care Navigator',
                  style: TextStyle(
                    color: inverse ? Colors.white : AppColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.55,
                  ),
                ),
                Text(
                  'PHILIPPINES',
                  style: TextStyle(
                    color: inverse ? AppColors.sunflower : AppColors.forest,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.65,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
