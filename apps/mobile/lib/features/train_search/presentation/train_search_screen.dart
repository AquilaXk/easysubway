import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/train_search_models.dart';
import '../domain/train_search_scope_policy.dart';

enum _StationSlot { departure, arrival }

class TrainSearchScreen extends StatefulWidget {
  const TrainSearchScreen({
    required this.repository,
    this.now = DateTime.now,
    super.key,
  });

  final TrainSearchRepository repository;
  final DateTime Function() now;

  @override
  State<TrainSearchScreen> createState() => _TrainSearchScreenState();
}

class _TrainSearchScreenState extends State<TrainSearchScreen> {
  final _departureController = TextEditingController();
  final _arrivalController = TextEditingController();
  TrainStation? _departure;
  TrainStation? _arrival;
  _StationSlot? _suggestionSlot;
  List<TrainStation> _suggestions = const [];
  int _stationRequestToken = 0;
  int _searchRequestToken = 0;
  late DateTime _departureDate;
  DateTime? _returnDate;
  TrainSearchTrainType? _trainType;
  bool _roundTrip = false;
  bool _loading = false;
  TrainSearchResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _departureDate = _dateOnly(widget.now());
  }

  @override
  void dispose() {
    _departureController.dispose();
    _arrivalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('기차 검색')),
      body: SafeArea(
        child: ListView(
          key: const Key('trainSearchScrollView'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              '전국 여객열차',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '공식 시간표와 성인 1인 운임을 확인하세요.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            _stationField(
              slot: _StationSlot.departure,
              controller: _departureController,
              label: '출발역',
              key: const Key('trainSearchDepartureField'),
            ),
            _suggestionList(_StationSlot.departure),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton.outlined(
                key: const Key('trainSearchSwapButton'),
                tooltip: '출발역과 도착역 바꾸기',
                onPressed: _loading ? null : _swapStations,
                icon: const Icon(Icons.swap_vert),
              ),
            ),
            _stationField(
              slot: _StationSlot.arrival,
              controller: _arrivalController,
              label: '도착역',
              key: const Key('trainSearchArrivalField'),
            ),
            _suggestionList(_StationSlot.arrival),
            const SizedBox(height: 20),
            Semantics(
              label: '여정 종류',
              child: SegmentedButton<bool>(
                key: const Key('trainSearchTripType'),
                segments: const [
                  ButtonSegment(value: false, label: Text('편도')),
                  ButtonSegment(value: true, label: Text('왕복')),
                ],
                selected: {_roundTrip},
                onSelectionChanged: _loading
                    ? null
                    : (selection) {
                        setState(() {
                          _roundTrip = selection.single;
                          _returnDate = _roundTrip ? _departureDate : null;
                          _clearResult();
                        });
                      },
              ),
            ),
            const SizedBox(height: 16),
            _dateButton(
              key: const Key('trainSearchDepartureDateButton'),
              label: '가는 날',
              value: _departureDate,
              onPressed: () => _pickDate(returnDate: false),
            ),
            if (_roundTrip) ...[
              const SizedBox(height: 12),
              _dateButton(
                key: const Key('trainSearchReturnDateButton'),
                label: '오는 날',
                value: _returnDate ?? _departureDate,
                onPressed: () => _pickDate(returnDate: true),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('trainSearchTrainTypeField'),
              initialValue: _trainType?.apiValue ?? 'ALL',
              decoration: const InputDecoration(
                labelText: '열차종',
                border: OutlineInputBorder(),
              ),
              hint: const Text('전체 열차'),
              items: [
                const DropdownMenuItem(value: 'ALL', child: Text('전체 열차')),
                for (final type in TrainSearchTrainType.values)
                  DropdownMenuItem(
                    value: type.apiValue,
                    child: Text(type.labelKo),
                  ),
              ],
              onChanged: _loading
                  ? null
                  : (value) => setState(() {
                      _trainType = value == null || value == 'ALL'
                          ? null
                          : TrainSearchTrainType.parse(value);
                      _clearResult();
                    }),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('trainSearchSubmitButton'),
              onPressed: _loading ? null : _submit,
              icon: const Icon(Icons.search),
              label: const Text('열차 검색'),
            ),
            const SizedBox(height: 24),
            _resultBody(),
          ],
        ),
      ),
    );
  }

  Widget _stationField({
    required _StationSlot slot,
    required TextEditingController controller,
    required String label,
    required Key key,
  }) {
    return TextField(
      key: key,
      controller: controller,
      enabled: !_loading,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: label,
        hintText: '역 이름 두 글자 이상',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.train_outlined),
      ),
      onChanged: (value) {
        setState(() {
          if (slot == _StationSlot.departure) {
            _departure = null;
          } else {
            _arrival = null;
          }
          _clearResult();
        });
        unawaited(_loadStations(slot, value));
      },
    );
  }

  Widget _suggestionList(_StationSlot slot) {
    if (_suggestionSlot != slot || _suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          for (final station in _suggestions)
            ListTile(
              key: Key(
                'trainSearchStationSuggestion-${slot.name}-${station.id}',
              ),
              title: Text(station.name),
              subtitle: Text(station.id),
              onTap: () => _selectStation(slot, station),
            ),
        ],
      ),
    );
  }

  Widget _dateButton({
    required Key key,
    required String label,
    required DateTime value,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      key: key,
      onPressed: _loading ? null : onPressed,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('$label  ${_formatDate(value)}'),
      ),
    );
  }

  Widget _resultBody() {
    if (_loading) {
      return Semantics(
        label: '기차 검색 중',
        liveRegion: true,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(key: Key('trainSearchLoading')),
          ),
        ),
      );
    }
    if (_error case final String error) {
      return Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('trainSearchError'),
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.error_outline),
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('trainSearchRetryButton'),
                  onPressed: _submit,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final result = _result;
    if (result == null) {
      return const SizedBox(
        key: Key('trainSearchInitial'),
        child: Text('출발역과 도착역을 선택해 검색해 주세요.'),
      );
    }
    if (result.outbound.isEmpty && result.inbound.isEmpty) {
      return Semantics(
        liveRegion: true,
        child: Text('선택한 조건에 운행 열차가 없습니다.', key: Key('trainSearchEmpty')),
      );
    }
    return Column(
      key: const Key('trainSearchResults'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _journeySection('가는 열차', result.outbound),
        if (result.inbound.isNotEmpty) ...[
          const SizedBox(height: 20),
          _journeySection('오는 열차', result.inbound),
        ],
      ],
    );
  }

  Widget _journeySection(String title, List<TrainJourney> journeys) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (journeys.isEmpty)
          const Text('운행 열차가 없습니다.')
        else
          for (final journey in journeys) _journeyCard(journey),
      ],
    );
  }

  Widget _journeyCard(TrainJourney journey) {
    final fare = '${_formatNumber(journey.adultFareWon)}원';
    final semanticsLabel =
        '${journey.departureStationName} 출발, '
        '${journey.arrivalStationName} 도착, '
        '${journey.trainType.labelKo} ${journey.trainNumber}, 성인 1인 $fare';
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${journey.trainType.labelKo} ${journey.trainNumber}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${journey.departureStationName} → ${journey.arrivalStationName}',
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatTime(journey.departureAt)} → '
                  '${_formatTime(journey.arrivalAt)} · ${journey.durationMinutes}분',
                ),
                const SizedBox(height: 8),
                Text(
                  fare,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text('성인 1인'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadStations(_StationSlot slot, String query) async {
    final normalized = query.trim();
    final requestToken = ++_stationRequestToken;
    if (normalized.runes.length < 2) {
      if (mounted) {
        setState(() {
          _suggestionSlot = null;
          _suggestions = const [];
        });
      }
      return;
    }
    try {
      final stations = await widget.repository.stations(
        normalized,
        type: _trainType,
      );
      if (!mounted || requestToken != _stationRequestToken) return;
      setState(() {
        _suggestionSlot = slot;
        _suggestions = stations;
      });
    } on TrainSearchException catch (error) {
      if (!mounted || requestToken != _stationRequestToken) return;
      setState(() {
        _suggestionSlot = null;
        _suggestions = const [];
        _error = error.message;
      });
    }
  }

  void _selectStation(_StationSlot slot, TrainStation station) {
    _stationRequestToken++;
    setState(() {
      if (slot == _StationSlot.departure) {
        _departure = station;
        _departureController.text = station.name;
      } else {
        _arrival = station;
        _arrivalController.text = station.name;
      }
      _suggestionSlot = null;
      _suggestions = const [];
      _clearResult();
    });
  }

  void _swapStations() {
    setState(() {
      final station = _departure;
      _departure = _arrival;
      _arrival = station;
      final text = _departureController.text;
      _departureController.text = _arrivalController.text;
      _arrivalController.text = text;
      _suggestionSlot = null;
      _suggestions = const [];
      _clearResult();
    });
  }

  Future<void> _pickDate({required bool returnDate}) async {
    final today = _dateOnly(widget.now());
    final initialDate = returnDate
        ? (_returnDate ?? _departureDate)
        : _departureDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(today) ? today : initialDate,
      firstDate: returnDate && _departureDate.isAfter(today)
          ? _departureDate
          : today,
      lastDate: DateTime(today.year + 1, today.month, today.day),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (returnDate) {
        _returnDate = selected;
      } else {
        _departureDate = selected;
        if (_returnDate != null && _returnDate!.isBefore(selected)) {
          _returnDate = selected;
        }
      }
      _clearResult();
    });
  }

  Future<void> _submit() async {
    if (_loading) return;
    final departure = _departure;
    final arrival = _arrival;
    if (departure == null || arrival == null) {
      setState(() => _error = '출발역과 도착역을 선택해 주세요.');
      return;
    }
    if (departure.id == arrival.id) {
      setState(() => _error = '서로 다른 출발역과 도착역을 선택해 주세요.');
      return;
    }
    final requestToken = ++_searchRequestToken;
    setState(() {
      _loading = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.repository.search(
        TrainSearchCriteria(
          departure: departure,
          arrival: arrival,
          departureDate: _departureDate,
          returnDate: _roundTrip ? _returnDate : null,
          trainType: _trainType,
        ),
      );
      if (!mounted || requestToken != _searchRequestToken) return;
      setState(() {
        _loading = false;
        _result = result;
      });
    } on TrainSearchException catch (error) {
      if (!mounted || requestToken != _searchRequestToken) return;
      setState(() {
        _loading = false;
        _result = null;
        _error = error.message;
      });
    }
  }

  void _clearResult() {
    _searchRequestToken++;
    _result = null;
    _error = null;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _formatDate(DateTime value) =>
      '${value.year}.${value.month.toString().padLeft(2, '0')}.'
      '${value.day.toString().padLeft(2, '0')}';

  String _formatTime(DateTime value) {
    final koreaTime = value.toUtc().add(const Duration(hours: 9));
    return '${koreaTime.hour.toString().padLeft(2, '0')}:'
        '${koreaTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatNumber(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}
