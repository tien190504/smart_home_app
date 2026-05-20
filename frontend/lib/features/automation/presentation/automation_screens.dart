import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../devices/logic/device_dashboard_controller.dart';
import '../logic/automation_controller.dart';
import '../models/automation_models.dart';

class SmartTabView extends ConsumerStatefulWidget {
  const SmartTabView({super.key});

  @override
  ConsumerState<SmartTabView> createState() => _SmartTabViewState();
}

class _SmartTabViewState extends ConsumerState<SmartTabView> {
  int _selectedIndex = 0;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      ref.read(automationControllerProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final automationState = ref.watch(automationControllerProvider);
    if (automationState.errorMessage != null &&
        automationState.errorMessage != _lastError) {
      _lastError = automationState.errorMessage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(automationState.errorMessage!)),
        );
      });
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(automationControllerProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 120),
        children: [
          Row(
            children: [
              Text('My Home', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded),
              const Spacer(),
              const _TopActionIcon(icon: Icons.article_outlined),
              const SizedBox(width: 12),
              const _TopActionIcon(icon: Icons.grid_view_rounded),
            ],
          ),
          const SizedBox(height: 20),
          _AutomationModeTabs(
            selectedIndex: _selectedIndex,
            onSelected: (index) => setState(() => _selectedIndex = index),
          ),
          const SizedBox(height: 20),
          if (_selectedIndex == 0) ...[
            if (automationState.loading && automationState.schedules.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (automationState.schedules.isEmpty)
              const _EmptyAutomationState()
            else
              for (final schedule in automationState.schedules) ...[
                _AutomationCard(schedule: schedule),
                const SizedBox(height: 16),
              ],
          ] else
            const _TapToRunPlaceholder(),
        ],
      ),
    );
  }
}

class AutomationEditorScreen extends ConsumerStatefulWidget {
  const AutomationEditorScreen({
    super.key,
    this.scheduleId,
    this.deviceId,
  });

  final int? scheduleId;
  final int? deviceId;

  bool get isEditing => scheduleId != null;

  @override
  ConsumerState<AutomationEditorScreen> createState() =>
      _AutomationEditorScreenState();
}

