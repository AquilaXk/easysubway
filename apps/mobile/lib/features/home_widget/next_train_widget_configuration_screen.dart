import 'package:flutter/material.dart';

import 'next_train_widget_repository.dart';

typedef LoadWidgetSelections = Future<List<WidgetStationSelection>> Function();
typedef ConfigureWidget =
    Future<void> Function(WidgetStationSelection selection);

class NextTrainWidgetConfigurationScreen extends StatefulWidget {
  const NextTrainWidgetConfigurationScreen({
    required this.loadSelections,
    required this.configure,
    super.key,
  });

  final LoadWidgetSelections loadSelections;
  final ConfigureWidget configure;

  @override
  State<NextTrainWidgetConfigurationScreen> createState() =>
      _NextTrainWidgetConfigurationScreenState();
}

class _NextTrainWidgetConfigurationScreenState
    extends State<NextTrainWidgetConfigurationScreen> {
  late final Future<List<WidgetStationSelection>> _selections = widget
      .loadSelections();
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('위젯 역 선택')),
      body: FutureBuilder<List<WidgetStationSelection>>(
        future: _selections,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final selections = snapshot.data ?? const [];
          if (snapshot.hasError || selections.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('시간표가 있는 즐겨찾기 역이 없어요.'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('홈 화면에 표시할 역과 노선을 선택해 주세요.'),
              const SizedBox(height: 12),
              for (final selection in selections)
                ListTile(
                  enabled: !_submitting,
                  title: Text(selection.stationName),
                  subtitle: Text(selection.lineName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _configure(selection),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _configure(WidgetStationSelection selection) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.configure(selection);
    } on Object {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = '위젯을 설정하지 못했어요.';
        });
      }
    }
  }
}
