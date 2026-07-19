import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
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
      return Center(
        child: FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Sign in to open this conversation'),
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
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to care workspace',
                    onPressed: () => context.go('/care'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const CircleAvatar(
                    backgroundColor: Color(0xFFE8F1FD),
                    foregroundColor: AppColors.blue,
                    child: Icon(Icons.health_and_safety_rounded),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Care conversation',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Text(
                          'Messages are visible only to authorized participants.',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Medical safety information',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('For emergencies'),
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
                    icon: const Icon(Icons.info_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not load messages: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
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
                  return const Center(
                    child: Text(
                      'No messages yet. Start the care conversation below.',
                    ),
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
                          color: mine ? AppColors.blue : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: mine
                              ? null
                              : Border.all(color: const Color(0xFFDDE5EE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((item['message']?.toString() ?? '').isNotEmpty)
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
                                icon: const Icon(Icons.attach_file_rounded),
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
                                        ? Icons.done_all_rounded
                                        : Icons.done_rounded,
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
          Material(
            color: Colors.white,
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 14),
              child: Column(
                children: [
                  if (_attachment != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(_attachment!.name),
                      subtitle: Text('${(_attachment!.size / 1024).ceil()} KB'),
                      trailing: IconButton(
                        tooltip: 'Remove attachment',
                        onPressed: _sending
                            ? null
                            : () => setState(() => _attachment = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Attach a medical document or image',
                        onPressed: _sending ? null : _pickAttachment,
                        icon: const Icon(Icons.attach_file_rounded),
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
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
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