class _AutomationEditorScreenState
    extends ConsumerState<AutomationEditorScreen> {
  final _nameController = TextEditingController();
  final Set<int> _selectedDays = <int>{1, 2, 3, 4, 5, 6, 7};
  int? _selectedDeviceId;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 19, minute: 0);
  bool _enabled = true;
  bool _targetPower = true;
  bool _seeded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedDeviceId = widget.deviceId;
    Future<void>.microtask(() {
      ref.read(automationControllerProvider.notifier).initialize();
      ref.read(dashboardControllerProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardControllerProvider);
    final automationState = ref.watch(automationControllerProvider);
    final devices = dashboardState.devices;
    final hasSelectedDevice = devices.any((device) => device.id == _selectedDeviceId);
    final editingSchedule = widget.scheduleId == null
        ? null
        : automationState.schedules
              .where((schedule) => schedule.id == widget.scheduleId)
              .firstOrNull;

    if (!_seeded) {
      if (editingSchedule != null) {
        _seedFromSchedule(editingSchedule);
      } else if (_selectedDeviceId == null && devices.isNotEmpty) {
        _selectedDeviceId = devices.first.id;
        _nameController.text = '${devices.first.name} Schedule';
        _seeded = true;
      } else if (_selectedDeviceId != null || devices.isNotEmpty) {
        _nameController.text = _nameController.text.isEmpty
            ? 'Automation Schedule'
            : _nameController.text;
        _seeded = true;
      }
    }

    if (widget.isEditing && editingSchedule == null && automationState.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Automation' : 'Create Automation'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Schedule a device to turn on or off automatically at a fixed time.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Automation name',
                hintText: 'Morning lights',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: hasSelectedDevice ? _selectedDeviceId : null,
              decoration: const InputDecoration(labelText: 'Device'),
              selectedItemBuilder: (context) {
                return [
                  for (final device in devices)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${device.name} | ${device.roomLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ];
              },
              items: [
                for (final device in devices)
                  DropdownMenuItem<int>(
                    value: device.id,
                    child: Text(
                      '${device.name} | ${device.roomLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: devices.isEmpty
                  ? null
                  : (value) {
                      setState(() {
                        _selectedDeviceId = value;
                        if (_nameController.text.trim().isEmpty) {
                          final selected = devices
                              .where((device) => device.id == value)
                              .firstOrNull;
                          if (selected != null) {
                            _nameController.text = '${selected.name} Schedule';
                          }
                        }
                      });
                    },
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                    title: const Text('Automation enabled'),
                    subtitle: const Text('Keep this schedule active'),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _targetPower,
                    onChanged: (value) => setState(() => _targetPower = value),
                    title: Text(_targetPower ? 'Action: Turn On' : 'Action: Turn Off'),
                    subtitle: const Text(
                      'This command will be sent at the scheduled time',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _pickTime,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.schedule_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scheduled time',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatAutomationTime(_selectedTime),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Repeat on', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final day in const [1, 2, 3, 4, 5, 6, 7])
                  FilterChip(
                    label: Text(AutomationSchedule.weekdayLabel(day)),
                    selected: _selectedDays.contains(day),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedDays.add(day);
                        } else if (_selectedDays.length > 1) {
                          _selectedDays.remove(day);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: widget.isEditing ? 'Save Automation' : 'Create Automation',
              loading: _saving,
              onPressed: devices.isEmpty ? null : _save,
            ),
            if (widget.isEditing) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving || editingSchedule == null
                      ? null
                      : () => _delete(editingSchedule),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Delete Automation'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _seedFromSchedule(AutomationSchedule schedule) {
    _nameController.text = schedule.name;
    _selectedDeviceId = schedule.deviceId;
    _enabled = schedule.enabled;
    _targetPower = schedule.targetPower;
    _selectedTime = parseAutomationTime(schedule.timeOfDay);
    _selectedDays
      ..clear()
      ..addAll(schedule.daysOfWeek);
    _seeded = true;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _selectedTime = picked);
  }

  Future<void> _save() async {
    final selectedDeviceId = _selectedDeviceId;
    if (selectedDeviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a device first.')),
      );
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a schedule name.')),
      );
      return;
    }

    setState(() => _saving = true);
    final request = AutomationScheduleRequest(
      name: _nameController.text.trim(),
      deviceId: selectedDeviceId,
      enabled: _enabled,
      targetPower: _targetPower,
      timeOfDay: formatAutomationTime(_selectedTime),
      daysOfWeek: (_selectedDays.toList()..sort()),
      timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
    );

    try {
      final controller = ref.read(automationControllerProvider.notifier);
      if (widget.scheduleId == null) {
        await controller.createSchedule(request);
      } else {
        await controller.updateSchedule(widget.scheduleId!, request);
      }
      if (!mounted) {
        return;
      }
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Automation updated successfully.'
                : 'Automation created successfully.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this automation.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete(AutomationSchedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete automation?'),
          content: Text('Remove "${schedule.name}" from your schedule list.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(automationControllerProvider.notifier)
          .deleteSchedule(schedule.id);
      if (!mounted) {
        return;
      }
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Automation deleted.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this automation.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _AutomationModeTabs extends StatelessWidget {
  const _AutomationModeTabs({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final item in const [(0, 'Automation'), (1, 'Tap-to-Run')])
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: selectedIndex == item.$1
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    item.$2,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: selectedIndex == item.$1
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

class _AutomationCard extends ConsumerWidget {
  const _AutomationCard({required this.schedule});

  final AutomationSchedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => context.push('/automation/${schedule.id}/edit'),
      borderRadius: BorderRadius.circular(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          schedule.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${schedule.deviceName} • ${schedule.roomLabel}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetaPill(
                    icon: Icons.schedule_rounded,
                    color: const Color(0xFF4CAF50),
                    label: schedule.timeOfDay,
                  ),
                  _MetaPill(
                    icon: schedule.targetPower
                        ? Icons.wb_sunny_outlined
                        : Icons.nightlight_round,
                    color: schedule.targetPower
                        ? const Color(0xFFFF9F1C)
                        : const Color(0xFF4361EE),
                    label: schedule.actionLabel,
                  ),
                  _MetaPill(
                    icon: Icons.repeat_rounded,
                    color: const Color(0xFF7B61FF),
                    label: schedule.daysLabel,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      schedule.enabled
                          ? 'Automation is active'
                          : 'Automation is paused',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Switch(
                    value: schedule.enabled,
                    onChanged: (value) async {
                      try {
                        await ref
                            .read(automationControllerProvider.notifier)
                            .toggleEnabled(schedule, value);
                      } catch (_) {
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not update the schedule.'),
                          ),
                        );
                      }
                    },
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

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopActionIcon extends StatelessWidget {
  const _TopActionIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(icon, color: AppColors.textPrimary),
    );
  }
}

class _EmptyAutomationState extends StatelessWidget {
  const _EmptyAutomationState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.schedule_send_rounded,
              color: AppColors.primary,
              size: 34,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No automation yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first ON/OFF schedule to have devices run automatically.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TapToRunPlaceholder extends StatelessWidget {
  const _TapToRunPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DisabledFeatureBanner(
      title: 'Tap-to-Run is next',
      subtitle:
          'Scheduled automation is now available. Tap-to-run shortcuts can be layered on later without changing your schedules.',
      icon: Icons.bolt_rounded,
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
