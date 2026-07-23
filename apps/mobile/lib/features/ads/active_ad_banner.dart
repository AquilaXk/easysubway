import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ad_slot.dart';
import 'ad_repository.dart';

typedef AdImageLoader =
    Future<ImageProvider<Object>> Function(Uri uri, BuildContext context);
typedef AdLauncher = Future<bool> Function(Uri uri, {required LaunchMode mode});

DateTime _utcNow() => DateTime.now().toUtc();

class ActiveAdBanner extends StatefulWidget {
  const ActiveAdBanner({
    required this.repository,
    required this.placement,
    this.imageLoader = _loadNetworkImage,
    this.launcher = _launchExternal,
    this.now = _utcNow,
    super.key,
  });

  final AdRepository repository;
  final AdPlacement placement;
  final AdImageLoader imageLoader;
  final AdLauncher launcher;
  final DateTime Function() now;

  @override
  State<ActiveAdBanner> createState() => _ActiveAdBannerState();
}

class _ActiveAdBannerState extends State<ActiveAdBanner>
    with WidgetsBindingObserver {
  AdCreative? _creative;
  ImageProvider<Object>? _image;
  bool _started = false;
  int _generation = 0;
  Timer? _expiryTimer;
  bool _impressionRecorded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    _reload();
  }

  @override
  void didUpdateWidget(ActiveAdBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repository != oldWidget.repository ||
        widget.placement != oldWidget.placement ||
        widget.imageLoader != oldWidget.imageLoader) {
      _creative = null;
      _image = null;
      _reload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_started || state != AppLifecycleState.resumed) {
      return;
    }
    // 운영 비활성화·endsAt null 소재는 Timer만으로는 내려가지 않으므로
    // 포그라운드 복귀 때 active를 다시 조회한다.
    _reload();
  }

  void _reload() {
    _resetLifecycle();
    final generation = ++_generation;
    unawaited(
      _load(
        generation,
        widget.repository,
        widget.placement,
        widget.imageLoader,
      ),
    );
  }

  Future<void> _load(
    int generation,
    AdRepository repository,
    AdPlacement placement,
    AdImageLoader imageLoader,
  ) async {
    try {
      final creative = await repository.fetchActive(placement);
      if (!mounted || generation != _generation) {
        return;
      }
      if (creative == null || _isExpired(creative)) {
        _collapseRenderedBanner();
        return;
      }
      final image = await imageLoader(creative.imageUrl, context);
      if (!mounted || generation != _generation) {
        return;
      }
      if (_isExpired(creative)) {
        _collapseRenderedBanner();
        return;
      }
      setState(() {
        _creative = creative;
        _image = image;
      });
      _scheduleExpiry(generation, creative);
      _recordImpressionAfterFrame(generation, repository, creative);
    } on Exception {
      // 조회·decode 실패는 이미 그린 유효 배너를 유지한다.
      // _reload가 Timer를 지웠으므로 유지 소재의 endsAt Timer를 복구한다.
      if (!mounted || generation != _generation) {
        return;
      }
      _restoreExpiryForKeptBanner(generation);
    }
  }

  void _collapseRenderedBanner() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (_creative == null && _image == null) {
      return;
    }
    setState(() {
      _creative = null;
      _image = null;
    });
  }

  void _restoreExpiryForKeptBanner(int generation) {
    final creative = _creative;
    if (creative == null) {
      return;
    }
    if (_isExpired(creative)) {
      _collapseRenderedBanner();
      return;
    }
    _scheduleExpiry(generation, creative);
  }

  bool _isExpired(AdCreative creative) {
    final endsAt = creative.endsAt;
    return endsAt != null && !endsAt.isAfter(widget.now());
  }

  void _scheduleExpiry(int generation, AdCreative creative) {
    final endsAt = creative.endsAt;
    if (endsAt == null) {
      return;
    }
    _expiryTimer = Timer(endsAt.difference(widget.now()), () {
      if (!mounted ||
          generation != _generation ||
          !identical(_creative, creative)) {
        return;
      }
      setState(() {
        _creative = null;
        _image = null;
      });
      _expiryTimer = null;
    });
  }

  void _recordImpressionAfterFrame(
    int generation,
    AdRepository repository,
    AdCreative creative,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          !identical(_creative, creative) ||
          _image == null ||
          _isExpired(creative) ||
          _impressionRecorded) {
        return;
      }
      _impressionRecorded = true;
      unawaited(
        repository.recordEvent(
          creative.placement,
          creative.creativeId,
          AdEventType.impression,
        ),
      );
    });
  }

  void _resetLifecycle() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _impressionRecorded = false;
  }

  Future<void> _openLanding() async {
    final creative = _creative;
    if (creative == null) {
      return;
    }
    if (_isExpired(creative)) {
      _expiryTimer?.cancel();
      _expiryTimer = null;
      setState(() {
        _creative = null;
        _image = null;
      });
      return;
    }
    unawaited(
      widget.repository.recordEvent(
        creative.placement,
        creative.creativeId,
        AdEventType.click,
      ),
    );
    try {
      await widget.launcher(
        creative.landingUrl,
        mode: LaunchMode.externalApplication,
      );
    } on Exception {
      // 외부 브라우저 실패 시 내부 이동이나 다른 URL로 fallback하지 않는다.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _resetLifecycle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creative = _creative;
    final image = _image;
    if (creative == null || image == null) {
      return const SizedBox.shrink();
    }

    return Semantics(
      key: const Key('activeAdBannerTapTarget'),
      label: '광고, ${creative.altText}',
      button: true,
      onTap: _openLanding,
      excludeSemantics: true,
      child: AdBannerSlot(
        slotKey: const Key('activeAdBannerSlot'),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openLanding,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image(
                      image: image,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '광고',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                creative.advertiserName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          creative.altText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  const SizedBox(
                    key: Key('activeAdBannerExternalCta'),
                    width: 48,
                    height: 48,
                    child: Icon(Icons.open_in_new),
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

Future<ImageProvider<Object>> _loadNetworkImage(
  Uri uri,
  BuildContext context,
) async {
  final provider = NetworkImage(uri.toString());
  Object? failure;
  StackTrace? failureStack;
  await precacheImage(
    provider,
    context,
    onError: (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    },
  );
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack ?? StackTrace.current);
  }
  return provider;
}

Future<bool> _launchExternal(Uri uri, {required LaunchMode mode}) {
  return launchUrl(uri, mode: mode);
}
