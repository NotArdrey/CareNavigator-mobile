import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/public_config.dart';
import '../models/auth/user_role.dart';
import '../repositories/auth_repository.dart';
import '../repositories/admin_repository.dart';
import '../repositories/care_repository.dart';
import '../repositories/care_assistant_repository.dart';
import '../repositories/hospital_repository.dart';
import '../repositories/consultation_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/public_settings_repository.dart';
import '../repositories/workspace_repository.dart';

final publicConfigProvider = Provider<PublicConfig>(
  (ref) => const PublicConfig.fromEnvironment(),
);

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  final config = ref.watch(publicConfigProvider);
  return config.hasSupabaseConfiguration ? Supabase.instance.client : null;
});

final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseAuthRepository(client);
});

final hospitalRepositoryProvider = Provider<HospitalRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseHospitalRepository(client);
});

final careAssistantRepositoryProvider = Provider<CareAssistantRepository?>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseCareAssistantRepository(client);
});

final consultationRepositoryProvider = Provider<ConsultationRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseConsultationRepository(client);
});

final careRepositoryProvider = Provider<CareRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseCareRepository(client);
});

final adminRepositoryProvider = Provider<AdminRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseAdminRepository(client);
});

final workspaceRepositoryProvider = Provider<WorkspaceRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseWorkspaceRepository(client);
});

final profileRepositoryProvider = Provider<ProfileRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseProfileRepository(client);
});

final publicSettingsRepositoryProvider = Provider<PublicSettingsRepository?>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabasePublicSettingsRepository(client);
});

final publicAppSettingsProvider = FutureProvider<PublicAppSettings>((ref) {
  final repository = ref.watch(publicSettingsRepositoryProvider);
  if (repository == null) return const PublicAppSettings();
  return repository.load();
});

final careProfileProvider = FutureProvider.autoDispose<CareProfile>((
  ref,
) async {
  final repository = ref.watch(profileRepositoryProvider);
  if (repository == null) {
    throw StateError('This care service is temporarily unavailable.');
  }
  return repository.loadProfile();
});

typedef WorkspaceRequest = ({UserRole role, String? section, String? itemId});

final workspaceSnapshotProvider = FutureProvider.autoDispose
    .family<WorkspaceSnapshot, WorkspaceRequest>((ref, request) async {
      final repository = ref.watch(workspaceRepositoryProvider);
      if (repository == null) {
        throw StateError('This care service is temporarily unavailable.');
      }
      return repository.load(
        role: request.role,
        section: request.section,
        itemId: request.itemId,
      );
    });

final conversationMessagesProvider = StreamProvider.autoDispose
    .family<List<CareMessage>, String>((ref, conversationId) {
      final repository = ref.watch(careRepositoryProvider);
      if (repository == null) {
        return Stream.error(
          StateError('This care service is temporarily unavailable.'),
        );
      }
      return repository.watchMessages(conversationId);
    });

final careNotificationsProvider =
    StreamProvider.autoDispose<List<CareNotification>>((ref) {
      final repository = ref.watch(careRepositoryProvider);
      if (repository == null) {
        return Stream.error(
          StateError('This care service is temporarily unavailable.'),
        );
      }
      return repository.watchNotifications();
    });

final authIdentityProvider = StreamProvider<AppIdentity>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository?.watchIdentity() ?? Stream.value(const AppIdentity.guest());
});

final appIdentityProvider =
    NotifierProvider<AppIdentityController, AppIdentity>(
      AppIdentityController.new,
    );

class AppIdentityController extends Notifier<AppIdentity> {
  @override
  AppIdentity build() {
    ref.listen(authIdentityProvider, (previous, next) {
      next.whenData((identity) {
        state = identity;
      });
    }, fireImmediately: true);
    return const AppIdentity.guest();
  }

  Future<void> signInAnonymously() async {
    final repository = ref.read(authRepositoryProvider);
    if (repository == null) {
      throw StateError('This care service is temporarily unavailable.');
    }
    state = await repository.signInAnonymously();
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final repository = ref.read(authRepositoryProvider);
    if (repository == null) {
      throw StateError('This care service is temporarily unavailable.');
    }
    state = await repository.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    final repository = ref.read(authRepositoryProvider);
    if (repository != null) await repository.signOut();
    state = const AppIdentity.guest();
  }
}
