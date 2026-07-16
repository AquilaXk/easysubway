import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../accessible_design.dart';
import '../../../app/app_components.dart';

class DataSourceAttributionScreen extends StatefulWidget {
  const DataSourceAttributionScreen({
    super.key,
    this.initialManifest,
    this.initialInventory,
  }) : assert(
         (initialManifest == null) == (initialInventory == null),
         'initialManifest and initialInventory must be provided together.',
       );

  final Map<String, Object?>? initialManifest;
  final Map<String, Object?>? initialInventory;

  @override
  State<DataSourceAttributionScreen> createState() =>
      _DataSourceAttributionScreenState();
}

class _DataSourceAttributionScreenState
    extends State<DataSourceAttributionScreen> {
  static const _mapManifestAsset =
      'assets/datapacks/metro_map_pack/manifest.json';
  static const _sourceInventoryAsset = 'assets/datapacks/source-inventory.json';

  late final Future<
    ({Map<String, Object?> manifest, Map<String, Object?> inventory})
  >
  _future = _load();

  Future<({Map<String, Object?> manifest, Map<String, Object?> inventory})>
  _load() async {
    final initialManifest = widget.initialManifest;
    final initialInventory = widget.initialInventory;
    if (initialManifest != null && initialInventory != null) {
      return (manifest: initialManifest, inventory: initialInventory);
    }
    final [manifestText, inventoryText] = await Future.wait([
      rootBundle.loadString(_mapManifestAsset),
      rootBundle.loadString(_sourceInventoryAsset),
    ]);
    return (
      manifest: jsonDecode(manifestText) as Map<String, Object?>,
      inventory: jsonDecode(inventoryText) as Map<String, Object?>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('dataSourceAttributionScreen'),
      appBar: AppBar(title: const Text('데이터 및 지도 출처')),
      body: SafeArea(
        child:
            FutureBuilder<
              ({Map<String, Object?> manifest, Map<String, Object?> inventory})
            >(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ListView(
                    padding: mainPagePadding,
                    children: const [
                      AppCard(
                        child: AppInfoRow(
                          icon: Icons.error_outline,
                          iconColor: EasySubwayAccessibleColors.amber,
                          title: '자료 제공 정보를 불러오지 못했어요',
                          subtitle: '앱을 다시 열고, 계속 보이지 않으면 고객지원에 알려 주세요.',
                        ),
                      ),
                    ],
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final manifest = snapshot.data!.manifest;
                final inventory = snapshot.data!.inventory;
                final maps = (manifest['maps'] as List)
                    .cast<Map<String, Object?>>();
                final sources = (inventory['sources'] as List)
                    .cast<Map<String, Object?>>()
                    .toList(growable: false);
                return ListView(
                  padding: mainPagePadding,
                  children: [
                    const AppCard(
                      child: AppInfoRow(
                        icon: Icons.fact_check_outlined,
                        iconColor: EasySubwayAccessibleColors.amber,
                        title: '현재 앱 표시',
                        // 내부 거버넌스 언어(pilot·"~보장한다고 말하지 않아요") 대신
                        // 어떤 자료로 무엇을 확인했는지 사실·metadata로 표현한다(#1765).
                        subtitle:
                            '지도와 길·시설 안내는 공식·공개 자료를 바탕으로 해요. 상록수·사당역은 현장 확인까지 마쳤고, 나머지 역은 자료를 바탕으로 안내해요.',
                      ),
                    ),
                    const AppSectionTitle(title: '지도 표시용 asset'),
                    for (final map in maps) _AttributionCard.map(map, manifest),
                    const AppSectionTitle(title: '데이터 품질 Level'),
                    const AppCard(
                      child: AppInfoRow(
                        icon: Icons.verified_outlined,
                        iconColor: EasySubwayAccessibleColors.mintDark,
                        title: 'Level 1-4 품질 기준',
                        subtitle:
                            'Level 1은 역·노선 수, Level 2는 필수 시설 근거, Level 3은 운행상태와 최신 여부, Level 4는 현장 또는 운영기관이 확인한 쉬운 길을 봐요.',
                      ),
                    ),
                    const AppCard(
                      child: AppInfoRow(
                        icon: Icons.analytics_outlined,
                        iconColor: EasySubwayAccessibleColors.amber,
                        title: '품질 지표',
                        subtitle:
                            '필수 시설 근거 비율, 운행상태 확인 비율, 최신 정보 비율, 확인된 쉬운 길 비율, 현장 확인 경로 비율을 함께 확인해요.',
                      ),
                    ),
                    const AppSectionTitle(title: '경로·시설 안내용 데이터'),
                    for (final source in sources)
                      _AttributionCard.source(source),
                  ],
                );
              },
            ),
      ),
    );
  }
}

