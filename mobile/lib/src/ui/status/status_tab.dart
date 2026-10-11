import 'package:flutter/material.dart';

import '../../settings.dart';
import '../../status_controller.dart';
import '../theme.dart';
import 'live_status_card.dart';
import 'set_status_panel.dart';

class StatusTab extends StatelessWidget {
  const StatusTab({
    super.key,
    required this.statusController,
    required this.apiKey,
    required this.onOpenSettings,
  });

  final StatusController statusController;
  final ApiKeyController apiKey;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => statusController.refresh(reloadAvatar: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          LiveStatusCard(controller: statusController),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: apiKey,
            builder: (context, _) => apiKey.isLoaded && !apiKey.hasKey
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _MissingKeyBanner(onOpenSettings: onOpenSettings),
                  )
                : const SizedBox.shrink(),
          ),
          SetStatusPanel(controller: statusController),
        ],
      ),
    );
  }
}

class _MissingKeyBanner extends StatelessWidget {
  const _MissingKeyBanner({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.selection.withValues(alpha: 0.18),
        borderRadius: kBorderRadius,
        border: Border.all(color: AppColors.selection),
      ),
      child: Row(
        children: [
          const Icon(Icons.key_outlined, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Add your API key to change your status.'),
          ),
          TextButton(onPressed: onOpenSettings, child: const Text('Settings')),
        ],
      ),
    );
  }
}
