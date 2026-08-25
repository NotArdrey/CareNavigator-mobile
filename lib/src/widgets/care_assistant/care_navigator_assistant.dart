import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/hospitals/hospital_models.dart';
import '../../providers/care_assistant_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/hospital_directory_provider.dart';
import '../../repositories/care_assistant_repository.dart';
import '../../routing/root_overlay.dart';
import '../../theme/app_tokens.dart';
import '../branding/brand_mark.dart';

class CareNavigatorAssistant extends ConsumerStatefulWidget {
  const CareNavigatorAssistant({super.key});

  @override
  ConsumerState<CareNavigatorAssistant> createState() =>
      _CareNavigatorAssistantState();
}

class _CareNavigatorAssistantState
    extends ConsumerState<CareNavigatorAssistant> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 720;
    if (mobile) {
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.only(right: 16, bottom: 20),
        child: _assistantButton(compact: true),
      );
    }

    final size = MediaQuery.sizeOf(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(right: 24, bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_isOpen) ...[
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 380,
                maxHeight: math.min(560, size.height - 150),
              ),
              child: _CareAssistantPanel(
                onClose: () => setState(() => _isOpen = false),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _assistantButton(compact: false),
        ],
      ),
    );
  }

  Widget _assistantButton({required bool compact}) {
    if (compact) {
      return FloatingActionButton(
        key: const Key('care-assistant-launcher'),
        heroTag: 'care-navigator-assistant',
        tooltip: 'Open CareNavigator assistant',
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.primary,
        elevation: 4,
        onPressed: _openAssistant,
        child: const BrandMark(size: 26),
      );
    }
    return FloatingActionButton.extended(
      key: const Key('care-assistant-launcher'),
      heroTag: 'care-navigator-assistant',
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        side: const BorderSide(color: AppColors.border),
      ),
      onPressed: _openAssistant,
      icon: const BrandMark(size: 24),
      label: const Text('Care assistant'),
    );
  }

  Future<void> _openAssistant() async {
    final mobile = MediaQuery.sizeOf(context).width < 720;
    if (!mobile) {
      setState(() => _isOpen = !_isOpen);
      return;
    }
    setState(() => _isOpen = true);
    await showRootSheet<void>(
      showDragHandle: false,
      builder: (context) => const _CareAssistantPanel(isSheet: true),
    );
    if (mounted) setState(() => _isOpen = false);
  }
}

class _CareAssistantPanel extends ConsumerStatefulWidget {
  const _CareAssistantPanel({this.isSheet = false, this.onClose});

  final bool isSheet;
  final VoidCallback? onClose;

  @override
  ConsumerState<_CareAssistantPanel> createState() =>
      _CareAssistantPanelState();
}

