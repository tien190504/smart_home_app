import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../automation/logic/automation_controller.dart';
import '../../automation/models/automation_models.dart';
import '../../automation/presentation/automation_screens.dart';
import '../../weather/logic/weather_controller.dart';
import '../../../core/config/connection_settings_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/logic/auth_controller.dart';
import '../logic/device_dashboard_controller.dart';
import '../models/device_models.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  int _currentIndex = 0;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      ref.read(dashboardControllerProvider.notifier).initialize();
      ref.read(automationControllerProvider.notifier).initialize();
      ref.read(weatherControllerProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardControllerProvider);
    if (dashboardState.errorMessage != null &&
        dashboardState.errorMessage != _lastError) {
      _lastError = dashboardState.errorMessage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(dashboardState.errorMessage!)));
      });
    }

    final pages = <Widget>[
      const HomeDashboardTab(),
      const SmartTabView(),
      const LockedTabView(
        title: 'Reports',
        subtitle:
            'Reports UI is kept in navigation but disabled until reporting APIs are available.',
        icon: Icons.insert_chart_outlined_rounded,
      ),
      const AccountTab(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_currentIndex]),
      floatingActionButton: switch (_currentIndex) {
        0 => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'voice',
                onPressed: () => context.push('/assistant?listen=1'),
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                child: const Icon(Icons.mic_none_rounded),
              ),
              const SizedBox(width: 12),
              FloatingActionButton(
                heroTag: 'addDevice',
                onPressed: () => context.push('/add-device'),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                child: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        1 => FloatingActionButton(
            heroTag: 'addAutomation',
            onPressed: () => context.push('/automation/new'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add_rounded),
          ),
        _ => null,
      },
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.smart_button_outlined),
            label: 'Smart',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            label: 'Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

