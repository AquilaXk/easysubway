// 역 검색용 정렬 prefix term 인덱스.
// 모든 prefix 조합을 Map으로 펼치지 않고, 정렬된 term 테이블에서
// lower-bound + startsWith 순회로 후보 station id만 모은다.

enum StationSearchTermKind { korean, english, subname, chosung }

class StationSearchTermEntry implements Comparable<StationSearchTermEntry> {
  const StationSearchTermEntry({
    required this.normalizedKey,
    required this.stationId,
    required this.termKind,
  });

  final String normalizedKey;
  final String stationId;
  final StationSearchTermKind termKind;

  @override
  int compareTo(StationSearchTermEntry other) {
    final byKey = normalizedKey.compareTo(other.normalizedKey);
    if (byKey != 0) {
      return byKey;
    }
    return stationId.compareTo(other.stationId);
  }
}

/// 인덱스 구축에 필요한 최소 station 행.
class StationSearchIndexStationRow {
  const StationSearchIndexStationRow({
    required this.stationId,
    required this.koreanTerms,
    required this.englishTerms,
    required this.subnameTerms,
    required this.chosungTerms,
  });

  final String stationId;
  final List<String> koreanTerms;
  final List<String> englishTerms;
  final List<String> subnameTerms;
  final List<String> chosungTerms;
}

class StationSearchIndex {
  StationSearchIndex._({
    required this.sortedKoreanTerms,
    required this.sortedEnglishTerms,
    required this.sortedSubnameTerms,
    required this.sortedChosungTerms,
  });

  final List<StationSearchTermEntry> sortedKoreanTerms;
  final List<StationSearchTermEntry> sortedEnglishTerms;
  final List<StationSearchTermEntry> sortedSubnameTerms;
  final List<StationSearchTermEntry> sortedChosungTerms;

  factory StationSearchIndex.build(List<StationSearchIndexStationRow> rows) {
    final korean = <StationSearchTermEntry>[];
    final english = <StationSearchTermEntry>[];
    final subname = <StationSearchTermEntry>[];
    final chosung = <StationSearchTermEntry>[];

    for (final row in rows) {
      for (final term in row.koreanTerms) {
        if (term.isEmpty) {
          continue;
        }
        korean.add(
          StationSearchTermEntry(
            normalizedKey: term,
            stationId: row.stationId,
            termKind: StationSearchTermKind.korean,
          ),
        );
      }
      for (final term in row.englishTerms) {
        if (term.isEmpty) {
          continue;
        }
        english.add(
          StationSearchTermEntry(
            normalizedKey: term,
            stationId: row.stationId,
            termKind: StationSearchTermKind.english,
          ),
        );
      }
      for (final term in row.subnameTerms) {
        if (term.isEmpty) {
          continue;
        }
        subname.add(
          StationSearchTermEntry(
            normalizedKey: term,
            stationId: row.stationId,
            termKind: StationSearchTermKind.subname,
          ),
        );
      }
      for (final term in row.chosungTerms) {
        if (term.isEmpty) {
          continue;
        }
        chosung.add(
          StationSearchTermEntry(
            normalizedKey: term,
            stationId: row.stationId,
            termKind: StationSearchTermKind.chosung,
          ),
        );
      }
    }

    korean.sort();
    english.sort();
    subname.sort();
    chosung.sort();

    return StationSearchIndex._(
      sortedKoreanTerms: List.unmodifiable(korean),
      sortedEnglishTerms: List.unmodifiable(english),
      sortedSubnameTerms: List.unmodifiable(subname),
      sortedChosungTerms: List.unmodifiable(chosung),
    );
  }

  /// [query]로 시작하는 term의 station id를 중복 없이 모은다.
  Set<String> lookupPrefix(
    List<StationSearchTermEntry> sortedTerms,
    String query,
  ) {
    if (query.isEmpty || sortedTerms.isEmpty) {
      return const {};
    }
    final start = _lowerBound(sortedTerms, query);
    if (start >= sortedTerms.length) {
      return const {};
    }
    final ids = <String>{};
    for (var i = start; i < sortedTerms.length; i++) {
      final entry = sortedTerms[i];
      if (!entry.normalizedKey.startsWith(query)) {
        break;
      }
      ids.add(entry.stationId);
    }
    return ids;
  }

  Set<String> lookupChosungPrefix(String query) =>
      lookupPrefix(sortedChosungTerms, query);

  Set<String> lookupNamePrefix(String query) {
    return {
      ...lookupPrefix(sortedKoreanTerms, query),
      ...lookupPrefix(sortedEnglishTerms, query),
      ...lookupPrefix(sortedSubnameTerms, query),
    };
  }
}

int _lowerBound(List<StationSearchTermEntry> sorted, String query) {
  var low = 0;
  var high = sorted.length;
  while (low < high) {
    final mid = low + ((high - low) >> 1);
    if (sorted[mid].normalizedKey.compareTo(query) < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}
