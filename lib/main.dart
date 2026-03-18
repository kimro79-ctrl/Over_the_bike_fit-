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
  runApp(const BikeFitApp());
}

// ---------------------------------------------------------
// 1. 스플래시 화면 (3초 유지)
// ---------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // 3초 후 메인 화면으로 이동
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const WorkoutScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 등록된 background.png를 스플래시로 활용
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/background.png',
                width: 150,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.directions_bike, size: 100, color: Colors.greenAccent),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              "INDOOR BIKE FIT",
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.black, letterSpacing: 3),
            ),
            const SizedBox(height: 15),
            const CircularProgressIndicator(color: Colors.greenAccent, strokeWidth: 2),
          ],
        ),
      ),
    );
  }
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
      home: const SplashScreen(), // 시작은 스플래시
    );
  }
}

// ---------------------------------------------------------
// 2. 메인 운동 화면
// ---------------------------------------------------------
class WorkoutRecord {
  final String id, date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds};
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
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
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) { _showToast("블루투스를 켜주세요."); return; }
    if (!await Permission.bluetoothScan.isGranted || !await Permission.bluetoothConnect.isGranted) {
      await [Permission.bluetoothScan, Permission.bluetoothConnect].request(); return;
    }
    _filteredResults.clear();
    try {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: false);
    } catch (e) { _showToast("스캔 오류"); return; }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
          List<ScanResult> devices = [];
          for (var r in results) {
            String name = r.device.platformName.trim().toUpperCase();
            if (name.isEmpty || name.contains("UNKNOWN")) continue; // Unknown 필터링
            bool isWatch = name.contains("WATCH") || name.contains("GALAXY") || name.contains("FIT") || name.contains("AMAZFIT") || name.contains("GTS") || name.contains("GTR");
            if (isWatch && !devices.any((e) => e.device.remoteId == r.device.remoteId)) { devices.add(r); }
          }
          if (mounted) setModalState(() { _filteredResults = devices; });
        });
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.45,
          child: Column(children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text("연결할 워치를 선택하세요", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: _filteredResults.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                  : ListView.builder(
                      itemCount: _filteredResults.length,
                      itemBuilder: (context, index) {
                        final d = _filteredResults[index].device;
                        return ListTile(
                          leading: const Icon(Icons.watch, color: Colors.greenAccent),
                          title: Text(d.platformName, style: const TextStyle(color: Colors.white)),
                          onTap: () { Navigator.pop(context); _connectToDevice(d); },
                        );
                      }),
            )
          ]),
        );
      }),
    ).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _setupDevice(device);
    } catch (e) { _showToast("연결 실패"); }
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() => _isWatchConnected = true);
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) {
      if (s.uuid.toString().toUpperCase().contains("180D")) {
        for (var c in s.characteristics) {
          if (c.uuid.toString().toUpperCase().contains("2A37")) {
            await c.setNotifyValue(true);
            c.lastValueStream.listen(_decodeHR);
          }
        }
      }
    }
  }

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
        }
      });
    }
  }

  void _showToast(String msg) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating)); }

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.6, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.black)))),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              const SizedBox(height: 40),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                _connectBtn(),
              ]),
              const SizedBox(height: 25),
              _chartArea(),
              const Spacer(),
              _goalCard(progress),
              const SizedBox(height: 20),
              _dataBanner(),
              const SizedBox(height: 30),
              _controlRow(),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _connectBtn() => GestureDetector(
      onTap: _showDeviceScanPopup,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.greenAccent)),
          child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(color: Colors.greenAccent, fontSize: 10))));

  Widget _chartArea() => SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])));

  Widget _goalCard(double p) => Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CALORIE GOAL", style: TextStyle(fontSize: 10, color: Colors.white54)), Text("${_calories.toInt()}/${_goalCalories.toInt()} kcal", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: p, backgroundColor: Colors.white10, color: Colors.greenAccent),
      ]));

  Widget _dataBanner() => Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _stat("심박수", "$_heartRate", Colors.greenAccent),
        _stat("평균", "$_avgHeartRate", Colors.redAccent),
        _stat("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
        _stat("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)
      ]));

  Widget _stat(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white54)), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);

  Widget _controlRow() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _circleBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, () {
          setState(() {
            _isWorkingOut = !_isWorkingOut;
            if (_isWorkingOut) { _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() { _duration += const Duration(seconds: 1); if (_heartRate >= 90) _calories += 0.12; })); }
            else { _workoutTimer?.cancel(); }
          });
        }),
        const SizedBox(width: 20),
        _circleBtn(Icons.save, () async {
          if (_duration.inSeconds < 5) { _showToast("기록이 너무 짧음"); return; }
          final r = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
          _records.insert(0, r);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('workout_records', jsonEncode(_records.map((e) => e.toJson()).toList()));
          _showToast("저장 완료");
        }),
        const SizedBox(width: 20),
        _circleBtn(Icons.calendar_month, () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _loadInitialData)))),
      ]);

  Widget _circleBtn(IconData i, VoidCallback t) => GestureDetector(onTap: t, child: Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white10, border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white)));
}

// ---------------------------------------------------------
// 3. 기록 화면 (기존과 동일)
// ---------------------------------------------------------
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}
class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now(); DateTime? _selectedDay; late List<WorkoutRecord> _currentRecords;
  @override void initState() { super.initState(); _currentRecords = List.from(widget.records); _selectedDay = _focusedDay; }
  @override Widget build(BuildContext context) {
    final daily = _currentRecords.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    return Theme(data: ThemeData(brightness: Brightness.light), child: Scaffold(appBar: AppBar(title: const Text("기록"), elevation: 0), body: Column(children: [
      TableCalendar(locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay, selectedDayPredicate: (day) => isSameDay(_selectedDay, day), onDaySelected: (s, f) => setState(() { _selectedDay = s; _focusedDay = f; }), calendarStyle: const CalendarStyle(todayDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle), selectedDecoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle))),
      Expanded(child: ListView.builder(itemCount: daily.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.directions_bike), title: Text("${daily[i].calories.toInt()} kcal"), subtitle: Text("${daily[i].duration.inMinutes}분 운동"))))
    ])));
  }
}
