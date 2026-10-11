import 'package:flutter/material.dart';

import '../api.dart';
import '../heartbeat.dart';
import '../settings.dart';
import '../status_controller.dart';
import 'permissions.dart';
import 'schedule/schedule_tab.dart';
import 'settings/settings_tab.dart';
import 'status/status_tab.dart';
import 'theme.dart';
import 'widgets.dart';

/// Root screen: owns the controllers and switches between the three tabs.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _statusTab = 0;
  static const _settingsTab = 2;

  final _api = YabosenApi();
  late final _apiKey = ApiKeyController(_api);
  late final _status = StatusController(_api);
  final _heartbeat = HeartbeatController();
  late final AppLifecycleListener _lifecycle;

  int _tab = _statusTab;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onShow: _onForeground,
      onHide: _status.stopPolling,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _status.dispose();
    _heartbeat.dispose();
    _apiKey.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _apiKey.load();
    await _heartbeat.load(hasKey: _apiKey.hasKey);
    _status.startPolling();
    if (!_apiKey.hasKey && mounted) setState(() => _tab = _settingsTab);
    await _syncHeartbeat();
  }

  void _onForeground() {
    _status.startPolling();
    _heartbeat.refresh();
  }

  /// Starts/stops the service to match the toggle and key, asking for the
  /// needed permissions first when it is about to start.
  Future<void> _syncHeartbeat() async {
    final hasKey = _apiKey.hasKey;
    if (_heartbeat.shouldRun(hasKey: hasKey) && !_heartbeat.running) {
      if (!mounted) return;
      await requestHeartbeatPermissions(context);
    }
    final error = await _heartbeat.apply(hasKey: hasKey);
    if (error != null && mounted) showErrorSnack(context, error);
  }

  Future<void> _onApiKeyChanged() async {
    _heartbeat.onApiKeyChanged(hasKey: _apiKey.hasKey);
    await _syncHeartbeat();
    await _status.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: ListenableBuilder(
          listenable: _status,
          builder: (context, _) => Row(
            children: [
              StatusDot(
                color: _status.status?.status.color ?? AppColors.muted,
                size: 10,
              ),
              const SizedBox(width: 10),
              const Text('Yabosen Controller'),
            ],
          ),
        ),
        actions: [
          ListenableBuilder(
            listenable: _heartbeat,
            builder: (context, _) => IconButton(
              tooltip: _heartbeat.running
                  ? 'Heartbeat running'
                  : 'Heartbeat stopped',
              icon: Icon(
                _heartbeat.running ? Icons.favorite : Icons.favorite_border,
                color: _heartbeat.running ? AppColors.accent : AppColors.muted,
              ),
              onPressed: () => setState(() => _tab = _settingsTab),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          StatusTab(
            statusController: _status,
            apiKey: _apiKey,
            onOpenSettings: () => setState(() => _tab = _settingsTab),
          ),
          ScheduleTab(api: _api, apiKey: _apiKey),
          SettingsTab(
            api: _api,
            apiKey: _apiKey,
            heartbeat: _heartbeat,
            statusController: _status,
            onApiKeyChanged: _onApiKeyChanged,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.circle_outlined),
            selectedIcon: Icon(Icons.circle),
            label: 'Status',
          ),
          NavigationDestination(
            icon: Icon(Icons.bedtime_outlined),
            selectedIcon: Icon(Icons.bedtime),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
