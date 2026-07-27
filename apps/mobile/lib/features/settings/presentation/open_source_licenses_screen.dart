import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

typedef LicenseEntriesLoader = Future<List<LicenseEntry>> Function();

class OpenSourceLicensesScreen extends StatefulWidget {
  const OpenSourceLicensesScreen({this.licenseEntriesLoader, super.key});

  final LicenseEntriesLoader? licenseEntriesLoader;

  @override
  State<OpenSourceLicensesScreen> createState() =>
      _OpenSourceLicensesScreenState();
}

class _OpenSourceLicensesScreenState extends State<OpenSourceLicensesScreen> {
  late final Future<List<_PackageLicenses>> _packages = _loadPackages();

  Future<List<_PackageLicenses>> _loadPackages() async {
    final entries =
        await (widget.licenseEntriesLoader?.call() ??
            LicenseRegistry.licenses.toList());
    final grouped = <String, List<LicenseEntry>>{};
    for (final entry in entries) {
      final packageNames = entry.packages.isEmpty
          ? const <String>['기타']
          : entry.packages;
      for (final packageName in packageNames) {
        grouped.putIfAbsent(packageName, () => []).add(entry);
      }
    }
    final packages =
        grouped.entries
            .map((entry) => _PackageLicenses(entry.key, entry.value))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return packages;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('openSourceLicensesScreen'),
      appBar: AppBar(title: const Text('오픈 소스 라이선스')),
      body: SafeArea(
        child: FutureBuilder<List<_PackageLicenses>>(
          future: _packages,
          builder: (context, snapshot) {
            final packages = snapshot.data;
            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _NoticeHeader()),
                if (snapshot.connectionState != ConnectionState.done)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('오픈 소스 정보를 불러오지 못했어요.'),
                      ),
                    ),
                  )
                else if (packages == null || packages.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('등록된 오픈 소스 고지가 없어요.')),
                  )
                else
                  SliverList.builder(
                    itemCount: packages.length,
                    itemBuilder: (context, index) =>
                        _PackageLicenseTile(package: packages[index]),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NoticeHeader extends StatelessWidget {
  const _NoticeHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: EasySubwayAccessibleColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: const Text(
            'OSS Notice | EasySubway',
            style: TextStyle(
              color: EasySubwayAccessibleColors.interactionOnPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '© 2026 아퀼라 소프트웨어',
                style: TextStyle(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 12),
              Text(
                '쉬운 지하철은 아래 오픈 소스 소프트웨어를 사용합니다. '
                '각 항목을 펼치면 앱 빌드에 등록된 저작권 고지와 라이선스 전문을 확인할 수 있습니다.',
                style: TextStyle(
                  color: EasySubwayAccessibleColors.secondaryText,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: EasySubwayAccessibleColors.line),
      ],
    );
  }
}

class _PackageLicenses {
  const _PackageLicenses(this.name, this.entries);

  final String name;
  final List<LicenseEntry> entries;
}

class _PackageLicenseTile extends StatefulWidget {
  const _PackageLicenseTile({required this.package});

  final _PackageLicenses package;

  @override
  State<_PackageLicenseTile> createState() => _PackageLicenseTileState();
}

class _PackageLicenseTileState extends State<_PackageLicenseTile> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: Key('openSourcePackage-${widget.package.name}'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      title: Text(
        widget.package.name,
        style: const TextStyle(
          color: EasySubwayAccessibleColors.text,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: const Text('저작권 고지 및 라이선스 전문'),
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
      children: _expanded
          ? [
              for (
                var index = 0;
                index < widget.package.entries.length;
                index += 1
              ) ...[
                if (index > 0) const Divider(height: 32),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.package.entries[index].paragraphs
                        .map((paragraph) => paragraph.text)
                        .join('\n\n'),
                    style: const TextStyle(
                      color: EasySubwayAccessibleColors.secondaryText,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ]
          : const [],
    );
  }
}
