import 'dart:math' as math;

// 노선도 축소 하한(#2600).
//
// [문제] 축소할수록 팬 프레임이 무너진다. 바탕 도식을 매 프레임 전부 재래스터화
// 하고 그 비용이 **뷰포트에 들어오는 요소 수**에 비례하기 때문이다 — 축소하면
// 같은 화면에 들어오는 노선·역·역명이 늘어난다. SM-A175N profile 실측(수도권,
// 팬 raster p90 / raster jank):
//
//   배율 0.16 → 16.3ms / 7.4%(스와이프 19.4%)
//   배율 0.24 → 13.0ms / 3.1%
//   배율 0.40 → 10.0ms / 1.0%
//   배율 0.84 → 7.2ms / 0.5%   (지역 초기 화면)
//   배율 2.00 → 5.7ms / 0%
//
// [측정 뷰포트] 위 프로파일과 아래 표의 배율은 모두 오너 기기 SM-A175N 한 대에서
// 쟀다 — 화면 1080×2340 물리 px, devicePixelRatio 2.8125(= 384.0×832.0 logical),
// 그중 지도 캔버스는 384.0×602.4 logical이다.
//
// [이 하한이 보장하지 못하는 것 — 후속 추적 #2600]
//   (1) 하한은 뷰포트와 무관한 고정 scale인데 래스터 비용은 화면에 들어오는 요소
//       수에 비례한다. 태블릿·가로 모드처럼 캔버스 면적이 2~3배인 화면은 같은
//       배율에서 요소가 그만큼 늘어 위 프로파일이 그대로 재현되지 않는다.
//   (2) 프로파일은 수도권 한 권역만 쟀고, 부산 지정값 0.1128은 그 곡선의 최악
//       구간(0.16)보다 아래다. 오너 지정값이라 그대로 두되 부산은 여전히 렉
//       구간이 열려 있다.
//
// [해법] 렉이 생기는 배율 아래로는 **축소 자체를 막는다**. 종전 하한은 권역과
// 무관한 0.08(수도권 실측 곡선의 최악 구간보다도 아래)이라 사실상 열려 있었다.
//
// [왜 계산식이 아니라 표인가] "화면 높이 ÷ 노선망 세로" 같은 규칙으로 유도해
// 봤지만 오너가 실제로 원하는 조망과 맞지 않았다(같은 뷰포트에서 규칙값 부산
// 0.17·대구 0.39·수도권 0.30·광주 0.63·대전 0.58 vs 오너 지정 0.1128·0.2216·
// 0.2261·0.2399·0.3119). 권역마다 도식의 성격·여백·정보 밀도가 달라 **오너가
// 기기에서 직접 맞춘 값**이 정본이다. 유도식을 억지로 만들면 도식이 조금만
// 바뀌어도 오너 의도에서 벗어나므로, 실측값을 그대로 둔다.

/// 권역별 축소 하한(카메라 scale).
///
/// **오너 지정, 2026-07-27 실기기(SM-A175N) 실측.** 오너가 권역마다 원하는 최대
/// 축소 상태를 기기에서 직접 맞춘 뒤, uiautomator 접근성 덤프의 역 노드 화면
/// 좌표와 권역별 `*-alignment-fixture.json`의 원본 좌표를 대조해 얻은
/// 화면px/원본단위 중앙값 ÷ devicePixelRatio(2.8125)로 산출했다. 아래 주석의
/// `공통역 N개·M쌍`은 그 중앙값의 표본 크기(덤프와 fixture에 함께 있는 역 수와,
/// 거리비를 낸 역 쌍 수)다.
///
/// 값 조정은 **이 표 한 곳**에서 한다. 키는 표시용 권역명
/// ([routeMapDisplayRegionName] 정규화 결과)이다. 노선망 치수는
/// `tools/route-map/route-map-defs/<권역>-alignment-fixture.json` 좌표 bbox다.
const Map<String, double> kRouteMapMinScaleByRegion = <String, double>{
  // 공통역 53개·1367쌍 → 노선망 9996×4541.
  // 주의: 파일 상단 [이 하한이 보장하지 못하는 것] (2) — 실측 곡선상 팬 jank가
  // 큰 구간이다(수도권 0.16에서 7.4%, 그 아래는 더 나쁨). 오너 지정값이므로
  // 그대로 두되, 하한 상향이나 별도 최적화가 필요하다(#2600).
  '부산': 0.1128,
  // 공통역 49개·1168쌍 → 노선망 4102×1965.
  '대구': 0.2216,
  // 공통역 349개·653쌍 → 노선망 3361×2519.
  '수도권': 0.2261,
  // 공통역 19개·171쌍 → 노선망 1250×1220.
  '광주': 0.2399,
  // 공통역 22개·231쌍 → 노선망 1044×1320.
  '대전': 0.3119,
};

