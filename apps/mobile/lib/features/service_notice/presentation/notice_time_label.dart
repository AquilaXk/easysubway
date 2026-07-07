/// 오프라인 강등된 마지막 수신본에 붙이는 "N시간 전 기준" 라벨을 만든다.
///
/// 데이터 출처의 최종 갱신 시점을 숨기지 않는다는 원칙(강등 사다리)에 따라,
/// stale 상태에서 [asOf] 수신 시각을 사용자 언어로 표기한다.
String formatNoticeAsOf(DateTime asOf, DateTime now) {
  final elapsed = now.difference(asOf);
  if (elapsed.inMinutes < 1) {
    return '방금 전 기준';
  }
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes}분 전 기준';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours}시간 전 기준';
  }
  return '${elapsed.inDays}일 전 기준';
}
