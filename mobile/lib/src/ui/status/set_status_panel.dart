import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api.dart';
import '../../models.dart';
import '../../status_controller.dart';
import '../theme.dart';
import '../widgets.dart';

/// Activities offered in the selector (listening is set by other tools).
const _selectableActivities = [
  ActivityKind.none,
  ActivityKind.playing,
  ActivityKind.watching,
];

/// Custom message, activity and the six status buttons.
class SetStatusPanel extends StatefulWidget {
  const SetStatusPanel({super.key, required this.controller});

  final StatusController controller;

  @override
  State<SetStatusPanel> createState() => _SetStatusPanelState();
}

class _SetStatusPanelState extends State<SetStatusPanel> {
  final _message = TextEditingController();
  final _game = TextEditingController();
  final _show = TextEditingController();
  final _season = TextEditingController();
  final _episode = TextEditingController();

  ActivityKind _activity = ActivityKind.none;
  StatusKind? _sending;

  StatusController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final status = _controller.status;
    if (status != null) {
      _prefill(status);
    } else {
      _controller.addListener(_onFirstStatus);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onFirstStatus);
    for (final c in [_message, _game, _show, _season, _episode]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onFirstStatus() {
    final status = _controller.status;
    if (status == null) return;
    _controller.removeListener(_onFirstStatus);
    final untouched =
        _activity == ActivityKind.none &&
        [
          _message,
          _game,
          _show,
          _season,
          _episode,
        ].every((c) => c.text.isEmpty);
    // Don't overwrite anything the user typed before the first load.
    if (untouched) setState(() => _prefill(status));
  }

  /// Copies the server status into the form so tweaks start from it.
  void _prefill(LiveStatus status) {
    _message.text = status.customMessage ?? '';
    final name = status.activityName ?? '';
    switch (status.activity) {
      case ActivityKind.playing:
        _activity = ActivityKind.playing;
        _game.text = name;
      case ActivityKind.watching:
        _activity = ActivityKind.watching;
        _show.text = name;
        _season.text = StatusUpdate.seasonForEditing(status.seasonInfo) ?? '';
        _episode.text = status.episodeInfo ?? '';
      case ActivityKind.listening || ActivityKind.none:
        break;
    }
  }

  StatusUpdate? _buildUpdate(StatusKind status) {
    switch (_activity) {
      case ActivityKind.playing:
        if (_game.text.trim().isEmpty) {
          showErrorSnack(context, 'Enter the game name, or pick "None".');
          return null;
        }
        return StatusUpdate(
          status: status,
          customMessage: _message.text,
          activity: ActivityKind.playing,
          activityName: _game.text,
        );
      case ActivityKind.watching:
        if (_show.text.trim().isEmpty) {
          showErrorSnack(context, 'Enter the show name, or pick "None".');
          return null;
        }
        return StatusUpdate(
          status: status,
          customMessage: _message.text,
          activity: ActivityKind.watching,
          activityName: _show.text,
          seasonInfo: _season.text,
          episodeInfo: _episode.text,
        );
      case ActivityKind.listening || ActivityKind.none:
        return StatusUpdate(status: status, customMessage: _message.text);
    }
  }

  Future<void> _send(StatusKind status) async {
    final update = _buildUpdate(status);
    if (update == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = status);
    try {
      await _controller.setStatus(update);
      await HapticFeedback.mediumImpact();
      if (mounted) showInfoSnack(context, 'Status set to ${status.label}');
    } on ApiException catch (e) {
      await HapticFeedback.heavyImpact();
      if (mounted) showErrorSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Set status',
      children: [
        _ClearableField(
          controller: _message,
          label: 'Custom message',
          hint: 'Optional, e.g. "brb food"',
          icon: Icons.chat_bubble_outline,
        ),
        const SizedBox(height: 12),
        SegmentedButton<ActivityKind>(
          showSelectedIcon: false,
          segments: [
            for (final kind in _selectableActivities)
              ButtonSegment(value: kind, label: Text(kind.label)),
          ],
          selected: {_activity},
          onSelectionChanged: (selection) =>
              setState(() => _activity = selection.first),
        ),
        ..._activityFields(),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final status = _controller.status;
            return _StatusButtonGrid(
              // Highlight what is stored, even if the site shows an idle
              // override because the PC is off.
              current: status?.storedStatus ?? status?.status,
              sending: _sending,
              onPressed: _send,
            );
          },
        ),
      ],
    );
  }

  List<Widget> _activityFields() {
    switch (_activity) {
      case ActivityKind.playing:
        return [
          const SizedBox(height: 12),
          _ClearableField(
            controller: _game,
            label: 'Game',
            hint: 'e.g. Counter-Strike 2',
            icon: Icons.sports_esports_outlined,
          ),
        ];
      case ActivityKind.watching:
        return [
          const SizedBox(height: 12),
          _ClearableField(
            controller: _show,
            label: 'Show',
            hint: 'e.g. Frieren',
            icon: Icons.live_tv_outlined,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ClearableField(
                  controller: _season,
                  label: 'Season',
                  hint: '1',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ClearableField(
                  controller: _episode,
                  label: 'Episode',
                  hint: '3',
                ),
              ),
            ],
          ),
        ];
      case ActivityKind.listening || ActivityKind.none:
        return const [];
    }
  }
}

class _ClearableField extends StatelessWidget {
  const _ClearableField({
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: controller.clear,
                ),
        ),
      ),
    );
  }
}

class _StatusButtonGrid extends StatelessWidget {
  const _StatusButtonGrid({
    required this.current,
    required this.sending,
    required this.onPressed,
  });

  final StatusKind? current;
  final StatusKind? sending;
  final ValueChanged<StatusKind> onPressed;

  @override
  Widget build(BuildContext context) {
    const spacing = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - spacing * 2) / 3;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final kind in StatusKind.values)
              SizedBox(
                width: width,
                child: _StatusButton(
                  kind: kind,
                  selected: kind == current,
                  busy: kind == sending,
                  onPressed: sending == null ? () => onPressed(kind) : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.kind,
    required this.selected,
    required this.busy,
    required this.onPressed,
  });

  final StatusKind kind;
  final bool selected;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = kind.color;
    final enabled = onPressed != null;
    final background = selected
        ? color.withValues(alpha: 0.32)
        : color.withValues(alpha: 0.12);

    return Semantics(
      button: true,
      selected: selected,
      label: 'Set status ${kind.label}',
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: kBorderRadius,
          side: BorderSide(
            color: color.withValues(alpha: selected ? 1 : 0.55),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: kShape,
          splashColor: color.withValues(alpha: 0.3),
          child: SizedBox(
            height: 52,
            child: Opacity(
              opacity: enabled || busy ? 1 : 0.6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                  else
                    StatusDot(color: color, size: 10),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      kind.shortLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
