import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../mobile_error_reporter.dart';
import 'support_access_screen.dart';

enum InquiryKind { general, security }

class InquiryScreen extends StatefulWidget {
  const InquiryScreen({
    required this.accessInfo,
    required this.launcher,
    super.key,
  });

  final SupportAccessInfo accessInfo;
  final SupportAccessLauncher launcher;

  @override
  State<InquiryScreen> createState() => _InquiryScreenState();
}

class _InquiryScreenState extends State<InquiryScreen> {
  InquiryKind _kind = InquiryKind.general;
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  String get _defaultSubject {
    return switch (_kind) {
      InquiryKind.general => '쉬운 지하철 고객지원 문의',
      InquiryKind.security => '쉬운 지하철 보안 문의',
    };
  }

  String get _targetEmail {
    return switch (_kind) {
      InquiryKind.general => widget.accessInfo.supportEmail,
      InquiryKind.security => widget.accessInfo.securityEmail,
    };
  }

  bool get _canSend {
    final email = _targetEmail.trim();
    final body = _bodyController.text.trim();
    return email.isNotEmpty && body.isNotEmpty && !_isSending;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final targetEmailMissing = _targetEmail.trim().isEmpty;

    return Scaffold(
      key: const Key('inquiryScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        key: const Key('inquiryAppBar'),
        title: const Text('문의하기'),
        toolbarHeight: 60,
        backgroundColor: EasySubwayAccessibleColors.topBarSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('inquiryBackButton'),
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
            color: EasySubwayAccessibleColors.contentPrimary,
          ),
        ),
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider(key: Key('inquiryHeaderDivider')),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: easySubwayBottomActionInsets(context),
        child: FilledButton(
          key: const Key('inquirySendButton'),
          onPressed: _canSend ? () => unawaited(_sendInquiry()) : null,
          child: Text(_isSending ? '메일 앱 여는 중' : '메일로 보내기'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _InquirySection(
              title: '문의 유형',
              children: [
                _InquiryKindTile(
                  key: const Key('inquiryKindGeneral'),
                  title: '일반 문의',
                  subtitle: '이용 방법, 오류, 건의',
                  selected: _kind == InquiryKind.general,
                  onTap: () => setState(() => _kind = InquiryKind.general),
                ),
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 20,
                  endIndent: 20,
                  color: EasySubwayAccessibleColors.line,
                ),
                _InquiryKindTile(
                  key: const Key('inquiryKindSecurity'),
                  title: '보안 문의',
                  subtitle: '보안·개인정보 관련',
                  selected: _kind == InquiryKind.security,
                  onTap: () => setState(() => _kind = InquiryKind.security),
                ),
              ],
            ),
            if (_kind == InquiryKind.security) const _InquirySecurityNotice(),
            _InquirySection(
              title: '제목',
              children: [
                ColoredBox(
                  color: EasySubwayAccessibleColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: TextField(
                      key: const Key('inquirySubjectField'),
                      controller: _subjectController,
                      textInputAction: TextInputAction.next,
                      style: textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        height: 1.35,
                      ),
                      decoration: InputDecoration(
                        hintText: _defaultSubject,
                        hintStyle: textTheme.bodyLarge?.copyWith(
                          color: EasySubwayAccessibleColors.mutedText,
                          height: 1.35,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            _InquirySection(
              title: '내용 *',
              children: [
                ColoredBox(
                  color: EasySubwayAccessibleColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: TextField(
                      key: const Key('inquiryBodyField'),
                      controller: _bodyController,
                      minLines: 6,
                      maxLines: 12,
                      onChanged: (_) => setState(() {}),
                      style: textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        height: 1.35,
                      ),
                      decoration: InputDecoration(
                        hintText: '어떤 도움이 필요한지 적어 주세요.',
                        hintStyle: textTheme.bodyLarge?.copyWith(
                          color: EasySubwayAccessibleColors.mutedText,
                          height: 1.35,
                        ),
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                targetEmailMissing
                    ? '지금은 문의 메일을 보낼 주소를 확인할 수 없어요. 잠시 후 다시 시도해 주세요.'
                    : '보내기를 누르면 메일 앱이 열립니다.',
                key: Key(
                  targetEmailMissing
                      ? 'inquiryEmailMissingNotice'
                      : 'inquiryMailtoHint',
                ),
                style: textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendInquiry() async {
    final email = _targetEmail.trim();
    final subject = _subjectController.text.trim().isEmpty
        ? _defaultSubject
        : _subjectController.text.trim();
    final body = _bodyController.text.trim();
    final uri = buildSupportMailtoUri(
      email: email,
      subject: subject,
      body: body,
    );
    if (uri == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('문의 메일 주소를 확인할 수 없어요.')));
      return;
    }

    setState(() => _isSending = true);
    var opened = false;
    try {
      opened = await widget.launcher.open(uri);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '문의 메일 앱 실행 중 예외가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }

    if (!mounted || opened) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('메일 앱을 열 수 없어요. 직접 보내 주세요: $email')));
  }
}

class _InquirySection extends StatelessWidget {
  const _InquirySection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.secondaryText,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _InquiryKindTile extends StatelessWidget {
  const _InquiryKindTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle${selected ? ', 선택됨' : ''}',
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
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: EasySubwayAccessibleColors.mutedText,
              height: 1.3,
            ),
          ),
          trailing: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected
                ? EasySubwayAccessibleColors.brand
                : EasySubwayAccessibleColors.disclosure,
          ),
        ),
      ),
    );
  }
}

class _InquirySecurityNotice extends StatelessWidget {
  const _InquirySecurityNotice();

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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InquiryNoticeBullet(text: _contactNotice),
                    const SizedBox(height: 10),
                    _InquiryNoticeBullet(text: _scopeNotice),
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

class _InquiryNoticeBullet extends StatelessWidget {
  const _InquiryNoticeBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: EasySubwayAccessibleColors.secondaryText,
              shape: BoxShape.circle,
            ),
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
    );
  }
}
