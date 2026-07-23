import 'package:easysubway_mobile/features/stations/data/station_search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefix lookup은 lower-bound부터 startsWith 후보만 모은다', () {
    final index = StationSearchIndex.build(const [
      StationSearchIndexStationRow(
        stationId: 'a',
        koreanTerms: ['가산', '가산역'],
        englishTerms: ['gasan'],
        subnameTerms: [],
        chosungTerms: ['ㄱㅅ'],
      ),
      StationSearchIndexStationRow(
        stationId: 'b',
        koreanTerms: ['상록수', '상록수역'],
        englishTerms: ['sangnoksu'],
        subnameTerms: [],
        chosungTerms: ['ㅅㄹㅅ'],
      ),
      StationSearchIndexStationRow(
        stationId: 'c',
        koreanTerms: ['산본', '산본역'],
        englishTerms: ['sanbon'],
        subnameTerms: [],
        chosungTerms: ['ㅅㅂ'],
      ),
    ]);

    expect(index.lookupNamePrefix('상'), {'b'});
    expect(index.lookupNamePrefix('sang'), {'b'});
    expect(index.lookupChosungPrefix('ㅅ'), {'b', 'c'});
    expect(index.lookupChosungPrefix('ㅅㅂ'), {'c'});
    expect(index.lookupNamePrefix('없는'), isEmpty);
  });

  test('동일 역의 여러 term은 station id로 중복 제거된다', () {
    final index = StationSearchIndex.build(const [
      StationSearchIndexStationRow(
        stationId: 'gongneung',
        koreanTerms: ['공릉', '공릉역'],
        englishTerms: [],
        subnameTerms: ['서울과학기술대'],
        chosungTerms: ['ㄱㄹ', 'ㅅㅇㄱㅎㄱㅅㄷ'],
      ),
    ]);

    expect(index.lookupNamePrefix('공'), {'gongneung'});
    expect(index.lookupNamePrefix('서울'), {'gongneung'});
  });
}
