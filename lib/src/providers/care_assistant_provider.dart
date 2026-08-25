import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/hospitals/hospital_models.dart';
import '../repositories/care_assistant_repository.dart';
import '../repositories/repository_failure.dart';
import '../services/care_assistant_input_classifier.dart';
import 'core_providers.dart';
import 'hospital_directory_provider.dart';

const careAssistantWelcomeMessage =
    "Hi! Tell me what happened or what symptoms you're experiencing. I can share immediate first-aid steps when appropriate and help you find the right level of care. This guidance is not a diagnosis or a replacement for professional treatment.";

enum CareAssistantStatus {
  idle,
  responding,
  followUp,
  emergency,
  recommendationReady,
  error,
}

enum CareAssistantChatMessageRole { user, assistant }

class CareAssistantMessage {
  const CareAssistantMessage({
    required this.role,
    required this.text,
    this.images = const [],
  });

  final CareAssistantChatMessageRole role;
  final String text;
  final List<CareAssistantImage> images;
}

class CareAssistantRecommendation {
  const CareAssistantRecommendation({
    required this.hospitalId,
    required this.reasons,
    this.distanceKm,
    this.relevantServices = const [],
    this.relevantSpecialists = const [],
  });

  final String hospitalId;
  final List<String> reasons;
  final double? distanceKm;
  final List<String> relevantServices;
  final List<String> relevantSpecialists;
}

class CareAssistantConversation {
  const CareAssistantConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
    required this.status,
    required this.recommendations,
    required this.intent,
    required this.urgency,
    this.isPinned = false,
    this.isTitleEdited = false,
    this.recommendationSummary,
    this.isOffline = false,
    this.errorMessage,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<CareAssistantMessage> messages;
  final CareAssistantStatus status;
  final List<CareAssistantRecommendation> recommendations;
  final CareAssistantIntent intent;
  final CareAssistantUrgency urgency;
  final bool isPinned;
  final bool isTitleEdited;
  final String? recommendationSummary;
  final bool isOffline;
  final String? errorMessage;
}

class CareAssistantState {
  const CareAssistantState({
    required this.messages,
    required this.status,
    required this.recommendations,
    this.intent = CareAssistantIntent.unclear,
    this.urgency = CareAssistantUrgency.routine,
    this.recommendationSummary,
    this.isOffline = false,
    this.errorMessage,
    this.conversationId = 'default',
    this.conversationTitle = 'New consultation',
    this.conversations = const [],
    this.conversationPinned = false,
    this.conversationTitleEdited = false,
  });

  factory CareAssistantState.initial() => const CareAssistantState(
    messages: [
      CareAssistantMessage(
        role: CareAssistantChatMessageRole.assistant,
        text: careAssistantWelcomeMessage,
      ),
    ],
    status: CareAssistantStatus.idle,
    recommendations: [],
  );

  final List<CareAssistantMessage> messages;
  final CareAssistantStatus status;
  final List<CareAssistantRecommendation> recommendations;
  final CareAssistantIntent intent;
  final CareAssistantUrgency urgency;
  final String? recommendationSummary;
  final bool isOffline;
  final String? errorMessage;
  final String conversationId;
  final String conversationTitle;
  final List<CareAssistantConversation> conversations;
  final bool conversationPinned;
  final bool conversationTitleEdited;

  bool get isBusy => status == CareAssistantStatus.responding;
  bool get showEmergencyActions => urgency == CareAssistantUrgency.emergency;

  List<String> get recommendedHospitalIds => recommendations
      .map((recommendation) => recommendation.hospitalId)
      .toList(growable: false);

  String? get nearestRecommendedHospitalId {
    if (recommendations.isEmpty) return null;
    var nearest = recommendations.first;
    for (final recommendation in recommendations.skip(1)) {
      final distance = recommendation.distanceKm;
      if (distance != null &&
          (nearest.distanceKm == null || distance < nearest.distanceKm!)) {
        nearest = recommendation;
      }
    }
    return nearest.hospitalId;
  }

