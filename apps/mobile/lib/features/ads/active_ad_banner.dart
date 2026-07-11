import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ad_slot.dart';
import 'ad_repository.dart';

typedef AdImageLoader =
    Future<ImageProvider<Object>> Function(Uri uri, BuildContext context);
typedef AdLauncher = Future<bool> Function(Uri uri, {required LaunchMode mode});

class ActiveAdBanner extends StatefulWidget {
  const ActiveAdBanner({
    required this.repository,
    required this.placement,
    this.imageLoader = _loadNetworkImage,
    this.launcher = _launchExternal,
    super.key,
  });

  final AdRepository repository;
  final AdPlacement placement;
  final AdImageLoader imageLoader;
  final AdLauncher launcher;

  @override
  State<ActiveAdBanner> createState() => _ActiveAdBannerState();
}

class _ActiveAdBannerState extends State<ActiveAdBanner> {
  AdCreative? _creative;
  ImageProvider<Object>? _image;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final creative = await widget.repository.fetchActive(widget.placement);
      if (!mounted || creative == null) {
        return;
      }
      final image = await widget.imageLoader(creative.imageUrl, context);
      if (!mounted) {
        return;
      }
      setState(() {
        _creative = creative;
        _image = image;
      });
    } on Object {
      // ponytail: 조회·decode 실패는 사용자에게 빈 슬롯을 남기지 않고 닫는다.
    }
  }

  Future<void> _openLanding() async {
    final landingUrl = _creative?.landingUrl;
    if (landingUrl == null) {
      return;
    }
    try {
      await widget.launcher(landingUrl, mode: LaunchMode.externalApplication);
    } on Object {
      // 외부 브라우저 실패 시 내부 이동이나 다른 URL로 fallback하지 않는다.
    }
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
                    borderRadius: BorderRadius.circular(12),
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '광고',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            creative.advertiserName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            creative.altText,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
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
