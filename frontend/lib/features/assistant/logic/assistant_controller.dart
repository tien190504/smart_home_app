import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../devices/logic/device_dashboard_controller.dart';
import '../../weather/data/location_service.dart';
import '../../weather/models/weather_models.dart';
import '../data/assistant_api.dart';
import '../models/assistant_models.dart';

final assistantControllerProvider =
    StateNotifierProvider<AssistantController, AssistantState>((ref) {
      final controller = AssistantController(
        api: ref.watch(assistantApiProvider),
        locationService: ref.watch(currentLocationServiceProvider),
        dashboardController: ref.read(dashboardControllerProvider.notifier),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

class AssistantState {
  const AssistantState({
    required this.messages,
    required this.draft,
    required this.sending,
    required this.listening,
    required this.speechAvailable,
    this.errorMessage,
    this.voiceStatus,
  });

  factory AssistantState.initial() {
    return AssistantState(
      messages: [
        AssistantMessage(
          id: 'welcome',
          role: AssistantMessageRole.assistant,
          text:
              'Mình có thể trả lời chat, kiểm tra trạng thái thiết bị, lấy thời tiết và nhận lệnh giọng nói như "bật đèn phòng khách".',
          createdAt: DateTime.now(),
        ),
      ],
      draft: '',
      sending: false,
      listening: false,
      speechAvailable: false,
    );
  }

  final List<AssistantMessage> messages;
  final String draft;
  final bool sending;
  final bool listening;
  final bool speechAvailable;
  final String? errorMessage;
  final String? voiceStatus;

  AssistantState copyWith({
    List<AssistantMessage>? messages,
    String? draft,
    bool? sending,
    bool? listening,
    bool? speechAvailable,
    String? errorMessage,
    bool clearError = false,
    String? voiceStatus,
  }) {
    return AssistantState(
      messages: messages ?? this.messages,
      draft: draft ?? this.draft,
      sending: sending ?? this.sending,
      listening: listening ?? this.listening,
      speechAvailable: speechAvailable ?? this.speechAvailable,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      voiceStatus: voiceStatus ?? this.voiceStatus,
    );
  }
}

class AssistantController extends StateNotifier<AssistantState> {
  AssistantController({
    required AssistantApi api,
    required CurrentLocationService locationService,
    required DeviceDashboardController dashboardController,
  }) : _api = api,
       _locationService = locationService,
       _dashboardController = dashboardController,
       super(AssistantState.initial());

  final AssistantApi _api;
  final CurrentLocationService _locationService;
  final DeviceDashboardController _dashboardController;
  final SpeechToText _speechToText = SpeechToText();

  bool _initializingSpeech = false;
  bool _autoSubmitWhenListeningStops = false;
  bool _autoSubmitTriggered = false;

  Future<void> ensureSpeechReady() async {
    if (_speechToText.isAvailable || _initializingSpeech) {
      state = state.copyWith(speechAvailable: _speechToText.isAvailable);
      return;
    }

    _initializingSpeech = true;
    try {
      final available = await _speechToText.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );
      state = state.copyWith(
        speechAvailable: available,
        voiceStatus: available
            ? 'Voice assistant is ready.'
            : 'Speech recognition is unavailable on this device.',
      );
    } finally {
      _initializingSpeech = false;
    }
  }

  void updateDraft(String value) {
    state = state.copyWith(draft: value, clearError: true);
  }

  Future<void> sendDraft() async {
    await sendMessage(state.draft);
  }

  Future<void> sendMessage(String text) async {
    final message = text.trim();
    if (message.isEmpty || state.sending) {
      return;
    }

    final userMessage = AssistantMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      role: AssistantMessageRole.user,
      text: message,
      createdAt: DateTime.now(),
    );
    final placeholder = AssistantMessage(
      id: 'assistant-loading-${DateTime.now().microsecondsSinceEpoch}',
      role: AssistantMessageRole.assistant,
      text: 'Thinking...',
      createdAt: DateTime.now(),
      transient: true,
    );

    state = state.copyWith(
      draft: '',
      sending: true,
      messages: [...state.messages, userMessage, placeholder],
      clearError: true,
    );

    try {
      final location = await _resolveLocationForMessage(message);
      final reply = await _api.chat(
        message: message,
        latitude: location?.latitude,
        longitude: location?.longitude,
      );

      final messages = [...state.messages]
        ..removeWhere((message) => message.id == placeholder.id)
        ..add(
          AssistantMessage(
            id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
            role: AssistantMessageRole.assistant,
            text: reply.reply,
            createdAt: DateTime.now(),
            actions: reply.actions,
            weather: reply.weather,
          ),
        );

      state = state.copyWith(
        sending: false,
        messages: messages,
        clearError: true,
      );

      for (final action in reply.actions) {
        if (action.success && action.targetPower != null) {
          _dashboardController.applyExternalPowerUpdate(
            deviceId: action.deviceId,
            power: action.targetPower!,
          );
        }
      }
    } catch (_) {
      final messages = [...state.messages]
        ..removeWhere((message) => message.id == placeholder.id);
      state = state.copyWith(
        sending: false,
        messages: messages,
        errorMessage:
            'The assistant could not respond right now. Please try again.',
      );
    }
  }

  Future<void> startListening({bool autoSubmit = true}) async {
    await ensureSpeechReady();
    if (!_speechToText.isAvailable) {
      return;
    }

    _autoSubmitWhenListeningStops = autoSubmit;
    _autoSubmitTriggered = false;

    state = state.copyWith(
      listening: true,
      voiceStatus: 'Listening...',
      clearError: true,
    );

    await _speechToText.listen(
      onResult: _handleSpeechResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
  }

  Future<void> stopListening() async {
    await _speechToText.stop();
    state = state.copyWith(
      listening: false,
      voiceStatus: 'Listening stopped.',
    );
  }

  @override
  void dispose() {
    unawaited(_speechToText.stop());
    super.dispose();
  }

  Future<CurrentLocationSnapshot?> _resolveLocationForMessage(
    String message,
  ) async {
    if (_looksLikeWeatherRequest(message)) {
      return _locationService.tryResolveCurrentLocation(requestPermission: true);
    }

    return _locationService.tryResolveCurrentLocation(requestPermission: false);
  }

  bool _looksLikeWeatherRequest(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('weather') ||
        normalized.contains('temperature') ||
        normalized.contains('thời tiết') ||
        normalized.contains('thoi tiet') ||
        normalized.contains('nhiệt độ') ||
        normalized.contains('nhiet do');
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final transcript = result.recognizedWords.trim();
    state = state.copyWith(
      draft: transcript,
      voiceStatus: transcript.isEmpty ? 'Listening...' : 'Heard: $transcript',
    );

    if (result.finalResult &&
        _autoSubmitWhenListeningStops &&
        !_autoSubmitTriggered &&
        transcript.isNotEmpty) {
      _autoSubmitTriggered = true;
      unawaited(sendMessage(transcript));
    }
  }

  void _handleSpeechStatus(String status) {
    final listening = status == 'listening';
    state = state.copyWith(
      listening: listening,
      voiceStatus: listening ? 'Listening...' : 'Voice input is ready.',
    );

    if (!listening &&
        _autoSubmitWhenListeningStops &&
        !_autoSubmitTriggered &&
        state.draft.trim().isNotEmpty) {
      _autoSubmitTriggered = true;
      unawaited(sendMessage(state.draft));
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    state = state.copyWith(
      listening: false,
      errorMessage: error.errorMsg,
      voiceStatus: 'Voice recognition stopped.',
    );
  }
}