/// 표에 없는 권역의 하한 = 표에서 **가장 축소를 덜 허용하는 값**.
///
/// 권역이 추가되면 [kRouteMapMinScaleByRegion]에 오너 지정값을 넣어야 한다 —
/// 누락은 route_map_min_scale_test.dart의 등록 게이트가 red로 잡는다. 그 전까지는
/// 성능 쪽으로 보수적인 값을 쓴다(하한이 빠져 종전 0.08로 열리는 것이 최악이다).
/// 이 값이 미지 권역의 첫 화면을 확대해버리는 부작용은 [routeMapMinimumScale]의
/// `initialFitScale` 캡이 막는다.
///
/// 표를 재조정해도 따라오도록 리터럴 사본이 아니라 표에서 유도한다.
final double kRouteMapDefaultMinScale = kRouteMapMinScaleByRegion.values.reduce(
  math.max,
);

/// 저장형 권역명('부산권')을 [kRouteMapMinScaleByRegion]의 키인 표시형('부산')으로
/// 정규화한다.
///
/// 앱이 다루는 권역 문자열의 기본형은 `drift_station_repository`가 만든 저장형이라,
/// 정규화 없이 표를 조회하면 조용히 폴백으로 새어 나간다(같은 유형의 실기기 회귀:
/// 정규화 누락으로 basemapAssetId가 항상 null이 돼 오너 라벨이 bounds에 전혀
/// 반영되지 않았던 #2068). 그래서 정규화는 호출부가 아니라 조회 함수가 책임진다.
String routeMapDisplayRegionName(String region) => switch (region) {
  '부산권' => '부산',
  '광주권' => '광주',
  '대구권' => '대구',
  '대전권' => '대전',
  _ => region,
};

/// 이 권역의 축소 하한. [region]은 저장형('부산권')·표시형('부산') 모두 받는다.
///
/// 하한은 **축소만 막는 값**이라 다음 둘을 넘지 않는다.
/// - [maxScale]: minScale > maxScale인 불가능한 카메라 방지.
/// - [initialFitScale]: 이 지역 초기 화면 배율. 하한이 그보다 크면 첫 화면을
///   오히려 **확대**해 "소규모 권역은 초기 화면에 지역 전체"(#1764 E)와 "역 focus
///   배율 = 초기 배율의 1/0.42(≈2.38배)"(#2062) 계약이 함께 깨진다. 초기 배율이
///   하한보다 낮은 상태는 실제로 존재한다 — 오너 라벨 sidecar가 아직 로드되지
///   않은 프레임의 부산 contain-fit은 0.0984로 하한 0.1128보다 낮다. null이면
///   캡하지 않는다(하한 도입 전 회귀 테스트·순수 표 조회용).
double routeMapMinimumScale({
  required String region,
  required double maxScale,
  double? initialFitScale,
}) {
  final designated =
      kRouteMapMinScaleByRegion[routeMapDisplayRegionName(region)] ??
      kRouteMapDefaultMinScale;
  final capped = math.min(designated, maxScale);
  if (initialFitScale == null ||
      !initialFitScale.isFinite ||
      initialFitScale <= 0) {
    return capped;
  }
  return math.min(capped, initialFitScale);
}
