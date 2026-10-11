import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'src/heartbeat.dart';
import 'src/ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Port used by the heartbeat isolate to report results to the UI.
  FlutterForegroundTask.initCommunicationPort();
  HeartbeatService.init();
  runApp(const YabosenControllerApp());
}
