import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api.dart';
import '../../format.dart';
import '../../models.dart';
import '../../settings.dart';
import '../theme.dart';
import '../widgets.dart';

/// Edits the server-side sleep schedule.
class ScheduleTab extends StatefulWidget {
  const ScheduleTab({super.key, required this.api, required this.apiKey});

  final YabosenApi api;
  final ApiKeyController apiKey;

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  SleepSchedule? _saved;
  SleepSchedule? _draft;
  String? _loadError;
  bool _loading = false;
  bool _saving = false;
  Timer? _clock;

  bool get _dirty => _draft != null && _draft != _saved;

  @override
  void initState() {
    super.initState();
    _load();
    // Keeps the "Romania time now" hint current.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final schedule = await widget.api.fetchSleepSchedule();
      if (!mounted) return;
      setState(() {
        _saved = schedule;
        _draft = schedule;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      await widget.api.saveSleepSchedule(draft);
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _saved = draft);
      showInfoSnack(context, 'Sleep schedule saved');
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime({required bool sleepy}) async {
    final draft = _draft;
    if (draft == null) return;
    final current = _parseTime(sleepy ? draft.sleepyTime : draft.wakeyTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: sleepy ? 'SLEEPY TIME (ROMANIA)' : 'WAKEY TIME (ROMANIA)',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final value = SleepSchedule.formatTime(picked.hour, picked.minute);
    setState(() {
      _draft = sleepy
          ? draft.copyWith(sleepyTime: value)
          : draft.copyWith(wakeyTime: value);
    });
  }

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 0,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Panel(
            title: 'Sleep schedule',
            trailing: _loading
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Reload',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _load,
                  ),
            children: _draft == null ? _placeholder() : _editor(_draft!),
          ),
          const SizedBox(height: 12),
          const Panel(
            title: 'How it works',
            children: [
              InfoNote(
                'At sleepy time the site switches you to Sleeping, but only '
                'while your PC is off and your status is Online or Idle. '
                'DND, Streaming and Offline are never overridden.',
                icon: Icons.bedtime_outlined,
              ),
              SizedBox(height: 8),
              InfoNote(
                'After wakey time a Sleeping status goes back to Online.',
                icon: Icons.wb_sunny_outlined,
              ),
              SizedBox(height: 8),
              InfoNote(
                'This runs on the server, so it works even when this phone '
                'is off.',
                icon: Icons.cloud_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _placeholder() => [
    if (_loadError != null) ...[
      InfoNote(_loadError!, icon: Icons.cloud_off_outlined),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: _load, child: const Text('Try again')),
    ] else
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('Loading…')),
      ),
  ];

  List<Widget> _editor(SleepSchedule draft) {
    final romaniaNow = formatHm(bucharestWallClock());
    return [
      SwitchListTile(
        value: draft.enabled,
        onChanged: (value) =>
            setState(() => _draft = draft.copyWith(enabled: value)),
        title: const Text('Automatic sleep'),
        subtitle: const Text('Sleeping at night, Online in the morning'),
      ),
      const Divider(),
      _TimeTile(
        icon: Icons.nightlight_outlined,
        label: 'Sleepy time',
        value: draft.sleepyTime,
        enabled: draft.enabled,
        onTap: () => _pickTime(sleepy: true),
      ),
      _TimeTile(
        icon: Icons.wb_twilight_outlined,
        label: 'Wakey time',
        value: draft.wakeyTime,
        enabled: draft.enabled,
        onTap: () => _pickTime(sleepy: false),
      ),
      const SizedBox(height: 8),
      InfoNote(
        'Times are Romania time (Europe/Bucharest). It is $romaniaNow there now.',
        icon: Icons.public,
      ),
      if (_loadError != null) ...[
        const SizedBox(height: 8),
        InfoNote(_loadError!, icon: Icons.cloud_off_outlined),
      ],
      const SizedBox(height: 16),
      ListenableBuilder(
        listenable: widget.apiKey,
        builder: (context, _) {
          final hasKey = widget.apiKey.hasKey;
          return Row(
            children: [
              if (_dirty)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _draft = _saved),
                  child: const Text('Revert'),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _dirty && hasKey && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(hasKey ? 'Save' : 'API key needed'),
              ),
            ],
          );
        },
      ),
    ];
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: enabled ? AppColors.accent : AppColors.muted),
      title: Text(label),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.field,
          borderRadius: kBorderRadius,
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            color: enabled ? AppColors.text : AppColors.muted,
          ),
        ),
      ),
      // Still editable while disabled, so times can be set before enabling.
      onTap: onTap,
    );
  }
}