  String? nearestRecommendedHospitalIdFromCoordinates(
    List<HospitalDirectoryEntry> hospitals, {
    required double latitude,
    required double longitude,
  }) {
    if (recommendations.isEmpty) return null;
    final hospitalsById = {
      for (final hospital in hospitals) hospital.id: hospital,
    };
    final origin = LatLng(latitude, longitude);
    const distance = Distance();
    String? nearestId;
    double? nearestMeters;

    for (final recommendation in recommendations) {
      final hospital = hospitalsById[recommendation.hospitalId];
      if (hospital == null || !hospital.hasCoordinates) continue;
      final meters = distance(
        origin,
        LatLng(hospital.latitude!, hospital.longitude!),
      );
      if (nearestMeters == null || meters < nearestMeters) {
        nearestMeters = meters;
        nearestId = hospital.id;
      }
    }
    return nearestId;
  }

  bool get hasLocationAwareRecommendations => recommendations.any(
    (recommendation) => recommendation.distanceKm != null,
  );

  CareAssistantState copyWith({
    List<CareAssistantMessage>? messages,
    CareAssistantStatus? status,
    List<CareAssistantRecommendation>? recommendations,
    CareAssistantIntent? intent,
    CareAssistantUrgency? urgency,
    String? recommendationSummary,
    bool clearRecommendationSummary = false,
    bool? isOffline,
    String? errorMessage,
    bool clearError = false,
    String? conversationId,
    String? conversationTitle,
    List<CareAssistantConversation>? conversations,
    bool? conversationPinned,
    bool? conversationTitleEdited,
  }) => CareAssistantState(
    messages: messages ?? this.messages,
    status: status ?? this.status,
    recommendations: recommendations ?? this.recommendations,
    intent: intent ?? this.intent,
    urgency: urgency ?? this.urgency,
    recommendationSummary: clearRecommendationSummary
        ? null
        : recommendationSummary ?? this.recommendationSummary,
    isOffline: isOffline ?? this.isOffline,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    conversationId: conversationId ?? this.conversationId,
    conversationTitle: conversationTitle ?? this.conversationTitle,
    conversations: conversations ?? this.conversations,
    conversationPinned: conversationPinned ?? this.conversationPinned,
    conversationTitleEdited:
        conversationTitleEdited ?? this.conversationTitleEdited,
  );
}

final careAssistantProvider =
    NotifierProvider<CareAssistantController, CareAssistantState>(
      CareAssistantController.new,
    );

class CareAssistantController extends Notifier<CareAssistantState> {
  var _requestToken = 0;
  var _conversationSequence = 0;

  @override
  CareAssistantState build() => _newConversationState();

