class ProductionScopeCopy {
  const ProductionScopeCopy._();

  /// 안내 가능한 구간(명사구). 문장에 끼워 넣어 쓴다.
  static const supportedRegionKo = '상록수역·사당역 구간';

  /// 지원 범위 안내(문장). 앱바 부제·설정·도움말 등 단독 노출용.
  /// 개발/운영 용어(pilot 등) 없이 사용자 언어로 쓴다.
  static const supportedClaimKo = '지금은 $supportedRegionKo을 안내해요';

  static const unsupportedRegionStatus = 'UNSUPPORTED_REGION';
  static const unsupportedRegionActionKo = '다시 확인';

  static const routeSearchNotice =
      '$supportedRegionKo 길을 안내해요. 이 구간을 벗어난 경로는 아직 준비 중이에요.';
  static const stationSearchNotice =
      '$supportedRegionKo 역 정보를 먼저 보여드려요. 다른 지역은 준비되는 대로 추가할게요.';
  static const helpNotice =
      '지금은 $supportedRegionKo을 안내하고 있어요. 다른 구간은 준비되는 대로 추가할게요.';
}
