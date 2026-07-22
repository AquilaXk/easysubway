import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../accessible_design.dart';
import '../../../mobile_error_reporter.dart';
import '../../../user_data_deletion.dart';
import '../../account/presentation/user_data_deletion_screen.dart';

abstract interface class SupportAccessLauncher {
  Future<bool> open(Uri uri);
}

class UrlLauncherSupportAccessLauncher implements SupportAccessLauncher {
  const UrlLauncherSupportAccessLauncher();

  @override
  Future<bool> open(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class SupportAccessInfo {
  const SupportAccessInfo({
    this.termsOfServiceUrl = '',
    required this.privacyPolicyUrl,
    this.locationTermsUrl = '',
    required this.supportEmail,
    required this.dataDeletionEmail,
    this.securityEmail = '',
  });

  const SupportAccessInfo.fromEnvironment()
    : termsOfServiceUrl = const String.fromEnvironment(
        'EASYSUBWAY_TERMS_OF_SERVICE_URL',
      ),
      privacyPolicyUrl = const String.fromEnvironment(
        'EASYSUBWAY_PRIVACY_POLICY_URL',
      ),
      locationTermsUrl = const String.fromEnvironment(
        'EASYSUBWAY_LOCATION_TERMS_URL',
      ),
      supportEmail = const String.fromEnvironment('EASYSUBWAY_SUPPORT_EMAIL'),
      dataDeletionEmail = const String.fromEnvironment(
        'EASYSUBWAY_DATA_DELETION_EMAIL',
      ),
      securityEmail = const String.fromEnvironment('EASYSUBWAY_SECURITY_EMAIL');

  final String termsOfServiceUrl;
  final String privacyPolicyUrl;
  final String locationTermsUrl;
  final String supportEmail;
  final String dataDeletionEmail;
  final String securityEmail;

  SupportAccessInfo validatedForBuild({required bool isReleaseMode}) {
    if (!isReleaseMode) {
      return this;
    }
    _validateHttpsUrl(label: 'terms of service URL', value: termsOfServiceUrl);
    _validateHttpsUrl(label: 'privacy policy URL', value: privacyPolicyUrl);
    _validateHttpsUrl(label: 'location terms URL', value: locationTermsUrl);
    _validateEmail(label: 'support email', value: supportEmail);
    _validateEmail(label: 'data deletion email', value: dataDeletionEmail);
    _validateEmail(label: 'security email', value: securityEmail);
    return this;
  }

  static void _validateHttpsUrl({
    required String label,
    required String value,
  }) {
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      throw StateError('Release $label must be configured.');
    }
    final uri = Uri.tryParse(normalizedValue);
    if (uri == null || uri.scheme != 'https') {
      throw StateError('Release $label must use HTTPS.');
    }
    if (uri.host.isEmpty) {
      throw StateError('Release $label must include a host.');
    }
  }

  static void _validateEmail({required String label, required String value}) {
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      throw StateError('Release $label must be configured.');
    }
    final emailPattern = RegExp(
      r'^[^\s@]+@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$',
    );
    if (!emailPattern.hasMatch(normalizedValue)) {
      throw StateError('Release $label must be a valid email address.');
    }
  }
}

class SupportAccessScreen extends StatelessWidget {
  const SupportAccessScreen({
    required this.accessInfo,
    required this.launcher,
    required this.userDataDeletionRepository,
    required this.onUserDataDeleted,
    super.key,
  });

  final SupportAccessInfo accessInfo;
  final SupportAccessLauncher launcher;
  final UserDataDeletionRepository? userDataDeletionRepository;
  final Future<void> Function(UserDataDeletionResult result)? onUserDataDeleted;

  @override
  Widget build(BuildContext context) {
    final deletionChildren = <Widget>[
      if (userDataDeletionRepository != null)
        UserDataDeletionAccessItem(
          repository: userDataDeletionRepository!,
          onDeleted: onUserDataDeleted,
        )
      else if (_mailtoUri(accessInfo.dataDeletionEmail, '쉬운 지하철 내 정보 삭제 요청') !=
          null)
        _SupportAccessItem(
          key: const Key('dataDeletionAccessItem'),
          title: '내 정보 삭제 요청',
          value: accessInfo.dataDeletionEmail,
          displayValue: '이메일 보내기',
          uri: _mailtoUri(accessInfo.dataDeletionEmail, '쉬운 지하철 내 정보 삭제 요청'),
          launcher: launcher,
        ),
    ];
    final inquiryChildren = <Widget>[
      if (_mailtoUri(accessInfo.supportEmail, '쉬운 지하철 고객지원 문의') != null)
        _SupportAccessItem(
          key: const Key('supportAccessItem'),
          title: '고객지원',
          value: accessInfo.supportEmail,
          displayValue: '이메일 보내기',
          uri: _mailtoUri(accessInfo.supportEmail, '쉬운 지하철 고객지원 문의'),
          launcher: launcher,
        ),
      if (_mailtoUri(accessInfo.securityEmail, '쉬운 지하철 보안 문의') != null)
        _SupportAccessItem(
          key: const Key('securityContactAccessItem'),
          title: '보안 문의',
          value: accessInfo.securityEmail,
          displayValue: '보안 문제 알리기',
          uri: _mailtoUri(accessInfo.securityEmail, '쉬운 지하철 보안 문의'),
          launcher: launcher,
        ),
    ];

    return Scaffold(
      key: const Key('supportAccessScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        key: const Key('supportAccessAppBar'),
        title: const Text('도움말 및 문의'),
        toolbarHeight: 60,
        backgroundColor: EasySubwayAccessibleColors.topBarSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('supportAccessBackButton'),
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
          child: EasySubwayHeaderDivider(
            key: Key('supportAccessHeaderDivider'),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (deletionChildren.isNotEmpty)
              _SupportSettingsSection(
                key: const Key('supportSection-privacy'),
                title: '내 정보와 개인정보',
                children: deletionChildren,
              ),
            _SupportSettingsSection(
              key: const Key('supportSection-safety'),
              title: '이동 전 살펴보기',
              children: const [_SafetyDataNotice()],
            ),
            if (inquiryChildren.isNotEmpty)
              _SupportSettingsSection(
                key: const Key('supportSection-inquiry'),
                title: '문의',
                children: inquiryChildren,
              ),
            const _SecurityContactNotice(),
          ],
        ),
      ),
    );
  }
}

