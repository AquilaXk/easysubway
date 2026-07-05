/// 길찾기 결과와 역 안 이동의 불확실성(헤지)·주의 문구를 앱 전체가 쓰는 단일
/// 사전. 예전에는 route_search·internal_route·local_internal_route_repository가
/// 같은 원인 코드에 서로 다른 문구를 따로 갖고 있어("계단 없는 길인지 아직 알 수
/// 없어요" vs "…확인하지 못했어요") 같은 의미가 문구만 다르게 여러 벌 존재했다.
/// 여기 한 벌로 모으고, 불확실성은 의미 기준 3종(계단 없는 길·엘리베이터/통로
/// 상태·경로 연결)과 일반 1종으로만 표현한다. 안내 서비스의 신뢰를 스스로 깎지
/// 않도록 부정·면책 톤 대신 부드러운 진행형("확인하고 있어요")으로 안내한다(#1577).
library;

/// 무계단(계단 없는 길) 확인 여부를 아직 모를 때.
const routeHedgeStepFreeUnknown = '계단 없는 길인지 확인하고 있어요.';

/// 엘리베이터·통로 등 접근성 시설 상태를 아직 모를 때.
const routeHedgeAccessibilityUnknown = '엘리베이터·통로 상태를 확인하고 있어요.';

/// 경로가 실제로 이어지는지(연결) 아직 확인 못했을 때.
const routeHedgeConnectivityUnknown = '길이 이어지는지 확인하고 있어요.';

/// 세부 원인을 특정할 수 없는 일반 불확실성.
const routeHedgeGenericUnknown = '일부 안내를 확인하고 있어요.';

/// 불확실성 원인 코드 → 헤지 3종 + 일반. 알 수 없는 코드는 일반 문구로 모은다.
/// 같은 의미의 코드는 같은 문구로 수렴하므로(예: 경로 연결 미확인은 그래프·연결
/// 생성 코드가 모두 한 문구), 표시 단계의 중복 제거가 자연히 이뤄진다.
String routeUncertaintyHedgeLabel(String code) {
  return switch (code.trim()) {
    'STAIR_ONLY_ACCESS_UNKNOWN' => routeHedgeStepFreeUnknown,
    'ACCESSIBILITY_STATE_UNKNOWN' => routeHedgeAccessibilityUnknown,
    'ROUTE_GRAPH_UNKNOWN' ||
    'GENERATED_CONNECTOR_UNVERIFIED' => routeHedgeConnectivityUnknown,
    _ => routeHedgeGenericUnknown,
  };
}

/// 경로 주의(warning) 코드 → 문구. 사실성 주의(계단 포함·오래된 데이터 등)는
/// 그대로 두고, 불확실성 계열은 위 헤지 사전으로 위임해 한 벌로 통일한다.
String routeWarningLabel(String code) {
  return switch (code.trim()) {
    'LOW_DATA_CONFIDENCE' => '일부 시설 안내를 준비 중이에요.',
    'STALE_ACCESSIBILITY_DATA' => '시설 상태 안내가 오래됐을 수 있어요.',
    'STAIR_ONLY_ACCESS' => '계단 포함 구간이 있습니다.',
    'DURATION_UNKNOWN' => '소요 시간을 확인하고 있어요.',
    _ => routeUncertaintyHedgeLabel(code),
  };
}
