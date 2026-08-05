import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  bool _updating = false;

  Future<void> _markRead(String id) async {
    setState(() => _updating = true);
    try {
      await ref.read(careRepositoryProvider).markNotificationRead(id);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _markAllRead(List<Map<String, dynamic>> items) async {
    setState(() => _updating = true);
    try {
      for (final item in items.where((item) => item['is_read'] != true)) {
        await ref
            .read(careRepositoryProvider)
            .markNotificationRead(item['id'].toString());
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _preferences() async {
    final client = ref.read(supabaseClientProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    var email = false;
    var reminders = true;
    try {
      final current = await client
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (current != null) {
        // External channels are opt-in. A missing preferences row must not
        // silently enqueue deliveries to providers that may not be configured.
        email = current['email_enabled'] == true;
        reminders = current['appointment_reminders'] != false;
      }
    } catch (_) {
      // The dialog still presents safe defaults if no preference row exists.
    }
    if (!mounted) return;
    final values = await showDialog<Map<String, bool>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Notification preferences'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  value: email,
                  onChanged: (value) => setDialogState(() => email = value),
                  title: const Text('Email notifications'),
                  subtitle: const Text(
                    'Delivered by the configured email sender.',
                  ),
                ),
                SwitchListTile(
                  value: reminders,
                  onChanged: (value) => setDialogState(() => reminders = value),
                  title: const Text('Appointment reminders'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'email_enabled': email,
                'appointment_reminders': reminders,
              }),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (values == null) return;
    try {
      await client.from('notification_preferences').upsert({
        'user_id': userId,
        ...values,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification preferences saved.')),
        );
      }
    } catch (error) {
      _error(error);
    }
  }

  void _open(Map<String, dynamic> item) {
    final path = item['action_path']?.toString();
    if (path != null && path.startsWith('/')) context.go(path);
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseClientProvider);
    final width = MediaQuery.sizeOf(context).width;
    if (client.auth.currentSession == null) {
      return AppStatePanel(
        kind: AppStateKind.restricted,
        icon: AppIcons.lockPersonOutlined,
        title: 'Sign in required',
        message: 'Sign in to view your private CareNavigator notifications.',
        action: FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Sign in'),
        ),
      );
    }
    final stream = client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
    return SafeArea(
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          final unread = items.where((item) => item['is_read'] != true).length;
          return Column(
            children: [
              AppPageHeader(
                eyebrow: 'PRIVATE CARE INBOX',
                title: 'Updates that need a decision',
                subtitle: '$unread unread · ${items.length} total care updates',
                icon: AppIcons.notificationsRounded,
                onBack: () => context.go('/dashboard'),
                backTooltip: 'Back to my care',
                actions: [
                  IconButton(
                    tooltip: 'Preferences',
                    onPressed: _updating ? null : _preferences,
                    icon: const Icon(AppIcons.tuneRounded),
                  ),
                  if (width < 600)
                    IconButton(
                      tooltip: 'Mark all as read',
                      onPressed: unread == 0 || _updating
                          ? null
                          : () => _markAllRead(items),
                      icon: const Icon(AppIcons.doneAllRounded),
                    )
                  else
                    TextButton.icon(
                      onPressed: unread == 0 || _updating
                          ? null
                          : () => _markAllRead(items),
                      icon: const Icon(AppIcons.doneAllRounded),
                      label: const Text('Mark all read'),
                    ),
                ],
              ),
              Expanded(
                child: snapshot.hasError
                    ? AppStatePanel(
                        kind: AppStateKind.error,
                        icon: AppIcons.cloudOffRounded,
                        title: 'Unable to load notifications',
                        message: snapshot.error.toString(),
                      )
                    : snapshot.connectionState == ConnectionState.waiting
                    ? const AppLoadingState(label: 'Loading notifications')
                    : _NotificationWorkspace(
                        items: items,
                        unread: unread,
                        updating: _updating,
                        onPreferences: _preferences,
                        onMarkAll: unread == 0
                            ? null
                            : () => _markAllRead(items),
                        onMarkRead: _markRead,
                        onOpen: _open,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationWorkspace extends StatelessWidget {
  const _NotificationWorkspace({
    required this.items,
    required this.unread,
    required this.updating,
    required this.onPreferences,
    required this.onMarkAll,
    required this.onMarkRead,
    required this.onOpen,
  });

  final List<Map<String, dynamic>> items;
  final int unread;
  final bool updating;
  final VoidCallback onPreferences;
  final VoidCallback? onMarkAll;
  final Future<void> Function(String id) onMarkRead;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= AppBreakpoints.medium;
      final horizontal = AppPageBody.horizontalPadding(constraints.maxWidth);
      final summary = _NotificationSummary(
        unread: unread,
        total: items.length,
        onPreferences: updating ? null : onPreferences,
        onMarkAll: updating ? null : onMarkAll,
        compact: !desktop,
      );
      final inbox = _NotificationInbox(
        items: items,
        updating: updating,
        onMarkRead: onMarkRead,
        onOpen: onOpen,
      );
      if (!desktop) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.lg,
            horizontal,
            84,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              const SizedBox(height: AppSpacing.md),
              Expanded(child: inbox),
            ],
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(
          horizontal,
          AppSpacing.lg,
          horizontal,
          AppSpacing.xl,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 300, child: summary),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: inbox),
          ],
        ),
      );
    },
  );
}

class _NotificationSummary extends StatelessWidget {
  const _NotificationSummary({
    required this.unread,
    required this.total,
    required this.onPreferences,
    required this.onMarkAll,
    required this.compact,
  });

  final int unread;
  final int total;
  final VoidCallback? onPreferences;
  final VoidCallback? onMarkAll;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
    decoration: BoxDecoration(
      color: AppColors.evergreenDark,
      borderRadius: BorderRadius.circular(AppRadius.extraLarge),
      boxShadow: AppShadows.medium,
    ),
    child: compact
        ? Row(
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.forest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '$unread',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unread care updates',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                    Text(
                      '$total total in your private inbox',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.mist),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Notification preferences',
                onPressed: onPreferences,
                color: Colors.white,
                icon: const Icon(AppIcons.tuneRounded),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppStatusBadge(
                label: 'PRIVATE CARE FEED',
                color: AppColors.mint,
                icon: AppIcons.lockRounded,
                inverse: true,
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                '$unread',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: Colors.white,
                  height: .9,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Unread updates',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$total total events are retained in this care inbox.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.mist),
              ),
              const SizedBox(height: AppSpacing.xxl),
              _SummaryLegend(
                icon: AppIcons.calendarMonthOutlined,
                label: 'Appointments',
              ),
              _SummaryLegend(
                icon: AppIcons.scienceOutlined,
                label: 'Results and records',
              ),
              _SummaryLegend(
                icon: AppIcons.chatBubbleOutlineRounded,
                label: 'Care conversations',
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: onPreferences,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x55FFFFFF)),
                ),
                icon: const Icon(AppIcons.tuneRounded),
                label: const Text('Delivery preferences'),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton.icon(
                onPressed: onMarkAll,
                style: TextButton.styleFrom(foregroundColor: AppColors.mint),
                icon: const Icon(AppIcons.doneAllRounded),
                label: const Text('Mark all as read'),
              ),
            ],
          ),
  );
}

