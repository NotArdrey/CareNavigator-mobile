import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:care_navigator_ph/src/design_system/app_icons.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';

class AsyncValuePanel<T> extends StatelessWidget {
  const AsyncValuePanel({
    required this.value,
    required this.data,
    required this.onRetry,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T value) data;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const AppLoadingState(),
      error: (error, stackTrace) => AppStatePanel(
        kind: AppStateKind.error,
        icon: AppIcons.cloudOffRounded,
        title: 'Unable to load this information',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(AppIcons.refreshRounded),
          label: const Text('Try again'),
        ),
      ),
    );
  }
}
