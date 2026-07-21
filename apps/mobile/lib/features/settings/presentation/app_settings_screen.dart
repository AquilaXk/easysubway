import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../app/accessibility_theme.dart';
import '../../../mobile_error_reporter.dart';
import '../../../notification_settings.dart';
import '../../../onboarding.dart';
import '../../mobility_profile/mobility_preset_labels.dart';
import '../../mobility_profile/mobility_profile_policy.dart';

const _settingsPagePadding = EdgeInsets.only(bottom: 32);

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({
    required this.currentPreset,
    required this.viewPreferences,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.onViewPreferencesChanged,
    required this.onOpenMobilityProfile,
    required this.onOpenSupportAccess,
    required this.onOpenServiceInfo,
    required this.onOpenMyReports,
    this.bottomNavigationBar,
    super.key,
  });

  final MobilityPreset currentPreset;
  final OnboardingViewPreferences viewPreferences;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final Future<void> Function(OnboardingViewPreferences preferences)
  onViewPreferencesChanged;
  final Future<MobilityPreset?> Function() onOpenMobilityProfile;
  final VoidCallback onOpenSupportAccess;
  final VoidCallback onOpenServiceInfo;
  final VoidCallback onOpenMyReports;
  final Widget? bottomNavigationBar;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  late MobilityPreset _preset = widget.currentPreset;
  late OnboardingViewPreferences _viewPreferences = widget.viewPreferences;

  @override
  void didUpdateWidget(AppSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewPreferences != widget.viewPreferences) {
      _viewPreferences = widget.viewPreferences;
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingPreferenceScope(
      preferences: _viewPreferences,
      child: Scaffold(
        key: const Key('settingsScreen'),
        backgroundColor: EasySubwayAccessibleColors.surface,
        appBar: AppBar(
          key: const Key('settingsAppBar'),
          title: const Text('설정'),
          toolbarHeight: 60,
          backgroundColor: EasySubwayAccessibleColors.topBarSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: const Align(
            alignment: Alignment.bottomCenter,
            child: EasySubwayHeaderDivider(key: Key('settingsHeaderDivider')),
          ),
        ),
        bottomNavigationBar: widget.bottomNavigationBar,
        body: SafeArea(
          child: ListView(
            padding: _settingsPagePadding,
            children: [
              _AppSettingsSection(
                key: const Key('settingsSection-mobility'),
                title: '이동 조건',
                children: [
                  _AppSettingsActionTile(
                    key: const Key('mobilityProfileButton'),
                    title: mobilityPresetDisplayName(_preset),
                    subtitle: mobilityPresetDescription(_preset),
                    onTap: () async {
                      final selected = await widget.onOpenMobilityProfile();
                      if (!mounted || selected == null) {
                        return;
                      }
                      setState(() {
                        _preset = selected;
                      });
                    },
                  ),
                ],
              ),
              _AppSettingsSection(
                key: const Key('settingsSection-reading'),
                title: '화면 및 접근성',
                children: [
                  _AppSettingsPreferenceTile(
                    key: const Key('simpleViewSettingsButton'),
                    title: '간편 보기',
                    subtitle: '필수 행동과 상태 안내를 먼저 보여줘요',
                    enabled: _viewPreferences.simpleViewEnabled,
                    onChanged: (value) {
                      _updateViewPreferences(
                        _viewPreferences.copyWith(simpleViewEnabled: value),
                      );
                    },
                  ),
                  _AppSettingsPreferenceTile(
                    key: const Key('highContrastSettingsButton'),
                    title: '고대비',
                    subtitle: '버튼과 상태 문구의 대비를 더 강하게 보여줘요',
                    enabled: _viewPreferences.highContrastEnabled,
                    onChanged: (value) {
                      _updateViewPreferences(
                        _viewPreferences.copyWith(highContrastEnabled: value),
                      );
                    },
                  ),
                ],
              ),
              // 오프라인 안내 섹션·화면은 완전히 제거됐다(#1570): 오프라인 동작은
              // 설명 없이 그냥 되는 것이고, 데이터·지도 출처는 도움말·문의 하위에 이미 있다.
              if (widget.notificationRepository != null)
                _AppSettingsSection(
                  key: const Key('settingsSection-notification'),
                  title: '알림',
                  children: [
                    _AppSettingsActionTile(
                      key: const Key('notificationSettingsButton'),
                      title: '알림 설정',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NotificationSettingsScreen(
                              repository: widget.notificationRepository!,
                              notificationPermissionProvider:
                                  widget.notificationPermissionProvider,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              _AppSettingsSection(
                key: const Key('settingsSection-activity'),
                title: '내 활동',
                children: [
                  _AppSettingsActionTile(
                    key: const Key('myReportsSettingsButton'),
                    title: '내 제보',
                    onTap: widget.onOpenMyReports,
                  ),
                ],
              ),
              _AppSettingsSection(
                key: const Key('settingsSection-help-privacy'),
                title: '서비스 정보 및 도움말',
                children: [
                  _AppSettingsActionTile(
                    key: const Key('settingsServiceInfoButton'),
                    title: '서비스 정보',
                    onTap: widget.onOpenServiceInfo,
                  ),
                  _AppSettingsActionTile(
                    key: const Key('settingsSupportPrivacyButton'),
                    title: '도움말·문의',
                    onTap: widget.onOpenSupportAccess,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateViewPreferences(
    OnboardingViewPreferences preferences,
  ) async {
    final previous = _viewPreferences;
    setState(() {
      _viewPreferences = preferences;
    });
    try {
      await widget.onViewPreferencesChanged(preferences);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '설정 화면 보기 옵션 저장 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      if (_isSameViewPreferences(_viewPreferences, preferences)) {
        setState(() {
          _viewPreferences = previous;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장하지 못했어요. 이전 값으로 되돌렸어요.')),
      );
    }
  }
}

class _AppSettingsSection extends StatelessWidget {
  const _AppSettingsSection({
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
          key: Key('settingsSectionHeader-$title'),
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

class _AppSettingsActionTile extends StatelessWidget {
  const _AppSettingsActionTile({
    required this.title,
    this.subtitle,
    required this.onTap,
    super.key,
  });

  final String title;
  // 제목만으로 자명한 행은 회색 부가설명을 생략한다(#1570).
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
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
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.mutedText,
                    height: 1.3,
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

class _AppSettingsPreferenceTile extends StatelessWidget {
  const _AppSettingsPreferenceTile({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = enabled ? '켜짐' : '꺼짐';
    final action = enabled ? '끄기' : '켜기';
    return Semantics(
      label: '$title, $value, $subtitle, 두 번 탭해 $action',
      toggled: enabled,
      onTap: () => onChanged(!enabled),
      child: ExcludeSemantics(
        child: ListTile(
          onTap: () => onChanged(!enabled),
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: enabled,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: EasySubwayAccessibleColors.switchActiveTrack,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor:
                    EasySubwayAccessibleColors.switchInactiveTrack,
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSameViewPreferences(
  OnboardingViewPreferences left,
  OnboardingViewPreferences right,
) {
  return left.highContrastEnabled == right.highContrastEnabled &&
      left.simpleViewEnabled == right.simpleViewEnabled;
}