class _SummaryLegend extends StatelessWidget {
  const _SummaryLegend({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      children: [
        Icon(icon, color: AppColors.mint, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.mist,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _NotificationInbox extends StatelessWidget {
  const _NotificationInbox({
    required this.items,
    required this.updating,
    required this.onMarkRead,
    required this.onOpen,
  });
  final List<Map<String, dynamic>> items;
  final bool updating;
  final Future<void> Function(String id) onMarkRead;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const AppCard(
        child: AppEmptyState(
          icon: AppIcons.notificationsNoneRounded,
          title: 'Your care inbox is clear',
          message:
              'Appointments, records, prescriptions, and message updates will be grouped here.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(
          eyebrow: 'LATEST FIRST',
          title: 'Care activity',
          subtitle: 'Unread events stay visually prominent until reviewed.',
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: AppCard(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
              itemBuilder: (context, index) => _NotificationRow(
                item: items[index],
                updating: updating,
                onMarkRead: onMarkRead,
                onOpen: onOpen,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.updating,
    required this.onMarkRead,
    required this.onOpen,
  });
  final Map<String, dynamic> item;
  final bool updating;
  final Future<void> Function(String id) onMarkRead;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) {
    final isUnread = item['is_read'] != true;
    return InkWell(
      onTap: () async {
        if (isUnread) await onMarkRead(item['id'].toString());
        onOpen(item);
      },
      child: Container(
        color: isUnread
            ? AppColors.seaGlass.withValues(alpha: .42)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconTile(
              icon: _icon(item['notification_type']?.toString()),
              color: AppColors.forest,
              size: 42,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['title']?.toString() ?? 'Care update',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: isUnread
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                              ),
                        ),
                      ),
                      if (isUnread)
                        const AppStatusBadge(
                          label: 'NEW',
                          color: AppColors.forest,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(item['message']?.toString() ?? ''),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _time(item['created_at']),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (isUnread)
              IconButton(
                tooltip: 'Mark as read',
                onPressed: updating
                    ? null
                    : () => onMarkRead(item['id'].toString()),
                icon: const Icon(AppIcons.checkCircleOutlineRounded),
              )
            else
              const Icon(AppIcons.arrowOutwardRounded),
          ],
        ),
      ),
    );
  }
}

IconData _icon(String? type) {
  if (type?.contains('message') == true) {
    return AppIcons.chatBubbleOutlineRounded;
  }
  if (type?.contains('prescription') == true) {
    return AppIcons.medicationOutlined;
  }
  if (type?.contains('result') == true) return AppIcons.scienceOutlined;
  if (type?.contains('consultation') == true ||
      type?.contains('appointment') == true) {
    return AppIcons.calendarMonthOutlined;
  }
  if (type?.contains('emergency') == true) return AppIcons.emergencyOutlined;
  return AppIcons.notificationsOutlined;
}

String _time(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? '' : DateFormat.yMMMd().add_jm().format(date.toLocal());
}