class HomeDashboardTab extends ConsumerWidget {
  const HomeDashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardControllerProvider);
    final controller = ref.read(dashboardControllerProvider.notifier);

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final lightingDevices = controller.devicesForGroup(DeviceGroup.lighting);
    final cameraDevices = controller.devicesForGroup(DeviceGroup.cameras);
    final electricalDevices = controller.devicesForGroup(
      DeviceGroup.electrical,
    );
    final weatherController = ref.read(weatherControllerProvider.notifier);

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          controller.refresh(),
          weatherController.refresh(),
        ]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 130),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'My Home',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded),
                const Spacer(),
                _RoundIconButton(
                  icon: Icons.smart_toy_outlined,
                  onTap: () => context.push('/assistant'),
                ),
                const SizedBox(width: 12),
                _RoundIconButton(
                  icon: Icons.notifications_none_rounded,
                  badge: true,
                  onTap: () => _showInfo(
                    context,
                    'Notifications center is not available yet.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (state.brokerStatus != BrokerConnectionStatus.connected)
              _MqttStatusBanner(status: state.brokerStatus),
            if (state.brokerStatus != BrokerConnectionStatus.connected)
              const SizedBox(height: 14),
            const _WeatherCard(),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _CategoryCard(
                    title: 'Lighting',
                    subtitle: '${lightingDevices.length} devices',
                    icon: Icons.lightbulb_outline_rounded,
                    color: const Color(0xFFFFF3D9),
                    accent: const Color(0xFFF7B531),
                    onTap: () => context.push('/category/lighting'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CategoryCard(
                    title: 'Cameras',
                    subtitle: '${cameraDevices.length} devices',
                    icon: Icons.videocam_outlined,
                    color: const Color(0xFFF1ECFF),
                    accent: const Color(0xFF9C5FFF),
                    onTap: () => context.push('/category/cameras'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CategoryCard(
                    title: 'Electrical',
                    subtitle: '${electricalDevices.length} devices',
                    icon: Icons.bolt_outlined,
                    color: const Color(0xFFFFECE5),
                    accent: const Color(0xFFFF7A59),
                    onTap: () => context.push('/category/electrical'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SectionTitle(
              title: 'All Devices',
              trailing: IconButton(
                onPressed: controller.refresh,
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: state.rooms.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final room = state.rooms[index];
                  final active = room == state.selectedRoom;
                  return ChoiceChip(
                    label: Text(room),
                    selected: active,
                    onSelected: (_) => controller.setSelectedRoom(room),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            if (state.filteredDevices.isEmpty)
              _EmptyState(onAdd: () => context.push('/add-device'))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.filteredDevices.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.78,
                ),
                itemBuilder: (context, index) {
                  final device = state.filteredDevices[index];
                  return DeviceTile(
                    device: device,
                    onOpen: () => context.push('/device/${device.id}'),
                    onToggle: () => _toggleDevice(context, ref, device),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _toggleDevice(
  BuildContext context,
  WidgetRef ref,
  DeviceStateSnapshot device,
) async {
  try {
    await ref
        .read(dashboardControllerProvider.notifier)
        .toggleDevicePower(device);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

void _showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key, required this.groupKey});

  final String groupKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = DeviceGroupX.fromKey(groupKey);
    final dashboardState = ref.watch(dashboardControllerProvider);
    final devices = dashboardState.devices
        .where((device) => device.group == group)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text('${group.label} (${devices.length})')),
      body: devices.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No devices in ${group.label.toLowerCase()} yet.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: devices.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.8,
              ),
              itemBuilder: (context, index) {
                final device = devices[index];
                return DeviceTile(
                  device: device,
                  onOpen: () => context.push('/device/${device.id}'),
                  onToggle: () => _toggleDevice(context, ref, device),
                );
              },
            ),
    );
  }
}

class DeviceControlScreen extends ConsumerStatefulWidget {
  const DeviceControlScreen({super.key, required this.deviceId});

  final int deviceId;

  @override
  ConsumerState<DeviceControlScreen> createState() =>
      _DeviceControlScreenState();
}

class _DeviceControlScreenState extends ConsumerState<DeviceControlScreen> {
  String _selectedTab = 'White';

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      ref.read(automationControllerProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(
      dashboardControllerProvider.select(
        (state) => state.devices
            .where((item) => item.id == widget.deviceId)
            .firstOrNull,
      ),
    );
    final automationState = ref.watch(automationControllerProvider);

    if (device == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final lightingTabs = _lightingTabs(device);
    final selectedTab = _effectiveTab(device);
    final supportsColorTemperature =
        device.colorTemperature != null ||
        device.rawState.containsKey('colorTemperature') ||
        device.rawState.containsKey('color_temp');
    final isElectricalDevice =
        device.group == DeviceGroup.electrical || device.hasElectricalMetrics;
    final deviceSchedules = automationState.schedules
        .where((schedule) => schedule.deviceId == device.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/home');
          },
          icon: Icon(
            context.canPop() ? Icons.arrow_back_rounded : Icons.home_rounded,
          ),
          tooltip: context.canPop() ? 'Back' : 'Go to home',
        ),
        title: const Text('Control Device'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _DeviceIcon(kind: device.kind, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        device.roomLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: device.power,
                  onChanged: (_) => _sendToggle(device),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (device.kind == DeviceKind.lighting) ...[
              if (lightingTabs.length > 1)
                _SegmentTabs(
                  labels: lightingTabs,
                  selected: selectedTab,
                  onSelected: (value) async {
                    setState(() => _selectedTab = value);
                    await _sendLightingCommand(
                      device,
                      DeviceControlPayload(
                        power: device.power,
                        brightness: device.brightness,
                        mode: switch (value) {
                          'Color' => 'color',
                          'Scene' => 'scene',
                          _ => 'white',
                        },
                        scene: value == 'Scene' ? device.scene : null,
                        color: value == 'Color' ? device.color : null,
                        colorTemperature: value == 'White'
                            ? device.colorTemperature
                            : null,
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 280,
                        height: 250,
                        child: _LampGauge(
                          progress: device.brightness / 100,
                          tab: selectedTab,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.light_mode_outlined),
                          Expanded(
                            child: Slider(
                              value: device.brightness.clamp(1, 100) / 100,
                              onChanged: device.supportsBrightness
                                  ? (value) => _sendLightingCommand(
                                      device,
                                      DeviceControlPayload(
                                        power: device.power,
                                        brightness: (value * 100).round(),
                                        mode: device.mode,
                                        scene: selectedTab == 'Scene'
                                            ? device.scene
                                            : null,
                                        color: selectedTab == 'Color'
                                            ? device.color
                                            : null,
                                        colorTemperature: selectedTab == 'White'
                                            ? device.colorTemperature
                                            : null,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          Text('${device.brightness}%'),
                        ],
                      ),
                      if (selectedTab == 'White' &&
                          supportsColorTemperature) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Icon(Icons.thermostat_rounded),
                            Expanded(
                              child: Slider(
                                value:
                                    (((device.colorTemperature ?? 4200) -
                                                2700) /
                                            3800)
                                        .clamp(0.0, 1.0),
                                onChanged: (value) => _sendLightingCommand(
                                  device,
                                  DeviceControlPayload(
                                    power: device.power,
                                    brightness: device.brightness,
                                    mode: 'white',
                                    colorTemperature: (2700 + (value * 3800))
                                        .round(),
                                  ),
                                ),
                              ),
                            ),
                            Text('${device.colorTemperature ?? 4200}K'),
                          ],
                        ),
                      ],
                      if (selectedTab == 'Color' && device.supportsColor) ...[
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final color in const [
                              '#FFD166',
                              '#FF6B6B',
                              '#4D96FF',
                              '#22B573',
                              '#9C5FFF',
                            ])
                              _ColorPresetButton(
                                hexColor: color,
                                selected: device.color == color,
                                onTap: () => _sendLightingCommand(
                                  device,
                                  DeviceControlPayload(
                                    power: true,
                                    brightness: device.brightness,
                                    mode: 'color',
                                    color: color,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (selectedTab == 'Scene' && device.supportsScenes) ...[
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final scene in const [
                              'Relax',
                              'Focus',
                              'Movie',
                              'Sleep',
                            ])
                              ChoiceChip(
                                label: Text(scene),
                                selected: device.scene == scene,
                                onSelected: (_) => _sendLightingCommand(
                                  device,
                                  DeviceControlPayload(
                                    power: true,
                                    brightness: device.brightness,
                                    mode: 'scene',
                                    scene: scene,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      _StatusRow(
                        label: 'Online',
                        value: device.online ? 'Yes' : 'No',
                      ),
                      _StatusRow(
                        label: isElectricalDevice ? 'Load' : 'Power',
                        value: device.power ? 'On' : 'Off',
                      ),
                      if (isElectricalDevice) ...[
                        _StatusRow(
                          label: 'Relay',
                          value: switch (device.relayOnState) {
                            true => 'On',
                            false => 'Off',
                            null => '--',
                          },
                        ),
                        _StatusRow(
                          label: 'Switch',
                          value: switch (device.switchActiveState) {
                            true => 'Active',
                            false => 'Inactive',
                            null => '--',
                          },
                        ),
                        _StatusRow(
                          label: 'Measurement',
                          value: device.measurementValid ? 'Valid' : 'Waiting',
                        ),
                        _StatusRow(
                          label: 'Voltage',
                          value: device.voltageV != null
                              ? '${device.voltageV!.toStringAsFixed(1)} V'
                              : '--',
                        ),
                        _StatusRow(
                          label: 'Current',
                          value: device.currentA != null
                              ? '${device.currentA!.toStringAsFixed(3)} A'
                              : '--',
                        ),
                        _StatusRow(
                          label: 'Power W',
                          value: device.powerW != null
                              ? '${device.powerW!.toStringAsFixed(1)} W'
                              : '--',
                        ),
                        _StatusRow(
                          label: 'Energy',
                          value: device.energyKWh != null
                              ? '${device.energyKWh!.toStringAsFixed(3)} kWh'
                              : '--',
                        ),
                        _StatusRow(
                          label: 'Frequency',
                          value: device.frequencyHz != null
                              ? '${device.frequencyHz!.toStringAsFixed(1)} Hz'
                              : '--',
                        ),
                        _StatusRow(
                          label: 'PF',
                          value: device.powerFactor != null
                              ? device.powerFactor!.toStringAsFixed(2)
                              : '--',
                        ),
                      ] else ...[
                        _StatusRow(
                          label: 'Temperature',
                          value: device.temperature?.toStringAsFixed(1) ?? '--',
                        ),
                        _StatusRow(
                          label: 'Humidity',
                          value: device.humidity?.toStringAsFixed(1) ?? '--',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _DeviceAutomationPanel(
              schedules: deviceSchedules,
              onCreate: () => context.push('/automation/new?deviceId=${device.id}'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendToggle(DeviceStateSnapshot device) async {
    try {
      await ref
          .read(dashboardControllerProvider.notifier)
          .toggleDevicePower(device);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _sendLightingCommand(
    DeviceStateSnapshot device,
    DeviceControlPayload payload,
  ) async {
    try {
      await ref
          .read(dashboardControllerProvider.notifier)
          .sendCommand(deviceId: device.id, payload: payload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  List<String> _lightingTabs(DeviceStateSnapshot device) {
    final tabs = <String>['White'];
    if (device.supportsColor) {
      tabs.add('Color');
    }
    if (device.supportsScenes) {
      tabs.add('Scene');
    }
    return tabs;
  }

  String _effectiveTab(DeviceStateSnapshot device) {
    final tabs = _lightingTabs(device);
    if (tabs.contains(_selectedTab)) {
      return _selectedTab;
    }

    final modeTab = switch (device.mode.toLowerCase()) {
      'scene' => 'Scene',
      'color' => 'Color',
      _ => 'White',
    };
    if (tabs.contains(modeTab)) {
      return modeTab;
    }
    return tabs.first;
  }
}

class AccountTab extends ConsumerWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionSettingsControllerProvider);
    final config = connectionState.effectiveConfig;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(
            'Manage your LAN connection and sign-in session for this device.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          DisabledFeatureBanner(
            title: 'Active server',
            subtitle:
                'REST: ${config.restBaseUrl}\nMQTT: ${config.mqttTcpHost}:${config.mqttTcpPort}',
            icon: Icons.router_outlined,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/connection'),
              icon: const Icon(Icons.settings_ethernet_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Edit connection settings'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).logout();
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Sign out'),
              ),
            ),
          ),
          if (connectionState.usesRuntimeSettings) ...[
            const SizedBox(height: 18),
            Text(
              'This device will keep using the saved LAN server until you change it again.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class LockedTabView extends StatelessWidget {
  const LockedTabView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.device,
    required this.onOpen,
    required this.onToggle,
  });

  final DeviceStateSnapshot device;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      color: AppColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: _DeviceIcon(kind: device.kind, size: 28),
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: device.power,
                    onChanged: device.pendingCommand ? null : (_) => onToggle(),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                device.name,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                device.roomLabel,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    device.online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    size: 14,
                    color: device.online
                        ? AppColors.success
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      device.pendingCommand
                          ? 'Syncing...'
                          : device.online
                          ? 'Online'
                          : 'Offline',
                      style: Theme.of(context).textTheme.bodySmall,
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

class _DeviceAutomationPanel extends StatelessWidget {
  const _DeviceAutomationPanel({
    required this.schedules,
    required this.onCreate,
  });

  final List<AutomationSchedule> schedules;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Schedule Automatic ON/OFF',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            schedules.isEmpty
                ? 'Create a time-based automation for this device.'
                : 'This device already has ${schedules.length} automation schedule${schedules.length == 1 ? '' : 's'}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (schedules.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final schedule in schedules.take(3)) ...[
              _SchedulePreviewRow(schedule: schedule),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(schedules.isEmpty ? 'Create Schedule' : 'Add Another Schedule'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SchedulePreviewRow extends StatelessWidget {
  const _SchedulePreviewRow({required this.schedule});

  final AutomationSchedule schedule;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.name,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  '${schedule.daysLabel} • ${schedule.timeOfDay} • ${schedule.actionLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: schedule.enabled
                  ? AppColors.primarySoft
                  : AppColors.mutedSurface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              schedule.enabled ? 'On' : 'Paused',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _WeatherCard extends ConsumerWidget {
  const _WeatherCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weatherControllerProvider);
    final weather = state.weather;
    final location = state.location;

    final temperatureLabel = weather == null
        ? '--\u00B0C'
        : '${weather.temperatureC.toStringAsFixed(0)}\u00B0C';
    final addressLabel = location?.localityLabel ??
        (state.loading ? 'Detecting your location...' : 'Location unavailable');
    final subtitle = weather?.condition ??
        state.errorMessage ??
        (state.loading ? 'Loading weather...' : 'Tap refresh to retry');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF4B6BFF), Color(0xFF3D5BEA)],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  temperatureLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  addressLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFFFC641), Color(0xFFFF9F1C)],
              ),
            ),
            child: Icon(
              _weatherIconFor(weather?.iconKey),
              color: Colors.white,
              size: 54,
            ),
          ),
        ],
      ),
    );
  }

  IconData _weatherIconFor(String? iconKey) {
    return switch (iconKey) {
      'sunny' => Icons.wb_sunny_outlined,
      'night' => Icons.nightlight_round,
      'partly_cloudy' => Icons.cloud_queue_rounded,
      'cloudy' => Icons.cloud_outlined,
      'fog' => Icons.cloud_outlined,
      'drizzle' => Icons.grain_rounded,
      'rain' => Icons.umbrella_outlined,
      'snow' => Icons.ac_unit_rounded,
      'storm' => Icons.thunderstorm_outlined,
      _ => Icons.wb_cloudy_outlined,
    };
  }
}

class _MqttStatusBanner extends StatelessWidget {
  const _MqttStatusBanner({required this.status});

  final BrokerConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final title = switch (status) {
      BrokerConnectionStatus.connecting => 'Connecting to MQTT...',
      BrokerConnectionStatus.disconnected => 'Realtime connection is offline',
      BrokerConnectionStatus.connected => 'MQTT connected',
    };
    final color = switch (status) {
      BrokerConnectionStatus.connecting => AppColors.warning,
      BrokerConnectionStatus.disconnected => AppColors.error,
      BrokerConnectionStatus.connected => AppColors.success,
    };
    final icon = switch (status) {
      BrokerConnectionStatus.connecting => Icons.sync_rounded,
      BrokerConnectionStatus.disconnected => Icons.portable_wifi_off_rounded,
      BrokerConnectionStatus.connected => Icons.check_circle_outline_rounded,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.devices_other_outlined,
                size: 62,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Devices',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              'You have not added any devices yet.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Add Device',
              expanded: false,
              onPressed: onAdd,
              leading: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(width: 46, height: 46, child: Icon(icon)),
          ),
        ),
        if (badge)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _DeviceIcon extends StatelessWidget {
  const _DeviceIcon({required this.kind, required this.size});

  final DeviceKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Icon(
        switch (kind) {
          DeviceKind.lighting => Icons.lightbulb_outline_rounded,
          DeviceKind.camera => Icons.videocam_outlined,
          DeviceKind.speaker => Icons.speaker_rounded,
          DeviceKind.climate => Icons.ac_unit_rounded,
          DeviceKind.router => Icons.router_rounded,
          DeviceKind.electrical || DeviceKind.unknown => Icons.power_rounded,
        },
        color: AppColors.primary,
        size: size * 0.54,
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _ColorPresetButton extends StatelessWidget {
  const _ColorPresetButton({
    required this.hexColor,
    required this.selected,
    required this.onTap,
  });

  final String hexColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(
      int.parse(hexColor.substring(1), radix: 16) + 0xFF000000,
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.textPrimary : Colors.white,
            width: selected ? 3 : 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.26),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.mutedSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(label),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: selected == label
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: selected == label
                          ? Colors.white
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LampGauge extends StatelessWidget {
  const _LampGauge({required this.progress, required this.tab});

  final double progress;
  final String tab;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: const Size(280, 250),
          painter: _LampGaugePainter(progress: progress, tab: tab),
        ),
        const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_DeviceIcon(kind: DeviceKind.lighting, size: 84)],
        ),
      ],
    );
  }
}

class _LampGaugePainter extends CustomPainter {
  _LampGaugePainter({required this.progress, required this.tab});

  final double progress;
  final String tab;

  @override
  void paint(Canvas canvas, Size size) {
    const startAngle = 2.58;
    const sweepAngle = 4.12;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2.1),
      radius: size.width * 0.34,
    );

    final track = Paint()
      ..color = const Color(0xFFEAEFF7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweepAngle, false, track);

    final colors = switch (tab) {
      'Color' => const [Color(0xFFFF7A59), Color(0xFF9C5FFF)],
      'Scene' => const [Color(0xFF4D69F8), Color(0xFF22B573)],
      _ => const [Color(0xFFF8D372), Color(0xFFB9C8FF)],
    };

    final active = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: colors,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweepAngle * progress, false, active);
  }

  @override
  bool shouldRepaint(covariant _LampGaugePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.tab != tab;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
