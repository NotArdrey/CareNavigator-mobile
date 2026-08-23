import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hospitals/hospital_models.dart';
import '../repositories/hospital_repository.dart';
import '../repositories/repository_failure.dart';
import 'core_providers.dart';

final hospitalDirectoryProvider =
    NotifierProvider<HospitalDirectoryController, HospitalDirectoryState>(
      HospitalDirectoryController.new,
    );

class HospitalDirectoryState {
  const HospitalDirectoryState({
    required this.entries,
    required this.filters,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<HospitalDirectoryEntry> entries;
  final HospitalDirectoryFilters filters;
  final bool isLoading;
  final String? errorMessage;

  List<String> get provinces =>
      _uniqueSorted(entries.map((entry) => entry.province));

  List<String> get careLevels =>
      _uniqueSorted(entries.map((entry) => entry.careLevel));

  List<String> get services =>
      _uniqueSorted(entries.expand((entry) => entry.services));

  List<HospitalDirectoryEntry> get filteredEntries {
    final normalizedQuery = filters.query.trim().toLowerCase();
    final result = entries.where((entry) {
      final searchable = <String>[
        entry.name,
        entry.city,
        entry.province,
        entry.careLevel,
        ...entry.services,
        ...entry.departments,
        for (final doctor in entry.doctors) ...[
          doctor.displayLabel,
          doctor.specialtyLabel,
        ],
      ].join(' ').toLowerCase();
      return (normalizedQuery.isEmpty ||
              searchable.contains(normalizedQuery)) &&
          (filters.province == null || entry.province == filters.province) &&
          (filters.careLevel == null || entry.careLevel == filters.careLevel) &&
          (filters.service == null ||
              entry.services.contains(filters.service)) &&
          (!filters.onlyAvailable || entry.isAvailable);
    }).toList();

    switch (filters.sort) {
      case HospitalDirectorySort.relevance:
        break;
      case HospitalDirectorySort.distance:
        result.sort((left, right) => left.name.compareTo(right.name));
      case HospitalDirectorySort.availability:
        result.sort((left, right) {
          final availability = (right.isAvailable ? 1 : 0).compareTo(
            left.isAvailable ? 1 : 0,
          );
          if (availability != 0) return availability;
          return (left.estimatedWaitMinutes ?? 1 << 30).compareTo(
            right.estimatedWaitMinutes ?? 1 << 30,
          );
        });
    }
    return result;
  }

  HospitalDirectoryEntry? findById(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  HospitalDirectoryState copyWith({
    List<HospitalDirectoryEntry>? entries,
    HospitalDirectoryFilters? filters,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) => HospitalDirectoryState(
    entries: entries ?? this.entries,
    filters: filters ?? this.filters,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );

  static List<String> _uniqueSorted(Iterable<String> values) {
    final result =
        values
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return result;
  }
}

class HospitalDirectoryController extends Notifier<HospitalDirectoryState> {
  bool _refreshInProgress = false;
  StreamSubscription<void>? _directoryUpdateSubscription;

  @override
  HospitalDirectoryState build() {
    final repository = ref.watch(hospitalRepositoryProvider);
    if (repository == null) {
      return const HospitalDirectoryState(
        entries: [],
        filters: HospitalDirectoryFilters(),
        errorMessage: 'Hospital information is temporarily unavailable.',
      );
    }
    unawaited(Future<void>.microtask(() => _load(repository)));
    try {
      _directoryUpdateSubscription = repository
          .watchDirectoryUpdates()
          .skip(1)
          .listen(
            (_) => unawaited(_load(repository, showLoading: false)),
            onError: (_) {},
          );
      ref.onDispose(() => _directoryUpdateSubscription?.cancel());
    } catch (_) {
      // Test and offline repositories may not expose a live database stream.
    }
    return const HospitalDirectoryState(
      entries: [],
      filters: HospitalDirectoryFilters(),
      isLoading: true,
    );
  }

  Future<void> refresh() async {
    final repository = ref.read(hospitalRepositoryProvider);
    if (repository == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Hospital information is temporarily unavailable.',
      );
      return;
    }
    await _load(repository);
  }

  Future<void> _load(
    HospitalRepository repository, {
    bool showLoading = true,
  }) async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    if (showLoading) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final entries = await repository.loadPublicDirectory();
      state = state.copyWith(
        entries: entries,
        isLoading: false,
        clearError: true,
      );
    } on RepositoryFailure catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Hospital information could not be loaded. Try again.',
      );
    } finally {
      _refreshInProgress = false;
    }
  }

  void setQuery(String query) =>
      state = state.copyWith(filters: state.filters.copyWith(query: query));

  void setProvince(String? province) {
    if (province != null && !state.provinces.contains(province)) {
      throw ArgumentError.value(province, 'province', 'Unknown filter value.');
    }
    state = state.copyWith(
      filters: state.filters.copyWith(
        province: province,
        clearProvince: province == null,
      ),
    );
  }

  void setCareLevel(String? careLevel) {
    if (careLevel != null && !state.careLevels.contains(careLevel)) {
      throw ArgumentError.value(
        careLevel,
        'careLevel',
        'Unknown filter value.',
      );
    }
    state = state.copyWith(
      filters: state.filters.copyWith(
        careLevel: careLevel,
        clearCareLevel: careLevel == null,
      ),
    );
  }

  void setService(String? service) {
    if (service != null && !state.services.contains(service)) {
      throw ArgumentError.value(service, 'service', 'Unknown filter value.');
    }
    state = state.copyWith(
      filters: state.filters.copyWith(
        service: service,
        clearService: service == null,
      ),
    );
  }

  void setOnlyAvailable(bool value) => state = state.copyWith(
    filters: state.filters.copyWith(onlyAvailable: value),
  );

  void setSort(HospitalDirectorySort sort) =>
      state = state.copyWith(filters: state.filters.copyWith(sort: sort));

  void clearFilters() =>
      state = state.copyWith(filters: const HospitalDirectoryFilters());
}
