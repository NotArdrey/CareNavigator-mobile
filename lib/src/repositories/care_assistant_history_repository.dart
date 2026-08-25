import 'package:supabase/supabase.dart';

import 'repository_failure.dart';

class CareAssistantHistoryRecord {
  const CareAssistantHistoryRecord({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.isPinned,
    required this.isTitleEdited,
    required this.payload,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final bool isPinned;
  final bool isTitleEdited;
  final Map<String, dynamic> payload;
}

abstract interface class CareAssistantHistoryRepository {
  Future<List<CareAssistantHistoryRecord>> loadForUser(String userId);

  Future<void> saveForUser(
    String userId,
    CareAssistantHistoryRecord conversation,
  );

  Future<void> deleteForUser(String userId, String conversationId);
}

final class SupabaseCareAssistantHistoryRepository
    implements CareAssistantHistoryRepository {
  SupabaseCareAssistantHistoryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<CareAssistantHistoryRecord>> loadForUser(String userId) async {
    try {
      final rows = await _client
          .from('care_assistant_conversations')
          .select('id,title,is_pinned,is_title_edited,payload,updated_at')
          .eq('user_id', userId)
          .order('is_pinned', ascending: false)
          .order('updated_at', ascending: false);
      return rows
          .map(_recordFromRow)
          .whereType<CareAssistantHistoryRecord>()
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw UnexpectedRepositoryFailure(
        'Conversation history could not be loaded.',
        cause: error,
      );
    }
  }

  @override
  Future<void> saveForUser(
    String userId,
    CareAssistantHistoryRecord conversation,
  ) async {
    try {
      await _client.from('care_assistant_conversations').upsert({
        'id': conversation.id,
        'user_id': userId,
        'title': conversation.title,
        'is_pinned': conversation.isPinned,
        'is_title_edited': conversation.isTitleEdited,
        'payload': conversation.payload,
        'updated_at': conversation.updatedAt.toUtc().toIso8601String(),
      }, onConflict: 'user_id,id');
    } on PostgrestException catch (error) {
      throw UnexpectedRepositoryFailure(
        'Conversation history could not be saved.',
        cause: error,
      );
    }
  }

  @override
  Future<void> deleteForUser(String userId, String conversationId) async {
    try {
      await _client
          .from('care_assistant_conversations')
          .delete()
          .eq('id', conversationId)
          .eq('user_id', userId);
    } on PostgrestException catch (error) {
      throw UnexpectedRepositoryFailure(
        'Conversation could not be deleted.',
        cause: error,
      );
    }
  }

  static CareAssistantHistoryRecord? _recordFromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString().trim() ?? '';
    final title = row['title']?.toString().trim() ?? '';
    final updatedAt = DateTime.tryParse(row['updated_at']?.toString() ?? '');
    final rawPayload = row['payload'];
    if (id.isEmpty ||
        title.isEmpty ||
        updatedAt == null ||
        rawPayload is! Map) {
      return null;
    }
    return CareAssistantHistoryRecord(
      id: id,
      title: title,
      updatedAt: updatedAt.toLocal(),
      isPinned: row['is_pinned'] == true,
      isTitleEdited: row['is_title_edited'] == true,
      payload: rawPayload.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}
