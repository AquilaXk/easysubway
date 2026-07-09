import 'dart:async';

import 'package:flutter/material.dart';

import 'data_pack_update_state.dart';

class DataPackMeteredConsentGate extends StatefulWidget {
  const DataPackMeteredConsentGate({
    required this.stateRepository,
    required this.child,
    this.onAccept,
    this.recheckAfter,
    super.key,
  });

  final DataPackUpdateStateRepository? stateRepository;
  final Future<void> Function()? onAccept;
  final Future<void>? recheckAfter;
  final Widget child;

  @override
  State<DataPackMeteredConsentGate> createState() =>
      _DataPackMeteredConsentGateState();
}

class _DataPackMeteredConsentGateState
    extends State<DataPackMeteredConsentGate> {
  bool _shown = false;
  bool _checking = false;
  bool _checkAgainAfterCurrent = false;
  Future<void>? _watchedRecheckAfter;

  @override
  void initState() {
    super.initState();
    _scheduleCheck();
    _watchRecheckAfter();
  }

  @override
  void didUpdateWidget(DataPackMeteredConsentGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stateRepository != widget.stateRepository) {
      _shown = false;
      _scheduleCheck();
    }
    if (oldWidget.recheckAfter != widget.recheckAfter) {
      _watchRecheckAfter();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _scheduleCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_showIfNeeded());
      }
    });
  }

  void _watchRecheckAfter() {
    final recheckAfter = widget.recheckAfter;
    _watchedRecheckAfter = recheckAfter;
    if (recheckAfter == null) {
      return;
    }
    unawaited(
      recheckAfter.whenComplete(() {
        if (mounted && identical(_watchedRecheckAfter, recheckAfter)) {
          unawaited(_showIfNeeded());
        }
      }),
    );
  }

  Future<void> _showIfNeeded() async {
    if (_shown) {
      return;
    }
    if (_checking) {
      _checkAgainAfterCurrent = true;
      return;
    }
    final repository = widget.stateRepository;
    if (repository == null) {
      return;
    }
    _checking = true;
    final DataPackUpdatePolicyState state;
    try {
      state = await repository.readPolicyState();
    } finally {
      _checking = false;
    }
    if (_checkAgainAfterCurrent) {
      _checkAgainAfterCurrent = false;
      _scheduleCheck();
    }
    if (!mounted || _shown) {
      return;
    }
    final bytes = state.pendingConsentBytes;
    if (bytes == null) {
      return;
    }
    _shown = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 지하철 데이터'),
        content: Text('${_formatMegabytes(bytes)} 정도의 새 이동 정보가 있어요. 지금 받을까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Wi-Fi에서 자동으로 받기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('지금 받기'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await widget.onAccept?.call();
    }
  }
}

String _formatMegabytes(int bytes) {
  final megabytes = (bytes / (1024 * 1024)).ceil().clamp(1, 9999);
  return '${megabytes}MB';
}
