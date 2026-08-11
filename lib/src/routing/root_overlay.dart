import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'care-navigator-root',
);

Future<T?> showRootDialog<T>({
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool escapeDismissible = true,
}) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return Future<T?>.value();
  final previousFocus = FocusManager.instance.primaryFocus;
  try {
    return await showDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: barrierDismissible,
      barrierColor: Theme.of(context).colorScheme.scrim,
      requestFocus: true,
      builder: (dialogContext) {
        final dialog = builder(dialogContext);
        if (!escapeDismissible) return dialog;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              Navigator.of(dialogContext).pop();
            },
          },
          child: Focus(autofocus: true, child: dialog),
        );
      },
    );
  } finally {
    _restoreFocus(previousFocus);
  }
}

Future<T?> showRootSheet<T>({
  required WidgetBuilder builder,
  bool showDragHandle = true,
}) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return Future<T?>.value();
  final previousFocus = FocusManager.instance.primaryFocus;
  try {
    return await showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      showDragHandle: showDragHandle,
      barrierColor: Theme.of(context).colorScheme.scrim,
      requestFocus: true,
      builder: builder,
    );
  } finally {
    _restoreFocus(previousFocus);
  }
}

void _restoreFocus(FocusNode? previousFocus) {
  if (previousFocus == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (previousFocus.context != null && previousFocus.canRequestFocus) {
      previousFocus.requestFocus();
    }
  });
}

void showRootMessage(String message) {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
