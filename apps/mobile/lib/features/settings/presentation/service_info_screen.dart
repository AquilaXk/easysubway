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
    final rows = [
      _ServiceInfoActionTile(
        key: const Key('termsOfServiceItem'),
        title: '서비스 이용약관',
        onTap: () => _openDocument(context, accessInfo.termsOfServiceUrl),
      ),
      _ServiceInfoActionTile(
        key: const Key('privacyPolicyItem'),
        title: '개인정보 처리방침',
        onTap: () => _openDocument(context, accessInfo.privacyPolicyUrl),
      ),
      _ServiceInfoActionTile(
        key: const Key('locationTermsItem'),
        title: '위치정보 이용약관',
        onTap: () => _openDocument(context, accessInfo.locationTermsUrl),
      ),
      _ServiceInfoActionTile(
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
      _ServiceInfoActionTile(
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
    ];

    return Scaffold(
      key: const Key('serviceInfoScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        key: const Key('serviceInfoAppBar'),
        title: const Text('서비스 정보'),
        toolbarHeight: 60,
        backgroundColor: EasySubwayAccessibleColors.topBarSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('serviceInfoBackButton'),
          tooltip: '뒤로',
          onPressed: () => Navigator.of(context).maybePop(),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(EasySubwayTouchTarget.general),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(
            Icons.arrow_back,
            size: 26,
            color: Color(0xFF4B4B4B),
          ),
        ),
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider(key: Key('serviceInfoHeaderDivider')),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _ServiceInfoSection(
              key: const Key('serviceInfoSection-documents'),
              sectionTitle: '약관 및 정책',
              children: rows,
            ),
          ],
        ),
      ),
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

class _ServiceInfoSection extends StatelessWidget {
  const _ServiceInfoSection({
    required this.sectionTitle,
    required this.children,
    super.key,
  });

  // action tile의 `title:` 계약 추출과 구분한다(#2442).
  final String sectionTitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ColoredBox(
          key: Key('serviceInfoSectionHeader-$sectionTitle'),
          color: EasySubwayAccessibleColors.scaffoldSurface,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Semantics(
                header: true,
                child: Text(
                  sectionTitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.secondaryText,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
        ),
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 20,
              endIndent: 20,
              color: EasySubwayAccessibleColors.line,
            ),
        ],
      ],
    );
  }
}

class _ServiceInfoActionTile extends StatelessWidget {
  const _ServiceInfoActionTile({
    required this.title,
    required this.onTap,
    super.key,
  });

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      container: true,
      label: title,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ListTile(
          onTap: onTap,
          minVerticalPadding: 12,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          tileColor: EasySubwayAccessibleColors.surface,
          title: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: EasySubwayAccessibleColors.disclosure,
          ),
        ),
      ),
    );
  }
}
