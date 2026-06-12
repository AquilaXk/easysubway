import 'package:flutter/material.dart';

void main() {
  runApp(const EasySubwayApp());
}

class EasySubwayApp extends StatelessWidget {
  const EasySubwayApp({super.key});

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
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
                '접근성 이동 안내',
                style: textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '빠른 길보다, 갈 수 있는 길을 먼저 안내합니다.',
              style: textTheme.titleMedium?.copyWith(
                color: const Color(0xFF284D50),
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '고령자, 임산부, 장애인도 편하게 이동할 수 있도록 큰 글자와 명확한 선택지를 우선합니다.',
              style: textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF345C60),
                height: 1.55,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('stationSearchButton'),
              onPressed: () {},
              icon: const Icon(Icons.search),
              label: const Text('가까운 역 찾기'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('mobilityProfileButton'),
              onPressed: () {},
              icon: const Icon(Icons.accessibility_new),
              label: const Text('이동 조건 선택'),
            ),
            const SizedBox(height: 24),
            const FeatureTile(
              icon: Icons.accessible_forward,
              title: '이동 프로필',
              description: '휠체어, 유모차, 큰 짐처럼 이동 조건을 먼저 반영합니다.',
            ),
            const FeatureTile(
              icon: Icons.elevator,
              title: '시설 정보',
              description: '엘리베이터, 경사로, 넓은 개찰구 상태를 확인합니다.',
            ),
            const FeatureTile(
              icon: Icons.report_outlined,
              title: '신고와 검수',
              description: '현장에서 발견한 불편 정보를 신고하고 검수할 수 있게 준비합니다.',
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
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MergeSemantics(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colorScheme.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF102A2C),
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF345C60),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
