import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/logic/auth_controller.dart';
import '../features/provisioning/data/qr_image_scan_service.dart';
import '../features/provisioning/logic/provisioning_controller.dart';
import '../core/navigation/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/config/connection_settings_controller.dart';

class SmartifyApp extends ConsumerStatefulWidget {
  const SmartifyApp({super.key});

  @override
  ConsumerState<SmartifyApp> createState() => _SmartifyAppState();
}

class _SmartifyAppState extends ConsumerState<SmartifyApp>
    with WidgetsBindingObserver {
  String? _pendingRecoveredQrPayload;
  bool _checkedLostQrSelection = false;
  bool _recoveryNavigationScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ref.read(connectionSettingsControllerProvider.notifier).autoDiscover(),
      );
      unawaited(_restoreLostQrSelection());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(connectionSettingsControllerProvider.notifier).autoDiscover(
          force: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final authState = ref.watch(authControllerProvider);
    final connectionState = ref.watch(connectionSettingsControllerProvider);

    if (_pendingRecoveredQrPayload != null &&
        authState.isAuthenticated &&
        !connectionState.requiresSetup &&
        !_recoveryNavigationScheduled) {
      _recoveryNavigationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recoveryNavigationScheduled = false;
        unawaited(_resumeRecoveredQrFlow(router));
      });
    }

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Smartify',
      theme: AppTheme.light,
      routerConfig: router,
    );
  }

  Future<void> _restoreLostQrSelection() async {
    if (_checkedLostQrSelection) {
      return;
    }
    _checkedLostQrSelection = true;

    final recovery = await ref
        .read(qrImageScanServiceProvider)
        .restoreLostSelection();

    if (!mounted) {
      return;
    }

    if (recovery.rawPayload != null && recovery.rawPayload!.trim().isNotEmpty) {
      setState(() => _pendingRecoveredQrPayload = recovery.rawPayload);
      return;
    }

    if (recovery.errorMessage != null) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(content: Text(recovery.errorMessage!)),
      );
    }
  }

  Future<void> _resumeRecoveredQrFlow(GoRouter router) async {
    final rawPayload = _pendingRecoveredQrPayload;
    if (!mounted || rawPayload == null || rawPayload.trim().isEmpty) {
      return;
    }

    try {
      final controller = ref.read(provisioningControllerProvider.notifier);
      final payload = controller.decodeQr(rawPayload);
      controller.startDraft(payload);
      setState(() => _pendingRecoveredQrPayload = null);
      router.go('/wifi-setup');
    } catch (_) {
      setState(() => _pendingRecoveredQrPayload = null);
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('The recovered QR image is invalid or incomplete.'),
        ),
      );
    }
  }
}
