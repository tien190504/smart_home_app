import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/qr_image_scan_service.dart';
import '../logic/provisioning_controller.dart';
import '../models/provisioning_models.dart';

class AddDeviceScreen extends ConsumerStatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  ConsumerState<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends ConsumerState<AddDeviceScreen> {
  int _segment = 0;
  final _deviceCodeController = TextEditingController();
  final _pairingCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(provisioningControllerProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _deviceCodeController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(provisioningControllerProvider.notifier);
    final state = ref.watch(provisioningControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Device')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.mutedSurface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  for (final segment in const [
                    (0, 'Provision'),
                    (1, 'Add Manual'),
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _segment = segment.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _segment == segment.$1
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            segment.$2,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: _segment == segment.$1
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_segment == 0) ...[
              Text(
                'Looking for devices with QR codes',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const _WifiBluetoothHint(),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.qr_code_2_rounded,
                          color: Colors.white,
                          size: 160,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Scan the QR code attached to your device to start provisioning.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: kIsWeb
                    ? 'QR Scan On Mobile Only'
                    : 'Provision New Device',
                onPressed: kIsWeb ? null : () => context.push('/scan-device'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: kIsWeb ? null : _pickQrFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Use QR Image From Gallery'),
                  ),
                ),
              ),
            ] else ...[
              Text(
                'Link an existing device manually',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _deviceCodeController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Device code',
                  hintText: 'LAMP-LIVING-01',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _pairingCodeController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Pairing code',
                  hintText: 'K7COL6S2NX',
                ),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Link Device',
                loading: state.loading,
                onPressed: () => _manualProvision(context, controller),
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 16),
              DisabledFeatureBanner(
                title: 'Provisioning error',
                subtitle: state.errorMessage!,
                icon: Icons.error_outline_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _manualProvision(
    BuildContext context,
    ProvisioningController controller,
  ) async {
    try {
      await controller.manualProvision(
        deviceCode: _deviceCodeController.text,
        pairingCode: _pairingCodeController.text,
      );
      if (!context.mounted) {
        return;
      }
      context.go('/connected');
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      final message =
          ref.read(provisioningControllerProvider).errorMessage ??
          'Could not link this device manually.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pickQrFromGallery() async {
    // Prevent multiple concurrent selections
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final goRouter = GoRouter.of(context);

    final extraction = await ref.read(qrImageScanServiceProvider).pickFromGallery();

    // Widget is no longer mounted - user left the screen
    if (!mounted) {
      return;
    }

    if (extraction.errorMessage != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(extraction.errorMessage!)),
      );
      return;
    }

    final rawPayload = extraction.rawPayload;
    if (rawPayload == null) {
      // User cancelled - do nothing
      return;
    }

    final controller = ref.read(provisioningControllerProvider.notifier);
    try {
      final payload = controller.decodeQr(rawPayload);
      controller.startDraft(payload);

      scheduleProvisioningNavigation(() {
        if (!mounted) {
          return;
        }
        goRouter.push('/wifi-setup');
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('This QR code image is invalid or missing required fields.'),
        ),
      );
    }
  }
}

class ScanDeviceScreen extends ConsumerStatefulWidget {
  const ScanDeviceScreen({super.key});

  @override
  ConsumerState<ScanDeviceScreen> createState() => _ScanDeviceScreenState();
}

