import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseClientProvider);
    if (client.auth.currentSession == null) {
      return Center(
        child: FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Sign in to view notifications'),
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
                title: 'Notifications',
                subtitle: '$unread unread',
                icon: Icons.notifications_rounded,
                onBack: () => context.go('/dashboard'),
                backTooltip: 'Back to my care',
                actions: [
                  IconButton(
                    tooltip: 'Preferences',
                    onPressed: _updating ? null : _preferences,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  TextButton.icon(
                    onPressed: unread == 0 || _updating
                        ? null
                        : () => _markAllRead(items),
                    icon: const Icon(Icons.done_all_rounded),
                    label: const Text('Mark all read'),
                  ),
                ],
              ),
              Expanded(
                child: snapshot.hasError
                    ? Center(
                        child: Text(
                          'Could not load notifications: ${snapshot.error}',
                        ),
                      )
                    : snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.notifications_none_rounded,
                              size: 54,
                              color: Color(0xFF8094A8),
                            ),
                            SizedBox(height: 10),
                            Text('No notifications yet.'),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isUnread = item['is_read'] != true;
                          return Card(
                            color: isUnread
                                ? const Color(0xFFF2F7FE)
                                : Colors.white,
                            child: ListTile(
                              onTap: () async {
                                if (isUnread) {
                                  await _markRead(item['id'].toString());
                                }
                                if (mounted) _open(item);
                              },
                              leading: CircleAvatar(
                                backgroundColor: isUnread
                                    ? const Color(0xFFDDEBFB)
                                    : const Color(0xFFEDF1F5),
                                child: Icon(
                                  _icon(item['notification_type']?.toString()),
                                  color: isUnread
                                      ? AppColors.blue
                                      : const Color(0xFF60758C),
                                ),
                              ),
                              title: Text(
                                item['title']?.toString() ?? 'Update',
                                style: TextStyle(
                                  fontWeight: isUnread
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${item['message'] ?? ''}\n${_time(item['created_at'])}',
                              ),
                              isThreeLine: true,
                              trailing: isUnread
                                  ? IconButton(
                                      tooltip: 'Mark as read',
                                      onPressed: _updating
                                          ? null
                                          : () => _markRead(
                                              item['id'].toString(),
                                            ),
                                      icon: const Icon(
                                        Icons.check_circle_outline_rounded,
                                      ),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

IconData _icon(String? type) {
  if (type?.contains('message') == true) {
    return Icons.chat_bubble_outline_rounded;
  }
  if (type?.contains('prescription') == true) return Icons.medication_outlined;
  if (type?.contains('result') == true) return Icons.science_outlined;
  if (type?.contains('consultation') == true ||
      type?.contains('appointment') == true) {
    return Icons.calendar_month_outlined;
  }
  if (type?.contains('emergency') == true) return Icons.emergency_outlined;
  return Icons.notifications_outlined;
}

String _time(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? '' : DateFormat.yMMMd().add_jm().format(date.toLocal());
}
