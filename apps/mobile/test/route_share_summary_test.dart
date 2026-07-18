import 'package:easysubway_mobile/route_share_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fare = RouteShareFare(adultFareWon: 9800, currency: 'KRW');
  const legs = [
    RouteShareLeg(
      description: '상록수역에서 4호선 급행 승차',
      departureTime: '09:10',
      arrivalTime: '10:20',
    ),
    RouteShareLeg(
      description: '용산역에서 ITX-청춘 승차',
      departureTime: '10:30',
      arrivalTime: '11:42',
    ),
  ];

  test('한국어 경로 공유 요약은 선택과 시각, ITX 운임, 계획 시간 안내를 보존한다', () {
    final text = buildRouteShareSummary(
      const RouteShareSnapshot(
        languageCode: 'ko',
        originName: '상록수',
        destinationName: '춘천',
        objective: RouteShareObjective.fastest,
        transportScope: RouteShareTransportScope.subwayAndItxCheongchun,
        departureTime: '09:10',
        arrivalTime: '11:42',
        durationMinutes: 152,
        transferCount: 1,
        freshness: RouteShareFreshness.planned,
        legs: legs,
        fare: fare,
      ),
    );

    expect(text, contains('상록수 → 춘천'));
    expect(text, contains('기준: 최단시간'));
    expect(text, contains('교통수단: 지하철 + ITX-청춘'));
    expect(text, contains('09:10 → 11:42'));
    expect(text, contains('총 152분 · 환승 1회'));
    expect(text, contains('ITX-청춘'));
    expect(text, contains('공식 운임: 성인 9,800원'));
    expect(text, contains('계획 시간 기준'));
  });

  test('영어 경로 공유 요약은 동일 facts를 영어 copy로 만든다', () {
    final text = buildRouteShareSummary(
      const RouteShareSnapshot(
        languageCode: 'en',
        originName: 'Sangnoksu',
        destinationName: 'Chuncheon',
        objective: RouteShareObjective.fewestTransfers,
        transportScope: RouteShareTransportScope.subwayAndItxCheongchun,
        departureTime: '09:10',
        arrivalTime: '11:42',
        durationMinutes: 152,
        transferCount: 1,
        freshness: RouteShareFreshness.planned,
        legs: [
          RouteShareLeg(
            description: 'Take ITX-Cheongchun at Yongsan',
            departureTime: '10:30',
            arrivalTime: '11:42',
          ),
        ],
        fare: fare,
      ),
    );

    expect(text, contains('Sangnoksu → Chuncheon'));
    expect(text, contains('Objective: Fewest transfers'));
    expect(text, contains('Official fare: Adult KRW 9,800'));
    expect(text, contains('Planned schedule'));
  });

  test('같은 snapshot과 budget은 byte-for-byte 같은 text를 만든다', () {
    const snapshot = RouteShareSnapshot(
      languageCode: 'ko',
      originName: '상록수',
      destinationName: '춘천',
      objective: RouteShareObjective.fastest,
      transportScope: RouteShareTransportScope.subwayAndItxCheongchun,
      departureTime: '09:10',
      arrivalTime: '11:42',
      durationMinutes: 152,
      transferCount: 1,
      freshness: RouteShareFreshness.planned,
      legs: legs,
      fare: fare,
    );

    expect(
      buildRouteShareSummary(snapshot, maxLength: 400),
      buildRouteShareSummary(snapshot, maxLength: 400),
    );
  });

  test('긴 경로는 optional 중간 leg부터 줄이고 필수 facts와 disclaimer를 보존한다', () {
    final snapshot = RouteShareSnapshot(
      languageCode: 'ko',
      originName: '상록수',
      destinationName: '춘천',
      objective: RouteShareObjective.fastest,
      transportScope: RouteShareTransportScope.subwayAndItxCheongchun,
      departureTime: '09:10',
      arrivalTime: '11:42',
      durationMinutes: 152,
      transferCount: 5,
      freshness: RouteShareFreshness.planned,
      legs: List.generate(
        12,
        (index) => RouteShareLeg(
          description: '중간 이동 ${index + 1} ${'아주 긴 설명 ' * 4}',
          departureTime: '10:00',
          arrivalTime: '10:10',
        ),
      ),
      fare: fare,
    );

    final text = buildRouteShareSummary(snapshot, maxLength: 260);

    expect(text.length, lessThanOrEqualTo(260));
    expect(text, contains('상록수 → 춘천'));
    expect(text, contains('기준: 최단시간'));
    expect(text, contains('09:10 → 11:42'));
    expect(text, contains('총 152분 · 환승 5회'));
    expect(text, contains('계획 시간 기준'));
    expect(text, contains('중간 경로'));
  });

  test('정상 itinerary가 없으면 빈 공유 text를 만들지 않는다', () {
    expect(
      () => buildRouteShareSummary(
        const RouteShareSnapshot(
          languageCode: 'ko',
          originName: '상록수',
          destinationName: '춘천',
          objective: RouteShareObjective.fastest,
          transportScope: RouteShareTransportScope.subway,
          departureTime: '09:10',
          arrivalTime: '10:20',
          durationMinutes: 70,
          transferCount: 0,
          freshness: RouteShareFreshness.staticData,
          legs: [],
        ),
      ),
      throwsStateError,
    );
  });
}
