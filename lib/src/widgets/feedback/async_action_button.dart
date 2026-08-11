import 'package:flutter/material.dart';

class AsyncActionButton extends StatelessWidget {
  const AsyncActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
    this.destructive = false,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox.square(
      dimension: 17,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: filled ? Colors.white : null,
      ),
    );
    final action = busy ? null : onPressed;
    final button = filled
        ? FilledButton.icon(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: action,
            icon: busy ? indicator : Icon(icon),
            label: Text(busy ? 'Working…' : label),
          )
        : OutlinedButton.icon(
            style: destructive
                ? OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: action,
            icon: busy ? indicator : Icon(icon),
            label: Text(busy ? 'Working…' : label),
          );
    if (!busy) {
      return button;
    }
    return Semantics(
      liveRegion: true,
      button: true,
      enabled: false,
      label: '$label in progress',
      child: ExcludeSemantics(child: button),
    );
  }
}
