import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_models.dart';
import '../../auth/logic/auth_controller.dart';
import '../data/automation_api.dart';
import '../models/automation_models.dart';

final automationControllerProvider =
    StateNotifierProvider<AutomationController, AutomationState>((ref) {
      final controller = AutomationController(
        api: ref.watch(automationApiProvider),
      );

      ref.listen<AuthState>(authControllerProvider, (previous, next) {
        if (!next.isAuthenticated) {
          controller.reset();
          return;
        }
        unawaited(controller.initialize(forceRefresh: true));
      });

      ref.onDispose(controller.dispose);
      return controller;
    });

class AutomationState {
  const AutomationState({
    required this.loading,
    required this.schedules,
    this.errorMessage,
  });

  const AutomationState.initial()
    : this(
        loading: false,
        schedules: const [],
      );

  final bool loading;
  final List<AutomationSchedule> schedules;
  final String? errorMessage;

  AutomationState copyWith({
    bool? loading,
    List<AutomationSchedule>? schedules,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AutomationState(
      loading: loading ?? this.loading,
      schedules: schedules ?? this.schedules,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class AutomationController extends StateNotifier<AutomationState> {
  AutomationController({required AutomationApi api})
    : _api = api,
      super(const AutomationState.initial());

  final AutomationApi _api;

  bool _initialized = false;
  bool _loading = false;

  Future<void> initialize({bool forceRefresh = false}) async {
    if (_loading) {
      return;
    }
    if (_initialized && !forceRefresh) {
      return;
    }

    _loading = true;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final schedules = await _api.fetchSchedules();
      state = state.copyWith(
        loading: false,
        schedules: schedules,
        clearError: true,
      );
      _initialized = true;
    } catch (_) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Could not load automation schedules.',
      );
    } finally {
      _loading = false;
    }
  }

  Future<void> refresh() => initialize(forceRefresh: true);

  Future<AutomationSchedule> createSchedule(
    AutomationScheduleRequest request,
  ) async {
    final created = await _api.createSchedule(request);
    final schedules = [created, ...state.schedules]
      ..sort((left, right) => right.id.compareTo(left.id));
    state = state.copyWith(schedules: schedules, clearError: true);
    _initialized = true;
    return created;
  }

  Future<AutomationSchedule> updateSchedule(
    int scheduleId,
    AutomationScheduleRequest request,
  ) async {
    final updated = await _api.updateSchedule(scheduleId, request);
    final schedules = [...state.schedules];
    final index = schedules.indexWhere((item) => item.id == scheduleId);
    if (index >= 0) {
      schedules[index] = updated;
    } else {
      schedules.insert(0, updated);
    }
    state = state.copyWith(schedules: schedules, clearError: true);
    _initialized = true;
    return updated;
  }

  Future<void> deleteSchedule(int scheduleId) async {
    await _api.deleteSchedule(scheduleId);
    state = state.copyWith(
      schedules: state.schedules
          .where((schedule) => schedule.id != scheduleId)
          .toList(),
      clearError: true,
    );
  }

  Future<void> toggleEnabled(
    AutomationSchedule schedule,
    bool enabled,
  ) async {
    final optimistic = schedule.copyWith(enabled: enabled);
    _replace(optimistic);
    try {
      final updated = await _api.updateSchedule(
        schedule.id,
        schedule.toRequest().copyWith(enabled: enabled),
      );
      _replace(updated);
    } catch (_) {
      _replace(schedule);
      state = state.copyWith(
        errorMessage: 'Could not update the automation status.',
      );
      rethrow;
    }
  }

  void _replace(AutomationSchedule schedule) {
    final schedules = [...state.schedules];
    final index = schedules.indexWhere((item) => item.id == schedule.id);
    if (index >= 0) {
      schedules[index] = schedule;
    } else {
      schedules.insert(0, schedule);
    }
    state = state.copyWith(schedules: schedules, clearError: true);
  }

  void reset() {
    _initialized = false;
    _loading = false;
    state = const AutomationState.initial();
  }
}
