import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../settings.dart';

/// Current state of the permissions the heartbeat relies on.
class PermissionSnapshot {
  const PermissionSnapshot({
    required this.notifications,
    required this.batteryUnrestricted,
  });

  static Future<PermissionSnapshot> load() async => PermissionSnapshot(
    notifications: await FlutterForegroundTask.checkNotificationPermission(),
    batteryUnrestricted:
        await FlutterForegroundTask.isIgnoringBatteryOptimizations,
  );

  final NotificationPermission notifications;
  final bool batteryUnrestricted;
}

/// Requests what the heartbeat service needs before it starts:
/// the notification permission (Android 13+) and, after a friendly
/// explanation, the battery optimisation exemption. The battery prompt is
/// shown automatically only once unless [forceBatteryPrompt] is set.
Future<void> requestHeartbeatPermissions(
  BuildContext context, {
  bool forceBatteryPrompt = false,
}) async {
  await requestNotificationPermission();
  if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) return;
  if (!forceBatteryPrompt && await AppSettings.getBatteryPromptShown()) return;
  if (!context.mounted) return;
  await requestBatteryExemption(context);
}

/// Asks for POST_NOTIFICATIONS when it can still be asked for.
Future<NotificationPermission> requestNotificationPermission() async {
  final current = await FlutterForegroundTask.checkNotificationPermission();
  if (current != NotificationPermission.denied) return current;
  return FlutterForegroundTask.requestNotificationPermission();
}

/// Explains why, then opens the system "ignore battery optimisations" prompt.
/// Returns whether the app is exempt afterwards.
Future<bool> requestBatteryExemption(BuildContext context) async {
  await AppSettings.setBatteryPromptShown();
  if (!context.mounted) return false;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.battery_saver_outlined),
      title: const Text('Keep the heartbeat alive'),
      content: const Text(
        'Android pauses background apps to save battery, which would stop the '
        'heartbeat and let your status go stale.\n\n'
        'On the next screen, allow Yabosen Controller to run in the '
        'background without restrictions. It only sends one tiny request '
        'per minute.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  if (proceed != true) return false;
  await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  return FlutterForegroundTask.isIgnoringBatteryOptimizations;
}
