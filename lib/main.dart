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
  
  // 앱 실행 시 필수 권한 요청
  await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
  
  runApp(const BikeFitApp());
}

class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;

  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds
  };
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, 
        brightness: Brightness.dark, 
        scaffoldBackgroundColor: Colors.black,
      ),
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
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(
          item['id'] ?? DateTime.now().toString(),
          item['date'],
          item['avgHR'],
          (item['calories'] as num).toDouble(),
          Duration(seconds: item['durationSeconds'] ?? 0)
        )).toList();
      }
    });
  }

  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
          if (mounted) setModalState(() { _filteredResults = results.where((r) => r.device.platformName.isNotEmpty).toList(); });
        });
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.4,
          child: Column(children: [
            const Text("워치 검색", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(child: ListView.builder(
              itemCount: _filteredResults.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(_filteredResults[index].device.platformName),
                trailing: const Icon(Icons.bluetooth_searching, color: Colors.blueAccent),
                onTap: () { Navigator.pop(context); _connectToDevice(_filteredResults[index].device); }
              ),
            ))
          ]),
        );
      })).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try { await device.connect(); _setupDevice(device); } catch (e) { _showToast("연결 실패"); }
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() => _isWatchConnected = true);
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) {
      if (s.uuid == Guid("180D")) {
        for (var c in s.characteristics) {
          if (c.uuid == Guid("2A37")) {
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

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: Container(
        // 배경 이미지 설정 (1번 사진 반영)
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(icon: Icon(_isWatchConnected ? Icons.watch : Icons.watch_off, color: Colors.greenAccent), onPressed: _showDeviceScanPopup)
              ]),
              const SizedBox(height: 10),
              
              // 상단 심박수 차트 (네온 느낌 추가)
              SizedBox(height: 80, child: LineChart(LineChartData(
                gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
                lineBarsData: [LineChartBarData(
                  spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots,
                  isCurved: true, color: Colors.greenAccent, barWidth: 3, 
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: Colors.greenAccent.withOpacity(0.1))
                )]
              ))),
              
              const Spacer(),

              // 중앙 자전거 아이콘 (2번 사진 반영)
              Image.asset('assets/icon/bike_ui_dark.png', height: 180),

              const Spacer(),
              
              // 진행률 바 (네온 효과)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress, 
                  minHeight: 10,
                  color: Colors.greenAccent, 
                  backgroundColor: Colors.white12
                ),
              ),
              const SizedBox(height: 25),
              
              // 하단 스탯 (가독성 강화)
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _stat("심박수", "$_heartRate", Colors.redAccent), 
                _stat("평균", "$_avgHeartRate", Colors.orangeAccent), 
                _stat("칼로리", _calories.toStringAsFixed(1), Colors.greenAccent),
                _stat("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)
              ]),
              
              const SizedBox(height: 40),
              
              // 하단 버튼 세트 (유리 질감 스타일)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _btn(_isWorkingOut ? Icons.pause : Icons.play_arrow, Colors.greenAccent, () {
                  setState(() {
                    _isWorkingOut = !_isWorkingOut;
                    if (_isWorkingOut) {
                      _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                        setState(() { _duration += const Duration(seconds: 1); if (_heartRate >= 95) _calories += 0.15; });
                      });
                    } else { _workoutTimer?.cancel(); }
                  });
                }),
                const SizedBox(width: 25),
                _btn(Icons.save, Colors.white70, () async {
                  if (_isWorkingOut) return;
                  final r = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
                  setState(() { _records.insert(0, r); });
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('workout_records', jsonEncode(_records.map((e) => e.toJson()).toList()));
                  _showToast("기록 저장 완료");
                }),
                const SizedBox(width: 25),
                _btn(Icons.calendar_month, Colors.white70, () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records)))),
              ]),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stat(String l, String v, Color c) => Column(children: [
    Text(l, style: const TextStyle(fontSize: 12, color: Colors.white60)), 
    const SizedBox(height: 5),
    Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c))
  ]);

  Widget _btn(IconData i, Color c, VoidCallback t) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: c.withOpacity(0.2), blurRadius: 10, spreadRadius: 2)],
    ),
    child: ElevatedButton(
      onPressed: t, 
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.1), 
        foregroundColor: c,
        padding: const EdgeInsets.all(20), 
        shape: const CircleBorder(),
        side: BorderSide(color: c.withOpacity(0.4), width: 1.5)
      ), 
      child: Icon(i, size: 32)
    ),
  );
}

class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);
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
        appBar: AppBar(title: const Text("운동 기록")),
        body: Column(children: [
          TableCalendar(
            locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _selectedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() => _selectedDay = sel),
            calendarFormat: CalendarFormat.twoWeeks,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: BarChart(BarChartData(
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => Colors.blueAccent.withOpacity(0.8),
                  )
                ),
                gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
                barGroups: List.generate(daily.length, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: daily[i].calories, color: Colors.blueAccent)]))
              )),
            ),
          ),
          Expanded(child: ListView.builder(itemCount: daily.length, itemBuilder: (c, i) => ListTile(title: Text("${daily[i].calories.toInt()} kcal 소모"), subtitle: Text("${daily[i].duration.inMinutes}분 운동"))))
        ]),
      ),
    );
  }
}
