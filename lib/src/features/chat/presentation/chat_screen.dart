import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  PlatformFile? _attachment;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_markRead);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    try {
      await ref
          .read(careRepositoryProvider)
          .markConversationRead(widget.conversationId);
    } catch (_) {
      // Read receipts are retried the next time the conversation is opened.
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'pdf',
        'txt',
        'doc',
        'docx',
      ],
    );
    if (result == null || result.files.single.bytes == null) return;
    final file = result.files.single;
    if (file.size > 10 * 1024 * 1024) {
      _error('Attachments must be 10 MB or smaller.');
      return;
    }
    setState(() => _attachment = file);
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty && _attachment == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .sendMessage(
            conversationId: widget.conversationId,
            message: message.isEmpty ? null : message,
            attachmentBytes: _attachment?.bytes,
            attachmentName: _attachment?.name,
            attachmentMimeType: _mime(_attachment?.extension),
          );
      _controller.clear();
      if (mounted) setState(() => _attachment = null);
      await _markRead();
    } catch (error) {
      _error(error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openAttachment(String path) async {
    try {
      final url = await ref
          .read(supabaseClientProvider)
          .storage
          .from('consultation-attachments')
          .createSignedUrl(path, 300);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open attachment.');
      }
    } catch (error) {
      _error(error.toString());
    }
  }

  void _error(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseClientProvider);
    final authUserId = client.auth.currentUser?.id;
    if (authUserId == null) {
      return AppStatePanel(
        kind: AppStateKind.restricted,
        icon: AppIcons.lockOutlineRounded,
        title: 'Sign in required',
        message: 'Sign in to open this private care conversation.',
        action: FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Sign in'),
        ),
      );
    }
    final messages = client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('sent_at');
    return SafeArea(
      child: Column(
        children: [
          AppPageHeader(
            eyebrow: 'ENCRYPTED CARE CHANNEL',
            title: 'Care team conversation',
            subtitle: 'A private, auditable thread for authorized participants',
            icon: AppIcons.chatBubbleRounded,
            onBack: () => context.go('/care'),
            backTooltip: 'Back to care workspace',
            actions: [
              IconButton(
                tooltip: 'Medical safety information',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AppDialog(
                    eyebrow: 'MEDICAL SAFETY',
                    icon: AppIcons.emergencyOutlined,
                    title: 'For emergencies',
                    content: const Text(
                      'Chat is not an emergency service. Call 911 or go to the nearest emergency room for severe breathing difficulty, chest pain, stroke signs, heavy bleeding, seizure, or loss of consciousness.',
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Understood'),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(AppIcons.infoOutlineRounded),
              ),
            ],
          ),
          const _ChatContextBanner(),
          Expanded(
            child: Container(
              margin: EdgeInsets.fromLTRB(
                AppPageBody.horizontalPadding(MediaQuery.sizeOf(context).width),
                AppSpacing.md,
                AppPageBody.horizontalPadding(MediaQuery.sizeOf(context).width),
                0,
              ),
              decoration: BoxDecoration(
                color: AppColors.fog,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.extraLarge),
                ),
                border: Border.all(color: AppColors.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: messages,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AppEmptyState(
                      kind: AppStateKind.error,
                      icon: AppIcons.cloudOffRounded,
                      title: 'This conversation is unavailable',
                      message:
                          'The secure thread could not be opened. Return to the care workspace and choose an active conversation.',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const AppLoadingState(label: 'Loading messages');
                  }
                  final items = snapshot.data!;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        _scrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                      );
                    }
                    _markRead();
                  });
                  if (items.isEmpty) {
                    return const AppEmptyState(
                      icon: AppIcons.forumOutlined,
                      title: 'Begin the care conversation',
                      message:
                          'Messages, clinical context, and shared files will remain together in this private thread.',
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(18),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final mine = item['sender_id'] == authUserId;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 620),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(14, 11, 14, 8),
                          decoration: BoxDecoration(
                            color: mine
                                ? AppColors.evergreenDark
                                : AppColors.paper,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: Radius.circular(mine ? 20 : 5),
                              bottomRight: Radius.circular(mine ? 5 : 20),
                            ),
                            border: mine
                                ? null
                                : Border.all(color: const Color(0xFFDDE5EE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((item['message']?.toString() ?? '')
                                  .isNotEmpty)
                                Text(
                                  item['message'].toString(),
                                  style: TextStyle(
                                    color: mine ? Colors.white : AppColors.ink,
                                  ),
                                ),
                              if ((item['attachment_path']?.toString() ?? '')
                                  .isNotEmpty) ...[
                                if ((item['message']?.toString() ?? '')
                                    .isNotEmpty)
                                  const SizedBox(height: 7),
                                TextButton.icon(
                                  onPressed: () => _openAttachment(
                                    item['attachment_path'].toString(),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: mine
                                        ? Colors.white
                                        : AppColors.blue,
                                  ),
                                  icon: const Icon(AppIcons.attachFileRounded),
                                  label: Text(
                                    item['attachment_name']?.toString() ??
                                        'Open attachment',
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _time(item['sent_at']),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: mine
                                          ? Colors.white70
                                          : const Color(0xFF60758C),
                                    ),
                                  ),
                                  if (mine) ...[
                                    const SizedBox(width: 5),
                                    Icon(
                                      item['read_at'] != null
                                          ? AppIcons.doneAllRounded
                                          : AppIcons.doneRounded,
                                      size: 14,
                                      color: item['read_at'] != null
                                          ? const Color(0xFF9EEDE2)
                                          : Colors.white70,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Material(
            color: AppColors.alabaster,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 14),
              child: Column(
                children: [
                  if (_attachment != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(AppIcons.descriptionOutlined),
                      title: Text(_attachment!.name),
                      subtitle: Text('${(_attachment!.size / 1024).ceil()} KB'),
                      trailing: IconButton(
                        tooltip: 'Remove attachment',
                        onPressed: _sending
                            ? null
                            : () => setState(() => _attachment = null),
                        icon: const Icon(AppIcons.closeRounded),
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Attach a medical document or image',
                        onPressed: _sending ? null : _pickAttachment,
                        icon: const Icon(AppIcons.attachFileRounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 5,
                          enabled: !_sending,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Write a message',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Send message',
                        onPressed: _sending ? null : _send,
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.button,
                            ),
                          ),
                        ),
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(AppIcons.sendRounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatContextBanner extends StatelessWidget {
  const _ChatContextBanner();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppBreakpoints.compact;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppPageBody.horizontalPadding(width),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.md : AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.evergreenDark,
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(AppIcons.lockRounded, color: Colors.white),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    compact
                        ? 'Private care channel'
                        : 'Private, role-scoped care channel',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                  if (!compact)
                    Text(
                      'Clinical messages are retained with this conversation.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.mist),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(AppIcons.emergencyOutlined, color: AppColors.coral),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.xs),
              const Text(
                'Not for emergencies',
                style: TextStyle(
                  color: AppColors.mist,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _mime(String? extension) => switch (extension?.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'pdf' => 'application/pdf',
  'txt' => 'text/plain',
  'doc' => 'application/msword',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  _ => 'application/octet-stream',
};

String _time(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? '' : DateFormat.jm().format(date.toLocal());
}
