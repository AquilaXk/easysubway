import 'package:flutter/material.dart';

class MobilityProfileOption {
  const MobilityProfileOption({
    required this.id,
    required this.title,
    required this.summary,
    required this.icon,
    required this.mobilityType,
    required this.avoidStairs,
    required this.requireElevator,
    required this.allowEscalator,
    required this.minimizeTransfers,
    required this.avoidLongWalks,
  });

  final String id;
  final String title;
  final String summary;
  final IconData icon;
  final String mobilityType;
  final bool avoidStairs;
  final bool requireElevator;
  final bool allowEscalator;
  final bool minimizeTransfers;
  final bool avoidLongWalks;

  String get conditionSummary {
    final conditions = <String>[];
    if (avoidStairs) {
      conditions.add('계단 피하기');
    }
    if (requireElevator) {
      conditions.add('엘리베이터 이동');
    }
    if (minimizeTransfers) {
      conditions.add('환승 줄이기');
    }
    if (avoidLongWalks && !minimizeTransfers) {
      conditions.add('긴 보행 줄이기');
    }
    return conditions.take(2).join(' · ');
  }

  String get appliedConditionLabel => '$conditionSummary 적용 중';

  String semanticsLabel(bool isSelected) {
    final state = isSelected ? '선택됨' : '선택 가능';
    return '$title $state, $summary';
  }
}

// 서버 저장 API와 연결할 때 같은 기본값을 재사용하기 위해 화면 선택지를 데이터로 둔다.
const mobilityProfileOptions = <MobilityProfileOption>[
  MobilityProfileOption(
    id: 'elderly',
    title: '천천히 이동',
    summary: '계단을 피하고 쉬운 환승을 우선해요',
    icon: Icons.elderly,
    mobilityType: 'SENIOR',
    avoidStairs: true,
    requireElevator: false,
    allowEscalator: true,
    minimizeTransfers: true,
    avoidLongWalks: true,
  ),
  MobilityProfileOption(
    id: 'stroller',
    title: '유모차 이용',
    summary: '엘리베이터와 넓은 길을 우선해요',
    icon: Icons.child_friendly,
    mobilityType: 'STROLLER',
    avoidStairs: true,
    requireElevator: true,
    allowEscalator: false,
    minimizeTransfers: false,
    avoidLongWalks: true,
  ),
  MobilityProfileOption(
    id: 'wheelchair',
    title: '휠체어 이용',
    summary: '계단 없는 길만 안내해요',
    icon: Icons.accessible_forward,
    mobilityType: 'WHEELCHAIR',
    avoidStairs: true,
    requireElevator: true,
    allowEscalator: false,
    minimizeTransfers: true,
    avoidLongWalks: true,
  ),
  MobilityProfileOption(
    id: 'pregnant',
    title: '임신 중',
    summary: '짧게 걷고 적게 갈아타요',
    icon: Icons.pregnant_woman,
    mobilityType: 'PREGNANT',
    avoidStairs: true,
    requireElevator: false,
    allowEscalator: true,
    minimizeTransfers: true,
    avoidLongWalks: true,
  ),
  MobilityProfileOption(
    id: 'injured',
    title: '부상·회복 중',
    summary: '계단과 긴 보행을 줄여요',
    icon: Icons.healing,
    mobilityType: 'TEMPORARY_INJURY',
    avoidStairs: true,
    requireElevator: false,
    allowEscalator: true,
    minimizeTransfers: false,
    avoidLongWalks: true,
  ),
  MobilityProfileOption(
    id: 'luggage',
    title: '큰 짐이 있음',
    summary: '짐을 들고 이동하기 쉬운 길을 우선해요',
    icon: Icons.luggage,
    mobilityType: 'LUGGAGE',
    avoidStairs: true,
    requireElevator: false,
    allowEscalator: true,
    minimizeTransfers: false,
    avoidLongWalks: true,
  ),
];

class MobilityProfileScreen extends StatefulWidget {
  const MobilityProfileScreen({this.initialSelection, super.key});

  final MobilityProfileOption? initialSelection;

  @override
  State<MobilityProfileScreen> createState() => _MobilityProfileScreenState();
}

class _MobilityProfileScreenState extends State<MobilityProfileScreen> {
  MobilityProfileOption? _selectedOption;

  @override
  void initState() {
    super.initState();
    _selectedOption = widget.initialSelection;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('이동 조건')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: FilledButton.icon(
          key: const Key('mobilityProfileDoneButton'),
          onPressed: _selectedOption == null
              ? null
              : () => Navigator.of(context).pop(_selectedOption),
          icon: const Icon(Icons.check),
          label: const Text('선택 완료'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SelectionStatus(option: _selectedOption),
              if (_selectedOption != null) const SizedBox(height: 12),
              for (final option in mobilityProfileOptions)
                _MobilityProfileCard(
                  option: option,
                  selected: option.id == _selectedOption?.id,
                  onTap: () {
                    setState(() {
                      _selectedOption = option;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobilityProfileCard extends StatelessWidget {
  const _MobilityProfileCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final MobilityProfileOption option;
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
        label: option.semanticsLabel(selected),
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
              key: Key('mobilityProfileCard-${option.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 76),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(option.icon, color: colorScheme.primary, size: 34),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              option.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFF102A2C),
                                    fontWeight: FontWeight.w900,
                                    height: 1.25,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              option.summary,
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

class _SelectionStatus extends StatelessWidget {
  const _SelectionStatus({required this.option});

  final MobilityProfileOption? option;

  @override
  Widget build(BuildContext context) {
    final selectedOption = option;
    if (selectedOption == null) {
      return const SizedBox.shrink();
    }

    return Semantics(
      liveRegion: true,
      child: Text(
        '${selectedOption.title} 조건을 선택했습니다',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF102A2C),
          fontWeight: FontWeight.w800,
          height: 1.35,
        ),
      ),
    );
  }
}