class _ScanDeviceScreenState extends ConsumerState<ScanDeviceScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan Device')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: DisabledFeatureBanner(
              title: 'QR camera scan is mobile-only',
              subtitle:
                  'Use the mobile app for camera-based QR scanning, or go back and link the device manually on web.',
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleCapture,
          ),
          const Positioned.fill(child: _ScannerOverlay()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _showManualQrDialog,
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (_handled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Processing QR code...',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    "Can't scan the QR code?",
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  PrimaryButton(
                    label: 'Enter setup code manually',
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    onPressed: _showManualQrDialog,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pickQrFromGallery,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Choose QR Image From Gallery'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    if (_handled) {
      return;
    }
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.trim().isEmpty) {
      return;
    }
    _handled = true;
    await _processQrPayload(value);
  }

  Future<void> _processQrPayload(String rawPayload) async {
    final controller = ref.read(provisioningControllerProvider.notifier);
    try {
      final payload = controller.decodeQr(rawPayload);
      controller.startDraft(payload);
      await _scannerController.stop();
      if (!mounted) {
        return;
      }
      scheduleProvisioningNavigation(() {
        if (!mounted) {
          return;
        }
        context.push('/wifi-setup');
      });
    } catch (_) {
      _handled = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This QR code is invalid or missing required fields.'),
        ),
      );
    }
  }

  Future<void> _showManualQrDialog() async {
    final controller = TextEditingController();
    final rawPayload = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Paste QR payload'),
          content: TextField(
            controller: controller,
            maxLines: 8,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '{"deviceCode":"LAMP-LIVING-01", ...}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (!mounted || rawPayload == null || rawPayload.trim().isEmpty) {
      return;
    }

    _handled = true;
    await _processQrPayload(rawPayload);
  }

  Future<void> _pickQrFromGallery() async {
    if (_handled) {
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Stop scanner while picking from gallery
    await _scannerController.stop();

    final extraction = await ref.read(qrImageScanServiceProvider).pickFromGallery();

    // Widget is no longer mounted - user left the screen
    if (!mounted) {
      return;
    }

    if (extraction.errorMessage != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(extraction.errorMessage!)),
      );
      // Restart scanner so user can try again
      await _scannerController.start();
      return;
    }

    final rawPayload = extraction.rawPayload;
    if (rawPayload == null) {
      // User cancelled - restart scanner
      await _scannerController.start();
      return;
    }

    _handled = true;
    await _processQrPayload(rawPayload);
  }
}

class ProofOfPossessionScreen extends ConsumerStatefulWidget {
  const ProofOfPossessionScreen({super.key, this.rawPayload});

  final Object? rawPayload;

  @override
  ConsumerState<ProofOfPossessionScreen> createState() =>
      _ProofOfPossessionScreenState();
}

class _ProofOfPossessionScreenState
    extends ConsumerState<ProofOfPossessionScreen> {
  late final TextEditingController _popController;

  @override
  void initState() {
    super.initState();
    Future<void>(_bootstrapDraft);
    final draft = ref.read(provisioningControllerProvider).draft;
    _popController = TextEditingController(text: draft?.pop ?? '');
  }

  @override
  void dispose() {
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(provisioningControllerProvider).draft;
    if (draft == null) {
      return const _MissingProvisionStateScreen();
    }

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter proof of possession PIN',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                'Enter the PoP PIN bundled with your device to verify ownership before setup continues.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              _DeviceSummaryCard(
                title: draft.qrPayload.deviceName,
                subtitle:
                    'Device code: ${draft.qrPayload.deviceCode}\nPairing code: ${draft.qrPayload.pairingCode}',
                icon: Icons.lightbulb_outline_rounded,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _popController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'PoP PIN',
                  hintText: '12345678',
                ),
              ),
              const Spacer(),
              PrimaryButton(label: 'Continue', onPressed: _continueToWifi),
            ],
          ),
        ),
      ),
    );
  }

  void _bootstrapDraft() {
    if (widget.rawPayload is! String) {
      return;
    }
    final state = ref.read(provisioningControllerProvider);
    if (state.draft != null) {
      return;
    }
    try {
      final controller = ref.read(provisioningControllerProvider.notifier);
      final payload = controller.decodeQr(widget.rawPayload! as String);
      controller.startDraft(payload);
    } catch (_) {
      // Leave the draft empty so the missing-state screen can guide recovery.
    }
  }

  void _continueToWifi() {
    final value = _popController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PoP PIN is required.')));
      return;
    }
    ref.read(provisioningControllerProvider.notifier).updatePop(value);
    context.push('/wifi-setup');
  }
}

