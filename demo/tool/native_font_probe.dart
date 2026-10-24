import 'dart:async';

import 'package:flutter/material.dart';

/// Standalone device diagnostic: deliberately imports no CCRouter code.
/// Run from demo with `flutter build apk --profile -t tool/native_font_probe.dart`.
void main() => runApp(const MaterialApp(home: _FontProbe()));

class _FontProbe extends StatefulWidget {
  const _FontProbe();

  @override
  State<_FontProbe> createState() => _FontProbeState();
}

class _FontProbeState extends State<_FontProbe> {
  static const _families = <String?>[null, 'sans-serif', 'serif', 'monospace'];
  Timer? _timer;
  int _index = -1;

  @override
  void initState() {
    super.initState();
    // Let the host record a stable baseline before rendering Chinese variants.
    _timer = Timer(const Duration(seconds: 15), () {
      debugPrint('FONT_PROBE start finite 72-style set, three rounds');
      _timer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
        setState(() => _index++);
        if (_index % 72 == 0) {
          debugPrint('FONT_PROBE round ${_index ~/ 72 + 1}');
        }
        if (_index == 215) {
          timer.cancel();
          debugPrint('FONT_PROBE completed; idle with final style');
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = _index < 0 ? 0 : _index % 72;
    return Scaffold(
      appBar: AppBar(title: const Text('Pure Flutter font probe')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('step $_index / 215'),
            Text(
              _index < 0
                  ? 'Latin baseline'
                  : 'CCRouter 导航 展示 生命周期 策略 诊断 中文测试 English 0123456789',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _families[index ~/ 18],
                fontWeight: FontWeight.values[index % 9],
                fontStyle: (index ~/ 9).isEven
                    ? FontStyle.normal
                    : FontStyle.italic,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
