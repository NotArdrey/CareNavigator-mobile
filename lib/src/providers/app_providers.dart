import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:care_navigator_ph/src/models/care_models.dart';
import 'package:care_navigator_ph/src/models/user_profile.dart';
import 'package:care_navigator_ph/src/repositories/auth_repository.dart';
import 'package:care_navigator_ph/src/repositories/assessment_repository.dart';
import 'package:care_navigator_ph/src/repositories/admin_repository.dart';
import 'package:care_navigator_ph/src/repositories/consultation_repository.dart';
import 'package:care_navigator_ph/src/repositories/care_repository.dart';
import 'package:care_navigator_ph/src/repositories/hospital_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final hospitalRepositoryProvider = Provider<HospitalRepository>(
  (ref) => HospitalRepository(ref.watch(supabaseClientProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final consultationRepositoryProvider = Provider<ConsultationRepository>(
  (ref) => ConsultationRepository(ref.watch(supabaseClientProvider)),
);

final assessmentRepositoryProvider = Provider<AssessmentRepository>(
  (ref) => AssessmentRepository(ref.watch(supabaseClientProvider)),
);

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(supabaseClientProvider)),
);

final careRepositoryProvider = Provider<CareRepository>(
  (ref) => CareRepository(ref.watch(supabaseClientProvider)),
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authChanges,
);

final currentProfileProvider = FutureProvider<UserProfile?>((ref) async {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).getProfile();
});

final hospitalsProvider = FutureProvider.autoDispose
    .family<List<Hospital>, String>(
      (ref, query) =>
          ref.watch(hospitalRepositoryProvider).listHospitals(query: query),
    );

final hospitalProvider = FutureProvider.autoDispose.family<Hospital, String>(
  (ref, id) => ref.watch(hospitalRepositoryProvider).getHospital(id),
);

final hospitalServicesProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, id) =>
          ref.watch(hospitalRepositoryProvider).getHospitalServices(id),
    );

final careWorkspaceProvider = FutureProvider.autoDispose
    .family<CareJson, String>(
      (ref, role) => ref.watch(careRepositoryProvider).loadWorkspace(role),
    );

final typedCareWorkspaceProvider = FutureProvider.autoDispose
    .family<RoleWorkspace, String>(
      (ref, role) => ref.watch(careRepositoryProvider).loadTypedWorkspace(role),
    );

final conversationMessagesProvider = FutureProvider.autoDispose
    .family<List<CareJson>, String>(
      (ref, conversationId) =>
          ref.watch(careRepositoryProvider).listMessages(conversationId),
    );

final conversationMessagesStreamProvider = StreamProvider.autoDispose
    .family<List<CareJson>, String>(
      (ref, conversationId) =>
          ref.watch(careRepositoryProvider).watchMessages(conversationId),
    );

final careNotificationsProvider = FutureProvider.autoDispose<List<CareJson>>(
  (ref) => ref.watch(careRepositoryProvider).listNotifications(),
);

final careNotificationsStreamProvider =
    StreamProvider.autoDispose<List<CareJson>>(
      (ref) => ref.watch(careRepositoryProvider).watchNotifications(),
    );

final notificationPreferencesProvider = FutureProvider.autoDispose<CareJson>(
  (ref) => ref.watch(careRepositoryProvider).getNotificationPreferences(),
);

final videoSessionProvider = FutureProvider.autoDispose
    .family<CareJson, String>(
      (ref, consultationId) =>
          ref.watch(careRepositoryProvider).getVideoSession(consultationId),
    );

final laboratoryRequestsProvider = FutureProvider.autoDispose
    .family<List<CareJson>, String?>(
      (ref, patientId) => ref
          .watch(careRepositoryProvider)
          .listLaboratoryRequests(patientId: patientId),
    );

final hospitalAnalyticsProvider = FutureProvider.autoDispose<CareJson>(
  (ref) => ref.watch(careRepositoryProvider).getHospitalAnalytics(),
);

final platformAnalyticsProvider = FutureProvider.autoDispose<CareJson>(
  (ref) => ref.watch(careRepositoryProvider).getPlatformAnalytics(),
);

final systemSettingsProvider = FutureProvider.autoDispose<List<CareJson>>(
  (ref) => ref.watch(careRepositoryProvider).listSystemSettings(),
);

final maintenanceStateProvider = FutureProvider<CareJson>((ref) async {
  ref.watch(authStateProvider);
  final client = ref.watch(supabaseClientProvider);
  final results = await Future.wait<dynamic>([
    client
        .from('system_settings')
        .select('value')
        .eq('key', 'maintenance_mode')
        .maybeSingle(),
    client
        .from('maintenance_windows')
        .select('title, message, starts_at, ends_at')
        .eq('is_active', true)
        .lte('starts_at', DateTime.now().toUtc().toIso8601String())
        .gte('ends_at', DateTime.now().toUtc().toIso8601String())
        .order('starts_at', ascending: false)
        .limit(1),
  ]);
  final setting = results[0] as Map<String, dynamic>?;
  final windows = (results[1] as List).whereType<Map>().toList();
  final settingValue = setting?['value'];
  final settingEnabled =
      settingValue == true || settingValue?.toString().toLowerCase() == 'true';
  final activeWindow = windows.isEmpty
      ? null
      : Map<String, dynamic>.from(windows.first);
  final profile = client.auth.currentSession == null
      ? null
      : await ref.watch(authRepositoryProvider).getProfile();
  return {
    'active': settingEnabled || activeWindow != null,
    'administrator_bypass':
        profile != null &&
        {'hospital_admin', 'super_admin'}.contains(profile.role),
    'title': activeWindow?['title'] ?? 'Scheduled maintenance',
    'message':
        activeWindow?['message'] ??
        'Care workflows are temporarily unavailable while platform maintenance is in progress.',
    'ends_at': activeWindow?['ends_at'],
  };
});
