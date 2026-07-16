import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../mobile_error_reporter.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';

const _stationTimetablePagePadding = EdgeInsets.fromLTRB(20, 20, 20, 32);

class StationTimetableScreen extends StatefulWidget {
  const StationTimetableScreen({
    required this.stationId,
    required this.stationName,
    required this.lines,
    this.repository,
    super.key,
  });

  final String stationId;
  final String stationName;
  final List<StationSearchLine> lines;
  final StationTimetableRepository? repository;

  @override
  State<StationTimetableScreen> createState() => _StationTimetableScreenState();
}

class _StationTimetableScreenState extends State<StationTimetableScreen> {
  late String? _lineId;
  late StationTimetableDayType _dayType;
  StationTimetable? _timetable;
  String? _directionName;
  var _loading = false;
  var _requestId = 0;

  @override
  void initState() {
    super.initState();
    _lineId = widget.lines.firstOrNull?.id;
    final now = debugStationVerifiedClock();
    _dayType = _todayTimetableDayType(now);
    if (widget.repository != null && _lineId != null) {
      unawaited(_load(date: now, findCoverage: true));
    }
  }

  Future<void> _load({DateTime? date, bool findCoverage = false}) async {
    final repository = widget.repository;
    final lineId = _lineId;
    if (repository == null || lineId == null) {
      return;
    }
    final requestId = ++_requestId;
    setState(() => _loading = true);
    try {
      final timetable = findCoverage
          ? await loadFirstAvailableStationTimetable(
              stationId: widget.stationId,
              lines: widget.lines,
              repository: repository,
              date: date!,
            )
          : date == null
          ? await repository.loadStationTimetable(
              stationId: widget.stationId,
              lineId: lineId,
              dayType: _dayType,
              referenceDate: debugStationVerifiedClock(),
            )
          : await repository.loadStationTimetableForDate(
              stationId: widget.stationId,
              lineId: lineId,
              date: date,
            );
      if (!mounted || requestId != _requestId) {
        return;
      }
      if (timetable == null) {
        setState(() => _loading = false);
        return;
      }
      final directionNames = timetable.directions
          .map((direction) => direction.name)
          .toSet();
      setState(() {
        _timetable = timetable;
        _lineId = timetable.lineId;
        _dayType = timetable.dayType;
        _directionName = directionNames.contains(_directionName)
            ? _directionName
            : timetable.directions.firstOrNull?.name;
        _loading = false;
      });
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 시간표 조회 중 예외가 발생했습니다.');
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _timetable = null;
        _directionName = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetable = _timetable;
    final direction = timetable?.directions
        .where((item) => item.name == _directionName)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.stationName} 시간표')),
      body: SafeArea(
        child: ListView(
          padding: _stationTimetablePagePadding,
          children: [
            if (widget.lines.length > 1) ...[
              const _StationTimetableSectionTitle(title: '노선'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final line in widget.lines)
                    ChoiceChip(
                      key: Key('stationTimetableLine-${line.id}'),
                      label: Text(line.name),
                      selected: _lineId == line.id,
                      onSelected: (_) {
                        setState(() => _lineId = line.id);
                        unawaited(_load());
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            const _StationTimetableSectionTitle(title: '운행일'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final dayType in StationTimetableDayType.values)
                  ChoiceChip(
                    key: Key('stationTimetableDay-${dayType.name}'),
                    label: Text(dayType.label),
                    selected: _dayType == dayType,
                    onSelected: (_) {
                      setState(() => _dayType = dayType);
                      unawaited(_load());
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (timetable == null || !timetable.isAvailable)
              const _StationTimetableEmptyMessage(message: '시간표를 준비 중이에요.')
            else ...[
              const _StationTimetableSectionTitle(title: '방향'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in timetable.directions)
                    ChoiceChip(
                      key: Key('stationTimetableDirection-${item.name}'),
                      label: Text(item.name),
                      selected: _directionName == item.name,
                      onSelected: (_) =>
                          setState(() => _directionName = item.name),
                    ),
                ],
              ),
              if (direction != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    Text('첫차 ${direction.firstDeparture.timeLabel}'),
                    Text('막차 ${direction.lastDeparture.timeLabel}'),
                  ],
                ),
                const SizedBox(height: 12),
                for (
                  var index = 0;
                  index < direction.departures.length;
                  index++
                ) ...[
                  if (index > 0) const Divider(height: 1),
                  Semantics(
                    label: direction.departures[index].semanticLabel,
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(direction.departures[index].timeLabel),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

StationTimetableDayType _todayTimetableDayType(DateTime now) {
  return switch (now.weekday) {
    DateTime.saturday => StationTimetableDayType.saturday,
    DateTime.sunday => StationTimetableDayType.sundayHoliday,
    _ => StationTimetableDayType.weekday,
  };
}

Future<StationTimetable?> loadFirstAvailableStationTimetable({
  required String stationId,
  required List<StationSearchLine> lines,
  required StationTimetableRepository repository,
  required DateTime date,
}) async {
  StationTimetable? firstResult;
  for (final line in lines) {
    final timetable = await repository.loadStationTimetableForDate(
      stationId: stationId,
      lineId: line.id,
      date: date,
    );
    firstResult ??= timetable;
    if (timetable.isAvailable) {
      return timetable;
    }
  }
  return firstResult;
}

class _StationTimetableSectionTitle extends StatelessWidget {
  const _StationTimetableSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: EasySubwayAccessibleColors.text,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}

class _StationTimetableEmptyMessage extends StatelessWidget {
  const _StationTimetableEmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: EasySubwayAccessibleColors.secondaryText,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    );
  }
}