class _CareAssistantPanelState extends ConsumerState<_CareAssistantPanel> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  var _isHistoryOpen = false;
  List<CareAssistantImage> _selectedImages = const [];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(careAssistantProvider);
    final emergencyNumber =
        ref.watch(publicAppSettingsProvider).value?.emergencyNumber?.trim() ??
        '';
    final directory = ref.watch(hospitalDirectoryProvider);
    final media = MediaQuery.of(context);
    final availableHeight = math.max(
      280.0,
      media.size.height - media.viewInsets.bottom,
    );
    final panelHeight = widget.isSheet
        ? math.max(280.0, math.min(availableHeight * 0.82, 640.0))
        : math.max(360.0, math.min(availableHeight * 0.68, 560.0));

    return Padding(
      padding: EdgeInsets.only(
        bottom: widget.isSheet ? media.viewInsets.bottom : 0,
      ),
      child: Material(
        color: AppColors.surface,
        elevation: widget.isSheet ? 0 : 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(
              widget.isSheet ? AppRadius.sheet : AppRadius.panel,
            ),
            topRight: Radius.circular(
              widget.isSheet ? AppRadius.sheet : AppRadius.panel,
            ),
            bottomLeft: Radius.circular(widget.isSheet ? 0 : AppRadius.panel),
            bottomRight: Radius.circular(widget.isSheet ? 0 : AppRadius.panel),
          ),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: widget.isSheet ? double.infinity : 380,
          height: panelHeight,
          child: Stack(
            children: [
              Column(
                children: [
                  _PanelHeader(
                    historyOpen: _isHistoryOpen,
                    onMenu: () =>
                        setState(() => _isHistoryOpen = !_isHistoryOpen),
                  ),
                  const Divider(height: 1),
                  if (state.isOffline)
                    const _AssistantNotice(
                      icon: Icons.cloud_off_outlined,
                      color: AppColors.warning,
                      text:
                          'Offline mode: using only the current directory data.',
                    ),
                  Expanded(
                    child: ListView(
                      key: const Key('care-assistant-messages'),
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      children: [
                        if (state.showEmergencyActions)
                          _EmergencyActions(
                            emergencyNumber: emergencyNumber,
                            onOpenFacilities: () => context.go('/hospitals'),
                            onCall: _callEmergencyServices,
                            onStartOver: ref
                                .read(careAssistantProvider.notifier)
                                .reset,
                          ),
                        for (final message in state.messages)
                          _MessageBubble(message: message),
                        if (state.isBusy) const _RespondingIndicator(),
                        if (state.recommendations.isNotEmpty)
                          _RecommendationList(
                            directory: directory,
                            recommendations: state.recommendations,
                            summary: state.recommendationSummary,
                            onOpenFacility: (hospital) =>
                                _navigateTo('/hospitals/${hospital.id}'),
                            onCallFacility: _callFacility,
                            onShowFacilityMap: (hospital) {
                              _navigateTo(
                                Uri(
                                  path: '/hospitals/map',
                                  queryParameters: {
                                    'hospitalId': hospital.id,
                                    'source': 'recommendation',
                                  },
                                ).toString(),
                              );
                            },
                          ),
                        if (state.status == CareAssistantStatus.error &&
                            state.errorMessage != null)
                          _AssistantError(message: state.errorMessage!),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  _MessageComposer(
                    controller: _inputController,
                    enabled: !state.isBusy && !state.showEmergencyActions,
                    selectedImages: _selectedImages,
                    onChanged: (_) => setState(() {}),
                    onAttach: _pickImages,
                    onRemoveImage: (index) => setState(
                      () => _selectedImages = [
                        ..._selectedImages.take(index),
                        ..._selectedImages.skip(index + 1),
                      ],
                    ),
                    onSend: _send,
                  ),
                ],
              ),
              Positioned(
                top: 58,
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !_isHistoryOpen,
                  child: AnimatedSlide(
                    offset: _isHistoryOpen ? Offset.zero : const Offset(1, 0),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: _ChatHistoryDrawer(
                      state: state,
                      onNewChat: () {
                        ref.read(careAssistantProvider.notifier).newChat();
                        setState(() => _isHistoryOpen = false);
                      },
                      onSelect: (conversationId) {
                        ref
                            .read(careAssistantProvider.notifier)
                            .selectConversation(conversationId);
                        setState(() => _isHistoryOpen = false);
                      },
                      onRename: (conversationId, title) => ref
                          .read(careAssistantProvider.notifier)
                          .renameConversation(conversationId, title),
                      onTogglePin: (conversationId) => ref
                          .read(careAssistantProvider.notifier)
                          .togglePinConversation(conversationId),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    final images = _selectedImages;
    if (text.isEmpty && images.isEmpty) return;
    _inputController.clear();
    setState(() => _selectedImages = const []);
    await ref.read(careAssistantProvider.notifier).submit(text, images: images);
  }

  Future<void> _pickImages() async {
    if (_selectedImages.length >= 5) {
      showRootMessage('You can attach up to 5 images per message.');
      return;
    }
    const imageTypes = XTypeGroup(
      label: 'Health concern images',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
    );
    final selected = await openFiles(acceptedTypeGroups: const [imageTypes]);
    if (selected.isEmpty) return;

    final remainingSlots = 5 - _selectedImages.length;
    final candidates = selected.take(remainingSlots);
    final additions = <CareAssistantImage>[];
    var combinedBytes = _selectedImages.fold<int>(
      0,
      (total, image) => total + image.bytes.length,
    );
    for (final file in candidates) {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) continue;
      final extension = file.name.split('.').last.toLowerCase();
      final mimeType = switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => null,
      };
      if (mimeType == null) continue;
      if (combinedBytes + bytes.length > 2 * 1024 * 1024) {
        showRootMessage(
          'The combined size of all attached images must be smaller than 2 MB.',
        );
        break;
      }
      combinedBytes += bytes.length;
      additions.add(
        CareAssistantImage(bytes: bytes, mimeType: mimeType, name: file.name),
      );
    }
    if (!mounted || additions.isEmpty) {
      if (selected.length > remainingSlots && mounted) {
        showRootMessage('You can attach up to 5 images per message.');
      }
      return;
    }
    setState(() => _selectedImages = [..._selectedImages, ...additions]);
    if (selected.length > remainingSlots) {
      showRootMessage('Only the first 5 images were attached.');
    }
  }

  void _navigateTo(String location) {
    final router = GoRouter.of(context);
    if (widget.isSheet) {
      Navigator.of(context).pop();
    } else {
      widget.onClose?.call();
    }
    router.go(location);
  }

  Future<void> _callEmergencyServices() async {
    final emergencyNumber =
        ref.read(publicAppSettingsProvider).value?.emergencyNumber?.trim() ??
        '';
    if (emergencyNumber.isEmpty) {
      showRootMessage(
        'Contact your local emergency services or go to the nearest emergency department now.',
      );
      return;
    }
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: emergencyNumber),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      showRootMessage(
        'Call $emergencyNumber or go to the nearest emergency department now.',
      );
    }
  }

  Future<void> _callFacility(HospitalDirectoryEntry hospital) async {
    final number = (hospital.emergencyContactNumber ?? hospital.contactNumber)
        ?.trim();
    if (number == null || number.isEmpty) {
      showRootMessage('A contact number is not reported for ${hospital.name}.');
      return;
    }
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: number),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) showRootMessage('Call $number.');
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.historyOpen, required this.onMenu});

  final bool historyOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
    child: Row(
      children: [
        const BrandMark(size: 26),
        const SizedBox(width: 9),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CareNavigator assistant',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 2),
              Text(
                'First aid and facility guidance',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: historyOpen ? 'Close chat history' : 'Open chat history',
          onPressed: onMenu,
          icon: Icon(historyOpen ? Icons.close : Icons.menu),
        ),
      ],
    ),
  );
}

