import 'package:flutter/material.dart';

import '../../format.dart';
import '../../models.dart';
import '../../status_controller.dart';
import '../theme.dart';
import '../widgets.dart';

/// Shows what the website currently displays.
class LiveStatusCard extends StatelessWidget {
  const LiveStatusCard({super.key, required this.controller});

  final StatusController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final status = controller.status;
        final error = controller.error;
        final muted = Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AppColors.muted);

        return Panel(
          title: 'Live on yabosen.live',
          trailing: controller.loading
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => controller.refresh(reloadAvatar: true),
                ),
          children: [
            Row(
              children: [
                AvatarThumb(
                  url: controller.api.avatarUri(
                    version: controller.avatarVersion,
                  ),
                  size: 64,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: status == null
                      ? Text(
                          error == null ? 'Loading…' : 'Status unavailable',
                          style: Theme.of(context).textTheme.titleMedium,
                        )
                      : _StatusSummary(status: status),
                ),
              ],
            ),
            if (status?.customMessage case final message?) ...[
              const SizedBox(height: 12),
              _MessageBubble(message: message),
            ],
            if (status != null) ...[
              const SizedBox(height: 12),
              Text(
                'Last updated ${formatTimestamp(status.updatedAt)}'
                ' · ${formatAgo(status.updatedAt)}',
                style: muted,
              ),
            ],
            if (status != null && status.isIdleOverride) ...[
              const SizedBox(height: 8),
              InfoNote(
                'Shown as Idle because your PC heartbeat is stale. '
                'Stored status: ${status.storedStatus!.label}.',
                icon: Icons.desktop_access_disabled_outlined,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              InfoNote(error, icon: Icons.cloud_off_outlined),
            ],
          ],
        );
      },
    );
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.status});

  final LiveStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = status.startedAt;
    final subtitle = [
      if (status.activityText != null) status.status.label,
      if (started != null) 'since ${formatTimestamp(started)}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatusDot(color: status.status.color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status.headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 2),
            child: Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.field,
        borderRadius: kBorderRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.format_quote, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}