class _SupportSettingsSection extends StatelessWidget {
  const _SupportSettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ColoredBox(
          key: Key('supportSectionHeader-$title'),
          color: EasySubwayAccessibleColors.scaffoldSurface,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Semantics(
                header: true,
                child: Text(
                  title,
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

class _SecurityContactNotice extends StatelessWidget {
  const _SecurityContactNotice();

  static const _title = '보안 문의 안내';
  static const _contactNotice = '앱 보안이나 개인정보가 걱정되면 문의로 알려주세요.';
  static const _scopeNotice = '위치, 제보 사진, 알림, 개인정보 관련 걱정을 함께 보낼 수 있습니다.';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: EasySubwayAccessibleColors.scaffoldSurface,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Semantics(
                header: true,
                child: Text(
                  _title,
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
        Semantics(
          key: const Key('securityContactNotice'),
          container: true,
          label: '$_title, $_contactNotice $_scopeNotice',
          child: ExcludeSemantics(
            child: ColoredBox(
              color: EasySubwayAccessibleColors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _contactNotice,
                      style: textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _scopeNotice,
                      style: textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SafetyDataNotice extends StatelessWidget {
  const _SafetyDataNotice();

  static const _title = '이동 전 살펴보기';
  static const _referenceNotice = '경로와 시설 정보는 이동을 돕는 참고 정보입니다.';
  static const _fieldNotice = '실제 이동 전에는 현장 안내, 역무원 안내, 운영기관 공지를 먼저 확인해 주세요.';
  static const _limitationNotice = '실시간 상태나 무조건 안전한 경로를 보장하지 않습니다.';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      key: const Key('safetyDataNotice'),
      container: true,
      label: '$_title, $_referenceNotice $_fieldNotice $_limitationNotice',
      child: ExcludeSemantics(
        child: ColoredBox(
          color: EasySubwayAccessibleColors.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _referenceNotice,
                  style: textTheme.bodyLarge?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _fieldNotice,
                  style: textTheme.bodyLarge?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _limitationNotice,
                  style: textTheme.bodyLarge?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportAccessItem extends StatelessWidget {
  const _SupportAccessItem({
    required this.title,
    required this.value,
    required this.uri,
    required this.launcher,
    this.displayValue,
    super.key,
  });

  final String title;
  final String value;
  final Uri? uri;
  final SupportAccessLauncher launcher;
  final String? displayValue;

  @override
  Widget build(BuildContext context) {
    final targetUri = uri;
    final targetText = value.trim();
    final displayValue = this.displayValue ?? targetText;
    final semanticLabelParts = [title, displayValue];
    if (targetUri != null && displayValue != targetText) {
      semanticLabelParts.add(targetText);
    }
    final onTap = targetUri == null
        ? null
        : () => unawaited(_openTarget(context, targetUri, targetText));
    return Semantics(
      button: true,
      container: true,
      enabled: targetUri != null,
      label: semanticLabelParts.join(', '),
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
          subtitle: Text(
            displayValue,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: EasySubwayAccessibleColors.mutedText,
              height: 1.3,
            ),
          ),
          trailing: targetUri == null
              ? null
              : const Icon(
                  Icons.chevron_right,
                  color: EasySubwayAccessibleColors.disclosure,
                ),
        ),
      ),
    );
  }

  Future<void> _openTarget(
    BuildContext context,
    Uri uri,
    String targetText,
  ) async {
    bool opened = false;
    try {
      opened = await launcher.open(uri);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '도움말 외부 연결 실행 중 예외가 발생했습니다.',
      );
    }

    if (!context.mounted || opened) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('연결할 수 없습니다. 직접 확인해 주세요: $targetText')),
    );
  }
}

Uri? _mailtoUri(String value, String subject) {
  final email = value.trim();
  if (email.isEmpty) {
    return null;
  }
  return Uri(
    scheme: 'mailto',
    path: email,
    queryParameters: {'subject': subject},
  );
}