class _ChatHistoryDrawer extends StatelessWidget {
  const _ChatHistoryDrawer({
    required this.state,
    required this.onNewChat,
    required this.onSelect,
    required this.onRename,
    required this.onTogglePin,
  });

  final CareAssistantState state;
  final VoidCallback onNewChat;
  final ValueChanged<String> onSelect;
  final void Function(String conversationId, String title) onRename;
  final ValueChanged<String> onTogglePin;

  @override
  Widget build(BuildContext context) {
    final conversations =
        state.conversations.isEmpty
              ? [
                  CareAssistantConversation(
                    id: state.conversationId,
                    title: state.conversationTitle,
                    updatedAt: DateTime.now(),
                    messages: state.messages,
                    status: state.status,
                    recommendations: state.recommendations,
                    intent: state.intent,
                    urgency: state.urgency,
                    isPinned: state.conversationPinned,
                    recommendationSummary: state.recommendationSummary,
                    isOffline: state.isOffline,
                    errorMessage: state.errorMessage,
                  ),
                ]
              : [...state.conversations]
          ..sort((left, right) {
            if (left.isPinned != right.isPinned) {
              return left.isPinned ? -1 : 1;
            }
            return right.updatedAt.compareTo(left.updatedAt);
          });

    return Material(
      color: AppColors.surface,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: onNewChat,
              icon: const Icon(Icons.add),
              label: const Text('New Chat'),
            ),
            const SizedBox(height: 18),
            Text(
              'Recents',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: conversations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  final selected = conversation.id == state.conversationId;
                  return Material(
                    color: selected
                        ? AppColors.secondary.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: ListTile(
                      selected: selected,
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      leading: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.chat_bubble_outline,
                        size: 19,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                      title: Text(
                        conversation.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      trailing: SizedBox(
                        width: 84,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: conversation.isPinned
                                  ? 'Unpin conversation'
                                  : 'Pin conversation',
                              onPressed: () => onTogglePin(conversation.id),
                              icon: Icon(
                                conversation.isPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 18,
                                color: conversation.isPinned
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Edit conversation title',
                              onPressed: () => _rename(context, conversation),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                            ),
                          ],
                        ),
                      ),
                      onTap: () => onSelect(conversation.id),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    CareAssistantConversation conversation,
  ) async {
    var draft = conversation.title;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit conversation title'),
        content: TextFormField(
          initialValue: conversation.title,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Conversation title'),
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(draft),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title != null && title.trim().isNotEmpty) {
      onRename(conversation.id, title);
    }
  }
}

class _AssistantNotice extends StatelessWidget {
  const _AssistantNotice({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: color.withValues(alpha: 0.08),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final CareAssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == CareAssistantChatMessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isUser ? AppColors.selected : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: isUser ? AppColors.secondary : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.images.isNotEmpty) ...[
              SizedBox(
                width: 230,
                height: message.images.length == 1 ? 150 : 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: message.images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      Uint8List.fromList(message.images[index].bytes),
                      width: message.images.length == 1 ? 230 : 108,
                      height: message.images.length == 1 ? 150 : 112,
                      fit: BoxFit.cover,
                      semanticLabel:
                          'Attached health concern image ${index + 1}',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(message.text),
          ],
        ),
      ),
    );
  }
}