class _AttributionCard extends StatelessWidget {
  const _AttributionCard._({
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  factory _AttributionCard.map(
    Map<String, Object?> map,
    Map<String, Object?> manifest,
  ) {
    final license = (map['license'] as Map<String, Object?>?) ?? const {};
    final offline = (map['offline'] as Map<String, Object?>?) ?? const {};
    return _AttributionCard._(
      title: _text(map['name_ko']),
      subtitle: '제공·소유: ${_text(map['operator'])}',
      rows: [
        ('제공 기관', _text(license['source'], _text(map['name_ko']))),
        ('라이선스', '${_text(license['name'])} (${_text(license['spdx'])})'),
        ('작성자', _text(license['authors'])),
        ('라이선스 링크', _text(license['url'])),
        ('표기 필요', _yesNo(license['attributionRequired'])),
        ('가져온 날짜', _text(license['date'])),
        ('확인한 날짜', _text(manifest['generated_at_utc'])),
        (
          '상업적 이용 / 재배포',
          '${_allowed(license['commercialUseAllowed'])} / ${_allowed(license['redistributionAllowed'])}',
        ),
        ('검토 상태', _text(license['reviewStatus'])),
        ('변경 사항', _text(license['changes'])),
        ('파일 경로', _text(offline['path'])),
      ],
    );
  }

  factory _AttributionCard.source(Map<String, Object?> source) {
    final license = (source['license'] as Map<String, Object?>?) ?? const {};
    return _AttributionCard._(
      title: _text(source['displayName']),
      subtitle:
          '제공·소유: ${_text(source['provider'])} / ${_text(source['owner'])}',
      rows: [
        ('제공 기관', _text(source['displayName'])),
        ('라이선스', '${_text(license['name'])} (${_text(license['type'])})'),
        ('라이선스 링크', _text(license['evidenceUrl'])),
        ('표기 필요', _text(license['attribution'])),
        ('가져온 날짜', _text(source['retrievedAt'])),
        ('확인한 날짜', _text(source['observedDataUpdatedAt'])),
        (
          '상업적 이용 / 재배포',
          '${_allowed(license['commercialUseAllowed'])} / ${_allowed(license['redistributionAllowed'])}',
        ),
        (
          '변경 사항',
          source.containsKey('changes')
              ? _text(source['changes'])
              : '자료 목록에 별도 변경 고지 없음',
        ),
      ],
    );
  }

  final String title;
  final String subtitle;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = [
      title,
      subtitle,
      for (final row in rows) '${row.$1}: ${row.$2}',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: semanticLabel,
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              for (final row in rows)
                _AttributionRow(label: row.$1, value: row.$2),
            ],
          ),
        ),
      ),
    );
  }

  static String _text(Object? value, [String fallback = '미기록']) {
    if (value is List) {
      final joined = value
          .whereType<Object>()
          .map((item) => '$item')
          .join(', ');
      return joined.isEmpty ? fallback : joined;
    }
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _yesNo(Object? value) {
    if (value == true) {
      return '예';
    }
    if (value == false) {
      return '아니오';
    }
    return '미확정';
  }

  static String _allowed(Object? value) {
    if (value == true) {
      return '가능';
    }
    if (value == false) {
      return '불가';
    }
    return '미확정';
  }
}

class _AttributionRow extends StatelessWidget {
  const _AttributionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: EasySubwayAccessibleColors.secondaryText,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
