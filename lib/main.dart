import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  await _requestPermissions();
  runApp(const BikeFitApp());
}

Future<void> _requestPermissions() async {
  await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
}

class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds};
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0, _avgHeartRate = 0;
  double _calories = 0.0, _goalCalories = 300.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false, _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];
  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

  @override
  void initState() { super.initState(); _loadInitialData(); }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(item['id'] ?? DateTime.now().toString(), item['date'], item['avgHR'], (item['calories'] as num).toDouble(), Duration(seconds: item['durationSeconds'] ?? 0))).toList();
      }
    });
  }

  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    if ((await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request()).values.any((s) => s.isDenied)) return;
    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E1E), isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), 
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) { if (mounted) setModalState(() { _filteredResults = results.where((r) => r.device.platformName.isNotEmpty).toList(); }); });
        return Container(padding: const EdgeInsets.all(20), height: MediaQuery.of(context).size.height * 0.4, child: Column(children: [const SizedBox(height: 20), const Text("워치 검색"), Expanded(child: ListView.builder(itemCount: _filteredResults.length, itemBuilder: (context, index) => ListTile(title: Text(_filteredResults[index].device.platformName), onTap: () { Navigator.pop(context); _connectToDevice(_filteredResults[index].device); }))) ]));
      })).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });
  }

  void _connectToDevice(BluetoothDevice device) async { try { await device.connect(); _setupDevice(device); } catch (e) { _showToast("연결 실패"); } }
  void _setupDevice(BluetoothDevice device) async { setState(() { _isWatchConnected = true; }); (await device.discoverServices()).forEach((s) { if (s.uuid == Guid("180D")) s.characteristics.forEach((c) { if (c.uuid == Guid("2A37")) { c.setNotifyValue(true); c.lastValueStream.listen(_decodeHR); } }); }); } 
  void _decodeHR(List<int> data) { if (data.isEmpty) return; int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1]; if (mounted && hr > 0) { setState(() { _heartRate = hr; if (_isWorkingOut) { _timeCounter += 1; _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble())); if (_hrSpots.length > 50) _hrSpots.removeAt(0); _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt(); } }); } }
  void _showToast(String msg) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating)); }

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), IconButton(icon: Icon(_isWatchConnected ? Icons.watch : Icons.watch_off, color: Colors.greenAccent), onPressed: _showDeviceScanPopup)]),
        const SizedBox(height: 20),
        SizedBox(height: 100, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 3, dotData: const FlDotData(show: false))]))),
        const Spacer(),
        LinearProgressIndicator(value: progress, color: Colors.greenAccent, backgroundColor: Colors.white12),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_stat("심박수", "$_heartRate"), _stat("평균", "$_avgHeartRate"), _stat("칼로리", _calories.toStringAsFixed(1)), _stat("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}")]),
        const SizedBox(height: 40),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _btn(_isWorkingOut ? Icons.pause : Icons.play_arrow, () { setState(() { _isWorkingOut = !_isWorkingOut; if (_isWorkingOut) _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) { setState(() { _duration += const Duration(seconds: 1); if (_heartRate >= 95) _calories += 0.15; }); }); else _workoutTimer?.cancel(); }); }),
          const SizedBox(width: 20),
          _btn(Icons.save, () async { if (_isWorkingOut) return; final newRec = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration); setState(() { _records.insert(0, newRec); }); (await SharedPreferences.getInstance()).setString('workout_records', jsonEncode(_records.map((r) => r.toJson()).toList())); _showToast("저장 완료"); }),
          const SizedBox(width: 20),
          _btn(Icons.calendar_month, () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _loadInitialData)))),
        ]),
        const SizedBox(height: 20),
      ]))),
    );
  }
  Widget _stat(String l, String v) => Column(children: [Text(l, style: const TextStyle(fontSize: 12, color: Colors.white60)), Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]);
  Widget _btn(IconData i, VoidCallback t) => ElevatedButton(onPressed: t, style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(15), shape: const CircleBorder()), child: Icon(i));
}

class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _selectedDay = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final daily = widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay)).toList();
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        appBar: AppBar(title: const Text("기록 리포트")),
        body: Column(children: [
          TableCalendar(
            locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _selectedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() => _selectedDay = sel),
            calendarFormat: CalendarFormat.twoWeeks,
          ),
          // ✅ GitHub 빌드 에러 수정 구간
          SizedBox(height: 150, padding: const EdgeInsets.all(20), child: BarChart(BarChartData(
            barTouchData: BarTouchTouchData(touchTooltipData: BarTouchTooltipData(getTooltipColor: (group) => Colors.blueAccent.withOpacity(0.8))),
            gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
            barGroups: List.generate(daily.length, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: daily[i].calories, color: Colors.blueAccent)]))
          ))),
          Expanded(child: ListView.builder(itemCount: daily.length, itemBuilder: (c, i) => ListTile(title: Text("${daily[i].calories.toInt()} kcal"), subtitle: Text("${daily[i].duration.inMinutes}분"))))
        ]),
      ),
    );
  }
}
