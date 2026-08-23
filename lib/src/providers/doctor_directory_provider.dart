import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hospitals/hospital_models.dart';
import 'hospital_directory_provider.dart';

final doctorDirectoryProvider =
    NotifierProvider<DoctorDirectoryController, DoctorDirectoryState>(
      DoctorDirectoryController.new,
    );

class DoctorDirectoryState {
  const DoctorDirectoryState({required this.entries, required this.filters});

  final List<DoctorDirectoryEntry> entries;
  final DoctorDirectoryFilters filters;

  List<String> get specialties =>
      _uniqueSorted(entries.map((entry) => entry.doctor.specialtyLabel));

  List<String> get provinces =>
      _uniqueSorted(entries.map((entry) => entry.province));

  List<DoctorDirectoryEntry> get filteredEntries {
    final normalizedQuery = filters.query.trim().toLowerCase();
    final result = entries.where((entry) {
      final searchable = [
        entry.doctor.displayLabel,
        entry.doctor.specialtyLabel,
        entry.doctor.departmentLabel ?? '',
        entry.hospitalName,
        entry.city,
        entry.province,
      ].join(' ').toLowerCase();
      return (normalizedQuery.isEmpty ||
              searchable.contains(normalizedQuery)) &&
          (filters.specialty == null ||
              entry.doctor.specialtyLabel == filters.specialty) &&
          (filters.province == null || entry.province == filters.province) &&
          (!filters.onlineOnly || entry.doctor.offersOnlineCare) &&
          (!filters.availableFacilityOnly || entry.hospitalIsAvailable);
    }).toList();

    switch (filters.sort) {
      case DoctorDirectorySort.earliestAvailability:
        result.sort(
          (left, right) => left.doctor.nextAvailableAt.compareTo(
            right.doctor.nextAvailableAt,
          ),
        );
      case DoctorDirectorySort.distance:
        result.sort(
          (left, right) => (left.distanceKm ?? double.infinity).compareTo(
            right.distanceKm ?? double.infinity,
          ),
        );
      case DoctorDirectorySort.name:
        result.sort(
          (left, right) =>
              left.doctor.displayLabel.compareTo(right.doctor.displayLabel),
        );
    }
    return result;
  }

  DoctorDirectoryState copyWith({DoctorDirectoryFilters? filters}) =>
      DoctorDirectoryState(entries: entries, filters: filters ?? this.filters);

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

class DoctorDirectoryController extends Notifier<DoctorDirectoryState> {
  DoctorDirectoryFilters _filters = const DoctorDirectoryFilters();

  @override
  DoctorDirectoryState build() {
    final hospitals = ref.watch(hospitalDirectoryProvider);
    return DoctorDirectoryState(
      entries: [
        for (final hospital in hospitals.entries)
          for (final doctor in hospital.doctors)
            DoctorDirectoryEntry(
              doctor: doctor,
              hospitalId: hospital.id,
              hospitalName: hospital.name,
              city: hospital.city,
              province: hospital.province,
              hospitalIsAvailable: hospital.isAvailable,
              hospitalImageUrl: hospital.imageUrl,
            ),
      ],
      filters: _filters,
    );
  }

  void setQuery(String query) =>
      _setFilters(state.filters.copyWith(query: query));

  void setSpecialty(String? specialty) {
    if (specialty != null && !state.specialties.contains(specialty)) {
      throw ArgumentError.value(
        specialty,
        'specialty',
        'Unknown filter value.',
      );
    }
    _setFilters(
      state.filters.copyWith(
        specialty: specialty,
        clearSpecialty: specialty == null,
      ),
    );
  }

  void setProvince(String? province) {
    if (province != null && !state.provinces.contains(province)) {
      throw ArgumentError.value(province, 'province', 'Unknown filter value.');
    }
    _setFilters(
      state.filters.copyWith(
        province: province,
        clearProvince: province == null,
      ),
    );
  }

  void setOnlineOnly(bool value) =>
      _setFilters(state.filters.copyWith(onlineOnly: value));

  void setAvailableFacilityOnly(bool value) =>
      _setFilters(state.filters.copyWith(availableFacilityOnly: value));

  void setSort(DoctorDirectorySort sort) =>
      _setFilters(state.filters.copyWith(sort: sort));

  void clearFilters() => _setFilters(const DoctorDirectoryFilters());

  void _setFilters(DoctorDirectoryFilters filters) {
    _filters = filters;
    state = state.copyWith(filters: filters);
  }
}
