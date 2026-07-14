import 'package:easysubway_mobile/features/train_search/domain/train_search_scope_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filter와 stale deep link는 ITX-청춘을 노출하지 않는다', () {
    expect(TrainSearchTrainType.parse('ITX_CHEONGCHUN'), isNull);
    expect(
      TrainSearchTrainType.values.map((value) => value.apiValue),
      isNot(contains('ITX_CHEONGCHUN')),
    );
  });

  test('station picker와 response 정규화는 ITX row만 제거하고 대전 KTX는 유지한다', () {
    const rows = [
      _TrainRow('청량리', '춘천', 'ITX_CHEONGCHUN'),
      _TrainRow('용산', '대전', 'ITX_CHEONGCHUN'),
      _TrainRow('서울', '대전', 'KTX'),
    ];

    expect(
      TrainSearchScopePolicy.retainSupported(rows, (row) => row.trainType),
      [const _TrainRow('서울', '대전', 'KTX')],
    );
  });
}

class _TrainRow {
  const _TrainRow(this.departureStation, this.arrivalStation, this.trainType);

  final String departureStation;
  final String arrivalStation;
  final String trainType;

  @override
  bool operator ==(Object other) =>
      other is _TrainRow &&
      departureStation == other.departureStation &&
      arrivalStation == other.arrivalStation &&
      trainType == other.trainType;

  @override
  int get hashCode => Object.hash(departureStation, arrivalStation, trainType);
}
