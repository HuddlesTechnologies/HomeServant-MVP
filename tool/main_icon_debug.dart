import 'package:flutter/material.dart';
import 'package:homeservant/models/dashboard_theme.dart';
import 'package:homeservant/services/app_icon_service.dart';

void main() {
  runApp(const _IconDebugApp());
}

class _IconDebugApp extends StatefulWidget {
  const _IconDebugApp();

  @override
  State<_IconDebugApp> createState() => _IconDebugAppState();
}

class _IconDebugAppState extends State<_IconDebugApp> {
  String _log = 'starting';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _log = 'ICON_DEBUG applying sand');
    debugPrint('ICON_DEBUG applying sand');
    try {
      await AppIconService.apply(DashboardTheme.sand);
      debugPrint('ICON_DEBUG applied sand OK');
    } catch (e, st) {
      debugPrint('ICON_DEBUG FAILED sand: $e\n$st');
    }
    setState(() => _log = 'ICON_DEBUG done');
    debugPrint('ICON_DEBUG done');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Scaffold(body: Center(child: Text(_log))));
  }
}
