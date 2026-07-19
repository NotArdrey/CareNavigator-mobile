import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Shared top-level header for authenticated CareNavigator workspaces.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    required this.title,
    required this.subtitle,
    this.icon,
    this.leading,
    this.onBack,
    this.backTooltip,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onBack;
  final String? backTooltip;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: Container(
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE0E8F2))),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              tooltip: backTooltip ?? 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 7),
          ],
          leading ??
              CircleAvatar(
                backgroundColor: const Color(0xFFE8F1FD),
                foregroundColor: AppColors.blue,
                child: Icon(icon ?? Icons.health_and_safety_rounded),
              ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    ),
  );
}
