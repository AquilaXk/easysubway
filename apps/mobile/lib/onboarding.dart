import 'package:flutter/material.dart';

import 'mobility_profile.dart';

class OnboardingViewPreferences {
  const OnboardingViewPreferences({
    required this.largeTextEnabled,
    required this.highContrastEnabled,
    required this.simpleViewEnabled,
  });

  const OnboardingViewPreferences.defaults()
    : largeTextEnabled = true,
      highContrastEnabled = false,
      simpleViewEnabled = true;

  final bool largeTextEnabled;
  final bool highContrastEnabled;
  final bool simpleViewEnabled;

  OnboardingViewPreferences copyWith({
    bool? largeTextEnabled,
    bool? highContrastEnabled,
    bool? simpleViewEnabled,
  }) {
    return OnboardingViewPreferences(
      largeTextEnabled: largeTextEnabled ?? this.largeTextEnabled,
      highContrastEnabled: highContrastEnabled ?? this.highContrastEnabled,
      simpleViewEnabled: simpleViewEnabled ?? this.simpleViewEnabled,
    );
  }
}

class OnboardingResult {
  const OnboardingResult({required this.profile, required this.preferences});

  final MobilityProfileOption profile;
  final OnboardingViewPreferences preferences;
}

class OnboardingState {
  const OnboardingState.initial() : result = null;

  const OnboardingState.completed({required this.result});

  final OnboardingResult? result;

  bool get isCompleted => result != null;
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onCompleted, super.key});

  final ValueChanged<OnboardingResult> onCompleted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  MobilityProfileOption? _selectedProfile;
  OnboardingViewPreferences _preferences =
      const OnboardingViewPreferences.defaults();

  @override
  Widget build(BuildContext context) {
    final selectedProfile = _selectedProfile;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('쉬운 지하철')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: FilledButton.icon(
          key: const Key('onboardingDoneButton'),
          onPressed: selectedProfile == null
              ? null
              : () {
                  widget.onCompleted(
                    OnboardingResult(
                      profile: selectedProfile,
                      preferences: _preferences,
                    ),
                  );
                },
          icon: const Icon(Icons.check),
          label: const Text('시작하기'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Semantics(
              header: true,
              child: Text(
                '먼저 이동 조건을 골라 주세요',
                style: textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '이동 조건',
              style: textTheme.titleLarge?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final profile in mobilityProfileOptions)
              _OnboardingProfileCard(
                profile: profile,
                selected: profile.id == selectedProfile?.id,
                onTap: () {
                  setState(() {
                    _selectedProfile = profile;
                  });
                },
              ),
            const SizedBox(height: 12),
            Text(
              '보기 설정',
              style: textTheme.titleLarge?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            _OnboardingPreferenceSwitch(
              key: const Key('onboardingPreference-largeText'),
              title: '큰 글씨',
              value: _preferences.largeTextEnabled,
              onChanged: (value) {
                setState(() {
                  _preferences = _preferences.copyWith(largeTextEnabled: value);
                });
              },
            ),
            _OnboardingPreferenceSwitch(
              key: const Key('onboardingPreference-highContrast'),
              title: '고대비',
              value: _preferences.highContrastEnabled,
              onChanged: (value) {
                setState(() {
                  _preferences = _preferences.copyWith(
                    highContrastEnabled: value,
                  );
                });
              },
            ),
            _OnboardingPreferenceSwitch(
              key: const Key('onboardingPreference-simpleView'),
              title: '단순 보기',
              value: _preferences.simpleViewEnabled,
              onChanged: (value) {
                setState(() {
                  _preferences = _preferences.copyWith(
                    simpleViewEnabled: value,
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingProfileCard extends StatelessWidget {
  const _OnboardingProfileCard({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final MobilityProfileOption profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = selected
        ? colorScheme.primary
        : const Color(0xFFD5E2E4);
    final backgroundColor = selected ? const Color(0xFFE6F2F0) : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: profile.semanticsLabel(selected),
        selected: selected,
        button: true,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: borderColor, width: selected ? 2 : 1),
            ),
            child: InkWell(
              key: Key('onboardingProfileCard-${profile.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 76),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(profile.icon, color: colorScheme.primary, size: 34),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              profile.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFF102A2C),
                                    fontWeight: FontWeight.w900,
                                    height: 1.25,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              profile.summary,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: const Color(0xFF29484B),
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_circle, color: colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPreferenceSwitch extends StatelessWidget {
  const _OnboardingPreferenceSwitch({
    required super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final state = value ? '켜짐' : '꺼짐';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: '$title $state',
        toggled: value,
        onTap: () => onChanged(!value),
        child: ExcludeSemantics(
          child: SwitchListTile(
            value: value,
            onChanged: onChanged,
            title: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w800,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFD5E2E4)),
            ),
          ),
        ),
      ),
    );
  }
}
