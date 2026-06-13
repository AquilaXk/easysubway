import 'package:flutter/material.dart';

import 'mobility_profile.dart';
import 'route_search.dart';
import 'station_search.dart';

void main() {
  runApp(EasySubwayApp());
}

class EasySubwayApp extends StatelessWidget {
  EasySubwayApp({
    StationSearchRepository? repository,
    RouteSearchRepository? routeRepository,
    super.key,
  }) : repository =
           repository ??
           StationSearchApiRepository(baseUri: defaultStationApiBaseUri()),
       routeRepository =
           routeRepository ??
           RouteSearchApiRepository(baseUri: defaultStationApiBaseUri());

  final StationSearchRepository repository;
  final RouteSearchRepository routeRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasySubway',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006D77)),
        scaffoldBackgroundColor: const Color(0xFFF6F8F9),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          toolbarHeight: 64,
          titleTextStyle: TextStyle(
            color: Color(0xFF102A2C),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            side: const BorderSide(color: Color(0xFF006D77), width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(
        repository: repository,
        routeRepository: routeRepository,
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.repository,
    required this.routeRepository,
    super.key,
  });

  final StationSearchRepository repository;
  final RouteSearchRepository routeRepository;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('쉬운 지하철')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Semantics(
              header: true,
              child: Text(
                '역 찾기',
                style: textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('stationSearchButton'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StationSearchScreen(repository: repository),
                  ),
                );
              },
              icon: const Icon(Icons.search),
              label: const Text('역 검색'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('routeSearchButton'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        RouteSearchScreen(repository: routeRepository),
                  ),
                );
              },
              icon: const Icon(Icons.route),
              label: const Text('경로 검색'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('mobilityProfileButton'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<MobilityProfileOption>(
                    builder: (_) => const MobilityProfileScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.accessibility_new),
              label: const Text('이동 조건'),
            ),
            const SizedBox(height: 24),
            const FeatureTile(
              icon: Icons.accessible_forward,
              title: '이동 프로필',
              semanticLabel: '이동 프로필, 이동 조건 저장',
            ),
            const FeatureTile(
              icon: Icons.elevator,
              title: '시설 정보',
              semanticLabel: '시설 정보, 엘리베이터와 경사로',
            ),
            const FeatureTile(
              icon: Icons.report_outlined,
              title: '신고',
              semanticLabel: '신고, 불편 신고',
            ),
          ],
        ),
      ),
    );
  }
}

class FeatureTile extends StatelessWidget {
  const FeatureTile({
    required this.icon,
    required this.title,
    required this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MergeSemantics(
      child: Semantics(
        label: semanticLabel,
        child: ExcludeSemantics(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFD5E2E4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: colorScheme.primary, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF102A2C),
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
