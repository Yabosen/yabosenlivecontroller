import 'package:flutter/material.dart';

import '../../api.dart';
import '../../heartbeat.dart';
import '../../settings.dart';
import '../../status_controller.dart';
import '../theme.dart';
import 'api_key_panel.dart';
import 'avatar_panel.dart';
import 'heartbeat_panel.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.api,
    required this.apiKey,
    required this.heartbeat,
    required this.statusController,
    required this.onApiKeyChanged,
  });

  final YabosenApi api;
  final ApiKeyController apiKey;
  final HeartbeatController heartbeat;
  final StatusController statusController;
  final Future<void> Function() onApiKeyChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        ApiKeyPanel(apiKey: apiKey, onChanged: onApiKeyChanged),
        const SizedBox(height: 12),
        HeartbeatPanel(heartbeat: heartbeat, apiKey: apiKey, api: api),
        const SizedBox(height: 12),
        AvatarPanel(
          api: api,
          apiKey: apiKey,
          statusController: statusController,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Connected to ${api.baseUri.host}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