  Future<void> submit(
    String rawMessage, {
    List<CareAssistantImage> images = const [],
  }) async {
    final text = rawMessage.trim();
    if ((text.isEmpty && images.isEmpty) ||
        state.isBusy ||
        state.showEmergencyActions) {
      return;
    }

    final messageText = text.isEmpty
        ? 'Please help me understand the medical concern shown in this image.'
        : text;

    final token = ++_requestToken;
    final directory = ref.read(hospitalDirectoryProvider);
    final continuingMedicalConversation =
        state.intent == CareAssistantIntent.medical &&
        state.status == CareAssistantStatus.followUp;
    final profile = CareAssistantNeedProfile.fromText(
      messageText,
      continueMedicalConversation: continuingMedicalConversation,
    );
    final userMessage = CareAssistantMessage(
      role: CareAssistantChatMessageRole.user,
      text: messageText,
      images: images,
    );
    _publish(
      state.copyWith(
        messages: [...state.messages, userMessage],
        status: CareAssistantStatus.responding,
        recommendations: const [],
        clearRecommendationSummary: true,
        clearError: true,
        isOffline: false,
      ),
      title: state.messages.length == 1 && !state.conversationTitleEdited
          ? _titleFrom(text.isEmpty ? 'Image health concern' : text)
          : null,
    );

    if (profile.isEmergency) {
      final contact =
          ref.read(publicAppSettingsProvider).value?.emergencyNumber?.trim() ??
          '';
      final callInstruction = contact.isEmpty
          ? 'Contact your local emergency services'
          : 'Call $contact';
      _complete(
        token,
        directory: directory,
        profile: profile,
        reply: CareAssistantReply(
          message: '',
          intent: CareAssistantIntent.emergency,
          urgency: CareAssistantUrgency.emergency,
          firstAid: emergencyFirstAidFor(messageText),
        ),
        messageOverride:
            'This may require immediate medical attention. $callInstruction or go to the nearest emergency department now. Do not wait for an online consultation.',
      );
      return;
    }

    final repository = ref.read(careAssistantRepositoryProvider);
    if (repository == null) {
      if (profile.intent == CareAssistantIntent.nonMedical) {
        _complete(
          token,
          directory: directory,
          profile: profile,
          reply: const CareAssistantReply(
            message:
                'I can help with symptoms, healthcare needs, and finding an appropriate facility. Tell me what health concern you\'re experiencing.',
            intent: CareAssistantIntent.nonMedical,
            urgency: CareAssistantUrgency.routine,
          ),
        );
        return;
      }
      if (profile.intent == CareAssistantIntent.unclear) {
        _complete(
          token,
          directory: directory,
          profile: profile,
          reply: const CareAssistantReply(
            message: 'I want to make sure I understand what you need.',
            intent: CareAssistantIntent.unclear,
            urgency: CareAssistantUrgency.routine,
            followUpQuestion:
                'Are you experiencing a health symptom, looking for a type of care, or trying to find a healthcare facility?',
          ),
        );
        return;
      }
      _fail(token, 'The care assistant is temporarily unavailable.');
      return;
    }
    late final CareAssistantReply reply;
    try {
      reply = await repository.respond(
        messages: state.messages
            .map(
              (message) => CareAssistantTurn(
                role: message.role == CareAssistantChatMessageRole.user
                    ? CareAssistantMessageRole.user
                    : CareAssistantMessageRole.assistant,
                content: message.text,
              ),
            )
            .toList(growable: false),
        facilities: _candidateEntries(directory)
            .map(CareAssistantFacilitySnapshot.fromHospital)
            .toList(growable: false),
        images: images,
      );
    } on RepositoryFailure catch (error) {
      _fail(token, error.message);
      return;
    } catch (_) {
      _fail(token, 'The care assistant is temporarily unavailable.');
      return;
    }
    if (token != _requestToken) return;
    _complete(token, directory: directory, profile: profile, reply: reply);
  }

  void reset() {
    newChat();
  }

  void newChat() {
    _requestToken++;
    final conversations = _upsertConversation(state);
    state = _newConversationState().copyWith(conversations: conversations);
  }

  void selectConversation(String conversationId) {
    final conversation = state.conversations
        .where((item) => item.id == conversationId)
        .firstOrNull;
    if (conversation == null || conversation.id == state.conversationId) {
      return;
    }
    _requestToken++;
    final updatedAt = DateTime.now();
    final selected = CareAssistantConversation(
      id: conversation.id,
      title: conversation.title,
      updatedAt: updatedAt,
      messages: conversation.messages,
      status: conversation.status,
      recommendations: conversation.recommendations,
      intent: conversation.intent,
      urgency: conversation.urgency,
      isPinned: conversation.isPinned,
      isTitleEdited: conversation.isTitleEdited,
      recommendationSummary: conversation.recommendationSummary,
      isOffline: conversation.isOffline,
      errorMessage: conversation.errorMessage,
    );
    final conversations = [
      selected,
      ...state.conversations.where((item) => item.id != selected.id),
    ];
    state = CareAssistantState(
      messages: selected.messages,
      status: selected.status,
      recommendations: selected.recommendations,
      intent: selected.intent,
      urgency: selected.urgency,
      recommendationSummary: selected.recommendationSummary,
      isOffline: selected.isOffline,
      errorMessage: selected.errorMessage,
      conversationId: selected.id,
      conversationTitle: selected.title,
      conversations: conversations,
      conversationPinned: selected.isPinned,
      conversationTitleEdited: selected.isTitleEdited,
    );
  }