class WifiSetupScreen extends ConsumerStatefulWidget {
  const WifiSetupScreen({super.key});

  @override
  ConsumerState<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends ConsumerState<WifiSetupScreen> {
  late final TextEditingController _ssidController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(provisioningControllerProvider).draft;
    _ssidController = TextEditingController(text: draft?.ssid ?? '');
    _passwordController = TextEditingController(text: draft?.password ?? '');
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(provisioningControllerProvider).draft;
    if (draft == null) {
      return const _MissingProvisionStateScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi Setup')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect ${draft.qrPayload.deviceName}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                'Provide the Wi-Fi credentials that will be sent to the device over your custom BLE setup channel.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              const _WifiBluetoothHint(),
              const SizedBox(height: 20),
              if (kIsWeb) ...[
                const DisabledFeatureBanner(
                  title: 'BLE provisioning is mobile-only',
                  subtitle:
                      'The web app hides this flow in normal navigation because Bluetooth provisioning must run on Android or iOS.',
                  icon: Icons.phone_android_rounded,
                ),
                const SizedBox(height: 18),
              ],
              TextFormField(
                controller: _ssidController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Wi-Fi SSID',
                  hintText: 'Home Wi-Fi',
                  prefixIcon: Icon(Icons.wifi_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Wi-Fi Password',
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _DeviceSummaryCard(
                title: 'BLE service',
                subtitle:
                    'Service UUID: ${draft.qrPayload.ble.serviceUuid}\nWrite: ${draft.qrPayload.ble.writeCharacteristicUuid}',
                icon: Icons.bluetooth_searching_rounded,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Continue',
                onPressed: kIsWeb ? null : _continueToProvision,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _continueToProvision() {
    final ssid = _ssidController.text;
    final password = _passwordController.text;
    if (ssid.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wi-Fi SSID is required.')),
      );
      return;
    }
    ref
        .read(provisioningControllerProvider.notifier)
        .updateWifi(ssid: ssid, password: password);
    context.push('/connecting');
  }
}

class ConnectingDeviceScreen extends ConsumerStatefulWidget {
  const ConnectingDeviceScreen({super.key});

  @override
  ConsumerState<ConnectingDeviceScreen> createState() =>
      _ConnectingDeviceScreenState();
}

class _ConnectingDeviceScreenState
    extends ConsumerState<ConnectingDeviceScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _startProvisioning();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(provisioningControllerProvider);
    final draft = state.draft;
    if (draft == null) {
      return const _MissingProvisionStateScreen();
    }

    final progress = state.progress;
    final isFailure = progress.stage == ProvisioningStage.failure;
    final canLinkAfterFailure =
        isFailure &&
        state.draft != null &&
        (state.errorMessage?.toLowerCase().contains('wi-fi') == true ||
            state.errorMessage?.toLowerCase().contains('timed out') == true);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Device')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Connect to device',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const _WifiBluetoothHint(),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          draft.qrPayload.deviceName,
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _ProvisioningProgressCircle(
                    progress: progress.progress,
                    child: Icon(
                      _deviceIconForName(draft.qrPayload.deviceName),
                      size: 110,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    isFailure ? 'Provisioning failed' : 'Connecting...',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    progress.message.isEmpty
                        ? 'Preparing your device setup...'
                        : progress.message,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${(progress.progress * 100).round()}%',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 18),
                    DisabledFeatureBanner(
                      title: 'Provisioning error',
                      subtitle: state.errorMessage!,
                      icon: Icons.error_outline_rounded,
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (isFailure)
                    Column(
                      children: [
                        PrimaryButton(
                          label: 'Retry Provisioning',
                          loading: state.loading,
                          onPressed: _startProvisioning,
                        ),
                        if (canLinkAfterFailure) ...[
                          const SizedBox(height: 12),
                          PrimaryButton(
                            label: 'Link Device Anyway',
                            loading: state.loading,
                            backgroundColor: AppColors.primarySoft,
                            foregroundColor: AppColors.primary,
                            onPressed: _linkDeviceAnyway,
                          ),
                        ],
                      ],
                    )
                  else
                    const SizedBox.shrink(),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/add-device'),
                    child: const Text('Back to Add Device'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startProvisioning() async {
    if (_started) {
      return;
    }
    _started = true;

    try {
      await ref.read(provisioningControllerProvider.notifier).runProvisioning();
      if (!mounted) {
        return;
      }
      context.go('/connected');
    } catch (_) {
      _started = false;
    }
  }

  Future<void> _linkDeviceAnyway() async {
    if (_started) {
      return;
    }
    _started = true;

    try {
      await ref
          .read(provisioningControllerProvider.notifier)
          .linkCurrentDraftAfterFailure();
      if (!mounted) {
        return;
      }
      context.go('/connected');
    } catch (_) {
      _started = false;
    }
  }
}

class ConnectedDeviceScreen extends ConsumerWidget {
  const ConnectedDeviceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provisioningControllerProvider);
    final result = state.result;
    final progress = state.progress;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 52,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Connected!',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 12),
              Text(
                result == null
                    ? 'Your device has been linked successfully.'
                    : 'You have connected to ${result.deviceName}.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Icon(
                  _deviceIconForName(result?.deviceName ?? 'Smart Device'),
                  color: AppColors.primary,
                  size: 104,
                ),
              ),
              const SizedBox(height: 24),
              if (result != null)
                _DeviceSummaryCard(
                  title: result.deviceName,
                  subtitle:
                      'Device code: ${result.deviceCode}\nRealtime status will now update over MQTT.',
                  icon: Icons.wifi_tethering_rounded,
                ),
              const Spacer(),
              if (progress.stage == ProvisioningStage.success &&
                  progress.message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    progress.message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: 'Go to Homepage',
                      backgroundColor: AppColors.primarySoft,
                      foregroundColor: AppColors.primary,
                      onPressed: () => context.go('/home'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Control Device',
                      onPressed: result == null
                          ? null
                          : () => context.go('/device/${result.deviceId}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingProvisionStateScreen extends StatelessWidget {
  const _MissingProvisionStateScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DisabledFeatureBanner(
                title: 'Provisioning state is missing',
                subtitle:
                    'Restart the Add Device flow so the QR payload, PoP PIN, and BLE metadata are available.',
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Back to Add Device',
                expanded: false,
                onPressed: () => context.go('/add-device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WifiBluetoothHint extends StatelessWidget {
  const _WifiBluetoothHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bluetooth_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Turn on your Wi-Fi and Bluetooth to connect',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.32),
              Colors.black.withValues(alpha: 0.12),
              Colors.black.withValues(alpha: 0.44),
            ],
          ),
        ),
        child: Center(
          child: Container(
            width: 300,
            height: 360,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.82),
                width: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProvisioningProgressCircle extends StatelessWidget {
  const _ProvisioningProgressCircle({
    required this.progress,
    required this.child,
  });

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 280,
            height: 280,
            child: CircularProgressIndicator(
              value: clamped,
              strokeWidth: 10,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}

class _DeviceSummaryCard extends StatelessWidget {
  const _DeviceSummaryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _deviceIconForName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('lamp') ||
      lower.contains('light') ||
      lower.contains('bulb')) {
    return Icons.lightbulb_outline_rounded;
  }
  if (lower.contains('camera') || lower.contains('cctv')) {
    return Icons.videocam_outlined;
  }
  if (lower.contains('speaker')) {
    return Icons.speaker_rounded;
  }
  if (lower.contains('router')) {
    return Icons.router_rounded;
  }
  return Icons.devices_other_outlined;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
