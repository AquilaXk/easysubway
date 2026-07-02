class ProductionScopeCopy {
  const ProductionScopeCopy._();

  static const supportedClaimKo = '상록수·사당 검증 pilot';
  static const unsupportedRegionStatus = 'UNSUPPORTED_REGION';
  static const unsupportedRegionActionKo = '다시 확인';
  static const routeSearchNotice =
      '$supportedClaimKo 범위의 경로만 안내하고, 벗어난 경로는 $unsupportedRegionActionKo 상태로 보여줘요.';
  static const stationSearchNotice =
      '$supportedClaimKo 범위의 역 정보를 먼저 보여주고, 벗어난 지역은 $unsupportedRegionActionKo해 주세요.';
  static const helpNotice =
      '현재 지원 범위는 $supportedClaimKo입니다. 범위 밖 정보는 준비 중이거나 $unsupportedRegionActionKo해 주세요.';
}
