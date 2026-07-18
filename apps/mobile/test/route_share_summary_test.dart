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

  test('MIXED ETA는 한국어와 영어에서 일부 실시간 정보 반영으로 안내한다', () {
    const base = RouteShareSnapshot(
      languageCode: 'ko',
      originName: '상록수',
      destinationName: '사당',
      objective: RouteShareObjective.fastest,
      transportScope: RouteShareTransportScope.subway,
      departureTime: '08:05',
      arrivalTime: '08:12',
      durationMinutes: 7,
      transferCount: 0,
      freshness: RouteShareFreshness.mixed,
      legs: [
        RouteShareLeg(
          description: '상록수에서 사당까지 이동',
          departureTime: '08:05',
          arrivalTime: '08:12',
        ),
      ],
    );

    expect(buildRouteShareSummary(base), contains('일부 실시간 정보가 반영'));
    expect(
      buildRouteShareSummary(
        const RouteShareSnapshot(
          languageCode: 'en',
          originName: 'Sangnoksu',
          destinationName: 'Sadang',
          objective: RouteShareObjective.fastest,
          transportScope: RouteShareTransportScope.subway,
          departureTime: '08:05',
          arrivalTime: '08:12',
          durationMinutes: 7,
          transferCount: 0,
          freshness: RouteShareFreshness.mixed,
          legs: [
            RouteShareLeg(
              description: 'Ride from Sangnoksu to Sadang',
              departureTime: '08:05',
              arrivalTime: '08:12',
            ),
          ],
        ),
      ),
      contains('Some realtime information is included'),
    );
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
          description: switch (index) {
            0 => '출발 구간',
            11 => '도착 구간',
            _ => '중간 이동 ${index + 1} ${'아주 긴 설명 ' * 4}',
          },
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
    expect(text, contains('- 출발 구간'));
    expect(text, contains('- 도착 구간'));
    expect(text, contains('중간 경로'));
  });

  test('필수 마지막 leg가 budget에 안 들어가면 짧은 중간 leg로 대체하지 않는다', () {
    const first = RouteShareLeg(
      description: '출발 구간',
      departureTime: '09:10',
      arrivalTime: '09:20',
    );
    const middle = RouteShareLeg(
      description: '짧은 중간 구간',
      departureTime: '09:20',
      arrivalTime: '09:30',
    );
    const last = RouteShareLeg(
      description:
          '목적지 마지막 구간은 길더라도 반드시 보존해야 하는 핵심 이동 정보입니다. '
          '목적지 도착 노선과 하차 지점을 함께 설명합니다.',
      departureTime: '09:30',
      arrivalTime: '11:42',
    );
    const essentialOnly = RouteShareSnapshot(
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
      legs: [first, last],
      fare: fare,
    );
    const withMiddle = RouteShareSnapshot(
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
      legs: [first, middle, last],
      fare: fare,
    );
    final insufficientForLast =
        buildRouteShareSummary(essentialOnly).length - 1;

    expect(
      () => buildRouteShareSummary(withMiddle, maxLength: insufficientForLast),
      throwsStateError,
    );
  });

  test('ITX 범위는 builder 경계에서도 공식 KRW 운임이 필수다', () {
    expect(
      () => buildRouteShareSummary(
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
        ),
      ),
      throwsStateError,
    );
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
