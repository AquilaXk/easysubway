import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../accessible_design.dart';
import '../../../mobile_error_reporter.dart';
import '../../attribution/presentation/data_source_attribution_screen.dart';
import '../../support/presentation/support_access_screen.dart';
import 'open_source_licenses_screen.dart';

typedef SupportsInAppBrowser = Future<bool> Function();
typedef LaunchInAppBrowser = Future<bool> Function(Uri uri);

class ServiceInfoScreen extends StatelessWidget {
  const ServiceInfoScreen({
    required this.accessInfo,
    this.supportsInAppBrowser,
    this.launchInAppBrowser,
    this.licenseEntriesLoader,
    super.key,
  });

  final SupportAccessInfo accessInfo;
  final SupportsInAppBrowser? supportsInAppBrowser;
  final LaunchInAppBrowser? launchInAppBrowser;
  final LicenseEntriesLoader? licenseEntriesLoader;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('serviceInfoScreen'),
      appBar: AppBar(title: const Text('서비스 정보')),
      body: SafeArea(
        child: ListView(
          children: [
            _row(
              key: const Key('termsOfServiceItem'),
              title: '서비스 이용약관',
              onTap: () => _openDocument(context, accessInfo.termsOfServiceUrl),
            ),
            _row(
              key: const Key('privacyPolicyItem'),
              title: '개인정보 처리방침',
              onTap: () => _openDocument(context, accessInfo.privacyPolicyUrl),
            ),
            _row(
              key: const Key('locationTermsItem'),
              title: '위치정보 이용약관',
              onTap: () => _openDocument(context, accessInfo.locationTermsUrl),
            ),
            _row(
              key: const Key('dataSourceAttributionItem'),
              title: '정보제공처',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DataSourceAttributionScreen(),
                  ),
                );
              },
            ),
            _row(
              key: const Key('openSourceLicensesItem'),
              title: '오픈 소스 라이선스',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OpenSourceLicensesScreen(
                      licenseEntriesLoader: licenseEntriesLoader,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required Key key,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      key: key,
      minTileHeight: 60,
      title: Text(
        title,
        style: const TextStyle(
          color: EasySubwayAccessibleColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Future<void> _openDocument(BuildContext context, String value) async {
    final uri = Uri.tryParse(value.trim());
    try {
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('invalid legal document URL');
      }
      final supported =
          await (supportsInAppBrowser?.call() ??
              supportsLaunchMode(LaunchMode.inAppBrowserView));
      if (!supported) {
        throw StateError('in-app browser unsupported');
      }
      final opened =
          await (launchInAppBrowser?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.inAppBrowserView));
      if (!opened) {
        throw StateError('legal document launch failed');
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '서비스 정보 법적 문서 열기 중 예외가 발생했습니다.',
      );
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('문서를 열 수 없어요. 잠시 후 다시 시도해 주세요.')),
        );
    }
  }
}
