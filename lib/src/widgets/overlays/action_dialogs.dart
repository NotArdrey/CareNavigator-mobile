import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../routing/root_overlay.dart';

Future<bool> confirmRootAction({
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showRootDialog<bool>(
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: Icon(
        destructive ? Icons.warning_amber_outlined : Icons.help_outline,
        color: destructive ? AppColors.destructive : AppColors.primary,
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.destructive)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> requestDecisionNote({
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  int minimumLength = 5,
}) => showRootDialog<String>(
  barrierDismissible: false,
  builder: (context) => _DecisionNoteDialog(
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    destructive: destructive,
    minimumLength: minimumLength,
  ),
);

Future<DateTime?> requestRootDateTime({
  required DateTime initial,
  DateTime? minimum,
}) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return null;
  final today = DateUtils.dateOnly(DateTime.now());
  final minimumDate = minimum == null ? today : DateUtils.dateOnly(minimum);
  final firstDate = minimumDate.isAfter(today) ? minimumDate : today;
  final lastDate = today.add(const Duration(days: 365));
  final effectiveInitial = minimum != null && initial.isBefore(minimum)
      ? minimum.add(const Duration(minutes: 1))
      : initial;
  final requestedDate = DateUtils.dateOnly(effectiveInitial);
  final initialDate = requestedDate.isBefore(firstDate)
      ? firstDate
      : requestedDate.isAfter(lastDate)
      ? lastDate
      : requestedDate;
  final date = await showDatePicker(
    context: context,
    useRootNavigator: true,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: 'Select appointment date',
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    useRootNavigator: true,
    initialTime: TimeOfDay.fromDateTime(effectiveInitial),
    helpText: 'Select appointment time',
  );
  if (time == null || !context.mounted) return null;
  final selected = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (minimum != null && selected.isBefore(minimum)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Choose a reservation time at least 24 hours from now.'),
      ),
    );
    return null;
  }
  return selected;
}

class _DecisionNoteDialog extends StatefulWidget {
  const _DecisionNoteDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    required this.minimumLength,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final int minimumLength;

  @override
  State<_DecisionNoteDialog> createState() => _DecisionNoteDialogState();
}

class _DecisionNoteDialogState extends State<_DecisionNoteDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        widget.destructive ? Icons.gavel_outlined : Icons.approval_outlined,
        color: widget.destructive ? AppColors.destructive : AppColors.primary,
      ),
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.message),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Decision note',
                  alignLabelWithHint: true,
                ),
                validator: (value) =>
                    (value?.trim().length ?? 0) < widget.minimumLength
                    ? 'Enter at least ${widget.minimumLength} characters.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.destructive)
              : null,
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(_controller.text.trim());
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
