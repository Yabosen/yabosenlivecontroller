import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../api.dart';
import '../../format.dart';
import '../../heartbeat.dart';
import '../../settings.dart';
import '../permissions.dart';
import '../theme.dart';
import '../widgets.dart';

/// Toggle and diagnostics for the background heartbeat service.
class HeartbeatPanel extends StatefulWidget {
  const HeartbeatPanel({
    super.key,
    required this.heartbeat,
    required this.apiKey,
    required this.api,
  });

  final HeartbeatController heartbeat;
  final ApiKeyController apiKey;
  final YabosenApi api;

  @override
  State<HeartbeatPanel> createState() => _HeartbeatPanelState();
}

class _HeartbeatPanelState extends State<HeartbeatPanel> {
  PermissionSnapshot? _perms;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Re-check after returning from the system permission/battery screens.
    _lifecycle = AppLifecycleListener(onResume: _loadPermissions);
    _loadPermissions();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    final perms = await PermissionSnapshot.load();
    if (mounted) setState(() => _perms = perms);
  }

  Future<void> _toggle(bool enabled) async {
    if (enabled) {
      await requestHeartbeatPermissions(context, forceBatteryPrompt: true);
      if (!mounted) return;
    }
    final error = await widget.heartbeat.setEnabled(
      enabled,
      hasKey: widget.apiKey.hasKey,
    );
    if (!mounted) return;
    if (error != null) showErrorSnack(context, error);
    await _loadPermissions();
  }

  Future<void> _allowNotifications() async {
    await requestNotificationPermission();
    await _loadPermissions();
  }

  Future<void> _fixBattery() async {
    await requestBatteryExemption(context);
    await _loadPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.heartbeat, widget.apiKey]),
      builder: (context, _) {
        final hb = widget.heartbeat;
        final hasKey = widget.apiKey.hasKey;
        final last = hb.lastResult;
        final perms = _perms;

        return Panel(
          title: 'Background heartbeat',
          trailing: hb.busy
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
          children: [
            SwitchListTile(
              value: hb.enabled && hasKey,
              onChanged: hasKey && !hb.busy ? _toggle : null,
              title: const Text('Keep status alive'),
              subtitle: Text(
                hasKey
                    ? 'Pings the site every ${heartbeatInterval.inSeconds} s, '
                          'even when the app is closed or after a reboot.'
                    : 'Add an API key first.',
              ),
            ),
            const Divider(),
            const SizedBox(height: 4),
            KeyValueRow(
              label: 'Service',
              value: hb.running ? 'Running' : 'Stopped',
              valueColor: hb.running ? AppColors.success : AppColors.muted,
            ),
            KeyValueRow(
              label: 'Last beat',
              value: last == null
                  ? 'Never'
                  : '${formatTimestamp(last.at)} · '
                        '${last.ok ? last.message : 'failed'}',
              valueColor: last == null
                  ? AppColors.muted
                  : (last.ok ? AppColors.success : AppColors.error),
              action: TextButton(
                onPressed: hasKey && !hb.busy
                    ? () => hb.beatNow(widget.api)
                    : null,
                child: const Text('Send now'),
              ),
            ),
            if (last != null && !last.ok)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: InfoNote(last.message, icon: Icons.error_outline),
              ),
            if (perms != null) ...[
              KeyValueRow(
                label: 'Notifications',
                value: switch (perms.notifications) {
                  NotificationPermission.granted => 'Allowed',
                  NotificationPermission.denied => 'Not allowed',
                  NotificationPermission.permanently_denied =>
                    'Blocked in system settings',
                },
                valueColor:
                    perms.notifications == NotificationPermission.granted
                    ? null
                    : AppColors.error,
                action: perms.notifications == NotificationPermission.denied
                    ? TextButton(
                        onPressed: _allowNotifications,
                        child: const Text('Allow'),
                      )
                    : null,
              ),
              KeyValueRow(
                label: 'Battery',
                value: perms.batteryUnrestricted ? 'Unrestricted' : 'Optimised',
                valueColor: perms.batteryUnrestricted ? null : AppColors.error,
                action: perms.batteryUnrestricted
                    ? null
                    : TextButton(
                        onPressed: _fixBattery,
                        child: const Text('Fix'),
                      ),
              ),
            ],
            const SizedBox(height: 8),
            const InfoNote(
              'Some phones (Xiaomi, Samsung, Huawei…) also need "Autostart" '
              'or "Unrestricted" enabled in the app\'s system settings.',
            ),
          ],
        );
      },
    );
  }
}
