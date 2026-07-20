import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../accessible_design.dart';
import '../../../app/app_components.dart';
import '../../../design_tokens.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('도움말·문의')),
      body: SafeArea(
        child: ListView(
          padding: mainPagePadding,
          children: [
            const _SupportSectionTitle(title: '내 정보와 개인정보'),
            _SupportGroupCard(
              children: [
                if (userDataDeletionRepository != null)
                  UserDataDeletionAccessItem(
                    repository: userDataDeletionRepository!,
                    onDeleted: onUserDataDeleted,
                  )
                else if (_mailtoUri(
                      accessInfo.dataDeletionEmail,
                      '쉬운 지하철 내 정보 삭제 요청',
                    ) !=
                    null)
                  _SupportAccessItem(
                    key: const Key('dataDeletionAccessItem'),
                    icon: Icons.delete_outline,
                    title: '내 정보 삭제 요청',
                    value: accessInfo.dataDeletionEmail,
                    displayValue: '이메일 보내기',
                    uri: _mailtoUri(
                      accessInfo.dataDeletionEmail,
                      '쉬운 지하철 내 정보 삭제 요청',
                    ),
                    launcher: launcher,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _SupportSectionTitle(title: '이동 전 살펴보기'),
            const _SafetyDataNotice(),
            const SizedBox(height: 20),
            const _SupportSectionTitle(title: '문의'),
            _SupportGroupCard(
              children: [
                if (_mailtoUri(accessInfo.supportEmail, '쉬운 지하철 고객지원 문의') !=
                    null)
                  _SupportAccessItem(
                    key: const Key('supportAccessItem'),
                    icon: Icons.support_agent,
                    title: '고객지원',
                    value: accessInfo.supportEmail,
                    displayValue: '이메일 보내기',
                    uri: _mailtoUri(accessInfo.supportEmail, '쉬운 지하철 고객지원 문의'),
                    launcher: launcher,
                  ),
                if (_mailtoUri(accessInfo.securityEmail, '쉬운 지하철 보안 문의') !=
                    null)
                  _SupportAccessItem(
                    key: const Key('securityContactAccessItem'),
                    icon: Icons.security_outlined,
                    title: '보안 문의',
                    value: accessInfo.securityEmail,
                    displayValue: '보안 문제 알리기',
                    uri: _mailtoUri(accessInfo.securityEmail, '쉬운 지하철 보안 문의'),
                    launcher: launcher,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const _SecurityContactNotice(),
          ],
        ),
      ),
    );
  }
}

class _SupportSectionTitle extends StatelessWidget {
  const _SupportSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

class _SupportGroupCard extends StatelessWidget {
  const _SupportGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // 연결 가능한 항목이 없으면(전 항목 숨김) 빈 테두리 카드를 그리지 않는다.
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(
          const Divider(height: 1, color: EasySubwayAccessibleColors.line),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        border: Border.all(color: EasySubwayAccessibleColors.line),
        borderRadius: const BorderRadius.all(
          Radius.circular(EasySubwayRadius.sheet),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
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
    return Semantics(
      key: const Key('securityContactNotice'),
      container: true,
      label: '$_title, $_contactNotice $_scopeNotice',
      child: ExcludeSemantics(
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: EasySubwayAccessibleColors.line),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.security_outlined,
                      color: EasySubwayAccessibleColors.brand,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _title,
                        style: textTheme.titleMedium?.copyWith(
                          color: EasySubwayAccessibleColors.text,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _SecurityContactNoticeLine(text: _contactNotice),
                const _SecurityContactNoticeLine(text: _scopeNotice),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityContactNoticeLine extends StatelessWidget {
  const _SecurityContactNoticeLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(
              Icons.circle,
              size: 7,
              color: EasySubwayAccessibleColors.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
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
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: EasySubwayAccessibleColors.line),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: EasySubwayAccessibleColors.amber,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _title,
                        style: textTheme.titleMedium?.copyWith(
                          color: EasySubwayAccessibleColors.text,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _SafetyDataNoticeLine(text: _referenceNotice),
                const _SafetyDataNoticeLine(text: _fieldNotice),
                const _SafetyDataNoticeLine(text: _limitationNotice),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SafetyDataNoticeLine extends StatelessWidget {
  const _SafetyDataNoticeLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(
              Icons.circle,
              size: 7,
              color: EasySubwayAccessibleColors.amber,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportAccessItem extends StatelessWidget {
  const _SupportAccessItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.uri,
    required this.launcher,
    this.displayValue,
    super.key,
  });

  final IconData icon;
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
    return Semantics(
      button: true,
      enabled: targetUri != null,
      label: semanticLabelParts.join(', '),
      onTap: targetUri == null
          ? null
          : () => unawaited(_openTarget(context, targetUri, targetText)),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: targetUri == null
              ? null
              : () => unawaited(_openTarget(context, targetUri, targetText)),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    icon,
                    size: 24,
                    color: targetUri == null
                        ? EasySubwayAccessibleColors.mutedText
                        : EasySubwayAccessibleColors.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: EasySubwayAccessibleColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        displayValue,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: EasySubwayAccessibleColors.secondaryText,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (targetUri != null) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: EasySubwayAccessibleColors.mutedText,
                    size: 22,
                  ),
                ],
              ],
            ),
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