class _RespondingIndicator extends StatelessWidget {
  const _RespondingIndicator();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 8),
        Text(
          'CareNavigator is typing…',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.enabled,
    required this.selectedImages,
    required this.onChanged,
    required this.onAttach,
    required this.onRemoveImage,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final List<CareAssistantImage> selectedImages;
  final ValueChanged<String> onChanged;
  final VoidCallback onAttach;
  final ValueChanged<int> onRemoveImage;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedImages.isNotEmpty) ...[
          Container(
            key: const Key('care-assistant-image-preview'),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${selectedImages.length} image${selectedImages.length == 1 ? '' : 's'} attached',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 68,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: selectedImages.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 7),
                    itemBuilder: (context, index) => SizedBox(
                      width: 64,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                Uint8List.fromList(selectedImages[index].bytes),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 1,
                            right: 1,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: enabled
                                    ? () => onRemoveImage(index)
                                    : null,
                                child: const Padding(
                                  padding: EdgeInsets.all(3),
                                  child: Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Combined limit: 2 MB • For guidance only—not a diagnosis',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          enabled: enabled,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => onSend(),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'Describe what you’re experiencing',
            prefixIcon: IconButton(
              key: const Key('care-assistant-attach-image'),
              tooltip: 'Attach injury, rash, or allergy images',
              onPressed: enabled ? onAttach : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
            suffixIcon: IconButton(
              tooltip: 'Send message',
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send_outlined),
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmergencyActions extends StatelessWidget {
  const _EmergencyActions({
    required this.emergencyNumber,
    required this.onOpenFacilities,
    required this.onCall,
    required this.onStartOver,
  });

  final String emergencyNumber;
  final VoidCallback onOpenFacilities;
  final VoidCallback onCall;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 2, bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F1),
      borderRadius: BorderRadius.circular(AppRadius.control),
      border: Border.all(color: AppColors.emergency.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Emergency actions',
          style: TextStyle(
            color: AppColors.emergency,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.emergency,
            foregroundColor: Colors.white,
          ),
          onPressed: onCall,
          icon: const Icon(Icons.call_outlined),
          label: Text(
            emergencyNumber.isEmpty
                ? 'Contact emergency services'
                : 'Call $emergencyNumber',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onOpenFacilities,
          icon: const Icon(Icons.local_hospital_outlined),
          label: const Text('Open emergency facilities'),
        ),
        TextButton(onPressed: onStartOver, child: const Text('Start over')),
      ],
    ),
  );
}

class _RecommendationList extends StatelessWidget {
  const _RecommendationList({
    required this.directory,
    required this.recommendations,
    required this.summary,
    required this.onOpenFacility,
    required this.onShowFacilityMap,
    required this.onCallFacility,
  });

  final HospitalDirectoryState directory;
  final List<CareAssistantRecommendation> recommendations;
  final String? summary;
  final ValueChanged<HospitalDirectoryEntry> onOpenFacility;
  final ValueChanged<HospitalDirectoryEntry> onShowFacilityMap;
  final ValueChanged<HospitalDirectoryEntry> onCallFacility;

  @override
  Widget build(BuildContext context) {
    final visible = <(HospitalDirectoryEntry, CareAssistantRecommendation)>[];
    for (final recommendation in recommendations) {
      final hospital = directory.findById(recommendation.hospitalId);
      if (hospital != null) visible.add((hospital, recommendation));
    }
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Recommended from current results',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          if (summary != null) ...[
            const SizedBox(height: 4),
            Text(summary!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          for (final item in visible)
            _RecommendationCard(
              hospital: item.$1,
              recommendation: item.$2,
              onOpen: () => onOpenFacility(item.$1),
              onShowMap: () => onShowFacilityMap(item.$1),
              onCall: () => onCallFacility(item.$1),
            ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.hospital,
    required this.recommendation,
    required this.onOpen,
    required this.onShowMap,
    required this.onCall,
  });

  final HospitalDirectoryEntry hospital;
  final CareAssistantRecommendation recommendation;
  final VoidCallback onOpen;
  final VoidCallback onShowMap;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.control),
      border: Border.all(color: AppColors.secondary),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.local_hospital_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hospital.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          hospital.careLevel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        _ErStatusLine(hospital: hospital),
        const SizedBox(height: 8),
        if (recommendation.reasons.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Why recommended: ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: recommendation.reasons.first),
                  ],
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        const SizedBox(height: 8),
        _RecommendationFact(
          icon: Icons.emergency_outlined,
          text: 'Emergency Department: ${_emergencyHours(hospital)}',
        ),
        _RecommendationFact(
          icon: Icons.bed_outlined,
          text: _bedAvailabilityLabel(hospital),
        ),
        if (recommendation.relevantSpecialists.isNotEmpty)
          _RecommendationFact(
            icon: Icons.medical_services_outlined,
            text:
                'Relevant specialists with published schedules: ${recommendation.relevantSpecialists.join(', ')}',
          )
        else
          const _RecommendationFact(
            icon: Icons.medical_services_outlined,
            text: 'Relevant specialist availability: Not reported',
          ),
        if (recommendation.relevantServices.isNotEmpty)
          _RecommendationFact(
            icon: Icons.biotech_outlined,
            text:
                'Relevant published care: ${recommendation.relevantServices.join(' · ')}',
          ),
        _RecommendationFact(
          icon: Icons.location_on_outlined,
          text: [
            if (recommendation.distanceKm != null)
              '${recommendation.distanceKm!.toStringAsFixed(1)} km away (straight-line)',
            hospital.locationLabel,
          ].where((value) => value.isNotEmpty).join(' · '),
        ),
        _RecommendationFact(
          icon: Icons.schedule_outlined,
          text:
              'Availability updated: ${_formatRecommendationFreshness(hospital.statusLastUpdated)}',
        ),
        const _RecommendationFact(
          icon: Icons.verified_outlined,
          text: 'Facility verified · Live fields shown only when reported',
        ),
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            TextButton(onPressed: onOpen, child: const Text('View facility')),
            TextButton.icon(
              onPressed: hospital.hasCoordinates ? onShowMap : null,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Show in Maps'),
            ),
            TextButton.icon(
              onPressed:
                  (hospital.emergencyContactNumber ?? hospital.contactNumber)
                          ?.trim()
                          .isNotEmpty ==
                      true
                  ? onCall
                  : null,
              icon: const Icon(Icons.call_outlined, size: 18),
              label: const Text('Call'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ErStatusLine extends StatelessWidget {
  const _ErStatusLine({required this.hospital});

  final HospitalDirectoryEntry hospital;

  @override
  Widget build(BuildContext context) {
    final status = hospital.emergencyStatus?.toLowerCase();
    final (color, label) = switch (status) {
      'available' || 'open' => (AppColors.success, 'ER accepting patients'),
      'limited' || 'busy' => (AppColors.warning, 'ER has limited capacity'),
      'full' => (AppColors.emergency, 'ER full'),
      'unavailable' ||
      'temporarily_closed' => (AppColors.emergency, 'ER unavailable'),
      _ => (AppColors.textMuted, 'Current ER status unknown'),
    };
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _RecommendationFact extends StatelessWidget {
  const _RecommendationFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

String _emergencyHours(HospitalDirectoryEntry hospital) {
  for (final entry in hospital.operatingHours.entries) {
    if (entry.key.toLowerCase().contains('emergency') &&
        entry.value.trim().isNotEmpty) {
      return entry.value.trim();
    }
  }
  return 'Hours not reported';
}

String _bedAvailabilityLabel(HospitalDirectoryEntry hospital) {
  final available = hospital.availableBeds;
  final total = hospital.totalBeds;
  if (!hospital.hasCurrentEmergencyCapacity() &&
      (available != null || total != null)) {
    return 'ER bed count is stale · Call the hospital to confirm';
  }
  if (available != null && total != null) {
    return 'ER beds: $available available / $total total';
  }
  if (total != null) {
    return 'ER capacity: $total total · Current bed availability: Not reported';
  }
  if (available != null) {
    return 'ER beds available: $available · Total capacity: Not reported';
  }
  return 'Current ER bed availability: Not reported';
}

String _formatRecommendationFreshness(DateTime? value) {
  if (value == null) return 'Not reported';
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.isNegative || difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours} hr ago';
  if (difference.inDays < 30) return '${difference.inDays} days ago';
  final local = value.toLocal();
  return '${_recommendationMonthName(local.month)} ${local.day}, ${local.year}';
}

String _recommendationMonthName(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];

class _AssistantError extends StatelessWidget {
  const _AssistantError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) =>
      Text(message, style: const TextStyle(color: AppColors.destructive));
}
