import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/core_providers.dart';
import '../../routing/root_overlay.dart';
import '../../widgets/overlays/action_dialogs.dart';

class SharingManagementDialog extends ConsumerStatefulWidget {
  const SharingManagementDialog({super.key});
  @override
  ConsumerState<SharingManagementDialog> createState() =>
      _SharingManagementDialogState();
}

class _SharingManagementDialogState
    extends ConsumerState<SharingManagementDialog> {
  late Future<List<dynamic>> _relationships = _load();
  bool _busy = false;

  Future<List<dynamic>> _load() async => await ref
      .read(supabaseClientProvider)!
      .rpc<List<dynamic>>('list_patient_sharing_relationships');

  Future<void> _revoke(Map relationship) async {
    final grants = (relationship['grants'] as List?) ?? [];
    if (grants.isEmpty) return;
    final reason = await requestDecisionNote(
      title: 'Revoke sharing for this care relationship',
      message:
          'This revokes every active grant for ${relationship['display_name'] ?? 'the care team'} at ${relationship['hospital_name']}. '
          'All categories and selected records listed under this relationship are included. The care team loses access to them.',
      confirmLabel: 'Revoke relationship sharing',
      destructive: true,
    );
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(supabaseClientProvider)!
          .rpc(
            'revoke_patient_access_grant',
            params: {
              'target_grant_id': (grants.first as Map)['grant_id'],
              'reason': reason,
            },
          );
      if (mounted) setState(() => _relationships = _load());
      showRootMessage('All grants for this care relationship were revoked.');
    } catch (error) {
      showRootMessage('Sharing could not be revoked: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sharing by care relationship'),
    content: SizedBox(
      width: 560,
      child: FutureBuilder<List<dynamic>>(
        future: _relationships,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Sharing could not be loaded.'),
                TextButton(
                  onPressed: () => setState(() => _relationships = _load()),
                  child: const Text('Retry'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data!.isEmpty) {
            return const Text(
              'You have no active care relationships sharing records.',
            );
          }
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final raw in snapshot.data!) ...[
                  ListTile(
                    title: Text((raw as Map)['hospital_name'].toString()),
                    subtitle: Text(
                      '${raw['display_name'] ?? 'Care team'}\n${((raw['grants'] as List?) ?? []).expand((g) => (g['categories'] as List?) ?? []).toSet().join(', ')}',
                    ),
                    isThreeLine: true,
                  ),
                  TextButton(
                    onPressed: _busy || ((raw['grants'] as List?) ?? []).isEmpty
                        ? null
                        : () => _revoke(raw),
                    child: const Text(
                      'Revoke all sharing for this relationship',
                    ),
                  ),
                  const Divider(),
                ],
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}