  void renameConversation(String conversationId, String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) return;
    if (conversationId == state.conversationId) {
      _publish(
        state.copyWith(conversationTitle: title, conversationTitleEdited: true),
      );
      return;
    }
    state = state.copyWith(
      conversations: state.conversations
          .map(
            (conversation) => conversation.id == conversationId
                ? _copyConversation(
                    conversation,
                    title: title,
                    isTitleEdited: true,
                  )
                : conversation,
          )
          .toList(growable: false),
    );
  }

  void togglePinConversation(String conversationId) {
    if (conversationId == state.conversationId) {
      _publish(state.copyWith(conversationPinned: !state.conversationPinned));
      return;
    }
    state = state.copyWith(
      conversations: state.conversations
          .map(
            (conversation) => conversation.id == conversationId
                ? _copyConversation(
                    conversation,
                    isPinned: !conversation.isPinned,
                  )
                : conversation,
          )
          .toList(growable: false),
    );
  }

  void _complete(
    int token, {
    required HospitalDirectoryState directory,
    required CareAssistantNeedProfile profile,
    required CareAssistantReply reply,
    String? messageOverride,
  }) {
    if (token != _requestToken) return;

    // Only explicit deterministic emergency indicators can open the blocking
    // emergency UI. Potentially urgent but ambiguous symptoms remain
    // conversational until the user confirms severe warning signs.
    final emergency = profile.isEmergency;
    final backendOverEscalated =
        !emergency && reply.urgency == CareAssistantUrgency.emergency;
    final semanticIntent = reply.intent == CareAssistantIntent.emergency
        ? CareAssistantIntent.medical
        : reply.intent;
    final intent = emergency ? CareAssistantIntent.emergency : semanticIntent;
    final backendUrgency = backendOverEscalated
        ? CareAssistantUrgency.urgent
        : reply.urgency;
    final urgency = emergency
        ? CareAssistantUrgency.emergency
        : intent == CareAssistantIntent.nonMedical ||
              intent == CareAssistantIntent.unclear
        ? CareAssistantUrgency.routine
        : _moreUrgent(profile.urgency, backendUrgency);
    final followUp = emergency || intent == CareAssistantIntent.nonMedical
        ? null
        : (intent == CareAssistantIntent.medical
                  ? profile.safetyFollowUpQuestion ?? reply.followUpQuestion
                  : reply.followUpQuestion)
              ?.trim();
    final candidates = _candidateEntries(directory);
    final candidateIds = candidates.map((hospital) => hospital.id).toSet();
    var selectedIds = reply.recommendationIds
        .where(candidateIds.contains)
        .take(3)
        .toList(growable: false);

    if (!emergency &&
        selectedIds.isEmpty &&
        (followUp == null || followUp.isEmpty) &&
        profile.isReady) {
      selectedIds = _rankHospitals(
        candidates,
        profile,
        distanceById: reply.facilityDistances,
      ).take(3).map((hospital) => hospital.id).toList(growable: false);
    }

    if (profile.asksForNearest && reply.facilityDistances.isNotEmpty) {
      selectedIds = _sortIdsByDistance(selectedIds, reply.facilityDistances);
    }

    final recommendations = <CareAssistantRecommendation>[];
    for (final id in selectedIds) {
      final hospital = directory.findById(id);
      if (hospital == null) continue;
      recommendations.add(
        CareAssistantRecommendation(
          hospitalId: id,
          distanceKm: reply.facilityDistances[id],
          relevantServices: _relevantServicesFor(hospital, profile),
          relevantSpecialists: _relevantSpecialistsFor(hospital, profile),
          reasons: _reasonsFor(hospital, profile),
        ),
      );
    }

    var message = backendOverEscalated
        ? 'I need a little more information to guide you safely.'
        : (messageOverride ?? reply.message).trim();
    final firstAid = emergency
        ? reply.firstAid
        : backendOverEscalated
        ? null
        : reply.firstAid;
    if (firstAid != null && firstAid.isComplete) {
      message = '$message\n\n${_formatFirstAid(firstAid)}';
    }
    if (!emergency && followUp != null && followUp.isNotEmpty) {
      if (!message.contains(followUp)) message = '$message\n\n$followUp';
    }

    final status = emergency
        ? CareAssistantStatus.emergency
        : recommendations.isNotEmpty
        ? CareAssistantStatus.recommendationReady
        : followUp != null && followUp.isNotEmpty
        ? CareAssistantStatus.followUp
        : CareAssistantStatus.idle;

    _publish(
      state.copyWith(
        messages: [
          ...state.messages,
          CareAssistantMessage(
            role: CareAssistantChatMessageRole.assistant,
            text: message,
          ),
        ],
        status: status,
        recommendations: recommendations,
        intent: intent,
        urgency: urgency,
        recommendationSummary: recommendations.isEmpty
            ? null
            : reply.locationUsed
            ? 'Recommendations use your saved address and published hospital coordinates. Distances are straight-line estimates; check Maps for the actual route and travel time.'
            : 'Recommendations are limited to facilities currently shown in the directory. Add a saved address to enable distance-aware ranking.',
        clearRecommendationSummary: recommendations.isEmpty,
        clearError: true,
      ),
    );
  }

  void _fail(int token, String message) {
    if (token != _requestToken) return;
    _publish(
      state.copyWith(
        status: CareAssistantStatus.error,
        recommendations: const [],
        errorMessage: message,
        isOffline: true,
      ),
    );
  }

  String _formatFirstAid(CareAssistantFirstAidGuidance guidance) {
    final buffer = StringBuffer('Immediate first aid');
    for (var index = 0; index < guidance.immediateActions.length; index++) {
      buffer.write('\n${index + 1}. ${guidance.immediateActions[index]}');
    }
    buffer.write('\n\nWhat to avoid');
    for (final item in guidance.avoid) {
      buffer.write('\n• $item');
    }
    buffer.write('\n\nGet professional medical care if');
    for (final sign in guidance.warningSigns) {
      buffer.write('\n• $sign');
    }
    buffer.write(
      '\n\nFirst aid is temporary support, not a diagnosis or a replacement for professional treatment.',
    );
    return buffer.toString();
  }

  CareAssistantState _newConversationState() {
    _conversationSequence++;
    return CareAssistantState.initial().copyWith(
      conversationId:
          'chat-${DateTime.now().microsecondsSinceEpoch}-$_conversationSequence',
    );
  }

  void _publish(CareAssistantState next, {String? title}) {
    final titled = title == null
        ? next
        : next.copyWith(conversationTitle: title);
    state = titled.copyWith(conversations: _upsertConversation(titled));
  }

  List<CareAssistantConversation> _upsertConversation(
    CareAssistantState value,
  ) {
    final conversation = CareAssistantConversation(
      id: value.conversationId,
      title: value.conversationTitle,
      updatedAt: DateTime.now(),
      messages: value.messages,
      status: value.status,
      recommendations: value.recommendations,
      intent: value.intent,
      urgency: value.urgency,
      isPinned: value.conversationPinned,
      isTitleEdited: value.conversationTitleEdited,
      recommendationSummary: value.recommendationSummary,
      isOffline: value.isOffline,
      errorMessage: value.errorMessage,
    );
    return [
      conversation,
      ...value.conversations.where((item) => item.id != conversation.id),
    ];
  }

  CareAssistantConversation _copyConversation(
    CareAssistantConversation conversation, {
    String? title,
    bool? isPinned,
    bool? isTitleEdited,
  }) => CareAssistantConversation(
    id: conversation.id,
    title: title ?? conversation.title,
    updatedAt: conversation.updatedAt,
    messages: conversation.messages,
    status: conversation.status,
    recommendations: conversation.recommendations,
    intent: conversation.intent,
    urgency: conversation.urgency,
    isPinned: isPinned ?? conversation.isPinned,
    isTitleEdited: isTitleEdited ?? conversation.isTitleEdited,
    recommendationSummary: conversation.recommendationSummary,
    isOffline: conversation.isOffline,
    errorMessage: conversation.errorMessage,
  );

  String _titleFrom(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('chest pain')) return 'Chest Pain Concern';
    if (normalized.contains('headache') && normalized.contains('fever')) {
      return 'Headache and Fever';
    }
    if (normalized.contains('pediatric') ||
        normalized.contains('child') ||
        normalized.contains('baby')) {
      return 'Pediatric Care Recommendation';
    }
    if ((normalized.contains('near me') ||
            normalized.contains('nearest') ||
            normalized.contains('nearby')) &&
        (normalized.contains('er') || normalized.contains('hospital'))) {
      return 'Find ER Near Me';
    }
    final words = text
        .replaceAll(RegExp(r'[^A-Za-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(5)
        .map(
          (word) => word.length == 1
              ? word.toUpperCase()
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .toList(growable: false);
    return words.isEmpty ? 'New consultation' : words.join(' ');
  }

  static CareAssistantUrgency _moreUrgent(
    CareAssistantUrgency left,
    CareAssistantUrgency right,
  ) => left.index >= right.index ? left : right;

  List<HospitalDirectoryEntry> _candidateEntries(
    HospitalDirectoryState directory,
  ) {
    if (directory.filters.query.trim().isNotEmpty ||
        directory.filters.province != null ||
        directory.filters.careLevel != null ||
        directory.filters.service != null ||
        directory.filters.onlyAvailable) {
      return directory.filteredEntries;
    }
    return directory.entries;
  }

  List<HospitalDirectoryEntry> _rankHospitals(
    List<HospitalDirectoryEntry> candidates,
    CareAssistantNeedProfile profile, {
    Map<String, double> distanceById = const {},
  }) {
    final ranked = [
      for (final hospital in candidates)
        (
          hospital: hospital,
          score: _scoreHospital(hospital, profile),
          distanceKm: distanceById[hospital.id],
        ),
    ];
    ranked.sort((left, right) {
      if (profile.asksForNearest) {
        final distanceOrder = _compareDistances(
          left.distanceKm,
          right.distanceKm,
        );
        if (distanceOrder != 0) return distanceOrder;
      }
      final score = right.score.compareTo(left.score);
      if (score != 0) return score;
      final distanceOrder = _compareDistances(
        left.distanceKm,
        right.distanceKm,
      );
      if (distanceOrder != 0) return distanceOrder;
      return left.hospital.name.compareTo(right.hospital.name);
    });
    return ranked.map((item) => item.hospital).toList(growable: false);
  }

  List<String> _sortIdsByDistance(
    List<String> ids,
    Map<String, double> distanceById,
  ) {
    final sorted = [...ids];
    sorted.sort((left, right) {
      final distanceOrder = _compareDistances(
        distanceById[left],
        distanceById[right],
      );
      if (distanceOrder != 0) return distanceOrder;
      return left.compareTo(right);
    });
    return sorted;
  }

  int _compareDistances(double? left, double? right) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  double _scoreHospital(
    HospitalDirectoryEntry hospital,
    CareAssistantNeedProfile profile,
  ) {
    final searchable = _searchable(hospital);
    var score = 0.0;
    for (final capability in profile.capabilities) {
      if (_matchesCapability(searchable, capability)) score += 10;
    }
    if (profile.isEmergency && _matchesCapability(searchable, 'emergency')) {
      score += 8;
    }
    if (profile.isHighRiskChild &&
        _matchesCapability(searchable, 'pediatric')) {
      score += 8;
    }
    if (hospital.isAvailable) score += 4;
    return score;
  }

  List<String> _reasonsFor(
    HospitalDirectoryEntry hospital,
    CareAssistantNeedProfile profile,
  ) {
    final searchable = _searchable(hospital);
    final reasons = <String>[];
    final matched = {
      for (final capability in profile.capabilities)
        if (_matchesCapability(searchable, capability))
          _capabilityLabel(capability),
    }.toList(growable: false);
    if (matched.isNotEmpty) {
      reasons.add(
        'This facility publishes ${matched.join(', ')} relevant to ${profile.focusLabel}.',
      );
    } else {
      reasons.add(
        'This is a directory match, but the capability needed for ${profile.focusLabel} is not published; confirm suitability before traveling.',
      );
    }
    return reasons;
  }

  List<String> _relevantServicesFor(
    HospitalDirectoryEntry hospital,
    CareAssistantNeedProfile profile,
  ) {
    final published = {...hospital.departments, ...hospital.services};
    final relevant = <String>[];
    for (final label in published) {
      final normalized = label.toLowerCase();
      final matchesNeed = profile.capabilities.any(
        (capability) => _matchesCapability(normalized, capability),
      );
      final emergencySupport =
          profile.capabilities.contains('emergency') &&
          const [
            'cardio',
            'laboratory',
            'lab',
            'x-ray',
            'xray',
            'ct scan',
            'icu',
            'pharmacy',
          ].any(normalized.contains);
      if (matchesNeed || emergencySupport) relevant.add(label);
    }
    return relevant.take(5).toList(growable: false);
  }

  List<String> _relevantSpecialistsFor(
    HospitalDirectoryEntry hospital,
    CareAssistantNeedProfile profile,
  ) {
    final relevant = <String>[];
    for (final doctor in hospital.doctors) {
      final specialty = doctor.specialtyLabel.toLowerCase();
      final matches = profile.capabilities.any((capability) {
        final terms = switch (capability) {
          'pediatric' => const ['pediatric', 'paediatric'],
          'maternity' => const ['obstetric', 'gyneco', 'maternal'],
          'trauma' => const ['trauma', 'orthopedic', 'surgery', 'emergency'],
          'emergency' => const ['emergency', 'cardio'],
          'imaging' => const ['radiology', 'imaging'],
          'surgery' => const ['surgery', 'surgical'],
          _ => const ['general', 'family', 'internal medicine'],
        };
        return terms.any(specialty.contains);
      });
      if (matches && !relevant.contains(doctor.specialtyLabel)) {
        relevant.add(doctor.specialtyLabel);
      }
    }
    return relevant.take(3).toList(growable: false);
  }

  static String _searchable(HospitalDirectoryEntry hospital) => [
    hospital.name,
    hospital.careLevel,
    ...hospital.services,
    ...hospital.departments,
  ].join(' ').toLowerCase();

  static bool _matchesCapability(String value, String capability) {
    final terms = switch (capability) {
      'pediatric' => const ['pediatric', 'paediatric', 'children', 'child'],
      'maternity' => const [
        'maternity',
        'obstetric',
        'pregnancy',
        'labor',
        'delivery',
      ],
      'trauma' => const ['trauma', 'accident', 'fracture'],
      'emergency' => const ['emergency', 'urgent', 'er '],
      'imaging' => const [
        'imaging',
        'radiology',
        'x-ray',
        'xray',
        'ultrasound',
        'mri',
        'ct scan',
      ],
      'surgery' => const ['surgery', 'surgical', 'operating'],
      'general' => const ['family medicine', 'internal medicine', 'primary'],
      _ => [capability],
    };
    return terms.any(value.contains);
  }

  static String _capabilityLabel(String capability) => switch (capability) {
    'pediatric' => 'pediatric care',
    'maternity' => 'maternity care',
    'trauma' => 'trauma care',
    'emergency' => 'emergency care',
    'imaging' => 'imaging',
    'surgery' => 'surgical care',
    'general' => 'general care',
    _ => capability,
  };
}

class CareAssistantNeedProfile {
  const CareAssistantNeedProfile({
    required this.intent,
    required this.urgency,
    required this.isEmergency,
    required this.hasPatientType,
    required this.hasSeverity,
    required this.hasRecognizedConcern,
    required this.hasDuration,
    required this.isHighRiskChild,
    required this.patientType,
    required this.capabilities,
    required this.asksForNearest,
    required this.isExplicitlyNonMedical,
    this.safetyFollowUpQuestion,
  });

  factory CareAssistantNeedProfile.fromText(
    String rawText, {
    bool continueMedicalConversation = false,
  }) {
    final text = rawText.trim().toLowerCase();
    final initialClassification = classifyCareAssistantInput(text);
    final classification = continueMedicalConversation
        ? initialClassification.continueMedicalConversation()
        : initialClassification;
    final asksForNearest = _hasAny(text, const [
      'nearest',
      'closest',
      'near me',
      'nearby',
      'close to me',
      'around me',
    ]);
    final hasPatientType =
        _hasAny(text, const [
          'adult',
          'child',
          'kid',
          'infant',
          'baby',
          'toddler',
          'pediatric',
          'paediatric',
          'son',
          'daughter',
          'pregnant',
          'pregnancy',
          'maternity',
        ]) ||
        RegExp(r'\b\d{1,2}\s*[- ]?\s*(?:year|yr)[ -]?old\b').hasMatch(text);
    final patientType =
        _hasAny(text, const [
          'pregnant',
          'pregnancy',
          'maternity',
          'labor',
          'delivery',
        ])
        ? 'maternity'
        : _hasAny(text, const [
                'child',
                'kid',
                'infant',
                'baby',
                'toddler',
                'pediatric',
                'paediatric',
                'son',
                'daughter',
              ]) ||
              RegExp(
                r'\b\d{1,2}\s*[- ]?\s*(?:year|yr)[ -]?old\b',
              ).hasMatch(text)
        ? 'pediatric'
        : _hasAny(text, const ['adult'])
        ? 'adult'
        : null;
    final hasSeverity = _hasAny(text, const [
      'severe',
      'high fever',
      'very painful',
      'getting worse',
      'worsening',
      'cannot keep',
      'keeps vomiting',
      'heavy',
      'serious',
    ]);
    final hasDuration = _hasAny(text, const [
      'today',
      'yesterday',
      'hour',
      'hours',
      'day',
      'days',
      'week',
      'weeks',
      'since',
      'for ',
    ]);
    final respiratory = _hasAny(text, const [
      'breathing',
      'shortness of breath',
      'wheezing',
      'asthma',
    ]);
    final cardiac = _hasAny(text, const ['chest pain', 'heart pain']);
    final trauma = _hasAny(text, const [
      'accident',
      'injury',
      'injured',
      'fracture',
      'broken',
      'fall',
      'crash',
    ]);
    final feverOrVomiting = _hasAny(text, const ['fever', 'vomit', 'vomiting']);
    final stomach = _hasAny(text, const ['stomach', 'abdominal', 'belly']);
    final emergency = classification.isEmergency;
    final isHighRiskChild =
        patientType == 'pediatric' &&
        feverOrVomiting &&
        (_hasAny(text, const ['high fever', 'keeps vomiting', 'cannot keep']) ||
            hasSeverity);

    final capabilities = <String>[
      if (patientType == 'pediatric') 'pediatric',
      if (patientType == 'maternity') 'maternity',
      if (trauma) ...['trauma', 'imaging'],
      if (respiratory || cardiac || emergency || hasSeverity) 'emergency',
      if (_hasAny(text, const ['scan', 'x-ray', 'xray', 'imaging'])) 'imaging',
      if (_hasAny(text, const ['surgery', 'operation'])) 'surgery',
    ];
    if (capabilities.isEmpty && (stomach || feverOrVomiting)) {
      capabilities.add('general');
    }

    final recognizedHealthcareNeed =
        respiratory ||
        cardiac ||
        trauma ||
        feverOrVomiting ||
        stomach ||
        _hasAny(text, const [
          'pain',
          'rash',
          'infection',
          'dizzy',
          'headache',
          'doctor',
          'hospital',
          'clinic',
          'healthcare',
          'medical',
          'medicine',
          'checkup',
          'consultation',
          'swallow',
          'throat',
          'tonsil',
          'eat',
          'appetite',
          'chew',
          'mouth',
          'jaw',
          'cut',
          'wound',
          'burn',
          'scald',
          'sprain',
          'poison',
          'overdose',
          'bite',
          'sting',
          'nosebleed',
          'faint',
          'seizure',
          'choking',
          'allergic',
        ]);
    final intent = classification.intent;

    return CareAssistantNeedProfile(
      intent: intent,
      urgency: classification.urgency,
      isEmergency: emergency,
      hasPatientType: hasPatientType,
      hasSeverity: hasSeverity,
      hasRecognizedConcern: recognizedHealthcareNeed,
      hasDuration: hasDuration,
      isHighRiskChild: isHighRiskChild,
      patientType: patientType,
      capabilities: capabilities.isEmpty ? const ['general'] : capabilities,
      asksForNearest: asksForNearest,
      isExplicitlyNonMedical: initialClassification.isExplicitlyNonMedical,
      safetyFollowUpQuestion: classification.followUpQuestion,
    );
  }

  final bool isEmergency;
  final CareAssistantIntent intent;
  final CareAssistantUrgency urgency;
  final bool hasPatientType;
  final bool hasSeverity;
  final bool hasRecognizedConcern;
  final bool hasDuration;
  final bool isHighRiskChild;
  final String? patientType;
  final List<String> capabilities;
  final bool asksForNearest;
  final bool isExplicitlyNonMedical;
  final String? safetyFollowUpQuestion;

  bool get isReady =>
      hasRecognizedConcern &&
      (hasSeverity || hasDuration || isHighRiskChild || isEmergency);

  String get focusLabel {
    if (isHighRiskChild) {
      return 'pediatric assessment and appropriate emergency care';
    }
    if (patientType == 'pediatric') return 'pediatric assessment';
    if (patientType == 'maternity') return 'maternity or obstetric care';
    if (capabilities.contains('trauma')) return 'trauma assessment';
    if (capabilities.contains('imaging')) {
      return 'assessment with imaging if published';
    }
    if (capabilities.contains('surgery')) {
      return 'surgical assessment if needed';
    }
    if (capabilities.contains('emergency')) return 'appropriate emergency care';
    return 'the appropriate level of general care';
  }

  static bool _hasAny(String value, List<String> terms) =>
      terms.any(value.contains);
}
